/**
 * Module `vscode` — shim complet pour les extensions VSCode.
 *
 * Ce fichier est le module que les extensions importent via `require('vscode')`.
 * Il est injecté dans le require cache par host.js AVANT que l'extension soit chargée.
 *
 * Architecture :
 *   - Les appels vscode.* qui nécessitent une réponse de l'IDE → callFlutter()
 *   - Les événements de l'IDE vers l'extension → EventEmitter.fire() déclenché par onEvent()
 *   - Les types purs (Uri, Range, etc.) → pas de communication, instanciés localement
 *
 * Phases d'implémentation :
 *   Phase 1 (ce fichier) : structure complète + stubs pour toutes les APIs
 *   Phase 2 : window.* pleinement fonctionnel
 *   Phase 3 : workspace.* pleinement fonctionnel
 *   Phase 4 : languages.* pleinement fonctionnel
 *   Phase 5+ : commands, scm, tasks, debug, etc.
 *
 * Chaque namespace qui n'est pas encore implémenté retourne un stub qui :
 *   - Logge un avertissement lisible (pas d'erreur silencieuse)
 *   - Retourne une valeur sûre (Disposable vide, Promise résolue, etc.)
 */

'use strict';

const ipc     = require('../ipc.js'); // ipc.js est dans assets/extension_host/, pas dans api/
const types   = require('./types.js');
const webview = require('./webview.js');
const scmImpl  = require('./scm.js');
const tasksImpl = require('./tasks.js');
const debugImpl = require('./debug.js');

// ── Helpers internes ──────────────────────────────────────────────────────

function _stub(namespace, method) {
  return (...args) => {
    process.stderr.write(`[vscode shim] STUB: ${namespace}.${method}() called but not yet implemented.\n`);
    return Promise.resolve(undefined);
  };
}

function _stubDisposable(namespace, method) {
  return (...args) => {
    process.stderr.write(`[vscode shim] STUB: ${namespace}.${method}() called but not yet implemented.\n`);
    return new types.Disposable(() => {});
  };
}

let _statusBarItemCounter = 0;
let _decoCnt = 0;

// ── vscode.window ─────────────────────────────────────────────────────────
// Phase 2 : implémentation complète
// Phase 1 : stubs fonctionnels (callFlutter pour les messages)

