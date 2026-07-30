/**
 * Mock IPC bridge for Jest tests.
 * Simulates the Flutter ↔ Node.js communication without a real process.
 */
'use strict';

const _callHandlers = new Map();   // method → handler
const _eventHandlers = new Map();  // event → [handlers]
const _callLog = [];
const _eventLog = [];

// Records of all flutter calls made (for assertions)
const flutterCalls = [];

const ipc = {
  // ── Called by JS modules to invoke Flutter ────────────────────────────────
  callFlutter(method, params = []) {
    flutterCalls.push({ method, params });
    return Promise.resolve(_mockFlutterResponse(method, params));
  },

  // ── Called by JS modules to register call handlers ────────────────────────
  onCall(method, handler) {
    _callHandlers.set(method, handler);
  },

  // ── Called by JS modules to register event handlers ──────────────────────
  onEvent(event, handler) {
    const list = _eventHandlers.get(event) ?? [];
    list.push(handler);
    _eventHandlers.set(event, list);
  },

  // ── Called by JS modules to fire events to extensions ────────────────────
  fireEvent(event, data) {
    _eventLog.push({ event, data });
  },

  // ── Test helpers ──────────────────────────────────────────────────────────

  /**
   * Simulate Flutter calling a registered call handler.
   * e.g. ipc._simulateCall('provider.abc.invoke', args)
   */
  async _simulateCall(method, ...args) {
    const handler = _callHandlers.get(method);
    if (!handler) throw new Error(`No handler for: ${method}`);
    return handler(...args);
  },

  /**
   * Simulate Flutter firing an event to the extension.
   * e.g. ipc._simulateEvent('onDidChangeActiveTextEditor', editorData)
   */
  _simulateEvent(event, data) {
    const handlers = _eventHandlers.get(event) ?? [];
    for (const h of handlers) { try { h(data); } catch (_) {} }
  },

  /** Returns all callFlutter() invocations. */
  get calls() { return flutterCalls; },

  /** Clears the call log (use in beforeEach). */
  _reset() {
    flutterCalls.length = 0;
    _callHandlers.clear();
    _eventHandlers.clear();
  },
};

/**
 * Default mock responses for common Flutter calls.
 * Tests can override by monkey-patching ipc.callFlutter.
 */
function _mockFlutterResponse(method, params) {
  switch (method) {
    case 'vscode.window.showInformationMessage':
    case 'vscode.window.showWarningMessage':
    case 'vscode.window.showErrorMessage':
      return params.find(p => typeof p === 'string' && p !== params[0]) ?? null;
    case 'vscode.window.showInputBox':
      return 'mocked-input';
    case 'vscode.window.showQuickPick':
      return params[0]?.[0] ?? null;
    case 'vscode.env.clipboard.read':
      return '';
    case 'vscode.env.clipboard.write':
      return null;
    case 'vscode.env.openExternal':
      return true;
    case 'vscode.workspace.configuration.get':
      return { items: {} };
    case 'vscode.languages.getLanguages':
      return ['javascript', 'typescript', 'python', 'dart'];
    case 'vscode.commands.getAll':
      return [];
    case 'vscode.tasks.execute':
      return 'exec_1';
    case 'vscode.debug.start':
      return 'session_1';
    default:
      return null;
  }
}

module.exports = ipc;
