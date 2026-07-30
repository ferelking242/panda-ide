# Panda IDE — Extension Host : Suivi de progression

## Phase 1 — Foundation ✅ COMPLÈTE
**Commit :** `ad101d1`

### Fichiers créés
| Fichier | Rôle |
|---------|------|
| `.dev/plan.md` | Plan d'implémentation complet (toutes les phases) |
| `lib/extensions/models/extension_manifest.dart` | Parse package.json d'une extension (.vsix) |
| `lib/extensions/models/extension_message.dart` | Modèle IPC message (JSON-RPC) |
| `lib/extensions/models/marketplace_extension.dart` | Modèle résultat Open VSX |
| `lib/extensions/extension_registry.dart` | Catalogue persistant des extensions installées |
| `lib/extensions/vsix_installer.dart` | Téléchargement + extraction .vsix |
| `lib/extensions/ipc_bridge.dart` | Bridge JSON-RPC stdin/stdout Flutter↔Node.js |
| `lib/extensions/open_vsx_client.dart` | Client REST Open VSX marketplace |
| `lib/extensions/extension_host_manager.dart` | Gestionnaire du cycle de vie Node.js |
| `assets/extension_host/ipc.js` | Bridge IPC côté Node.js |
| `assets/extension_host/api/types.js` | Types VSCode (Uri, Range, Position, Diagnostic, etc.) |
| `assets/extension_host/api/vscode.js` | Module `vscode` complet (tous les namespaces) |
| `assets/extension_host/host.js` | Entry point du process Extension Host |

### Ce que Phase 1 permet
- ✅ Installer une extension depuis une URL .vsix ou un fichier local
- ✅ Télécharger/chercher depuis Open VSX
- ✅ Lancer un process Node.js pour une extension
- ✅ Communiquer en JSON-RPC stdin/stdout
- ✅ L'extension peut `require('vscode')` et accéder à tous les namespaces
- ✅ activate() / deactivate() fonctionnels
- ✅ Rejection des extensions avec binaires natifs x64

---

## Phase 2 — vscode.window API ✅ COMPLÈTE
**Commit :** `ba3e30b`

### Fichiers créés
| Fichier | Rôle |
|---------|------|
| `lib/extensions/extension_api_router.dart` | Routeur central vscode.* → handlers Flutter |
| `lib/extensions/ui/window_api_handler.dart` | showMessage (SnackBar/Dialog), showInputBox, showQuickPick |
| `lib/extensions/ui/output_channel_panel.dart` | Panneau Output Channel (bottom sheet style VSCode) |
| `lib/extensions/ui/status_bar_manager.dart` | StatusBarItems + widget ExtensionStatusBarItems |
| `lib/extensions/ui/progress_overlay.dart` | withProgress → overlay notification + WindowProgressIndicator |

### Ce que Phase 2 permet
- ✅ `vscode.window.showInformationMessage/Warning/Error` → SnackBar (sans boutons) ou Dialog (avec boutons)
- ✅ `vscode.window.showInputBox` → Dialog avec champ texte / password
- ✅ `vscode.window.showQuickPick` → Dialog liste filtrée, canPickMany supporté
- ✅ `vscode.window.createOutputChannel` + append/appendLine/clear/show → bottom sheet Output
- ✅ `vscode.window.createStatusBarItem` + text/tooltip/color/command → chips dans status bar
- ✅ `vscode.window.withProgress` → overlay animé (indeterminate + determinate) + inline title bar
- ✅ `ExtensionApiRouter` branché sur `ExtensionHostManager.apiCallHandler`

---

## Phase 3 — vscode.workspace API ✅ COMPLÈTE
**Commit :** (en cours — batch Phase 3 + 4)

### Fichiers créés
| Fichier | Rôle |
|---------|------|
| `lib/extensions/workspace_bridge.dart` | openTextDocument, saveAll, applyEdit, findFiles, workspaceFolders |
| `lib/extensions/fs_bridge.dart` | stat, readDirectory, createDirectory, readFile, writeFile, delete, rename, copy |
| `lib/extensions/config_store.dart` | getConfiguration / update — persisté SharedPreferences par section |

### Ce que Phase 3 permet
- ✅ `vscode.workspace.openTextDocument` → lit le fichier depuis le FS Android
- ✅ `vscode.workspace.saveAll` → délègue au callback IDE
- ✅ `vscode.workspace.applyEdit` → applique des WorkspaceEdit directement sur le FS
- ✅ `vscode.workspace.findFiles` → glob matching sur le workspace root
- ✅ `vscode.workspace.getConfiguration` / `update` → persisté via SharedPreferences
- ✅ `vscode.workspace.fs.*` → toutes les ops FileSystem (stat, read, write, delete, rename, copy, readDir)
- ✅ `WorkspaceBridge.workspaceRoot` configurable depuis l'IDE (à setter depuis le home page)