const window = {
  // Messages
  showInformationMessage: (message, ...items) =>
    ipc.callFlutter('vscode.window.showInformationMessage', [message, ...items]),
  showWarningMessage: (message, ...items) =>
    ipc.callFlutter('vscode.window.showWarningMessage', [message, ...items]),
  showErrorMessage: (message, ...items) =>
    ipc.callFlutter('vscode.window.showErrorMessage', [message, ...items]),

  // Input
  showInputBox: (options = {}) =>
    ipc.callFlutter('vscode.window.showInputBox', [options]),
  showQuickPick: (items, options = {}) =>
    ipc.callFlutter('vscode.window.showQuickPick', [
      Array.isArray(items) ? items : [], options,
    ]),
  showOpenDialog: (options = {}) =>
    ipc.callFlutter('vscode.window.showOpenDialog', [options]),
  showSaveDialog: (options = {}) =>
    ipc.callFlutter('vscode.window.showSaveDialog', [options]),

  // Output channel
  createOutputChannel: (name, languageIdOrOptions) => {
    ipc.callFlutter('vscode.window.outputChannel.create', [name]);
    return new types.OutputChannel(name, ipc);
  },

  // Status bar
  createStatusBarItem: (alignmentOrId, priorityOrAlignment, priority) => {
    const id = typeof alignmentOrId === 'string'
      ? alignmentOrId
      : `statusBarItem_${_statusBarItemCounter++}`;
    const alignment = typeof alignmentOrId === 'number'
      ? alignmentOrId : (typeof priorityOrAlignment === 'number' ? types.StatusBarAlignment.Left : priorityOrAlignment ?? types.StatusBarAlignment.Left);
    const prio = priority ?? (typeof priorityOrAlignment === 'number' ? priorityOrAlignment : 0);
    ipc.callFlutter('vscode.window.statusBarItem.create', [id, alignment, prio]);
    return new types.StatusBarItem(id, alignment, prio, ipc);
  },

  // Progress
  withProgress: (options, task) =>
    ipc.callFlutter('vscode.window.withProgress.start', [options]).then(() => {
      let _resolve;
      const progressToken = { isCancellationRequested: false, onCancellationRequested: new types.EventEmitter().event };
      const progress = {
        report: (value) => ipc.callFlutter('vscode.window.withProgress.report', [value]),
      };
      return Promise.resolve(task(progress, progressToken))
        .finally(() => ipc.callFlutter('vscode.window.withProgress.end', []));
    }),

  // Text editors (read-only access via Flutter)
  get activeTextEditor() {
    // Synchronous access — retourne le proxy de l'éditeur actif
    // L'état est maintenu via events (onDidChangeActiveTextEditor)
    return _activeEditor;
  },
  get visibleTextEditors() { return _visibleEditors; },

  showTextDocument: (documentOrUri, options) =>
    ipc.callFlutter('vscode.window.showTextDocument', [
      documentOrUri instanceof types.Uri ? documentOrUri.toJSON() : documentOrUri,
      options,
    ]),

  // Events (branchés sur les events venant de Flutter)
  onDidChangeActiveTextEditor:      _makeEditorEvent('onDidChangeActiveTextEditor'),
  onDidChangeVisibleTextEditors:    _makeEditorEvent('onDidChangeVisibleTextEditors'),
  onDidChangeTextEditorSelection:   _makeEditorEvent('onDidChangeTextEditorSelection'),
  onDidChangeTextEditorViewColumn:  _makeEditorEvent('onDidChangeTextEditorViewColumn'),
  onDidChangeTextEditorOptions:     _makeEditorEvent('onDidChangeTextEditorOptions'),
  onDidChangeWindowState:           _makeEditorEvent('onDidChangeWindowState'),

  // Decorations (Phase 2)
  createTextEditorDecorationType:(o)=>{const id=`deco-${_decoCnt++}`;return{id,dispose:()=>ipc.callFlutter('vscode.window.deco.dispose',[id])};},

  // Webview Panels (Phase 9) — implémentation complète via webview.js
  createWebviewPanel: (viewType, title, showOptions, options) =>
    webview.createWebviewPanel(viewType, title, showOptions, options),
  registerWebviewPanelSerializer: (viewType, serializer) =>
    webview.registerWebviewPanelSerializer(viewType, serializer),
  createWebviewView: (vt,t,so,opts)=>{const vid=`wvv-${vt}-${Date.now()}`;ipc.callFlutter('vscode.window.webviewView.create',[vid,vt,t,so,opts]);return{webview:{html:'',options:opts||{},cspSource:'',asWebviewUri:(u)=>u,postMessage:(m)=>ipc.callFlutter('vscode.window.webviewView.postMessage',[vid,m]),onDidReceiveMessage:new types.EventEmitter().event},visible:true,onDidDispose:new types.EventEmitter().event,onDidChangeVisibility:new types.EventEmitter().event,show:(p)=>ipc.callFlutter('vscode.window.webviewView.show',[vid,!!p]),dispose:()=>ipc.callFlutter('vscode.window.webviewView.dispose',[vid])};},

  // Tree views (Phase 8 — stub, TreeDataProvider is pull-model via commands)
  createTreeView: (tid, opts) => { const vid=`tree-${tid}-${Date.now()}`; ipc.callFlutter('vscode.window.treeView.create',[vid,tid,opts]); return {onDidChangeSelection:new types.EventEmitter().event,onDidChangeVisibility:new types.EventEmitter().event,onDidExpandElement:new types.EventEmitter().event,onDidCollapseElement:new types.EventEmitter().event,reveal:(el,o)=>ipc.callFlutter('vscode.window.treeView.reveal',[vid,el,o]),dispose:()=>ipc.callFlutter('vscode.window.treeView.dispose',[vid])}; },
  registerTreeDataProvider: (tid, prov) => { const pid=`tdp-${tid}-${Date.now()}`; ipc.onCall(`${pid}.getChildren`,async(e)=>{try{return await prov.getChildren(e)??[]}catch(x){return[]}}); ipc.onCall(`${pid}.getParent`,async(e)=>{try{return await prov.getParent(e)??null}catch(x){return null}}); ipc.onCall(`${pid}.getTreeItem`,async(e)=>{try{return await prov.getTreeItem(e)}catch(x){return null}}); ipc.callFlutter('vscode.window.treeDataProvider.register',[pid,tid]); return new types.Disposable(()=>{ipc.callFlutter('vscode.window.treeDataProvider.unregister',[pid])}); },

  // Terminal
  createTerminal: (options = {}) => {
    ipc.callFlutter('vscode.window.terminal.create', [options]);
    return _makeTerminalProxy(options.name ?? 'Extension Terminal');
  },
  get terminals() { return []; },
  get activeTerminal() { return null; },
  onDidOpenTerminal:  _makeEditorEvent('onDidOpenTerminal'),
  onDidCloseTerminal: _makeEditorEvent('onDidCloseTerminal'),

  // State
  get state() { return { focused: true }; },
};

// ── vscode.workspace ──────────────────────────────────────────────────────
// Phase 3 : implémentation complète

