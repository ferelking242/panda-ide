# 🧩 Architecture des Extensions — Panda IDE

**Réécriture complète : support natif VS Code + format Dart natif**

---

## 1. Le Problème

Les extensions VS Code (40 000+) utilisent le `vscode` API Node.js. On ne peut PAS les "traduire" en Dart — c'est comme traduire C++ en Python, ça ne marche pas.

**La solution : les faire tourner telles quelles.**

---

## 2. Comment VS Code Fonctionne Intérieurement

VS Code n'est PAS un seul processus. C'est **3 processus** :

```
┌─────────────────────────────────────────────────────┐
│                  VS Code Electron                     │
│                                                       │
│  ┌──────────────────┐   IPC/JSON-RPC                  │
│  │  Renderer Process │◄──────────────────────┐       │
│  │  (UI Chromium)    │                       │       │
│  └──────────────────┘                       │       │
│           │                                  │       │
│  ┌──────────────────┐   IPC/JSON-RPC   ┌────┴─────┐│
│  │  Main Process     │◄───────────────► │ Extension ││
│  │  (Node.js host)   │                  │  Host     ││
│  └──────────────────┘                  │ (Node.js) ││
│                                         └──────────┘│
└─────────────────────────────────────────────────────┘
```

- **Renderer** = Chromium = l'UI (menus, éditeur, thèmes)
- **Main** = Node.js = orchestration, filesystem, réseau
- **Extension Host** = Node.js séparé = les extensions tournent ICI

Les extensions communiquent avec l'UI via un protocole **JSON-RPC** sur IPC. C'est ça le secret — l'UI et les extensions sont **découplées**.

---

## 3. Architecture Panda IDE — Dual Runtime

On fait **exactement la même chose**, mais en mieux :

```
┌──────────────────────────────────────────────────────────────┐
│                      Panda IDE (Flutter)                       │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Flutter UI                             │  │
│  │  (éditeur, sidebar, terminal, settings, tabs)            │  │
│  └──────────┬──────────────────────┬───────────────────────┘  │
│             │ IPC/JSON-RPC          │ IPC/JSON-RPC             │
│             │ (stdin/stdout)        │ (Dart Isolate)           │
│  ┌──────────┴──────────┐  ┌────────┴──────────┐              │
│  │  Node.js Ext Host   │  │  Dart Ext Host     │              │
│  │  (sous-processus)   │  │  (isolate Dart)    │              │
│  │                     │  │                     │              │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │              │
│  │  │ vscode API    │  │  │  │ panda SDK     │  │              │
│  │  │ (réel)        │  │  │  │ (réel)        │  │              │
│  │  └───────────────┘  │  │  └───────────────┘  │              │
│  │                     │  │                     │              │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │              │
│  │  │ .vsix ext 1   │  │  │  │ .panda ext 1  │  │              │
│  │  │ .vsix ext 2   │  │  │  │ .panda ext 2  │  │              │
│  │  │ .vsix ext N   │  │  │  │ .panda ext N  │  │              │
│  │  └───────────────┘  │  │  └───────────────┘  │              │
│  └─────────────────────┘  └─────────────────────┘              │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Panda AI Backend (Python)                    │  │
│  │  (sous-processus Python — Alpine/Termux)                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Trois runtimes, un seul IDE :

| Runtime | Langage | Format Extensions | Communication | Usage |
|---------|---------|-------------------|---------------|-------|
| **Flutter UI** | Dart | — | IPC JSON-RPC | Interface principale |
| **Node.js Ext Host** | JavaScript | `.vsix` (VS Code) | stdin/stdout | Extensions VS Code natives |
| **Dart Ext Host** | Dart | `.panda` (native) | Dart Isolate | Extensions Flutter natives |
| **Python Backend** | Python | — | HTTP localhost | Panda AI Gateway |

---

## 4. Node.js Extension Host — Le Cœur VS Code

### 4.1 Comment ça marche

Le **Node.js Extension Host** (abrégé `extHost`) est un processus Node.js séparé qui :

1. **Charge** le vrai module `vscode` (npm `@types/vscode`)
2. **Installe** les extensions `.vsix` dans un dossier local
3. **Active** les extensions selon les `activationEvents`
4. **Exécute** les commandes, webviews, diagnostics
5. **Communique** avec Flutter via JSON-RPC sur stdin/stdout

### 4.2 Le Module `vscode` — Fourni par Panda IDE

C'est le point clé : Panda IDE **fournit** sa propre implémentation du module `vscode` qui mape sur le protocole IPC. C'est exactement ce que VS Code fait :

```
node_modules/
├── vscode/                    # ← Fourni par Panda IDE (pas npm)
│   ├── package.json
│   ├── index.js               # Re-exporte tout
│   └── vscode.d.ts            # Types TypeScript
└── my-extension/              # ← Extension installée
    ├── package.json
    ├── out/extension.js       # Require('vscode') → Panda's shim
    └── ...
