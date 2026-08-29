/**
 * Panda Device — VS Code extension for Android WiFi Debugging.
 *
 * Guides the user through adb pair/connect flow (Shizuku-style),
 * manages Flutter SDK installation, and runs apps on device.
 */
'use strict';

const vscode = require('vscode');

/** @type {vscode.StatusBarItem | undefined} */
let statusBarItem = undefined;

function activate(context) {
  console.log('[Panda Device] Extension activating...');

  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left, 90
  );
  statusBarItem.text = '$(device-mobile) Panda Device';
  statusBarItem.tooltip = 'Panda Device — Click for status';
  statusBarItem.command = 'panda-device.status';
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  context.subscriptions.push(
    vscode.commands.registerCommand('panda-device.pair', pairDevice),
    vscode.commands.registerCommand('panda-device.connect', connectDevice),
    vscode.commands.registerCommand('panda-device.status', showStatus),
    vscode.commands.registerCommand('panda-device.ensureFlutter', ensureFlutter),
    vscode.commands.registerCommand('panda-device.run', runOnDevice),
  );

  // Register webview
  context.subscriptions.push(
    vscode.window.registerWebviewPanelSerializer('panda-device.setup', {
      async deserializeWebviewPanel(panel) {
        setupWebview(panel);
      }
    })
  );

  console.log('[Panda Device] Extension activated ✓');
}

function deactivate() {}

// ── Pairing Flow ──────────────────────────────────────────────────────────

async function pairDevice() {
  // Step 1: Check adb
  const adbOk = await vscode.panda.device.isAdbAvailable();
  if (!adbOk) {
    const action = await vscode.window.showErrorMessage(
      'adb n\'est pas installé dans le terminal.',
      'Installer adb'
    );
    if (action === 'Installer adb') {
      await vscode.panda.terminal.exec('apt update && apt install -y android-tools-adb');
    }
    return;
  }

  // Step 2: Open developer settings
  const openSettings = await vscode.window.showInformationMessage(
    'Étape 1: Active le Débogage sans fil\n\n'
    + '1. Options développeur → Débogage sans fil\n'
    + '2. Appuie sur "Associer l\'appareil avec un code"\n'
    + '3. GARDE la popup ouverte !',
    'Ouvrir les options', 'Annuler'
  );
  if (openSettings !== 'Ouvrir les options') return;

  await vscode.panda.device.openDeveloperSettings();

  // Step 3: Ask for pairing port
  const port = await vscode.window.showInputBox({
    prompt: 'Port d\'APPAIRAGE (affiché dans la popup)',
    placeHolder: '44851',
    validateInput: (v) => {
      const n = parseInt(v);
      return (n > 0 && n < 65535) ? null : 'Port invalide';
    }
  });
  if (!port) return;

  // Step 4: Ask for pairing code
  const code = await vscode.window.showInputBox({
    prompt: 'Code d\'appairage à 6 chiffres (affiché dans la popup)',
    placeHolder: '041602',
    validateInput: (v) => {
      return /^\d{6}$/.test(v.trim()) ? null : 'Le code doit faire 6 chiffres';
    }
  });
  if (!code) return;

  // Step 5: Pair
  await vscode.window.withProgress({
    location: vscode.ProgressLocation.Notification,
    title: 'Appairage en cours...',
  }, async (p) => {
    p.report({ message: `adb pair ${port}` });
    const result = await vscode.panda.device.pair(port, code.trim());
    if (result.success) {
      vscode.window.showInformationMessage('✅ Appairage réussi !');
    } else {
      vscode.window.showErrorMessage(
        'Échec de l\'appairage. Vérifie:\n'
        + '• Le port est celui de la popup (pas l\'écran principal)\n'
        + '• Le code fait bien 6 chiffres\n'
        + '• La popup est encore ouverte (expire en ~60s)'
      );
    }
  });
}