const workspace = {
  get workspaceFolders() { return _workspaceFolders; },
  get name()    { return _workspaceName; },
  get rootPath(){ return _workspaceFolders?.[0]?.uri.fsPath; },

  getWorkspaceFolder: (uri) => {
    const uriStr = uri.toString();
    return _workspaceFolders?.find(f => uriStr.startsWith(f.uri.toString())) ?? null;
  },

  getConfiguration: (section, scope) =>
    _makeConfigProxy(section, scope),

  onDidChangeConfiguration: _makeWorkspaceEvent('onDidChangeConfiguration'),
  onDidChangeWorkspaceFolders: _makeWorkspaceEvent('onDidChangeWorkspaceFolders'),

  // Fichiers
  openTextDocument: (uriOrPath) => {
    const arg = uriOrPath instanceof types.Uri ? uriOrPath.toJSON()
      : typeof uriOrPath === 'string' ? types.Uri.file(uriOrPath).toJSON()
      : uriOrPath; // { language, content }
    return ipc.callFlutter('vscode.workspace.openTextDocument', [arg]);
  },

  saveAll: (includeUntitled = false) =>
    ipc.callFlutter('vscode.workspace.saveAll', [includeUntitled]),

  applyEdit: (edit) =>
    ipc.callFlutter('vscode.workspace.applyEdit', [edit.toJSON()]),

  findFiles: (include, exclude, maxResults, token) =>
    ipc.callFlutter('vscode.workspace.findFiles', [include.toString?.() ?? include, exclude?.toString?.() ?? exclude, maxResults ?? null]),

  createFileSystemWatcher: (globPattern, ignoreCreate, ignoreChange, ignoreDelete) => {
    const watcher = new types.FileSystemWatcher(globPattern.toString?.() ?? globPattern, ipc);
    watcher.ignoreCreateEvents = !!ignoreCreate;
    watcher.ignoreChangeEvents = !!ignoreChange;
    watcher.ignoreDeleteEvents = !!ignoreDelete;
    ipc.callFlutter('vscode.workspace.fileWatcher.create', [globPattern.toString?.() ?? globPattern]);
    return watcher;
  },

  onDidOpenTextDocument:   _makeWorkspaceEvent('onDidOpenTextDocument'),
  onDidCloseTextDocument:  _makeWorkspaceEvent('onDidCloseTextDocument'),
  onDidChangeTextDocument: _makeWorkspaceEvent('onDidChangeTextDocument'),
  onDidSaveTextDocument:   _makeWorkspaceEvent('onDidSaveTextDocument'),
  onWillSaveTextDocument:  _makeWorkspaceEvent('onWillSaveTextDocument'),
  onDidCreateFiles:        _makeWorkspaceEvent('onDidCreateFiles'),
  onDidDeleteFiles:        _makeWorkspaceEvent('onDidDeleteFiles'),
  onDidRenameFiles:        _makeWorkspaceEvent('onDidRenameFiles'),

  // FileSystem API (Phase 3)
  fs: {
    stat:      (uri) => ipc.callFlutter('vscode.workspace.fs.stat',      [uri.toJSON()]),
    readDirectory: (uri) => ipc.callFlutter('vscode.workspace.fs.readDirectory', [uri.toJSON()]),
    createDirectory: (uri) => ipc.callFlutter('vscode.workspace.fs.createDirectory', [uri.toJSON()]),
    readFile:  (uri) => ipc.callFlutter('vscode.workspace.fs.readFile',  [uri.toJSON()]),
    writeFile: (uri, content) => ipc.callFlutter('vscode.workspace.fs.writeFile', [uri.toJSON(), Array.from(content)]),
    delete:    (uri, options) => ipc.callFlutter('vscode.workspace.fs.delete', [uri.toJSON(), options]),
    rename:    (source, target, options) => ipc.callFlutter('vscode.workspace.fs.rename', [source.toJSON(), target.toJSON(), options]),
    copy:      (source, target, options) => ipc.callFlutter('vscode.workspace.fs.copy', [source.toJSON(), target.toJSON(), options]),
    isWritableFileSystem: (scheme) => ipc.callFlutter('vscode.workspace.fs.isWritable', [scheme]),
  },

  textDocuments: [],

  registerTextDocumentContentProvider:(s,p)=>{const pid=`cdp-${s}-${Date.now()}`;ipc.onCall(`${pid}.provide`,async(u)=>{try{return await p.provideTextDocumentContent(u)}catch(e){return''}});ipc.callFlutter('vscode.workspace.contentProvider.register',[pid,s]);return new types.Disposable(()=>{ipc.callFlutter('vscode.workspace.contentProvider.unregister',[pid])});},
  registerFileSystemProvider:(s,p,o)=>{const pid=`fsp-${s}-${Date.now()}`;for(const m of['stat','readDirectory','readFile','writeFile','createDirectory','delete','rename','copy']){ipc.onCall(`${pid}.${m}`,async(...a)=>{try{return await p[m](...a)}catch(e){return null}});}ipc.callFlutter('vscode.workspace.fsProvider.register',[pid,s,o]);return new types.Disposable(()=>{ipc.callFlutter('vscode.workspace.fsProvider.unregister',[pid])});},
};

// ── vscode.languages ──────────────────────────────────────────────────────
// Phase 4 : implémentation complète

const _langProviderCounter = { value: 0 };

/**
 * Modèle pull : Flutter appelle 'provider.<id>.invoke' pour invoquer le provider.
 * Toutes les invocations (completions, hover, définition, …) utilisent le même
 * endpoint .invoke — les args différencient la méthode selon le type de provider.
 */
function _registerProvider(apiMethod, selector, handler, ...extraArgs) {
  const id = `${apiMethod}_${_langProviderCounter.value++}`;

  // Handler pull — Flutter appelle 'provider.<id>.invoke' avec les arguments sérialisés
  ipc.onCall(`provider.${id}.invoke`, async (...args) => {
    try {
      return await handler(...args) ?? null;
    } catch (e) {
      throw new Error(e?.message ?? String(e));
    }
  });

  // Informer Flutter du nouveau provider (selector, trigger chars, etc.)
  ipc.callFlutter(`vscode.languages.${apiMethod}.register`, [id, selector, ...extraArgs]);

  return new types.Disposable(() => {
    ipc.callFlutter(`vscode.languages.${apiMethod}.unregister`, [id]);
  });
}