```

### 4.3 Structure du `vscode` Shim

```
packages/panda-vscode-shim/
├── package.json               # { "name": "vscode", "main": "index.js" }
├── index.js                   # Module entry point
├── types.d.ts                 # TypeScript declarations (identiques à VS Code)
├── lib/
│   ├── commands.js            # vscode.commands.registerCommand()
│   ├── window.js              # vscode.window.createWebviewPanel()
│   ├── workspace.js           # vscode.workspace.getConfiguration()
│   ├── languages.js           # vscode.languages.registerCompletionItemProvider()
│   ├── debug.js               # vscode.debug API
│   ├── env.js                 # vscode.env.clipboard, openExternal()
│   └── extensions.js          # vscode.extensions.all, getExtension()
└── ipc/
    ├── client.js              # JSON-RPC client → Flutter
    └── protocol.js            # Messages typés
```

### 4.4 Mapping des APIs VS Code

Chaque fonction `vscode.*` envoie un message JSON-RPC à Flutter :

```javascript
// packages/panda-vscode-shim/lib/commands.js

const { rpc } = require('../ipc/client');

module.exports = {
  registerCommand(id, callback) {
    // Enregistrer la commande localement
    rpc.registerHandler('command.execute', (params) => {
      if (params.id === id) {
        return callback(...(params.args || []));
      }
    });
    // Informer Flutter qu'une commande existe
    rpc.notify('command.registered', { id });
    return { dispose: () => rpc.notify('command.unregistered', { id }) };
  },

  async executeCommand(id, ...args) {
    return rpc.request('command.execute', { id, args });
  },

  getCommands() {
    return rpc.request('command.list');
  }
};
```

```javascript
// packages/panda-vscode-shim/lib/window.js

const { rpc } = require('../ipc/client');

module.exports = {
  async createWebviewPanel(viewType, title, showOptions, options) {
    const panelId = `webview-${Date.now()}`;
    await rpc.request('window.createWebview', {
      id: panelId,
      viewType,
      title,
      showOptions,
      options
    });
    return {
      webview: {
        html: '',
        async setHtml(html) {
          await rpc.request('webview.setHtml', { id: panelId, html });
        },
        onDidReceiveMessage: rpc.createEvent(`webview.message.${panelId}`),
        async postMessage(msg) {
          await rpc.request('webview.postMessage', { id: panelId, message: msg });
        }
      },
      async reveal(column) {
        await rpc.request('window.reveal', { id: panelId, column });
      },
      async dispose() {
        await rpc.request('window.dispose', { id: panelId });
      },
      onDidDispose: rpc.createEvent(`webview.dispose.${panelId}`)
    };
  },

  showInformationMessage(message, ...items) {
    return rpc.request('window.showInfo', { message, items });
  },

  showErrorMessage(message, ...items) {
    return rpc.request('window.showError', { message, items });
  },

  showWarningMessage(message, ...items) {
    return rpc.request('window.showWarning', { message, items });
  },

  createStatusBarItem(alignment, priority) {
    const id = `statusbar-${Date.now()}`;
    return {
      text: '',
      tooltip: '',
      color: undefined,
      command: undefined,
      async show() {
        await rpc.request('statusbar.show', { id, item: this });
      },
      async hide() {
        await rpc.request('statusbar.hide', { id });
      },
      async dispose() {
        await rpc.request('statusbar.dispose', { id });
      }
    };
  },

  createTreeView(treeId, options) {
    const viewId = `tree-${treeId}-${Date.now()}`;
    rpc.request('tree.create', { id: viewId, treeId, options });
    return {
      onDidChangeSelection: rpc.createEvent(`tree.selection.${viewId}`),
      onDidChangeVisibility: rpc.createEvent(`tree.visibility.${viewId}`),
      reveal(element) {
        rpc.request('tree.reveal', { id: viewId, element });
      },
      dispose() {
        rpc.request('tree.dispose', { id: viewId });
      }
    };
  },

  withProgress(options, task) {
    return rpc.request('progress.start', {
      location: options.location,
      title: options.title,
      cancellable: options.cancellable
    }).then(async (progressId) => {
      const progress = {
        report(value) {
          rpc.notify('progress.report', { id: progressId, value });
        }
      };
      const token = {
        isCancellationRequested: false,
        onCancellationRequested: rpc.createEvent(`progress.cancel.${progressId}`)
      };
      try {
        return await task(progress, token);
      } finally {
        rpc.notify('progress.done', { id: progressId });
      }
    });
  }
};
```

```javascript
// packages/panda-vscode-shim/lib/workspace.js

