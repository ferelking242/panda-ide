/**
 * Panda AI — VS Code extension for the AI Gateway.
 *
 * Manages the Python FastAPI server that bridges ChatGPT, Claude,
 * and other AI providers via browser automation.
 */
'use strict';

const vscode = require('vscode');

/** @type {vscode.WebviewPanel | undefined} */
let dashboardPanel = undefined;

/** @type {vscode.StatusBarItem | undefined} */
let statusBarItem = undefined;

/** @type {boolean} */
let serverRunning = false;

// ── Activation ────────────────────────────────────────────────────────────

function activate(context) {
  console.log('[Panda AI] Extension activating...');

  // Status bar
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left, 100
  );
  statusBarItem.text = '$(robot) Panda AI';
  statusBarItem.tooltip = 'Panda AI Gateway — Click to open';
  statusBarItem.command = 'panda-ai.status';
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('panda-ai.install', installGateway),
    vscode.commands.registerCommand('panda-ai.start', startServer),
    vscode.commands.registerCommand('panda-ai.stop', stopServer),
    vscode.commands.registerCommand('panda-ai.status', showStatus),
    vscode.commands.registerCommand('panda-ai.openDashboard', openDashboard),
  );

  // Register webview provider for the dashboard panel
  context.subscriptions.push(
    vscode.window.registerWebviewPanelSerializer('panda-ai.dashboard', {
      async deserializeWebviewPanel(panel, state) {
        dashboardPanel = panel;
        setupDashboardWebview(panel);
      }
    })
  );

  console.log('[Panda AI] Extension activated ✓');
}

function deactivate() {
  console.log('[Panda AI] Extension deactivating...');
}

// ── Commands ──────────────────────────────────────────────────────────────

async function installGateway() {
  const progress = { report: () => {} };
  await vscode.window.withProgress({
    location: vscode.ProgressLocation.Notification,
    title: 'Panda AI: Installation',
    cancellable: false,
  }, async (p) => {
    p.report({ message: 'Vérification de Python...' });

    const pythonOk = await vscode.panda.terminal.isReady();
    if (!pythonOk) {
      p.report({ message: 'Installation de Python et dépendances...' });
      await vscode.panda.terminal.exec(
        'apt update && apt install -y python3 python3-pip python3-venv git'
      );
    }

    p.report({ message: 'Clonage de panda-ai...' });
    await vscode.panda.terminal.exec(
      'cd /root && git clone https://github.com/ferelking242/panda-ai.git'
    );

    p.report({ message: 'Installation des dépendances Python...' });
    await vscode.panda.terminal.exec(
      'cd /root/panda-ai && pip3 install -r requirements.txt'
    );

    p.report({ message: 'Installation de Patchright (Chromium)...' });
    await vscode.panda.terminal.exec(
      'cd /root/panda-ai && patchright install chromium'
    );

    p.report({ message: 'Installation des dépendances système...' });
    await vscode.panda.terminal.exec(
      'apt-get install -y libglib2.0-0t64 libnspr4 libnss3 libatk1.0-0t64 '
      + 'libatk-bridge2.0-0t64 libdbus-1-3 libcups2t64 libxkbcommon0 '
      + 'libasound2t64 libgbm1 libcairo2 libpango-1.0-0 libxcomposite1 '
      + 'libxdamage1 libxfixes3 libxrandr2 libatspi2.0-0t64'
    );

    vscode.window.showInformationMessage('Panda AI installé ✓');
  });
}

async function startServer() {
  if (serverRunning) {
    vscode.window.showInformationMessage('Panda AI est déjà en cours d\'exécution');
    return;
  }

  const config = vscode.workspace.getConfiguration('panda-ai');
  const provider = config.get('provider', 'chatgpt');

  try {
    await vscode.panda.gateway.start(provider);
    serverRunning = true;
    updateStatusBar(true);
    vscode.window.showInformationMessage(`Panda AI démarré (${provider})`);
  } catch (e) {
    vscode.window.showErrorMessage(`Erreur: ${e.message}`);
  }
}