const languages = {
  createDiagnosticCollection: (name = 'default') =>
    new types.DiagnosticCollection(name, ipc),

  registerCompletionItemProvider: (selector, provider, ...triggerCharacters) =>
    _registerProvider('completionItemProvider', selector,
      (doc, pos, token, ctx) => provider.provideCompletionItems(doc, new types.Position(pos.line, pos.character), token, ctx),
      triggerCharacters),

  registerHoverProvider: (selector, provider) =>
    _registerProvider('hoverProvider', selector,
      (doc, pos, token) => provider.provideHover(doc, new types.Position(pos.line, pos.character), token)),

  registerDefinitionProvider: (selector, provider) =>
    _registerProvider('definitionProvider', selector,
      (doc, pos, token) => provider.provideDefinition(doc, new types.Position(pos.line, pos.character), token)),

  registerDeclarationProvider: (selector, provider) =>
    _registerProvider('declarationProvider', selector,
      (doc, pos, token) => provider.provideDeclaration(doc, new types.Position(pos.line, pos.character), token)),

  registerReferenceProvider: (selector, provider) =>
    _registerProvider('referenceProvider', selector,
      (doc, pos, token, ctx) => provider.provideReferences(doc, new types.Position(pos.line, pos.character), ctx, token)),

  registerDocumentFormattingEditProvider: (selector, provider) =>
    _registerProvider('formattingProvider', selector,
      (doc, options, token) => provider.provideDocumentFormattingEdits(doc, options, token)),

  registerDocumentRangeFormattingEditProvider: (selector, provider) =>
    _registerProvider('rangeFormattingProvider', selector,
      (doc, range, options, token) => provider.provideDocumentRangeFormattingEdits(doc, new types.Range(range.start.line, range.start.character, range.end.line, range.end.character), options, token)),

  registerOnTypeFormattingEditProvider: (selector, provider, firstTriggerCharacter, ...moreTriggerCharacter) =>
    _registerProvider('onTypeFormattingProvider', selector,
      (doc, pos, ch, options, token) => provider.provideOnTypeFormattingEdits(doc, new types.Position(pos.line, pos.character), ch, options, token),
      [firstTriggerCharacter, ...moreTriggerCharacter]),

  registerCodeActionsProvider: (selector, provider, metadata) =>
    _registerProvider('codeActionsProvider', selector,
      (doc, range, ctx, token) => provider.provideCodeActions(doc, new types.Range(range.start.line, range.start.character, range.end.line, range.end.character), ctx, token),
      metadata),

  registerCodeLensProvider: (selector, provider) =>
    _registerProvider('codeLensProvider', selector,
      (doc, token) => provider.provideCodeLenses(doc, token)),

  registerDocumentSymbolProvider: (selector, provider, metadata) =>
    _registerProvider('documentSymbolProvider', selector,
      (doc, token) => provider.provideDocumentSymbols(doc, token),
      metadata),

  registerWorkspaceSymbolProvider: (provider) =>
    _registerProvider('workspaceSymbolProvider', null,
      (query, token) => provider.provideWorkspaceSymbols(query, token)),

  registerDocumentHighlightProvider: (selector, provider) =>
    _registerProvider('documentHighlightProvider', selector,
      (doc, pos, token) => provider.provideDocumentHighlights(doc, new types.Position(pos.line, pos.character), token)),

  registerRenameProvider: (selector, provider) =>
    _registerProvider('renameProvider', selector,
      (doc, pos, newName, token) => provider.provideRenameEdits(doc, new types.Position(pos.line, pos.character), newName, token)),

  registerSignatureHelpProvider: (selector, provider, ...triggerChars) =>
    _registerProvider('signatureHelpProvider', selector,
      (doc, pos, token, ctx) => provider.provideSignatureHelp(doc, new types.Position(pos.line, pos.character), token, ctx),
      triggerChars),

  registerImplementationProvider: (selector, provider) =>
    _registerProvider('implementationProvider', selector,
      (doc, pos, token) => provider.provideImplementation(doc, new types.Position(pos.line, pos.character), token)),

  registerTypeDefinitionProvider: (selector, provider) =>
    _registerProvider('typeDefinitionProvider', selector,
      (doc, pos, token) => provider.provideTypeDefinition(doc, new types.Position(pos.line, pos.character), token)),

  registerFoldingRangeProvider: (selector, provider) =>
    _registerProvider('foldingRangeProvider', selector,
      (doc, ctx, token) => provider.provideFoldingRanges(doc, ctx, token)),

  registerSelectionRangeProvider: (selector, provider) =>
    _registerProvider('selectionRangeProvider', selector,
      (doc, positions, token) => provider.provideSelectionRanges(doc, positions.map(p => new types.Position(p.line, p.character)), token)),

  registerCallHierarchyProvider: (selector, provider) =>
    _registerProvider('callHierarchyProvider', selector,
      (doc, pos, token) => provider.prepareCallHierarchy(doc, new types.Position(pos.line, pos.character), token)),

  registerInlayHintsProvider: (selector, provider) =>
    _registerProvider('inlayHintsProvider', selector,
      (doc, range, token) => provider.provideInlayHints(doc, new types.Range(range.start.line, range.start.character, range.end.line, range.end.character), token)),

  registerLinkedEditingRangeProvider: (selector, provider) =>
    _registerProvider('linkedEditingRangeProvider', selector,
      (doc, pos, token) => provider.provideLinkedEditingRanges(doc, new types.Position(pos.line, pos.character), token)),

  setLanguageConfiguration: (language, configuration) => {
    ipc.callFlutter('vscode.languages.setLanguageConfiguration', [language, configuration]);
    return new types.Disposable(() => {});
  },

  getLanguages: () =>
    ipc.callFlutter('vscode.languages.getLanguages', []),

  match: (selector, document) => {
    // Synchronous match — simplified (full scoring non-implémenté en Phase 1)
    if (typeof selector === 'string') return selector === document?.languageId ? 10 : 0;
    if (Array.isArray(selector)) return selector.some(s => languages.match(s, document)) ? 10 : 0;
    if (selector?.language && selector.language !== document?.languageId) return 0;
    return 10;
  },

  getDiagnostics: (uri) =>
    ipc.callFlutter('vscode.languages.getDiagnostics', [uri ? uri.toJSON() : null]),

  onDidChangeDiagnostics: _makeWorkspaceEvent('onDidChangeDiagnostics'),
};