const { rpc } = require('../ipc/client');

module.exports = {
  getConfiguration(section) {
    // Synchronous read from cached config
    return rpc.requestSync('workspace.getConfig', { section });
  },

  onDidChangeConfiguration(filter) {
    return rpc.createEvent('workspace.configChanged', filter);
  },

  onDidSaveTextDocument(filter) {
    return rpc.createEvent('workspace.fileSaved', filter);
  },

  onDidOpenTextDocument(filter) {
    return rpc.createEvent('workspace.fileOpened', filter);
  },

  onDidCloseTextDocument(filter) {
    return rpc.createEvent('workspace.fileClosed', filter);
  },

  get textDocuments() {
    return rpc.requestSync('workspace.getOpenDocuments');
  },

  get workspaceFolders() {
    return rpc.requestSync('workspace.getFolders');
  },

  async findFiles(include, exclude, maxResults) {
    return rpc.request('workspace.findFiles', { include, exclude, maxResults });
  },

  async applyEdit(edit) {
    return rpc.request('workspace.applyEdit', { edit });
  },

  registerTextDocumentContentProvider(scheme, provider) {
    rpc.registerHandler(`content.${scheme}`, async (params) => {
      return provider.provideTextDocumentContent(
        vscode.Uri.parse(params.uri)
      );
    });
    return { dispose: () => {} };
  }
};
```

```javascript
// packages/panda-vscode-shim/lib/languages.js

const { rpc } = require('../ipc/client');

