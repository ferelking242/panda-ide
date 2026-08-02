/**
 * debug.js — API vscode.debug — Debug Adapter Protocol — Phase 12.
 *
 * Implémente l'API debug de VSCode côté JS.
 * Le vrai Debug Adapter est géré par DebugBridge.dart (DAP sur TCP).
 * Ce module est le proxy JS qui transmet les appels à Flutter.
 *
 * Référence : https://code.visualstudio.com/api/extension-guides/debugger-extension
 * DAP spec  : https://microsoft.github.io/debug-adapter-protocol/
 */

'use strict';

const ipc = require('../ipc.js');

// ── State ─────────────────────────────────────────────────────────────────────

const _debugConfigProviders = new Map();     // type → provider
const _debugAdapterFactories = new Map();    // type → factory
const _debugSessions = new Map();            // sessionId → session proxy
let _activeSession = null;

const _onDidStartSession_listeners   = [];
const _onDidTerminateSession_listeners = [];
const _onDidChangeActiveSession_listeners = [];
const _onDidReceiveCustomEvent_listeners = [];
const _onDidChangeBreakpoints_listeners  = [];

function _makeEvent(listeners) {
  return (listener) => {
    listeners.push(listener);
    return { dispose: () => { const i = listeners.indexOf(listener); if (i >= 0) listeners.splice(i, 1); } };
  };
}

function _fireEvent(listeners, data) {
  for (const l of listeners) { try { l(data); } catch (_) {} }
}

// ── DebugSession proxy ────────────────────────────────────────────────────────

function createSessionProxy(sessionId, name, type) {
  return {
    id: sessionId,
    name,
    type,
    workspaceFolder: undefined,
    configuration: {},
    parentSession: undefined,

    customRequest(command, args) {
      return ipc.callFlutter('vscode.debug.customRequest', [sessionId, command, args]);
    },

    getDebugProtocolBreakpoint(breakpoint) {
      return ipc.callFlutter('vscode.debug.getBreakpoint', [sessionId, breakpoint]);
    },
  };
}

// ── Events from Flutter ───────────────────────────────────────────────────────

ipc.onEvent('debug.sessionStarted', (data) => {
  const session = createSessionProxy(data.id, data.name, data.type);
  _debugSessions.set(data.id, session);
  _activeSession = session;
  _fireEvent(_onDidStartSession_listeners, session);
  _fireEvent(_onDidChangeActiveSession_listeners, session);
});

ipc.onEvent('debug.sessionTerminated', (data) => {
  const session = _debugSessions.get(data.id);
  if (session) {
    _debugSessions.delete(data.id);
    _fireEvent(_onDidTerminateSession_listeners, session);
  }
  if (_activeSession?.id === data.id) {
    _activeSession = null;
    _fireEvent(_onDidChangeActiveSession_listeners, null);
  }
});

// ── API publique ────────────────────────────────────────────────────────────