// ── vscode.commands ───────────────────────────────────────────────────────
// Phase 5

const _commandHandlers = new Map();

const commands = {
  registerCommand: (command, callback, thisArg) => {
    _commandHandlers.set(command, thisArg ? callback.bind(thisArg) : callback);
    ipc.callFlutter('vscode.commands.register', [command]);
    return new types.Disposable(() => {
      _commandHandlers.delete(command);
      ipc.callFlutter('vscode.commands.unregister', [command]);
    });
  },

  registerTextEditorCommand: (command, callback, thisArg) =>
    commands.registerCommand(command, (...args) => {
      const editor = window.activeTextEditor;
      if (editor) callback.call(thisArg, editor, editor.selection, ...args);
    }),

  executeCommand: (command, ...rest) => {
    // Essaie d'abord les handlers locaux (enregistrés par cette extension)
    const local = _commandHandlers.get(command);
    if (local) return Promise.resolve(local(...rest));
    // Sinon, demande à Flutter d'exécuter la commande
    return ipc.callFlutter('vscode.commands.execute', [command, ...rest]);
  },

  getCommands: (filterInternal = false) =>
    ipc.callFlutter('vscode.commands.getAll', [filterInternal]),
};

// Quand Flutter invoque une commande enregistrée par cette extension
ipc.onEvent('command.invoke', ({ command, args }) => {
  const handler = _commandHandlers.get(command);
  if (handler) {
    Promise.resolve(handler(...(args || []))).catch(e => {
      process.stderr.write(`[vscode shim] Command "${command}" failed: ${e?.message || e}\n`);
    });
  }
});

// ── vscode.extensions ─────────────────────────────────────────────────────
// Phase 6

const extensions = {
  getExtension: (extensionId) =>
    ipc.callFlutter('vscode.extensions.get', [extensionId]),
  get all() {
    // Synchronous — retourne cache local (mis à jour via events)
    return _extensionsCache;
  },
  onDidChange: _makeEditorEvent('onDidChangeExtensions'),
};
let _extensionsCache = [];

// ── vscode.env ────────────────────────────────────────────────────────────
// Phase 7

const env = {
  get appName()    { return 'Panda IDE'; },
  get appRoot()    { return process.env.PANDA_EXT_PATH ?? ''; },
  get language()   { return 'en'; },
  get machineId()  { return process.env.PANDA_MACHINE_ID ?? 'panda-android'; },
  get sessionId()  { return process.env.PANDA_SESSION_ID ?? 'panda-session'; },
  get isNewAppInstall() { return false; },
  get isTelemetryEnabled() { return false; },
  get uiKind()     { return 1; /* UIKind.Desktop */ },
  get shell()      { return '/data/data/com.panda.ide/runtimes/bash/bin/bash'; },
  get remoteName() { return undefined; },
  get logLevel()   { return types.LogLevel.Info; },
  get onDidChangeTelemetryEnabled() { return new types.EventEmitter().event; },

  clipboard: {
    readText:  ()     => ipc.callFlutter('vscode.env.clipboard.read',  []),
    writeText: (text) => ipc.callFlutter('vscode.env.clipboard.write', [text]),
  },

  openExternal: (uri) =>
    ipc.callFlutter('vscode.env.openExternal', [uri.toJSON?.() ?? uri]),

  asExternalUri: (uri) => Promise.resolve(uri),

  createTelemetryLogger:()=>({sendUsageData:()=>{},sendErrorData:()=>{},logUsage:()=>{},logError:()=>{},logWarning:()=>{},logInformation:()=>{},dispose:()=>{}}),
};