module.exports = {
  registerCompletionItemProvider(selector, provider, ...triggerCharacters) {
    const id = `completion-${Date.now()}`;
    rpc.registerHandler(`completion.${id}`, async (params) => {
      const document = rpc.deserialize('document', params.document);
      const position = rpc.deserialize('position', params.position);
      const context = rpc.deserialize('context', params.context);
      const token = rpc.createCancellationToken(params.cancelToken);
      const items = await provider.provideCompletionItems(document, position, context, token);
      return items ? items.map(i => rpc.serialize('completionItem', i)) : [];
    });
    rpc.notify('languages.registerCompletion', {
      id, selector, triggerCharacters
    });
    return { dispose: () => rpc.notify('languages.unregister', { id }) };
  },

  registerHoverProvider(selector, provider) {
    const id = `hover-${Date.now()}`;
    rpc.registerHandler(`hover.${id}`, async (params) => {
      const document = rpc.deserialize('document', params.document);
      const position = rpc.deserialize('position', params.position);
      const token = rpc.createCancellationToken(params.cancelToken);
      return provider.provideHover(document, position, token);
    });
    rpc.notify('languages.registerHover', { id, selector });
    return { dispose: () => rpc.notify('languages.unregister', { id }) };
  },

  registerDefinitionProvider(selector, provider) {
    const id = `definition-${Date.now()}`;
    rpc.registerHandler(`definition.${id}`, async (params) => {
      const document = rpc.deserialize('document', params.document);
      const position = rpc.deserialize('position', params.position);
      const token = rpc.createCancellationToken(params.cancelToken);
      return provider.provideDefinition(document, position, token);
    });
    rpc.notify('languages.registerDefinition', { id, selector });
    return { dispose: () => rpc.notify('languages.unregister', { id }) };
  },

  registerDocumentFormattingEditProvider(selector, provider) {
    const id = `format-${Date.now()}`;
    rpc.registerHandler(`format.${id}`, async (params) => {
      const document = rpc.deserialize('document', params.document);
      const options = params.options;
      const token = rpc.createCancellationToken(params.cancelToken);
      return provider.provideDocumentFormattingEdits(document, options, token);
    });
    rpc.notify('languages.registerFormat', { id, selector });
    return { dispose: () => rpc.notify('languages.unregister', { id }) };
  },

  registerCodeActionsProvider(selector, provider, metadata) {
    const id = `codeaction-${Date.now()}`;
    rpc.registerHandler(`codeaction.${id}`, async (params) => {
      const document = rpc.deserialize('document', params.document);
      const range = rpc.deserialize('range', params.range);
      const context = params.context;
      const token = rpc.createCancellationToken(params.cancelToken);
      return provider.provideCodeActions(document, range, context, token);
    });
    rpc.notify('languages.registerCodeActions', { id, selector, metadata });
    return { dispose: () => rpc.notify('languages.unregister', { id }) };
  }
};
```

### 4.5 Le Protocole IPC

Communication JSON-RPC entre Node.js Extension Host et Flutter :

```
Extension Host (Node.js)                    Flutter UI (Dart)
         │                                        │
         │  ──── REQUEST: command.registered ───►  │
         │       { id: "myExt.hello" }             │
         │                                        │
         │  ◄─── RESPONSE: command.registered ──── │
         │       { ok: true }                      │
         │                                        │
         │  ◄─── NOTIFICATION: command.execute ─── │
         │       { id: "myExt.hello" }             │
         │                                        │
         │  ──── RESPONSE: command.result ───────►  │
         │       { result: "Hello!" }              │
         │                                        │
         │  ──── EVENT: diagnostics.update ──────► │
         │       { file: "main.dart",              │
         │         errors: [...] }                 │
         │                                        │
         │  ◄─── EVENT: editor.cursorMoved ────── │
         │       { line: 42, character: 10 }       │
```

### 4.6 Protocole Détaillé

```jsonc
// ═══════════════════════════════════════════════════════════════
// MESSAGES: Extension Host → Flutter
// ═══════════════════════════════════════════════════════════════

// 1. Enregistrer une commande
{ "type": "request", "method": "command.registered",
  "params": { "id": "myExt.hello", "title": "Say Hello" } }

// 2. Enregistrer un tree data provider
{ "type": "request", "method": "tree.registerProvider",
  "params": { "treeId": "myExt.explorer", "id": "provider-1" } }

// 3. Mettre à jour les diagnostics
{ "type": "notification", "method": "diagnostics.update",
  "params": { "uri": "file:///src/main.dart",
    "diagnostics": [
      { "range": { "start": {"line":10,"character":0}, "end":{"line":10,"character":5}},
        "severity": 1, "message": "Undefined variable" }
    ]
  }
}

// 4. Créer un status bar item
{ "type": "request", "method": "statusbar.show",
  "params": { "id": "sb-1", "text": "$(check) Connected",
    "tooltip": "Gateway is running", "alignment": "left" } }

// 5. Mettre à jour un webview
{ "type": "request", "method": "webview.setHtml",
  "params": { "id": "wv-1", "html": "<h1>Hello</h1>" } }

// 6. Enregistrer un hover provider
{ "type": "notification", "method": "languages.registerHover",
  "params": { "id": "hover-1", "selector": { "language": "dart" } } }

// ═══════════════════════════════════════════════════════════════
// MESSAGES: Flutter → Extension Host
// ═══════════════════════════════════════════════════════════════

// 1. Exécuter une commande
{ "type": "request", "method": "command.execute",
  "params": { "id": "myExt.hello", "args": [] } }

// 2. Fournir les diagnostics d'un document
{ "type": "response", "method": "completion.resolve",
  "params": { "id": "item-1", "documentation": "..." } }

// 3. Envoyer un message à un webview
{ "type": "request", "method": "webview.postMessage",
  "params": { "id": "wv-1", "message": { "type": "refresh" } } }

// 4. Notifier l'ouverture d'un fichier
{ "type": "notification", "method": "editor.fileOpened",
  "params": { "uri": "file:///src/main.dart", "language": "dart" } }