const debug = {
  /**
   * vscode.debug.registerDebugAdapterDescriptorFactory(type, factory)
   */
  registerDebugAdapterDescriptorFactory(type, factory) {
    _debugAdapterFactories.set(type, factory);

    // Handle Flutter asking for the adapter descriptor
    ipc.onCall(`debug.getAdapterDescriptor.${type}`, async (session, executable) => {
      try {
        const descriptor = await factory.createDebugAdapterDescriptor(session, executable);
        if (!descriptor) return null;

        // DebugAdapterExecutable
        if (descriptor.command) {
          return { type: 'executable', command: descriptor.command, args: descriptor.args ?? [] };
        }
        // DebugAdapterServer
        if (descriptor.port) {
          return { type: 'server', port: descriptor.port, host: descriptor.host ?? '127.0.0.1' };
        }
        // DebugAdapterInlineImplementation (advanced)
        return null;
      } catch (e) {
        process.stderr.write(`[vscode.debug] createDebugAdapterDescriptor error: ${e?.message ?? e}\n`);
        return null;
      }
    });

    return {
      dispose() {
        _debugAdapterFactories.delete(type);
      },
    };
  },

  /**
   * vscode.debug.registerDebugConfigurationProvider(type, provider, triggerKind?)
   */
  registerDebugConfigurationProvider(type, provider, triggerKind) {
    _debugConfigProviders.set(type, provider);

    // Handle Flutter asking for initial configurations
    ipc.onCall(`debug.provideConfigurations.${type}`, async (folder, token) => {
      try {
        return await provider.provideDebugConfigurations?.(folder, token) ?? [];
      } catch (e) {
        return [];
      }
    });

    // Handle Flutter asking to resolve a configuration
    ipc.onCall(`debug.resolveConfiguration.${type}`, async (folder, config, token) => {
      try {
        return await provider.resolveDebugConfiguration?.(folder, config, token) ?? config;
      } catch (e) {
        return config;
      }
    });

    return {
      dispose() {
        _debugConfigProviders.delete(type);
      },
    };
  },

  /**
   * vscode.debug.startDebugging(folder, nameOrConfig, parentSession?)
   */
  startDebugging(folder, nameOrConfig, parentSession) {
    const config = typeof nameOrConfig === 'string'
      ? { name: nameOrConfig, type: 'unknown', request: 'launch' }
      : (nameOrConfig ?? { name: 'Debug', type: 'unknown', request: 'launch' });

    return ipc.callFlutter('vscode.debug.start', [
      folder ? folder.uri?.toString?.() : null,
      config,
      parentSession?.id ?? null,
    ]).then(sessionId => !!sessionId);
  },

  /**
   * vscode.debug.stopDebugging(session?)
   */
  stopDebugging(session) {
    return ipc.callFlutter('vscode.debug.stop', [session?.id ?? null]);
  },

  get activeDebugSession() { return _activeSession; },
  get activeDebugConsole() {
    return {
      append: (value) => ipc.callFlutter('vscode.debug.console.append', [value]).catch(() => {}),
      appendLine: (value) => ipc.callFlutter('vscode.debug.console.appendLine', [value]).catch(() => {}),
    };
  },

  get breakpoints() { return _breakpoints; },

  addBreakpoints(breakpoints) {
    _breakpoints.push(...breakpoints);
    ipc.callFlutter('vscode.debug.addBreakpoints', [breakpoints]).catch(() => {});
  },

  removeBreakpoints(breakpoints) {
    const ids = new Set(breakpoints.map(b => b.id));
    _breakpoints = _breakpoints.filter(b => !ids.has(b.id));
    ipc.callFlutter('vscode.debug.removeBreakpoints', [breakpoints]).catch(() => {});
  },

  onDidChangeActiveDebugSession:        _makeEvent(_onDidChangeActiveSession_listeners),
  onDidStartDebugSession:               _makeEvent(_onDidStartSession_listeners),
  onDidTerminateDebugSession:           _makeEvent(_onDidTerminateSession_listeners),
  onDidReceiveDebugSessionCustomEvent:  _makeEvent(_onDidReceiveCustomEvent_listeners),
  onDidChangeBreakpoints:               _makeEvent(_onDidChangeBreakpoints_listeners),

  // Debug API types
  DebugAdapterExecutable: class {
    constructor(command, args, options) {
      this.command = command;
      this.args = args ?? [];
      this.options = options ?? {};
    }
  },
  DebugAdapterServer: class {
    constructor(port, host) {
      this.port = port;
      this.host = host ?? '127.0.0.1';
    }
  },
  BreakpointLocationsRequest: {},
};

let _breakpoints = [];

// Sync breakpoints from Flutter
ipc.onEvent('debug.breakpointsChanged', ({ added, removed, changed }) => {
  if (removed) {
    const removedIds = new Set((removed ?? []).map(b => b.id));
    _breakpoints = _breakpoints.filter(b => !removedIds.has(b.id));
  }
  if (added) _breakpoints.push(...(added ?? []));
  _fireEvent(_onDidChangeBreakpoints_listeners, { added: added ?? [], removed: removed ?? [], changed: changed ?? [] });
});

module.exports = debug;
