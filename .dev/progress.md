# Panda IDE — Extension Host : Suivi de progression

## Phase 1 — Foundation ✅ COMPLÈTE
**Commit :** `ad101d1`

| Fichier | Rôle |
|---------|------|
| `lib/extensions/models/extension_manifest.dart` | Parse package.json (.vsix) |
| `lib/extensions/models/extension_message.dart` | Modèle IPC JSON-RPC |
| `lib/extensions/models/marketplace_extension.dart` | Modèle Open VSX |
| `lib/extensions/extension_registry.dart` | Catalogue persistant |
| `lib/extensions/vsix_installer.dart` | Download + extraction .vsix |
| `lib/extensions/ipc_bridge.dart` | Bridge JSON-RPC stdin/stdout |
| `lib/extensions/open_vsx_client.dart` | Client REST Open VSX |
| `lib/extensions/extension_host_manager.dart` | Cycle de vie Node.js |
| `assets/extension_host/ipc.js` | Bridge IPC Node.js |
| `assets/extension_host/api/types.js` | Types VSCode |
| `assets/extension_host/api/vscode.js` | Module vscode complet |
| `assets/extension_host/host.js` | Entry point Extension Host |

---

## Phase 2 — vscode.window API ✅ COMPLÈTE
**Commit :** `ba3e30b`

| Fichier | Rôle |
|---------|------|
| `lib/extensions/extension_api_router.dart` | Routeur central vscode.* |
| `lib/extensions/ui/window_api_handler.dart` | showMessage, showInputBox, showQuickPick |
| `lib/extensions/ui/output_channel_panel.dart` | Output Channel bottom sheet |
| `lib/extensions/ui/status_bar_manager.dart` | StatusBarItems chips |
| `lib/extensions/ui/progress_overlay.dart` | withProgress overlay |

---

## Phase 3 — vscode.workspace API ✅ COMPLÈTE
**Commit :** `ae5fe41`

| Fichier | Rôle |
|---------|------|
| `lib/extensions/workspace_bridge.dart` | openTextDocument, saveAll, applyEdit, findFiles, config |
| `lib/extensions/fs_bridge.dart` | stat, readDir, readFile, writeFile, delete, rename, copy |
| `lib/extensions/config_store.dart` | getConfiguration / update — SharedPreferences |

---

## Phase 4 — vscode.languages API ✅ COMPLÈTE
**Commit :** `ae5fe41`

| Fichier | Rôle |
|---------|------|
| `lib/extensions/language_feature_router.dart` | Providers pull model — completion, hover, definition, format, codeAction, diagnostics |

---

## Phase 5 — vscode.commands ✅ COMPLÈTE
**Commit :** (batch 5+6+7)

| Fichier | Rôle |
|---------|------|
| `lib/extensions/command_registry.dart` | Registre + execute + search + contributes |
| `lib/extensions/ui/command_palette.dart` | Bottom sheet filtrable VSCode ">" style |

---

## Phase 6 — vscode.extensions ✅ COMPLÈTE
**Commit :** (batch 5+6+7)

| Fichier | Rôle |
|---------|------|
| `lib/extensions/extension_exports_registry.dart` | Stocke exports activate() par extensionId |

---

## Phase 7 — vscode.env ✅ COMPLÈTE
**Commit :** (batch 5+6+7)

- ✅ `vscode.env.clipboard.readText/writeText` → Clipboard Flutter
- ✅ `vscode.env.openExternal(uri)` → url_launcher
- ✅ Config proxy côté JS avec cache local

---

## Phase 8 — Open VSX Marketplace UI ✅ COMPLÈTE
**Commit :** ext/phase-8/marketplace-ui

| Fichier | Rôle |
|---------|------|
| `lib/extensions/ui/marketplace_page.dart` | Recherche Open VSX, filtres catégorie/tri, install |
| `lib/extensions/ui/extensions_panel.dart` | Extensions installées, enable/disable, README, désinstaller |

- ✅ Barre de recherche avec debounce 350ms
- ✅ Pagination automatique (scroll infini)
- ✅ Filtres catégories (7 catégories) + tri (4 options)
- ✅ Carte extension : icône, nom, publisher, version, description, downloads, rating
- ✅ Bouton Install → VsixInstaller (progress, success, error states)
- ✅ Panel extensions installées avec toggle enable/disable
- ✅ Page README (local puis Open VSX fallback)
- ✅ Détection extensions déjà installées

