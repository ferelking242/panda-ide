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

---

# Local AI Marketplace — Suivi de progression

## P1 — Fondations ✅ COMPLET
**Commit :** `d2d1a22`

| Fichier | Rôle |
|---------|------|
| `lib/local_models/models/device_profile.dart` | DeviceProfile — profil matériel |
| `lib/local_models/models/ai_model_entry.dart` | AiModelEntry, ModelQuant, InstalledModel |
| `lib/local_models/services/device_profiler.dart` | DeviceProfiler — /proc/cpuinfo, RAM, stockage |
| `lib/local_models/services/catalog_service.dart` | CatalogService — multi-stage (mem→prefs→remote→asset) |
| `lib/local_models/services/model_download_manager.dart` | Download chunked + reprise + SHA256 + index |
| `lib/local_models/ui/local_models_page.dart` | Marketplace — piles horizontales par catégorie |
| `assets/local_models_catalog.json` | Catalogue embarqué |

---

## P2 — Détail et recommandations ✅ COMPLET
**Commit :** `d2d1a22`

| Fichier | Rôle |
|---------|------|
| `lib/local_models/ui/local_model_detail_page.dart` | Page de détail — specs, compat, quant selector, download |
| `lib/local_models/services/device_profiler.dart` | Algorithme de recommandation par DeviceProfile |

---

## P3 — Optimisations llama.cpp ✅ COMPLET
**Commit :** `ad9b73b`

| Fichier | Rôle |
|---------|------|
| `lib/local_models/services/inference_config_service.dart` | Auto-config threads, ctx, flash attention, batch size |
| `lib/local_models/services/model_activation_service.dart` | Enregistrement modèle dans aiConfig + set default |

---

## P4 — Intelligence et polish ✅ COMPLET
**Commit :** feat(P4)

| Fichier | Rôle |
|---------|------|
| `lib/local_models/services/lru_cache_service.dart` | Cache LRU — touch, candidats, nettoyage auto/manuel |
| `lib/local_models/services/model_selector_service.dart` | Sélection auto du modèle par tâche IDE (7 types) |
| `lib/local_models/services/model_notification_service.dart` | Notifications rich Android — progress, succès, erreur |
| `lib/local_models/ui/advanced_inference_settings_page.dart` | Mode avancé — paramètres llama.cpp manuels |
| `lib/local_models/ui/lru_manager_page.dart` | UI gestion cache — liste LRU, nettoyage, settings |
| `assets/local_models_catalog.json` | Catalogue étendu : **50 modèles** (bartowski, unsloth, Google, Meta, Microsoft, Mistral, DeepSeek, IBM, Cohere…) |
| `pubspec.yaml` | Ajout `flutter_local_notifications: ^18.0.1` |

### Fonctionnalités P4

- ✅ **Cache LRU** : `LruCacheService` — `touch()` à chaque activation, `getCandidates()` triés par lastUsedAt, `autoCleanup()` déclenché si espace < seuil configurable
- ✅ **Nettoyage manuel** : `LruManagerPage` — liste des modèles installés avec badges LRU, sélection multiple, confirmation avant suppression
- ✅ **Settings LRU** : seuil de stockage (0.5-10 GB), jours avant éligibilité (7-90), toggle auto-cleanup
- ✅ **Sélection auto par tâche** : `ModelSelectorService` — 7 types de tâches IDE (`codeCompletion`, `agentChat`, `visionAnalysis`, `mathReasoning`, `generalChat`, `codeReview`, `debugAssistance`)
- ✅ **Scoring multi-critères** : codingScore × poids tâche + toolCalling + vision + reasoning + bonus LRU récent
- ✅ **Override par tâche** : `setDefaultForTask()` / `getOverrideForTask()` persisté dans SharedPreferences
- ✅ **Notifications Android** : `ModelNotificationService` — 2 canaux Android (`panda_models_progress` LOW + `panda_models_complete` HIGH), progression temps réel, bouton Annuler inline, succès avec "Charger le modèle", erreur avec "Réessayer"
- ✅ **Mode avancé llama.cpp** : `AdvancedInferenceSettingsPage` — sliders/champs pour n_threads, n_ctx, n_gpu_layers, n_batch, toggles Flash Attention + mmap, reset aux valeurs auto, sauvegarde dans aiConfig
- ✅ **Catalogue 50 modèles** : Qwen2.5 (0.5B→14B Coder + 3B→14B général + QwQ-32B), Phi-3/3.5/4 Mini, Gemma 3 (1B/4B/12B) + Gemma 2-2B, Llama 3.2 (1B/3B) + 3.1 8B + 3.3 70B, DeepSeek R1 (1.5B/7B/14B) + Coder V2 Lite + V3, Mistral 7B/Nemo/Small 3.1/Codestral, StarCoder2 (3B/7B), CodeGemma (2B/7B), LLaVA 1.6, Moondream2, Hermes 3, OpenChat 3.5, Yi 1.5/Coder, WizardCoder, WizardLM-2, Command-R, Functionary, Granite 3.1 (2B/8B), Aya Expanse, InternLM2.5, Falcon3, SmolLM2 (360M/1.7B), TinyLlama, Neural Chat, Solar, Stable Code, Orca-2, Zephyr, Marco-o1, DeepSeek V3 Q2

---

*Dernière mise à jour : Phase P4 (Local AI Marketplace) complétée — 2026-08-04*