// ── vscode.scm ────────────────────────────────────────────────────────────
// Phase 10 — implémentation complète via scm.js

const scm = scmImpl;

// ── vscode.tasks ──────────────────────────────────────────────────────────
// Phase 11 — implémentation complète via tasks.js

const tasks = tasksImpl;

// ── vscode.debug ──────────────────────────────────────────────────────────
// Phase 12 — implémentation complète via debug.js

const debug = debugImpl;

// ── vscode.authentication ─────────────────────────────────────────────────

const authentication = {
  getSession: (providerId, scopes, options) =>
    ipc.callFlutter('vscode.authentication.getSession', [providerId, scopes, options]),
  registerAuthenticationProvider:(id,p,o)=>{const pid=`auth-${id}-${Date.now()}`;for(const m of['getSessions','createSession','removeSession']){ipc.onCall(`${pid}.${m}`,async(...a)=>{try{return await p[m](...a)}catch(e){throw e}});}ipc.callFlutter('vscode.authentication.registerProvider',[pid,id,o]);return new types.Disposable(()=>{ipc.callFlutter('vscode.authentication.unregisterProvider',[pid])});},
  onDidChangeSessions: _makeEditorEvent('onDidChangeAuthSessions'),
};

// ── vscode.notebooks (stub) ───────────────────────────────────────────────

const notebooks = {
  registerNotebookCellStatusBarItemProvider: (notebookType, provider) => {
    const pid = `ncsp-${notebookType}-${Date.now()}`;
    ipc.onCall(`${pid}.provideCellStatusBarItems`, async (cell, token) => {
      try { return await provider.provideCellStatusBarItems(cell, token) ?? []; } catch(e) { return []; }
    });
    ipc.callFlutter('vscode.notebooks.registerCellStatusBarProvider', [pid, notebookType]);
    return new types.Disposable(() => {});
  },
  createNotebookController: (id, label, notebookType, handler) => {
    const pid = `nctl-${id}-${Date.now()}`;
    ipc.onCall(`${pid}.executeCells`, async (doc, cells) => { try { await handler(doc, cells); } catch(e) { throw e; } });
    ipc.callFlutter('vscode.notebooks.createController', [pid, id, label, notebookType]);
    return { id, label, notebookType, supportedLanguages: [], executeHandler: handler,
      onDidChangeSelectedNotebooks: new types.EventEmitter().event,
      dispose: () => ipc.callFlutter('vscode.notebooks.disposeController', [pid]) };
  },
  registerNotebookSerializer: (notebookType, serializer, options) => {
    const pid = `nser-${notebookType}-${Date.now()}`;
    ipc.onCall(`${pid}.deserialize`, async (content, token) => { try { return await serializer.deserializeNotebook(content, token); } catch(e) { return {}; } });
    ipc.onCall(`${pid}.serialize`, async (doc, token) => { try { return await serializer.serializeNotebook(doc, token); } catch(e) { return new Uint8Array(); } });
    ipc.callFlutter('vscode.notebooks.registerSerializer', [pid, notebookType, options]);
    return new types.Disposable(() => {});
  },
  openNotebookDocument: (uri) => ipc.callFlutter('vscode.notebooks.open', [uri.toJSON?.() ?? uri]),
  onDidOpenNotebookDocument: _makeWorkspaceEvent('onDidOpenNotebookDocument'),
  onDidCloseNotebookDocument: _makeWorkspaceEvent('onDidCloseNotebookDocument'),
  onDidChangeNotebookDocumentMetadata: _makeWorkspaceEvent('onDidChangeNotebookDocumentMetadata'),
  notebookDocuments: [],
  get notebookKernels() { return []; },
};

// ── vscode.lm (Language Models API) ──────────────────────────────────────

const lm = {
  selectChatModels: (sel) => ipc.callFlutter('vscode.lm.selectChatModels', [sel]),
  invokeLlm: (model, msgs, opts) => ipc.callFlutter('vscode.lm.invokeLlm', [model, msgs, opts]),
  onDidChangeChatModels: _makeEditorEvent('onDidChangeChatModels'),
};

// ── vscode.chat (Copilot Chat API) ───────────────────────────────────────

const chat = {
  createChatParticipant: (id, handler) => {
    const pid = `chatp-${id}-${Date.now()}`;
    ipc.onCall(`${pid}.respond`, async (req, ctx, token) => { try { return await handler(req, ctx, token); } catch(e) { throw e; } });
    ipc.callFlutter('vscode.chat.createParticipant', [pid, id]);
    return { id, onDidReceiveRequest: new types.EventEmitter().event, dispose: () => ipc.callFlutter('vscode.chat.disposeParticipant', [pid]) };
  },
  ChatRequestTurn: class { constructor(r,c,ref,loc) { this.request=r; this.command=c; this.references=ref; this.location=loc; } },
  ChatResponseTurn: class { constructor(r,c,ref,loc) { this.response=r; this.command=c; this.references=ref; this.location=loc; } },
  ChatRequestEditorSelection: class { constructor(uri,sel) { this.uri=uri; this.selection=sel; } },
  ChatLocation: Object.freeze({ Editor:1, Terminal:2, Notebook:3 }),
};

