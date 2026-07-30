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

**Config à brancher depuis l'IDE :**
```dart
WorkspaceBridge.instance.workspaceRoot = '/path/to/project';
WorkspaceBridge.instance.onSaveAll = () async => true;
WorkspaceBridge.instance.onApplyEdit = (edits) async => applyEdits(edits);
```

---

## Phase 4 — vscode.languages API ✅ COMPLÈTE
**Commit :** `ae5fe41`

| Fichier | Rôle |
|---------|------|
| `lib/extensions/language_feature_router.dart` | Providers pull model — completion, hover, definition, format, codeAction, diagnostics |

**Architecture pull :** Flutter appelle `provider.<id>.invoke` directement sur Node.js.

**Intégration code_forge (TODO dans editor_page.dart) :**
```dart
final items = await LanguageFeatureRouter.instance.requestCompletions(
  filePath: path, languageId: 'typescript',
  content: text, line: l, character: c, triggerCharacter: '.',
);
```

---

## Phase 5 — vscode.commands ✅ COMPLÈTE
**Commit :** (en cours — batch 5+6+7)

| Fichier | Rôle |
|---------|------|
| `lib/extensions/command_registry.dart` | Registre + execute + search + contributes |
| `lib/extensions/ui/command_palette.dart` | Bottom sheet filtrable VSCode ">" style |

- ✅ `vscode.commands.registerCommand` → `CommandRegistry.register()`
- ✅ `vscode.commands.executeCommand` → local handler ou `bridge.call('command.<id>')`
- ✅ `vscode.commands.getCommands` → liste des IDs enregistrés
- ✅ `CommandPalette.show(context)` — DraggableScrollableSheet, filtrable, arrow keys
- ✅ `CommandRegistry.registerContributed()` — pour contributes.commands du manifest

---

## Phase 6 — vscode.extensions ✅ COMPLÈTE
**Commit :** (en cours — batch 5+6+7)

| Fichier | Rôle |
|---------|------|
| `lib/extensions/extension_exports_registry.dart` | Stocke exports activate() par extensionId |

- ✅ `vscode.extensions.getExtension(id)` → `ExtensionExportsRegistry.getExtensionJson(id)`
- ✅ `vscode.extensions.all` → liste de toutes les extensions actives
- ✅ `host.js` envoie automatiquement les exports via `vscode.extensions.exports.register` après activate()
- ✅ Inter-extension access (une ext peut lire les exports d'une autre)

---

## Phase 7 — vscode.env ✅ COMPLÈTE
**Commit :** (en cours — batch 5+6+7)

- ✅ `vscode.env.clipboard.readText()` → `Clipboard.getData` Flutter
- ✅ `vscode.env.clipboard.writeText(text)` → `Clipboard.setData`
- ✅ `vscode.env.openExternal(uri)` → `url_launcher` (`launchUrl`)
- ✅ Config proxy côté JS avec cache local + fetch asynchrone depuis Flutter
- ✅ `onDidChangeConfiguration` event invalide le cache config

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

*Dernière mise à jour : Phases 5 + 6 + 7 complétées — 2026-07-30*