---

## Phase 9 — WebView Panels ✅ COMPLÈTE
**Commit :** ext/phase-9/webview-panels

| Fichier | Rôle |
|---------|------|
| `assets/extension_host/api/webview.js` | createWebviewPanel, postMessage, events lifecycle |
| `lib/extensions/ui/extension_webview.dart` | flutter_inappwebview, WebviewPanelManager, bidirectionnel |

- ✅ `vscode.window.createWebviewPanel(viewType, title, showOptions, options)`
- ✅ `panel.webview.html = '...'` → charge le HTML dans le WebView Flutter
- ✅ `panel.webview.postMessage(data)` → Extension → WebView (via JS handler)
- ✅ `window.acquireVsCodeApi().postMessage(data)` → WebView → Extension (via IPC event)
- ✅ Events: `onDidReceiveMessage`, `onDidDispose`, `onDidChangeViewState`
- ✅ `WebviewPanelManager` singleton gère tous les panels actifs
- ✅ `ExtensionWebviewContainer` — widget à onglets intégrable dans l'IDE

---

## Phase 10 — vscode.scm ✅ COMPLÈTE
**Commit :** ext/phase-10/scm

| Fichier | Rôle |
|---------|------|
| `assets/extension_host/api/scm.js` | createSourceControl, resourceGroups, inputBox |
| `lib/extensions/scm_bridge.dart` | ScmBridge singleton, SourceControl, ScmResourceGroup |

- ✅ `vscode.scm.createSourceControl(id, label, rootUri)`
- ✅ `sourceControl.createResourceGroup(id, label)`
- ✅ `group.resourceStates = [...]` → Flutter notifié
- ✅ `inputBox.value / placeholder` bidirectionnel
- ✅ `ChangeNotifier` pour réactivité UI Flutter

---

## Phase 11 — vscode.tasks ✅ COMPLÈTE
**Commit :** ext/phase-11/tasks

| Fichier | Rôle |
|---------|------|
| `assets/extension_host/api/tasks.js` | registerTaskProvider, fetchTasks, executeTask |
| `lib/extensions/tasks_bridge.dart` | TasksBridge, VsTask, TaskExecution |

- ✅ `vscode.tasks.registerTaskProvider(type, provider)` → handler pull via `onCall`
- ✅ `vscode.tasks.fetchTasks(filter?)` → agrège tous les providers
- ✅ `vscode.tasks.executeTask(task)` → lance via `launchInTerminal` callback
- ✅ `onDidStartTask / onDidEndTask` events
- ✅ Hook `launchInTerminal` à brancher sur flutter_pty depuis main.dart

---

## Phase 12 — vscode.debug (DAP) ✅ COMPLÈTE
**Commit :** ext/phase-12/debug

| Fichier | Rôle |
|---------|------|
| `assets/extension_host/api/debug.js` | registerDebugAdapterDescriptorFactory, startDebugging, breakpoints |
| `lib/extensions/debug_bridge.dart` | DebugBridge, DebugSession (DAP TCP), protocole Content-Length |

- ✅ `vscode.debug.registerDebugAdapterDescriptorFactory(type, factory)`
- ✅ `vscode.debug.registerDebugConfigurationProvider(type, provider)`
- ✅ `vscode.debug.startDebugging(folder, config)` → DebugBridge.startDebugging()
- ✅ `vscode.debug.stopDebugging(session?)`
- ✅ DAP wire format (Content-Length headers) sur TCP socket
- ✅ `initialize / launch / pause / continue / stepOver / stepIn / stepOut`
- ✅ `getStackTrace / getScopes / getVariables / setBreakpoints`
- ✅ Session events (`onDidStartDebugSession`, `onDidTerminateDebugSession`)

---

## Phase 13 — Contributes statiques ✅ COMPLÈTE
**Commit :** ext/phase-13/contributes

| Fichier | Rôle |
|---------|------|
| `lib/extensions/contributes/theme_loader.dart` | Thèmes couleur VSCode (.json) → ThemeData Flutter |
| `lib/extensions/contributes/snippet_loader.dart` | Snippets (.json) → completion items |
| `lib/extensions/contributes/grammar_loader.dart` | Grammaires TextMate (.tmLanguage.json) |
| `lib/extensions/contributes/icon_theme_loader.dart` | Thèmes d'icônes (.json) → file/folder icons |

