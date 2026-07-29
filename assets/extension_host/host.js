/**
 * host.js — Entry point du process Node.js Extension Host.
 *
 * Lancé par ExtensionHostManager.activate() via :
 *   node host.js /path/to/extension/main.js
 *
 * Responsabilités :
 *   1. Injecter le module `vscode` dans le cache require() AVANT de charger l'extension
 *   2. Charger l'extension et exposer ses exports via l'IPC
 *   3. Gérer activate() / deactivate() reçus depuis Flutter
 *   4. Gérer les erreurs proprement (exit code 1 + message sur stderr)
 *
 * Environnement fourni par ExtensionHostManager :
 *   PANDA_EXT_ID      : "publisher.name"
 *   PANDA_EXT_PATH    : chemin absolu vers le dossier de l'extension
 *   PANDA_EXT_VERSION : version semver de l'extension
 */

'use strict';

// ── 0. Résolution des chemins ─────────────────────────────────────────────

const path = require('path');

// Le chemin de l'entry point de l'extension est le premier argument CLI
const extensionEntryPoint = process.argv[2];

if (!extensionEntryPoint) {
  process.stderr.write('[host] FATAL: No extension entry point provided.\n');
  process.stderr.write('[host] Usage: node host.js /path/to/extension/main.js\n');
  process.exit(1);
}

// Chemin du dossier host.js (assets/extension_host/)
const HOST_DIR = __dirname;

// ── 1. Injection du module `vscode` dans require.cache ────────────────────

// On injecte AVANT tout require() de l'extension
// L'ordre est crucial : l'extension peut faire `require('vscode')` dès son
// module level (hors de activate()), donc on doit être prêts avant.

const ipc    = require(path.join(HOST_DIR, 'ipc.js'));
const vscode = require(path.join(HOST_DIR, 'api', 'vscode.js'));

// Injecter dans le cache require() sous 'vscode'
require.cache['vscode'] = {
  id:       'vscode',
  filename: 'vscode',
  loaded:   true,
  exports:  vscode,
  paths:    [],
  children: [],
  parent:   null,
};

// ── 2. Chargement de l'extension ──────────────────────────────────────────

let extensionModule;
try {
  extensionModule = require(extensionEntryPoint);
} catch (err) {
  process.stderr.write(`[host] FATAL: Failed to load extension "${extensionEntryPoint}":\n`);
  process.stderr.write(`[host] ${err.stack || err.message || err}\n`);
  process.exit(1);
}

// ── 3. Handlers IPC : activate / deactivate ───────────────────────────────

ipc.onCall('activate', async (context) => {
  if (typeof extensionModule.activate !== 'function') {
    // L'extension n'exporte pas de fonction activate — c'est valide (ex: themes)
    return null;
  }

  try {
    const result = await extensionModule.activate(context ?? {});
    // Notifie Flutter que l'activation a réussi
    return result ?? null;
  } catch (err) {
    process.stderr.write(`[host][${process.env.PANDA_EXT_ID}] activate() failed:\n`);
    process.stderr.write(`[host] ${err.stack || err.message || err}\n`);
    throw err;
  }
});

ipc.onCall('deactivate', async () => {
  if (typeof extensionModule.deactivate !== 'function') {
    return null;
  }
  try {
    await extensionModule.deactivate();
    return null;
  } catch (err) {
    process.stderr.write(`[host][${process.env.PANDA_EXT_ID}] deactivate() failed:\n`);
    process.stderr.write(`[host] ${err.stack || err.message || err}\n`);
    // On ne re-throw pas lors de deactivate — on ferme quand même proprement
    return null;
  }
});

// Handler générique pour les commandes invoquées par Flutter
ipc.onEvent('command.invoke', ({ command, args }) => {
  // Les extensions enregistrent leurs commandes via vscode.commands.registerCommand()
  // qui ajoute un handler dans le module vscode. Rien à faire ici directement.
});

// ── 4. Gestion des erreurs non capturées ──────────────────────────────────

process.on('uncaughtException', (err) => {
  process.stderr.write(`[host][${process.env.PANDA_EXT_ID}] uncaughtException:\n`);
  process.stderr.write(`[host] ${err.stack || err.message || err}\n`);
  // On ne quitte PAS — l'extension peut avoir des erreurs non fatales
  // et continuer à fonctionner pour le reste de ses features.
});

process.on('unhandledRejection', (reason) => {
  process.stderr.write(`[host][${process.env.PANDA_EXT_ID}] unhandledRejection:\n`);
  process.stderr.write(`[host] ${String(reason?.stack ?? reason)}\n`);
});

// ── 5. Heartbeat (optionnel) ──────────────────────────────────────────────
// Flutter peut envoyer un event 'ping' pour vérifier que le process est vivant.
ipc.onEvent('ping', () => {
  ipc.fireEvent('pong', { extId: process.env.PANDA_EXT_ID, ts: Date.now() });
});

// ── Prêt ──────────────────────────────────────────────────────────────────
// Le process est maintenant en attente de messages sur stdin.
// La boucle readline dans ipc.js gère la suite.
process.stderr.write(`[host] Ready — extension: ${process.env.PANDA_EXT_ID ?? 'unknown'}\n`);