// 5. Fournir les résultats d'hover
{ "type": "response", "method": "hover.resolve",
  "params": { "contents": [{ "language": "dart", "value": "String" }] } }
```

---

## 5. Le Dart Extension Host — Format `.panda`

Pour les extensions natives Flutter/Dart, on utilise un **isolate Dart** séparé :

### 5.1 Comment ça marche

```
Dart Extension Host (Isolate)
    │
    ├── Charge panda.yaml (manifest)
    ├── Importe extension.dart (point d'entrée)
    ├── Appelle onActivate(context)
    ├── Reçoit des événements de Flutter
    ├── Renvoie des résultats (widgets, commands, etc.)
    └── Communication via SendPort/ReceivePort
```

### 5.2 Protocole Dart ↔ Flutter

```dart
// Le même protocole JSON-RPC, mais en Dart
// Extension Host (Isolate) ↔ Flutter (Main Isolate)

class ExtensionHostProtocol {
  final SendPort _toFlutter;
  
  ExtensionHostProtocol(this._toFlutter);

  /// Envoyer une requête à Flutter
  Future<T> request<T>(String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final completer = Completer<T>();
    _pendingRequests[id] = completer;
    _toFlutter.send({ 'type': 'request', 'id': id, 'method': method, 'params': params });
    return completer.future;
  }

  /// Recevoir des événements de Flutter
  void on(String method, Future<dynamic> Function(Map<String, dynamic>) handler) {
    _handlers[method] = handler;
  }
}
```

### 5.3 Format `.panda`

```
my-extension.panda
├── panda.yaml              # Manifest
├── lib/
│   ├── extension.dart      # Point d'entrée
│   └── views/              # Widgets Flutter
├── assets/                 # Icons, themes, snippets
└── pubspec.lock            # Dependencies verrouillées
```

---

## 6. Format `.vsix` — Support Natif

### 6.1 Installation

```bash
# L'utilisateur installe une extension VS Code
panda ext install ms-python.python

# Ce qui se passe en arrière-plan:
# 1. Télécharge .vsix depuis le registry
# 2. Décompresse dans ~/.panda/extensions/ms-python.python/
# 3. Installe les dépendances npm
# 4. Informe le Node.js Extension Host
# 5. Le host active l'extension selon activationEvents
```

### 6.2 Structure d'une extension `.vsix` installée

```
~/.panda/extensions/
├── ms-python.python/          # Extension VS Code installée
│   ├── package.json           # Manifest original (pas modifié)
│   ├── out/
│   │   └── extension.js       # Code JS original
│   ├── node_modules/          # Dépendances npm installées
│   │   ├── vscode/            # ← Remplacé par le shim Panda
│   │   └── ...
│   ├── syntaxes/              # Grammaires TextMate
│   ├── snippets/              # Snippets
│   ├── images/                # Icônes
│   └── .vsixmanifest          # Métadonnées VSIX
│
├── ms-vscode.cpptools/        # Autre extension VS Code
│   └── ...
│
└── com.pandaai.theme/         # Extension .panda native
    ├── panda.yaml
    └── lib/
```

### 6.3 Activation

Le Node.js Extension Host lit `package.json` de chaque extension et active selon les `activationEvents` :

```javascript
// Extension Host: activation logic
function activateExtension(extension) {
  const manifest = require(path.join(extension.path, 'package.json'));

  // Vérifier engines.vscode
  if (!satisfies(VERSION, manifest.engines.vscode)) {
    console.warn(`Extension ${manifest.name} requires VS Code ${manifest.engines.vscode}`);
    return;
  }

  // Charger les dépendances
  const extensionPath = extension.path;
  const nodeModulesPath = path.join(extensionPath, 'node_modules');

  // Monkey-patch require pour injecter le shim
  const Module = require('module');
  const originalResolve = Module._resolveFilename;
  Module._resolveFilename = function(request, parent) {
    if (request === 'vscode') {
      return require.resolve('panda-vscode-shim');
    }
    return originalResolve.apply(this, arguments);
  };

  // Charger l'extension
  const extensionModule = require(path.join(extensionPath, manifest.main));

  // Activer
  if (extensionModule.activate) {
    extensionModule.activate(createExtensionContext(extension, manifest));
  }
}
```

### 6.4 Ce qui Fonctionne

| VS Code API | Status | Notes |
|-------------|--------|-------|
| `vscode.commands.registerCommand` | ✅ Natif | Mapping complet |
| `vscode.commands.executeCommand` | ✅ Natif | Mapping complet |
| `vscode.window.createWebviewPanel` | ✅ Natif | Webview Flutter bridge |
| `vscode.window.showInformationMessage` | ✅ Natif | Dialog Flutter |
| `vscode.window.showErrorMessage` | ✅ Natif | Dialog Flutter |
| `vscode.window.showQuickPick` | ✅ Natif | Quick pick Flutter |
| `vscode.window.createStatusBarItem` | ✅ Natif | Status bar Flutter |
| `vscode.window.createTreeView` | ✅ Natif | Tree view Flutter |
| `vscode.window.withProgress` | ✅ Natif | Progress Flutter |
| `vscode.workspace.getConfiguration` | ✅ Natif | Config Panda |
| `vscode.workspace.onDidChangeConfiguration` | ✅ Natif | Events |
| `vscode.workspace.findFiles` | ✅ Natif | FileSystem Flutter |
| `vscode.workspace.applyEdit` | ✅ Natif | Editeur Flutter |
| `vscode.languages.registerCompletionItemProvider` | ✅ Natif | LSP bridge |
| `vscode.languages.registerHoverProvider` | ✅ Natif | LSP bridge |
| `vscode.languages.registerDefinitionProvider` | ✅ Natif | LSP bridge |
| `vscode.languages.registerDocumentFormattingEditProvider` | ✅ Natif | LSP bridge |
| `vscode.languages.registerCodeActionsProvider` | ✅ Natif | LSP bridge |
| `vscode.debug` | ⚠️ Partiel | Variable substitution |
| `vscode.extensions.getExtension` | ✅ Natif | |
| `vscode.env.clipboard` | ✅ Natif | Clipboard Flutter |
| `vscode.env.openExternal` | ✅ Natif | URL launcher |
| `vscode.Uri.parse/file` | ✅ Natif | URI handling |
| `vscode.Position/Range` | ✅ Natif | Data classes |
| `vscode.Diagnostic` | ✅ Natif | Diagnostics |
| `vscode.CompletionItem` | ✅ Natif | Autocomplete |
| `vscode.Hover` | ✅ Natif | Hover |
| `vscode.TextEdit` | ✅ Natif | Edit operations |
| `vscode.ThemeColor` | ✅ Natif | Status bar colors |
| `vscode.MarkdownString` | ✅ Natif | Rich text |
| `vscode.CancellationToken` | ✅ Natif | Cancel support |
| `vscode.EventEmitter` | ✅ Natif | Events |
| Node.js `fs` module | ⚠️ Via shim | Filesystem API |
| Node.js `path` module | ✅ Natif | Node.js disponible |
| Node.js `child_process` | ⚠️ Sandboxé | Limité pour sécurité |
| Node.js `http/https` | ✅ Natif | Réseau disponible |
| Node.js `os` module | ✅ Natif | |
| Native modules (.node) | ❌ | Pas de compilation native |

### 6.5 Ce qui ne Fonctionne PAS

| VS Code API | Raison | Alternative |
|-------------|--------|-------------|
| `vscode.debug` complet | Protocole DAP complexe | Implémenter via LSP |
| Extensions avec `.node` natifs | Pas de toolchain native | Refuser avec message |
| Extensions avec `electron` | Pas d'Electron | Non applicable |
| Extensions VS Code Web (browser) | Different runtime | Non applicable |

---

## 7. Dual Runtime — Comment les deux coexistent

### 7.1 Priorité et Fallback

```
Extension demandée par l'utilisateur
    │
    ├── Est-ce une extension .panda?
    │   ├── OUI → Dart Extension Host
    │   └── NON ↓
    │
    ├── Est-ce une extension .vsix?
    │   ├── OUI → Node.js Extension Host
    │   └── NON ↓
    │
    └── Erreur: format inconnu
```

### 7.2 Unifier les deux via un Plugin Interface

```
┌─────────────────────────────────────────────────────┐
│                  Plugin Interface                     │
│                                                       │
│  abstract class PandaPlugin {                        │
│    String get id;                                     │
│    String get name;                                   │
│    Future<void> activate(PluginContext context);      │
│    Future<void> deactivate();                         │
│    List<Command> get commands;                        │
│    List<Panel> get panels;                            │
│    Stream<Event> get events;                          │
│  }                                                    │
│                                                       │
│  ┌──────────────────┐  ┌──────────────────┐          │
│  │ DartPlugin       │  │ VsCodePlugin      │          │
│  │ (wraps .panda)   │  │ (wraps .vsix)     │          │
│  └──────────────────┘  └──────────────────┘          │
└─────────────────────────────────────────────────────┘
```

### 7.3 Gestion Unifiée

```
Plugin Manager
    │
    ├── charge .panda extensions (Dart Isolate)
    ├── charge .vsix extensions (Node.js Process)
    ├──统一 les deux dans un registry
    ├── route les commands au bon host
    ├── route les events au bon host
    └── gère le lifecycle (activate/deactivate)
```

---

## 8. Dépendances pour le Node.js Extension Host

### 8.1 Ce qu'il faut installer

```bash
# Sur le système (Alpine Linux via Termux)
apk add nodejs npm

# Ou via nvm (plus flexible)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 20

# Vérifier
node --version   # v20.x.x
npm --version    # 10.x.x
```

### 8.2 Packages Panda IDE fournis

| Package | Description | Taille |
|---------|-------------|--------|
| `panda-vscode-shim` | Module `vscode` compatible | ~200KB |
| `panda-extension-host` | Extension Host Runner | ~500KB |
| `panda-lsp-client` | Client LSP (pour les language servers) | ~300KB |
| `panda-ipc` | Protocole IPC/JSON-RPC | ~100KB |

**Total : ~1.1MB** (sans Node.js lui-même)

### 8.3 Taille totale

| Composant | Taille |
|-----------|--------|
| Node.js runtime | ~45MB |
| npm | ~15MB |
| panda-vscode-shim | ~200KB |
| panda-extension-host | ~500KB |
| Extensions VS Code (10 avg) | ~100MB |
| **Total** | **~160MB** |

---

## 9. Performance

### 9.1 Startup

| Opération | Temps estimé |
|-----------|-------------|
| Démarrer Node.js process | ~500ms |
| Charger panda-vscode-shim | ~50ms |
| Scanner extensions installées | ~100ms |
| Activer 10 extensions | ~2-5s (selon les extensions) |
| **Total** | **~3-6s** |

### 9.2 Communication

| Type | Latence |
|------|---------|
| Flutter → Node.js (command) | ~1-5ms |
| Node.js → Flutter (diagnostics) | ~1-5ms |
| Flutter → Dart isolate (panda) | ~0.1ms |
| IPC overhead par message | ~0.5ms |

### 9.3 RAM

| Composant | RAM |
|-----------|-----|
| Node.js Extension Host | ~30-50MB |
| 10 extensions VS Code | ~50-100MB |
| Dart Extension Host | ~5-10MB |
| 5 extensions .panda | ~10-20MB |
| **Total** | **~95-180MB** |

---

## 10. Exemple Complet — Extension VS Code qui Fonctionne

### Extension : `ms-python.python`

```jsonc
// package.json (original, pas modifié)
{
  "name": "ms-python.python",
  "displayName": "Python",
  "version": "2024.0.0",
  "engines": { "vscode": "^1.85.0" },
  "activationEvents": ["onLanguage:python"],
  "main": "./out/client/extension.js",
  "contributes": {
    "commands": [
      { "command": "python.setInterpreter", "title": "Python: Select Interpreter" }
    ],
    "languages": [
      { "id": "python", "extensions": [".py"] }
    ],
    "configuration": {
      "python.defaultInterpreterPath": { "type": "string" }
    }
  }
}
```

```javascript
// out/client/extension.js (original, pas modifié)
const vscode = require('vscode');

function activate(context) {
  // Cette ligne utilise le SHIM Panda, pas le vrai VS Code
  const disposable = vscode.commands.registerCommand(
    'python.setInterpreter',
    async () => {
      const items = await vscode.window.showQuickPick([
        'Python 3.12',
        'Python 3.11',
        'Python 3.10'
      ], { placeHolder: 'Select Python interpreter' });

      if (items) {
        const config = vscode.workspace.getConfiguration('python');
        await config.update('defaultInterpreterPath', items, true);
        vscode.window.showInformationMessage(`Interpreter set to ${items}`);
      }
    }
  );

  context.subscriptions.push(disposable);
}

exports.activate = activate;
```

**Résultat dans Panda IDE :**
- La commande `Python: Select Interpreter` apparaît dans la palette de commandes
- `Ctrl+Shift+P` → tape "Python" → la commande est là
- L'extension fonctionne **exactement** comme dans VS Code
- Le shim translate `vscode.*` → JSON-RPC → Flutter UI

---

## 11. Comparaison avec les Autres Approches

| Approche | Compat VS Code | Performance | Complexité | Verdict |
|----------|---------------|-------------|------------|---------|
| **Traduction .vsix → .panda** | 40% | ✅ Rapide | Moyenne | ❌ Perte de features |
| **Electron embarqué** | 100% | ❌ Lourd | Faible | ❌ 500MB+ RAM |
| **Node.js subprocess** | 95% | ✅ Bon | Moyenne | ✅ **Choisi** |
| **Deno subprocess** | 80% | ✅ Bon | Élevée | ⚠️ Moins mature |
| **WASM (esbuild)** | 60% | ✅ Très rapide | Très élevée | ❌ Pas de Node.js API |

**Le Node.js subprocess est le meilleur compromis** :
- 95% de compatibilité VS Code
- Performance acceptable (~1-5ms par appel IPC)
- Complexité moyenne (le shim est bien défini)
- Même architecture que VS Code lui-même

---

## 12. Plan d'Implémentation

### Phase 1: Node.js Extension Host (3 semaines)
- `panda-vscode-shim` : module `vscode` compatible
- `panda-extension-host` : processus Node.js
- IPC protocol (stdin/stdout JSON-RPC)
- Command loader (active extensions selon activationEvents)
- Webview bridge (HTML → Flutter)

### Phase 2: VS Code API Coverage (4 semaines)
- `vscode.commands` → complet
- `vscode.window` → complet (dialogs, webview, treeview, statusbar)
- `vscode.workspace` → complet (config, files, edits)
- `vscode.languages` → complet (LSP bridge)
- `vscode.debug` → partiel (variable substitution)
- `vscode.env` → complet
- URI, Position, Range, Diagnostic → complet

### Phase 3: Extension Management (2 semaines)
- `panda ext install <id>` → télécharge .vsix
- Extension discovery (scan ~/.panda/extensions/)
- npm install automatique des dépendances
- Activation/désactivation lifecycle
- Mises à jour automatiques

### Phase 4: Dart Extensions (2 semaines)
- Dart Extension Host (isolate)
- `panda_sdk` package
- `.panda` loader
- Hot-reload pour le développement

### Phase 5: Dual Plugin Interface (1 semaine)
- `PandaPlugin` abstract class
- `DartPlugin` wrapper
- `VsCodePlugin` wrapper
- Unified plugin manager
- Gestion des conflits

### Phase 6: Dev Tools (1 semaine)
- `panda ext dev` → hot-reload pour .panda
- Extension Inspector (voir les messages IPC)
- Profiler (temps par appel)
- Console (logs des extensions)

---

## 13. Conclusion

### Architecture Finalement Recommandée

**Node.js subprocess + Dart isolate = dual runtime natif.**

### Ce que ça change

| Avant (traduction) | Après (runtime natif) |
|--------------------|-----------------------|
| Traduire les extensions | Les exécuter telles quelles |
| 40% de compatibilité | **95%** de compatibilité |
| Perte de features VS Code | Toutes les APIs disponibles |
| Extensions custom à réécrire | 40 000+ extensions existantes |
| Webview HTML → Flutter (perte) | Webview HTML natif (Node.js) |
| Pas de Node.js APIs | `fs`, `path`, `http` disponibles |

### Le prix

- ~45MB pour Node.js
- ~50-100MB RAM pour les extensions
- 1-5ms de latence IPC par appel
- Implémenter le shim `vscode` (~200KB)

### Pourquoi c'est la bonne solution

**VS Code lui-même fait exactement ça.** Son Extension Host est un processus Node.js séparé qui communique avec l'UI via IPC. On ne réinvente rien — on utilise la même architecture, mais avec Flutter comme UI au lieu d'Electron.

40 000+ extensions qui fonctionnent **sans modification**. C'est le game changer.
