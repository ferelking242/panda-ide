/**
 * webview.js — API vscode.window WebView Panels — Phase 9.
 *
 * Gère la création de panels WebView, le postMessage bidirectionnel
 * et les événements de cycle de vie.
 *
 * Utilisé par vscode.js (importé comme module séparé pour garder vscode.js lisible).
 */

'use strict';

const ipc = require('../ipc.js');

let _panelCounter = 0;

// ── WebviewPanel proxy ──────────────────────────────────────────────────────

/**
 * Crée un proxy pour un WebviewPanel.
 * L'état réel est côté Flutter ; ce proxy est le handle côté JS.
 */
function createWebviewPanelProxy(panelId, viewType, title, options) {
  const webviewOptions = options?.webviewOptions ?? options ?? {};

  // EventEmitter pour les messages entrants depuis le WebView
  const onMessageEmitter = new _SimpleEmitter();
  const onDidDisposeEmitter = new _SimpleEmitter();
  const onDidChangeViewStateEmitter = new _SimpleEmitter();

  // Écoute les messages du WebView → IPC event 'webview.message.<panelId>'
  ipc.onEvent(`webview.message.${panelId}`, (data) => {
    onMessageEmitter.fire({ data });
  });

  // Écoute la disposition du panel
  ipc.onEvent(`webview.dispose.${panelId}`, () => {
    onDidDisposeEmitter.fire();
    panel._disposed = true;
  });

  // Écoute les changements de vue
  ipc.onEvent(`webview.viewStateChanged.${panelId}`, (state) => {
    onDidChangeViewStateEmitter.fire({ webviewPanel: panel, ...state });
  });

  const webview = {
    // Options
    options: webviewOptions,
    html: '',

    // Setter html → envoie à Flutter pour charger dans le WebView
    get html() { return this._html ?? ''; },
    set html(value) {
      this._html = value;
      ipc.callFlutter('vscode.webview.setHtml', [panelId, value]).catch(() => {});
    },

    // postMessage : extension → WebView
    postMessage(message) {
      return ipc.callFlutter('vscode.webview.postMessage', [panelId, message]);
    },

    // Événements
    onDidReceiveMessage: onMessageEmitter.event,

    // CSP source (stub)
    cspSource: 'https://vscode-cdn.net',

    asWebviewUri(localResource) {
      // Convert a local file URI to a webview URI — return as-is on Android
      return localResource;
    },
  };

  const panel = {
    panelId,
    viewType,
    title,
    _disposed: false,

    get webview() { return webview; },

    set title(newTitle) {
      this._title = newTitle;
      ipc.callFlutter('vscode.webview.setTitle', [panelId, newTitle]).catch(() => {});
    },
    get title() { return this._title ?? title; },

    // reveal(viewColumn?, preserveFocus?)
    reveal(viewColumn, preserveFocus) {
      ipc.callFlutter('vscode.webview.reveal', [panelId, viewColumn ?? 1, preserveFocus ?? false])
        .catch(() => {});
    },

    dispose() {
      if (this._disposed) return;
      this._disposed = true;
      ipc.callFlutter('vscode.webview.dispose', [panelId]).catch(() => {});
      onDidDisposeEmitter.fire();
    },

    // Events
    onDidDispose: onDidDisposeEmitter.event,
    onDidChangeViewState: onDidChangeViewStateEmitter.event,

    // Serializer (Phase 9 — stub for restore)
    get visible() { return !this._disposed; },
    get active()  { return !this._disposed; },
  };

  return panel;
}

// ── Simple EventEmitter for WebView ────────────────────────────────────────

class _SimpleEmitter {
  constructor() {
    this._listeners = [];
    this.event = (listener) => {
      this._listeners.push(listener);
      return { dispose: () => { this._listeners = this._listeners.filter(l => l !== listener); } };
    };
  }
  fire(data) {
    for (const l of this._listeners) {
      try { l(data); } catch (e) {}
    }
  }
}

// ── API publique ────────────────────────────────────────────────────────────

module.exports = {
  /**
   * vscode.window.createWebviewPanel(viewType, title, showOptions, options?)
   */
  createWebviewPanel(viewType, title, showOptions, options) {
    const panelId = `webview_panel_${_panelCounter++}`;
    const retain = options?.retainContextWhenHidden ?? false;
    const enableScripts = options?.webviewOptions?.enableScripts ??
                          options?.enableScripts ?? true;
    const localResourceRoots = options?.webviewOptions?.localResourceRoots ??
                                options?.localResourceRoots ?? [];

    // Demande à Flutter de créer le WebView
    ipc.callFlutter('vscode.webview.create', [{
      panelId,
      viewType,
      title,
      showOptions: typeof showOptions === 'number'
        ? { viewColumn: showOptions }
        : (showOptions ?? { viewColumn: 1 }),
      options: {
        retainContextWhenHidden: retain,
        enableScripts,
        localResourceRoots: localResourceRoots.map(u => u.toString?.() ?? u),
      },
    }]).catch(() => {});

    return createWebviewPanelProxy(panelId, viewType, title, options);
  },

  /**
   * vscode.window.registerWebviewPanelSerializer(viewType, serializer)
   * Phase 9 — stub (no session restore on Android for now)
   */
  registerWebviewPanelSerializer(viewType, serializer) {
    // No-op: we don't persist webview state across app restarts yet
    return { dispose: () => {} };
  },
};
