/**
 * scm.js — API vscode.scm — Phase 10.
 *
 * Source Control Management API.
 * Permet aux extensions Git/SCM de créer des SourceControl, des groupes
 * de ressources, et d'interagir avec l'input box.
 *
 * Référence : https://code.visualstudio.com/api/extension-guides/scm-provider
 */

'use strict';

const ipc = require('../ipc.js');

let _scmCounter = 0;
let _groupCounter = 0;

// ── ResourceGroup proxy ──────────────────────────────────────────────────────

function createResourceGroupProxy(scmId, groupId, label) {
  let _resourceStates = [];
  let _label = label;
  let _hideWhenEmpty = false;
  let _disposed = false;

  const proxy = {
    id: groupId,
    get label() { return _label; },
    set label(v) {
      _label = v;
      ipc.callFlutter('vscode.scm.updateGroup', [scmId, groupId, { label: v }]).catch(() => {});
    },

    get resourceStates() { return _resourceStates; },
    set resourceStates(states) {
      _resourceStates = states ?? [];
      ipc.callFlutter('vscode.scm.setResourceStates', [scmId, groupId,
        _resourceStates.map(r => ({
          resourceUri: r.resourceUri?.toString?.() ?? r.resourceUri,
          decorations: r.decorations ?? 0,
          tooltip: r.tooltip,
          letter: r.contextValue?.[0]?.toUpperCase(),
        }))
      ]).catch(() => {});
    },

    get hideWhenEmpty() { return _hideWhenEmpty; },
    set hideWhenEmpty(v) {
      _hideWhenEmpty = !!v;
      ipc.callFlutter('vscode.scm.updateGroup', [scmId, groupId, { hideWhenEmpty: _hideWhenEmpty }]).catch(() => {});
    },

    dispose() {
      if (_disposed) return;
      _disposed = true;
      ipc.callFlutter('vscode.scm.disposeGroup', [scmId, groupId]).catch(() => {});
    },
  };

  return proxy;
}

// ── SourceControl proxy ──────────────────────────────────────────────────────

function createSourceControlProxy(scmId, id, label, rootUri) {
  let _count;
  let _statusBarCommands;
  let _commitTemplate;
  let _acceptInputCommand;
  let _disposed = false;

  const inputBox = {
    get value() {
      // Synchronous read from local cache — updated via event
      return _inputBoxCache[scmId] ?? '';
    },
    set value(v) {
      _inputBoxCache[scmId] = v;
      ipc.callFlutter('vscode.scm.setInputBoxValue', [scmId, v]).catch(() => {});
    },
    get placeholder() { return _inputBoxPlaceholderCache[scmId] ?? 'Message'; },
    set placeholder(v) {
      _inputBoxPlaceholderCache[scmId] = v;
      ipc.callFlutter('vscode.scm.setInputBoxPlaceholder', [scmId, v]).catch(() => {});
    },
    visible: true,
    enabled: true,
  };

  const proxy = {
    id: scmId,

    get label() { return label; },

    get rootUri() { return rootUri; },

    get inputBox() { return inputBox; },

    get count() { return _count; },
    set count(v) {
      _count = v;
      ipc.callFlutter('vscode.scm.update', [scmId, { count: v }]).catch(() => {});
    },

    get statusBarCommands() { return _statusBarCommands; },
    set statusBarCommands(v) {
      _statusBarCommands = v;
      ipc.callFlutter('vscode.scm.update', [scmId, { statusBarCommands: v }]).catch(() => {});
    },

    get commitTemplate() { return _commitTemplate; },
    set commitTemplate(v) {
      _commitTemplate = v;
      ipc.callFlutter('vscode.scm.update', [scmId, { commitTemplate: v }]).catch(() => {});
    },

    get acceptInputCommand() { return _acceptInputCommand; },
    set acceptInputCommand(v) {
      _acceptInputCommand = v;
      ipc.callFlutter('vscode.scm.update', [scmId, { acceptInputCommand: v }]).catch(() => {});
    },

    createResourceGroup(rgId, rgLabel) {
      const fullGroupId = `${scmId}_${rgId}_${_groupCounter++}`;
      ipc.callFlutter('vscode.scm.createResourceGroup', [scmId, fullGroupId, rgLabel]).catch(() => {});
      return createResourceGroupProxy(scmId, fullGroupId, rgLabel);
    },

    dispose() {
      if (_disposed) return;
      _disposed = true;
      ipc.callFlutter('vscode.scm.dispose', [scmId]).catch(() => {});
    },
  };

  return proxy;
}

// ── Local state caches ────────────────────────────────────────────────────────

const _inputBoxCache = {};
const _inputBoxPlaceholderCache = {};

// Flutter → JS: sync input box value
ipc.onEvent('scm.inputBoxValue', ({ scmId, value }) => {
  _inputBoxCache[scmId] = value;
});

// ── API publique ────────────────────────────────────────────────────────────

const scm = {
  /**
   * vscode.scm.createSourceControl(id, label, rootUri?)
   */
  createSourceControl(id, label, rootUri) {
    const scmId = `scm_${id}_${_scmCounter++}`;

    ipc.callFlutter('vscode.scm.create', [{
      scmId,
      id,
      label,
      rootUri: rootUri?.toString?.() ?? rootUri ?? null,
    }]).catch(() => {});

    return createSourceControlProxy(scmId, id, label, rootUri);
  },

  // inputBox singleton (top-level vscode.scm.inputBox)
  get inputBox() {
    return {
      get value() { return _inputBoxCache['__global__'] ?? ''; },
      set value(v) { _inputBoxCache['__global__'] = v; },
      placeholder: 'Message',
      visible: true,
    };
  },
};

module.exports = scm;