// ── vscode.tests ──────────────────────────────────────────────────────────

const tests = {
  createTestController: (id, label) => {
    const pid = `tc-${id}-${Date.now()}`;
    ipc.onCall(`${pid}.resolveHandler`, async (item) => { try { return await controller.resolveHandler(item); } catch(e) { return undefined; } });
    ipc.onCall(`${pid}.runHandler`, async (req, token) => { try { await controller.runHandler(req, token); } catch(e) { throw e; } });
    ipc.callFlutter('vscode.tests.createController', [pid, id, label]);
    const controller = { id, label,
      items: { forEach:()=>{}, add:()=>{}, delete:()=>{}, replace:()=>{}, size:0, [Symbol.iterator]:function*(){} },
      resolveHandler: undefined, runHandler: undefined,
      createTestItem: (id, label, uri) => ({ id, label, uri, children: [], tags: [], busy: false }),
      invalidateTestResults: () => {}, refreshHandler: undefined,
      onDidChangeTestProfile: new types.EventEmitter().event, onDidCreateTestItem: new types.EventEmitter().event, onDidChangeTestItem: new types.EventEmitter().event,
      dispose: () => ipc.callFlutter('vscode.tests.disposeController', [pid]),
    };
    controller.resolveHandler = () => {};
    controller.runHandler = () => {};
    return controller;
  },
  TestTag: Object.freeze({ debug: { id: 'debug' }, executable: { id: 'executable' } }),
  TestRunProfileKind: Object.freeze({ Run:1, Debug:2, Coverage:3 }),
  TestResultState: Object.freeze({ Queued:1, Running:2, Passed:3, Failed:4, Skipped:5, Errored:6 }),
};

// ── États internes (mis à jour via events de Flutter) ─────────────────────

let _activeEditor      = null;
let _visibleEditors    = [];
let _workspaceFolders  = null;
let _workspaceName     = 'workspace';

ipc.onEvent('onDidChangeActiveTextEditor',   (editor) => { _activeEditor = editor; });
ipc.onEvent('onDidChangeVisibleTextEditors', (editors) => { _visibleEditors = editors ?? []; });
ipc.onEvent('workspaceFolders.update',       (data) => {
  _workspaceFolders = data?.folders ?? null;
  _workspaceName    = data?.name ?? 'workspace';
});
ipc.onEvent('extensions.update', (exts) => { _extensionsCache = exts ?? []; });

// ── Helpers d'EventEmitter pour les events Flutter → Extension ────────────

function _makeEditorEvent(eventName) {
  const emitter = new types.EventEmitter();
  ipc.onEvent(eventName, (data) => emitter.fire(data));
  return emitter.event;
}

function _makeWorkspaceEvent(eventName) {
  const emitter = new types.EventEmitter();
  ipc.onEvent(eventName, (data) => emitter.fire(data));
  return emitter.event;
}

// ── Configuration proxy ───────────────────────────────────────────────────

// Cache local de la configuration — rempli de manière asynchrone depuis Flutter
// key: "<section>.<key>" → value
const _configCache = new Map();

// Récupère la config d'une section au premier accès
function _fetchConfig(section) {
  ipc.callFlutter('vscode.workspace.configuration.get', [section ?? ''])
    .then((proxy) => {
      if (proxy && proxy.items) {
        const prefix = section ? `${section}.` : '';
        for (const [k, v] of Object.entries(proxy.items)) {
          _configCache.set(`${prefix}${k}`, v);
        }
      }
    })
    .catch(() => {});
}

function _makeConfigProxy(section, scope) {
  // Lancer un fetch asynchrone pour la section si pas encore en cache
  if (section && !_configCache.has(`__fetched_${section}`)) {
    _configCache.set(`__fetched_${section}`, true);
    _fetchConfig(section);
  }

  return {
    get: (key, defaultValue) => {
      // Cherche d'abord sous "section.key", puis juste "key"
      const fullKey  = section ? `${section}.${key}` : key;
      const cached   = _configCache.get(fullKey) ?? _configCache.get(key);
      return cached !== undefined ? cached : defaultValue;
    },
    has: (key) => {
      const fullKey = section ? `${section}.${key}` : key;
      return _configCache.has(fullKey) || _configCache.has(key);
    },
    inspect: (key) => {
      const fullKey = section ? `${section}.${key}` : key;
      const val = _configCache.get(fullKey);
      return {
        key:            fullKey,
        defaultValue:   undefined,
        globalValue:    val,
        workspaceValue: val,
      };
    },
    update: (key, value, target) => {
      const fullKey = section ? `${section}.${key}` : key;
      _configCache.set(fullKey, value);
      return ipc.callFlutter('vscode.workspace.configuration.update',
        [section ?? null, key, value, target ?? 1]);
    },
  };
}

// Quand Flutter signale un changement de config (ex: l'utilisateur modifie un setting)
ipc.onEvent('onDidChangeConfiguration', (data) => {
  if (data?.section) {
    // Invalider le cache de la section pour forcer un re-fetch
    _configCache.delete(`__fetched_${data.section}`);
  }
});

