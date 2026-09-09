# Panda IDE — VSCode Extension Host: Plan d'implémentation complet

> Objectif : Support 100% des extensions VSCode (runtime Node.js local, Open VSX marketplace,
> API vscode.* complète, WebViews, debug, SCM, tasks, snippets, themes, grammars).
> Approche : propre, modulaire, une phase à la fois. Pas de shortcuts.

---

## Références techniques

| Projet | Ce qu'on en tire |
|--------|-----------------|
| [coder/code-server](https://github.com/coder/code-server) | Preuve que l'Extension Host tourne hors Electron |
| [microsoft/vscode extensionHostProtocol.ts](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/extensions/common/extensionHostProtocol.ts) | Protocole IPC officiel |
| [open-vsx.org](https://open-vsx.org) | Marketplace légal (pas Microsoft) |
| [VSCodroid](https://github.com/rmyndharis/VSCodroid) | Précédent Android — apprendre de leurs erreurs |

---

## Architecture globale

```
┌─────────────────────────────────────────────────────┐
│                  Flutter / Dart                      │
│                                                      │
│  ExtensionHostManager ←─── IpcBridge ───────────┐   │
│       │                        ↕ JSON-RPC        │   │
│  ExtensionRegistry        stdin/stdout           │   │
│       │                        │                 │   │
│  VsixInstaller            Node.js Process        │   │
│       │                   (host.js)              │   │
│  OpenVsxClient                 │                 │   │
│       │                   vscode API shim        │   │
│  ExtensionApiRouter ←──── (vscode.js)            │   │
│       │                        │                 │   │
│  UI (Marketplace,          Extension code        │   │
│      Panel, WebView)       (extension.js)        │   │
└─────────────────────────────────────────────────────┘
```

### Protocole IPC (newline-delimited JSON)

```
Flutter → Node.js  (activate, deactivate, events from editor)
Node.js → Flutter  (vscode.* API calls)

Message format:
{ "id": 1, "type": "call",   "method": "activate", "params": [{...context}] }
{ "id": 1, "type": "return", "result": null }
{ "id": 2, "type": "call",   "method": "vscode.window.showInformationMessage", "params": ["Hello"] }
{ "id": 2, "type": "return", "result": "OK" }
{ "id": 0, "type": "event",  "event": "onDidChangeTextDocument", "data": {...} }
```

---

## Phases d'implémentation

### PHASE 1 — Foundation  ✅ en cours
**But :** tout ce qu'il faut pour charger et lancer une extension simple.

- [x] `.dev/plan.md` (ce fichier)
- [ ] `lib/extensions/models/extension_manifest.dart` — parse package.json d'une extension
- [ ] `lib/extensions/models/extension_message.dart` — modèle message IPC
- [ ] `lib/extensions/models/marketplace_extension.dart` — résultat Open VSX
- [ ] `lib/extensions/extension_registry.dart` — catalogue des extensions installées (SharedPrefs)
- [ ] `lib/extensions/vsix_installer.dart` — téléchargement + extraction .vsix (ZIP)
- [ ] `lib/extensions/ipc_bridge.dart` — JSON-RPC stdin/stdout avec Node.js
- [ ] `lib/extensions/open_vsx_client.dart` — client REST Open VSX (search, download)
- [ ] `lib/extensions/extension_host_manager.dart` — spawn/kill process Node.js par extension
- [ ] `assets/extension_host/ipc.js` — côté JS du bridge IPC
- [ ] `assets/extension_host/api/types.js` — Uri, Range, Position, Disposable, etc.
- [ ] `assets/extension_host/api/vscode.js` — root module (export tous les namespaces)
- [ ] `assets/extension_host/host.js` — entry point du process Extension Host

### PHASE 2 — vscode.window API
**But :** les extensions peuvent afficher des messages, inputs, output channels.

- [ ] `assets/extension_host/api/window.js`
  - showInformationMessage / showWarningMessage / showErrorMessage
  - showInputBox / showQuickPick
  - createOutputChannel / withProgress
  - createStatusBarItem
  - showTextDocument / visibleTextEditors
  - createWebviewPanel (stub → Phase 9)
- [ ] `lib/extensions/extension_api_router.dart` — route les appels window.* → Flutter UI
- [ ] Widgets Flutter : SnackBar, Dialog, BottomSheet, OutputChannelPanel

### PHASE 3 — vscode.workspace API
**But :** les extensions peuvent lire/écrire des fichiers, la config, les watchers.

- [ ] `assets/extension_host/api/workspace.js`
  - workspaceFolders / rootPath
  - openTextDocument / saveAll
  - getConfiguration / onDidChangeConfiguration
  - createFileSystemWatcher
  - findFiles / applyEdit (WorkspaceEdit)
  - fs (FileSystem API)
- [ ] Bridge Dart → accès fichiers via path package

### PHASE 4 — vscode.languages API
**But :** completion, hover, diagnostics, formatting — le cœur de l'utilité des extensions.

- [ ] `assets/extension_host/api/languages.js`
  - registerCompletionItemProvider
  - registerHoverProvider
  - registerDefinitionProvider / registerReferenceProvider
  - registerDiagnosticsCollection
  - registerDocumentFormattingEditProvider
  - registerCodeLensProvider / registerCodeActionProvider
  - setLanguageConfiguration
- [ ] Bridge → code_forge widget (CompletionItems, Diagnostics, Hover)

### PHASE 5 — vscode.commands API
**But :** les extensions peuvent enregistrer et exécuter des commandes.

- [ ] `assets/extension_host/api/commands.js`
  - registerCommand / executeCommand
  - getCommands
- [ ] CommandPalette Flutter (search + execute)
- [ ] Contributes keybindings → Flutter shortcut map

### PHASE 6 — vscode.extensions API
**But :** les extensions peuvent se parler entre elles.

- [ ] `assets/extension_host/api/extensions.js`
  - getExtension / all
  - Extension.activate / .exports

### PHASE 7 — vscode.env API
**But :** infos d'environnement, clipboard, shell.

- [ ] `assets/extension_host/api/env.js`
  - appName / appRoot / language / machineId
  - clipboard.readText / writeText
  - openExternal / asExternalUri

### PHASE 8 — Open VSX Marketplace UI
**But :** l'utilisateur peut chercher et installer des extensions depuis l'app.

- [ ] `lib/extensions/ui/marketplace_page.dart`
  - Barre de recherche → GET /api/-/search
  - Carte extension (icône, nom, auteur, nb downloads, rating)
  - Bouton Install → VsixInstaller
  - Filtres (catégorie, tri)
- [ ] `lib/extensions/ui/extensions_panel.dart`
  - Liste des extensions installées (sidebar)
  - Enable / Disable / Uninstall
  - Voir README de l'extension

### PHASE 9 — WebView Panels
**But :** les extensions qui affichent du HTML (ex: preview Markdown, Svelte, etc.).

- [ ] `assets/extension_host/api/webview.js` — createWebviewPanel, postMessage
- [ ] `lib/extensions/ui/extension_webview.dart` — flutter_inappwebview (déjà en dépendance)
- [ ] Bridge postMessage bidirectionnel WebView ↔ Extension Host

### PHASE 10 — vscode.scm API
**But :** extensions Git (GitLens, etc.) peuvent afficher leur UI.

- [ ] `assets/extension_host/api/scm.js`
  - createSourceControl
  - SourceControlResourceGroup
  - InputBox / CommitTemplate
- [ ] Bridge → Git operations existantes dans le repo_bloc

### PHASE 11 — vscode.tasks API
**But :** les extensions peuvent définir et exécuter des tâches (npm run build, etc.).

- [ ] `assets/extension_host/api/tasks.js`
  - registerTaskProvider / fetchTasks / executeTask
  - TaskExecution / TaskProcessStartEvent
- [ ] Bridge → terminal intégré (flutter_pty déjà là)

### PHASE 12 — vscode.debug API (Debug Adapter Protocol)
**But :** support des debuggers (Python debugpy, Node.js inspector, etc.).

- [ ] `assets/extension_host/api/debug.js`
  - registerDebugAdapterDescriptorFactory
  - startDebugging / stopDebugging
  - DebugSession / BreakpointsChangeEvent
- [ ] DAP client Dart (Debug Adapter Protocol — JSON over socket)
- [ ] Debug UI Flutter (breakpoints, call stack, variables, console)

### PHASE 13 — Contributes statiques
**But :** themes, snippets, grammars — pas besoin de Node.js, chargés directement.

- [ ] `lib/extensions/contributes/theme_loader.dart` — charge .json color theme
- [ ] `lib/extensions/contributes/snippet_loader.dart` — charge .json snippets → code_forge
- [ ] `lib/extensions/contributes/grammar_loader.dart` — charge TextMate .tmLanguage.json
- [ ] `lib/extensions/contributes/icon_theme_loader.dart` — charge .json icon theme

### PHASE 14 — Extension Settings UI
**But :** les extensions peuvent déclarer des settings (contributes.configuration).

- [ ] Parser `contributes.configuration` depuis package.json
- [ ] Page Settings Flutter auto-générée depuis le JSON Schema
- [ ] Sync avec vscode.workspace.getConfiguration()

### PHASE 15 — CI/CD & Tests
**But :** chaque phase est testée automatiquement.

- [ ] `.github/workflows/test-extension-host.yml` — teste host.js + API shim avec Jest
- [ ] `test/extension_host/` — tests Jest pour chaque namespace vscode.*
- [ ] Tests Flutter pour IpcBridge, VsixInstaller, OpenVsxClient
- [ ] `.github/workflows/build-android-arm64.yml` — déjà existant, ajouter step de test

---

## Limites connues (documentées, pas cachées)

| Limitation | Raison | Contournement |
|-----------|--------|--------------|
| Extensions avec binaires `.node` natifs x64 | Incompatible ARM64 Android | Documenter clairement, refuser l'install avec message explicite |
| Microsoft Marketplace | Interdit légalement hors VS Code | Open VSX uniquement |
| RAM par extension | ~30-80 MB par process Node.js | Limite configurable (défaut 3 extensions actives max) |
| Extensions Electron-only (accès DOM) | Pas de DOM sur Android | Détection automatique + message d'erreur |

---

## Suivi de progression

Chaque phase est un commit séparé avec tag sémantique :
- `ext/phase-1/foundation`
- `ext/phase-2/window-api`
- etc.

Fichier de suivi : `.dev/progress.md` (mis à jour à chaque phase complétée).