### Protocole de configuration (à brancher depuis l'IDE)
```dart
WorkspaceBridge.instance.workspaceRoot = '/storage/emulated/0/...';
WorkspaceBridge.instance.onSaveAll = () async => true;
WorkspaceBridge.instance.onApplyEdit = (edits) async => _applyEdits(edits);
```

---

## Phase 4 — vscode.languages API ✅ COMPLÈTE
**Commit :** (en cours — batch Phase 3 + 4)

### Fichiers créés
| Fichier | Rôle |
|---------|------|
| `lib/extensions/language_feature_router.dart` | Route providers extension → code_forge (completion, hover, definition, format, codeAction, diagnostics) |

### Architecture providers (modèle pull)
```
Extension (JS)                Flutter (LanguageFeatureRouter)
─────────────                 ──────────────────────────────
languages.register*Provider() → vscode.languages.<type>.register (IPC apiCall)
  └─ ipc.onCall('provider.<id>.invoke', handler)

Quand l'IDE demande des complétions:
  bridge.call('provider.<id>.invoke', [doc, pos, ctx])
  └─ Node.js appelle handler(doc, pos, ctx) → retourne CompletionList
  └─ Flutter convertit → ExtensionCompletionItem[]
```

### Ce que Phase 4 permet
- ✅ `vscode.languages.registerCompletionItemProvider` → flutter bridge stocke providerId + selector
- ✅ `vscode.languages.registerHoverProvider` → idem
- ✅ `vscode.languages.registerDefinitionProvider` → idem
- ✅ `vscode.languages.registerDocumentFormattingEditProvider` → idem
- ✅ `vscode.languages.registerCodeActionsProvider` → idem
- ✅ `DiagnosticCollection.set()` → push vers `LanguageFeatureRouter.setDiagnostics()`
- ✅ `LanguageFeatureRouter.diagnosticsVersion` → ValueNotifier réactif pour l'UI
- ✅ `requestCompletions / requestHover / requestDefinition / requestFormat / requestCodeActions`
- ✅ `bridgeLookup` wiré depuis `ExtensionHostManager.getBridge`
- ✅ `ExtensionApiRouter.attachToManager()` wire les deux (apiCallHandler + bridgeLookup)

### Intégration code_forge (à faire depuis editor_page.dart)
```dart
// Quand le curseur se déplace et qu'une completion est déclenchée:
final items = await LanguageFeatureRouter.instance.requestCompletions(
  filePath: controller.filePath,
  languageId: 'typescript',
  content: controller.text,
  line: cursor.line, character: cursor.column,
  triggerCharacter: '.',
);
// → items est une List<ExtensionCompletionItem> à injecter dans CodeForge
```

---

## Phase 5 — vscode.commands ⬜ À FAIRE
- [ ] `lib/extensions/command_registry.dart` — registre des commandes + CommandPalette Flutter

---

## Phase 6 — vscode.extensions ⬜ À FAIRE
- [ ] Exposer les exports des extensions aux autres extensions

---

## Phase 7 — vscode.env ⬜ À FAIRE
- [ ] Clipboard Flutter ↔ vscode.env.clipboard
- [ ] url_launcher ↔ vscode.env.openExternal

---

## Phase 8 — Open VSX Marketplace UI ⬜ À FAIRE
- [ ] `lib/extensions/ui/marketplace_page.dart`
- [ ] `lib/extensions/ui/extensions_panel.dart`

---

## Phase 9 — WebView Panels ⬜ À FAIRE
- [ ] `lib/extensions/ui/extension_webview.dart` (flutter_inappwebview)
- [ ] postMessage bidirectionnel

---

## Phase 10 — vscode.scm ⬜ À FAIRE
---

## Phase 11 — vscode.tasks ⬜ À FAIRE
---

## Phase 12 — vscode.debug (DAP) ⬜ À FAIRE
---

## Phase 13 — Contributes statiques (themes, snippets, grammars) ⬜ À FAIRE
---

## Phase 14 — Extension Settings UI ⬜ À FAIRE
---

## Phase 15 — CI/CD & Tests ⬜ À FAIRE
---

*Dernière mise à jour : Phases 3 + 4 complétées — 2026-07-30*