async function connectDevice() {
  const adbOk = await vscode.panda.device.isAdbAvailable();
  if (!adbOk) {
    vscode.window.showErrorMessage('adb non installé');
    return;
  }

  const port = await vscode.window.showInputBox({
    prompt: 'Port de DÉBOGAGE (affiché sur l\'écran "Débogage sans fil")',
    placeHolder: '5555',
    validateInput: (v) => {
      const n = parseInt(v);
      return (n > 0 && n < 65535) ? null : 'Port invalide';
    }
  });
  if (!port) return;

  const result = await vscode.panda.device.connect(port.trim());
  if (result.success) {
    vscode.window.showInformationMessage('📱 Appareil connecté !');
    updateStatusBar(true);
  } else {
    vscode.window.showErrorMessage(
      'Connexion échouée. Vérifie:\n'
      + '• Le port est celui de l\'écran principal\n'
      + '• Le téléphone est sur le même WiFi\n'
      + '• Le débogage sans fil est actif'
    );
  }
}

async function ensureFlutter() {
  await vscode.window.withProgress({
    location: vscode.ProgressLocation.Notification,
    title: 'Flutter SDK',
  }, async (p) => {
    p.report({ message: 'Vérification...' });
    const output = await vscode.panda.terminal.exec('which flutter && flutter --version');
    if (output && output.includes('Flutter')) {
      const version = output.match(/Flutter (\S+)/)?.[1] ?? '?';
      vscode.window.showInformationMessage(`Flutter ${version} ✓`);
    } else {
      p.report({ message: 'Installation de Flutter...' });
      const channel = vscode.workspace.getConfiguration('panda-device')
        .get('flutterChannel', 'stable');
      await vscode.panda.terminal.exec(
        `cd /opt && git clone -b ${channel} https://github.com/flutter/flutter.git && export PATH="/opt/flutter/bin:$PATH" && flutter precache`
      );
      vscode.window.showInformationMessage('Flutter installé ✓');
    }
  });
}

async function runOnDevice() {
  const devices = await vscode.panda.device.listDevices();
  if (!devices || devices.length === 0) {
    vscode.window.showErrorMessage('Aucun appareil connecté. Lance d\'abord l\'appairage.');
    return;
  }

  await vscode.window.withProgress({
    location: vscode.ProgressLocation.Notification,
    title: 'Run sur l\'appareil...',
  }, async () => {
    await vscode.panda.terminal.exec('export PATH="/opt/flutter/bin:$PATH" && flutter run');
  });
}

async function showStatus() {
  const adbOk = await vscode.panda.device.isAdbAvailable();
  const devices = adbOk ? await vscode.panda.device.listDevices() : [];
  const flutterOutput = await vscode.panda.terminal.exec('which flutter 2>/dev/null && flutter --version 2>/dev/null | head -1');
  const flutterOk = flutterOutput && flutterOutput.includes('Flutter');

  const items = [
    `**adb:** ${adbOk ? '✅' : '❌ Non installé'}`,
    `**Appareil:** ${devices.length > 0 ? `✅ ${devices.length} connecté(s)` : '❌ Aucun'}`,
    `**Flutter:** ${flutterOk ? '✅' : '❌ Non installé'}`,
  ];

  const action = await vscode.window.showInformationMessage(
    items.join('\n  '),
    'Appairer', 'Flutter SDK', 'Run'
  );

  if (action === 'Appairer') await pairDevice();
  else if (action === 'Flutter SDK') await ensureFlutter();
  else if (action === 'Run') await runOnDevice();
}

function updateStatusBar(connected) {
  if (statusBarItem) {
    statusBarItem.text = connected
      ? '$(device-mobile) Panda Device ●'
      : '$(device-mobile) Panda Device';
  }
}

function setupWebview(panel) {
  panel.webview.html = `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>Panda Device</title></head>
<body style="font-family:sans-serif;background:#1e1e2e;color:#cdd6f4;padding:20px;">
  <h2 style="color:#94e2d5;">📱 Panda Device</h2>
  <p>Utilisez les commandes du palette (Ctrl+Shift+P) pour:</p>
  <ul>
    <li><code>Panda Device: Pair</code> — Appairage WiFi</li>
    <li><code>Panda Device: Connect</code> — Connexion debug</li>
    <li><code>Panda Device: Run</code> — Lancer l'app</li>
  </ul>
</body></html>`;
}

module.exports = { activate, deactivate };