// ── Terminal proxy ────────────────────────────────────────────────────────

function _makeTerminalProxy(name) {
  return {
    name,
    processId: Promise.resolve(0),
    creationOptions: {},
    exitStatus: undefined,
    state: { isInteractedWith: false },
    sendText: (text, addNewLine = true) =>
      ipc.callFlutter('vscode.window.terminal.sendText', [name, text, addNewLine]),
    show: (preserveFocus) =>
      ipc.callFlutter('vscode.window.terminal.show', [name, !!preserveFocus]),
    hide: () =>
      ipc.callFlutter('vscode.window.terminal.hide', [name]),
    dispose: () =>
      ipc.callFlutter('vscode.window.terminal.dispose', [name]),
  };
}

// ── Export final du module `vscode` ───────────────────────────────────────

module.exports = {
  // Namespaces
  window,
  workspace,
  languages,
  commands,
  extensions,
  env,
  scm,
  tasks,
  debug,
  authentication,
  notebooks,
  lm,
  chat,
  tests,

  // Types
  ...types,

  // version
  version: '1.80.0', // Version minimale supportée

  // CancellationToken factory
  CancellationTokenSource: class CancellationTokenSource {
    constructor() {
      this._emitter = new types.EventEmitter();
      this.token = {
        isCancellationRequested: false,
        onCancellationRequested: this._emitter.event,
      };
    }
    cancel() {
      this.token.isCancellationRequested = true;
      this._emitter.fire(undefined);
    }
    dispose() { this._emitter.dispose(); }
  },

  // Themecolor (stub)
  ThemeColor: class ThemeColor {
    constructor(id) { this.id = id; }
  },
  ThemeIcon: class ThemeIcon {
    constructor(id, color) { this.id = id; this.color = color; }
    static File       = new (class TI { constructor() { this.id = 'file'; } })();
    static Folder     = new (class TI { constructor() { this.id = 'folder'; } })();
  },

  // RelativePattern
  RelativePattern: class RelativePattern {
    constructor(base, pattern) {
      this.base    = base;
      this.pattern = pattern;
    }
    toString() { return `${this.base.toString?.() ?? this.base}/${this.pattern}`; }
  },

  // SnippetString
  SnippetString: class SnippetString {
    constructor(value = '') { this.value = value; }
    appendText(str)             { this.value += str.replace(/[$}\\]/g, '\\$&'); return this; }
    appendTabstop(n)            { this.value += n !== undefined ? `$${n}` : '$0'; return this; }
    appendPlaceholder(v, n = 0) { this.value += n ? `\${${n}:${typeof v === 'function' ? '' : v}}` : `\${0:${v}}`; return this; }
    appendChoice(values, n = 0) { this.value += `\${${n}|${values.join(',')}|}`; return this; }
    appendVariable(name, df)    { this.value += df !== undefined ? `\${${name}:${df}}` : `\${${name}}`; return this; }
  },

  // Task (Phase 11)
  Task: class Task {
    constructor(definition, scope, name, source, execution, problemMatchers) {
      this.definition     = definition;
      this.scope          = scope;
      this.name           = name;
      this.source         = source;
      this.execution      = execution;
      this.problemMatchers = problemMatchers ?? [];
      this.isBackground   = false;
      this.presentationOptions = {};
      this.runOptions     = {};
    }
  },
  ShellExecution: class ShellExecution {
    constructor(commandOrLine, argsOrOptions, options) {
      this.commandLine = typeof commandOrLine === 'string' ? commandOrLine : commandOrLine;
      this.args        = argsOrOptions && !argsOrOptions.cwd ? argsOrOptions : undefined;
      this.options     = options ?? (argsOrOptions?.cwd ? argsOrOptions : undefined);
    }
  },
  ProcessExecution: class ProcessExecution {
    constructor(process_, argsOrOptions, options) {
      this.process = process_;
      this.args    = Array.isArray(argsOrOptions) ? argsOrOptions : undefined;
      this.options = options ?? (argsOrOptions && !Array.isArray(argsOrOptions) ? argsOrOptions : undefined);
    }
  },
  TaskScope: Object.freeze({ Global: 1, Workspace: 2 }),

  // TreeItem (Phase 8)
  TreeItem: class TreeItem {
    constructor(labelOrUri, collapsibleState) {
      if (labelOrUri instanceof types.Uri) {
        this.resourceUri = labelOrUri;
        this.label = undefined;
      } else {
        this.label = labelOrUri;
      }
      this.collapsibleState = collapsibleState ?? 0;
      this.id          = undefined;
      this.iconPath    = undefined;
      this.description = undefined;
      this.tooltip     = undefined;
      this.command     = undefined;
      this.contextValue = undefined;
    }
  },
  TreeItemCollapsibleState: Object.freeze({ None: 0, Collapsed: 1, Expanded: 2 }),

  // FileDecoration
  FileDecoration: class FileDecoration {
    constructor(badge, tooltip, color) { this.badge = badge; this.tooltip = tooltip; this.color = color; }
  },

  // ConfigurationTarget
  ConfigurationTarget: Object.freeze({ Global: 1, Workspace: 2, WorkspaceFolder: 3 }),
};