- ✅ ThemeLoader : charge `contributes.themes`, génère `ThemeData` Flutter approximatif
- ✅ SnippetLoader : charge `contributes.snippets`, search by prefix par langage
- ✅ GrammarLoader : charge `contributes.grammars` + `contributes.languages` (ext → languageId)
- ✅ IconThemeLoader : charge `contributes.iconThemes`, résolution icône par nom/extension fichier
- ✅ Tous les JSON : strip comments (`//`) avant parsing
- ✅ Chargement lazy (par extension) ou bulk (`loadAll()`)

---

## Phase 14 — Extension Settings UI ✅ COMPLÈTE
**Commit :** ext/phase-14/settings-ui

| Fichier | Rôle |
|---------|------|
| `lib/extensions/ui/extension_settings_page.dart` | Auto-génère UI depuis contributes.configuration |

- ✅ Parse `contributes.configuration` (objet ou tableau de sections)
- ✅ Génère des widgets Flutter par type : boolean → Switch, number → TextField, enum → Dropdown, string → TextField
- ✅ Persistance via `ConfigStore.instance.updateConfiguration()`
- ✅ Synchronisé avec `vscode.workspace.getConfiguration()` côté JS
- ✅ Bouton "Reset" pour revenir aux valeurs par défaut
- ✅ Affiche clé (monospace), titre, description de chaque setting

---

## Phase 15 — CI/CD & Tests ✅ COMPLÈTE
**Commit :** ext/phase-15/ci-tests

| Fichier | Rôle |
|---------|------|
| `.github/workflows/test-extension-host.yml` | CI GitHub Actions — Jest sur push/PR |
| `test/extension_host/package.json` | Config Jest |
| `test/extension_host/mocks/ipc.js` | Mock IPC pour tests isolés |
| `test/extension_host/ipc.test.js` | Tests format IPC wire + mock helpers |
| `test/extension_host/vscode.window.test.js` | Tests window API |
| `test/extension_host/vscode.workspace.test.js` | Tests workspace API |
| `test/extension_host/vscode.languages.test.js` | Tests languages + provider pull |
| `test/extension_host/vscode.commands.test.js` | Tests commands + command.invoke event |
| `test/extension_host/vscode.env.test.js` | Tests env + clipboard + openExternal |
| `test/extension_host/vscode.scm.test.js` | Tests SCM bridge |
| `test/extension_host/vscode.tasks.test.js` | Tests tasks + provider |
| `test/extension_host/vscode.debug.test.js` | Tests debug + DAP |

---

## Wiring main.dart ✅ COMPLET

**Commit :** ext/wiring/main-dart

| Fichier | Rôle |
|---------|------|
| `lib/extensions/extension_host_setup.dart` | Extrait les assets JS, configure le manager, wire terminal, charge les contributes |
| `lib/main.dart` | Appelle `ExtensionHostSetup.init()` au démarrage + `attachToManager()` + `setContext()` |

- ✅ `ExtensionHostSetup.init(sharedPath)` appelé dans `main()` (Android uniquement, try/catch non-fatal)
- ✅ Assets JS extraits de assets/ vers `$appDir/extension_host/` au démarrage
- ✅ `ExtensionHostManager.configure(nodeBinPath, hostJsPath)` — node + host.js sur filesystem
- ✅ `TasksBridge.launchInTerminal` branché sur `libbash.so` avec env Android complet
- ✅ Contributes statiques chargés en parallèle (Theme + Snippet + Grammar + IconTheme)
- ✅ `ExtensionApiRouter.instance.attachToManager()` appelé dans `MainApp.build()` (Android uniquement)
- ✅ `ExtensionApiRouter.instance.setContext(context)` mis à jour via `addPostFrameCallback` à chaque rebuild

### Navigation vers les UI extensions (à intégrer dans les menus/sidebar)

```dart
// Marketplace Open VSX
Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplacePage()));

// Panel extensions installées
Navigator.push(context, MaterialPageRoute(builder: (_) => const ExtensionsPanel()));

// WebViews extensions dans le layout
child: ExtensionWebviewContainer()
```

---

*Dernière mise à jour : Wiring main.dart complété — 2026-07-30*