async function stopServer() {
  try {
    await vscode.panda.gateway.stop();
    serverRunning = false;
    updateStatusBar(false);
    vscode.window.showInformationMessage('Panda AI arrêté');
  } catch (e) {
    vscode.window.showErrorMessage(`Erreur: ${e.message}`);
  }
}

async function showStatus() {
  const status = await vscode.panda.gateway.status();
  const pythonOk = await vscode.panda.gateway.isPythonAvailable();

  const items = [
    `**Serveur:** ${status.running ? '🟢 En cours' : '🔴 Arrêté'}`,
    `**Python:** ${pythonOk ? '✅ Installé' : '❌ Non installé'}`,
    `**Provider:** ${status.provider ?? 'chatgpt'}`,
    `**API:** http://127.0.0.1:8000`,
  ];

  const action = await vscode.window.showInformationMessage(
    items.join('\n  '),
    'Démarrer', 'Dashboard', 'Installer'
  );

  if (action === 'Démarrer') await startServer();
  else if (action === 'Dashboard') await openDashboard();
  else if (action === 'Installer') await installGateway();
}

async function openDashboard() {
  if (dashboardPanel) {
    dashboardPanel.reveal(vscode.ViewColumn.One);
    return;
  }

  dashboardPanel = vscode.window.createWebviewPanel(
    'panda-ai.dashboard',
    'Panda AI Dashboard',
    vscode.ViewColumn.One,
    { enableScripts: true, retainContextWhenHidden: true }
  );

  setupDashboardWebview(dashboardPanel);

  dashboardPanel.onDidDispose(() => {
    dashboardPanel = undefined;
  });
}

// ── Webview ───────────────────────────────────────────────────────────────

function setupDashboardWebview(panel) {
  panel.webview.html = `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Panda AI Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #1e1e2e; color: #cdd6f4; padding: 20px;
    }
    h1 { font-size: 20px; margin-bottom: 16px; color: #89b4fa; }
    .status { padding: 12px 16px; border-radius: 8px; margin-bottom: 12px; }
    .running { background: #1e3a2f; border: 1px solid #a6e3a1; }
    .stopped { background: #3a1e1e; border: 1px solid #f38ba8; }
    .info { font-size: 13px; color: #a6adc8; margin-top: 8px; }
    .btn {
      display: inline-block; padding: 8px 16px; border-radius: 6px;
      border: none; cursor: pointer; font-size: 13px; margin-right: 8px;
      margin-top: 12px;
    }
    .btn-primary { background: #89b4fa; color: #1e1e2e; }
    .btn-danger { background: #f38ba8; color: #1e1e2e; }
    .btn:hover { opacity: 0.85; }
    iframe { width: 100%; height: 500px; border: 1px solid #45475a; border-radius: 8px; margin-top: 16px; }
  </style>
</head>
<body>
  <h1>🐼 Panda AI Gateway</h1>
  <div id="status" class="status stopped">
    <strong>🔴 Serveur arrêté</strong>
    <div class="info">Cliquez "Démarrer" pour lancer le serveur</div>
  </div>
  <div>
    <button class="btn btn-primary" onclick="startServer()">▶ Démarrer</button>
    <button class="btn btn-danger" onclick="stopServer()">■ Arrêter</button>
    <button class="btn btn-primary" onclick="installGateway()">📦 Installer</button>
  </div>
  <iframe id="dashboard" src="about:blank" style="display:none;"></iframe>
  <script>
    const vscode = acquireVsCodeApi();
    function startServer() { vscode.postMessage({ command: 'start' }); }
    function stopServer() { vscode.postMessage({ command: 'stop' }); }
    function installGateway() { vscode.postMessage({ command: 'install' }); }
  </script>
</body>
</html>`;
}

function updateStatusBar(running) {
  if (statusBarItem) {
    statusBarItem.text = running
      ? '$(robot) Panda AI ●'
      : '$(robot) Panda AI';
    statusBarItem.backgroundColor = undefined;
  }
}

module.exports = { activate, deactivate };
