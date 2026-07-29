# Panda IDE — Extension Host : Suivi de progression

## Phase 1 — Foundation ✅ COMPLÈTE
**Commit tag :** `ext/phase-1/foundation`

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

### Limitations Phase 1 (résolues dans les phases suivantes)
- Les stubs window.* ne font que `callFlutter()` sans handler côté Flutter → Phase 2
- workspace.getConfiguration() retourne juste les defaultValues → Phase 3
- languages.* → providers enregistrés mais non branchés à code_forge → Phase 4
- Marketplace UI non présente → Phase 8

---

## Phase 2 — vscode.window API ⬜ À FAIRE
**Objectif :** Toutes les APIs `vscode.window.*` pleinement fonctionnelles côté Flutter.

### Fichiers à créer
- [ ] `lib/extensions/extension_api_router.dart` — route les appels vscode.* → widgets Flutter
- [ ] `lib/extensions/ui/window_api_handler.dart` — showMessage, showInputBox, showQuickPick
- [ ] `lib/extensions/ui/output_channel_panel.dart` — panneau OutputChannel dans l'UI
- [ ] `lib/extensions/ui/status_bar_manager.dart` — StatusBarItems dans la barre de statut
- [ ] `lib/extensions/ui/progress_overlay.dart` — withProgress → overlay Flutter

---

## Phase 3 — vscode.workspace API ⬜ À FAIRE
**Objectif :** Accès complet aux fichiers, config, watchers depuis une extension.

### Fichiers à créer
- [ ] `lib/extensions/workspace_bridge.dart` — implémente toutes les ops workspace côté Flutter
- [ ] `lib/extensions/fs_bridge.dart` — FileSystem API (read, write, stat, etc.)
- [ ] `lib/extensions/config_store.dart` — gère les configurations d'extension (contributes.configuration)

---

## Phase 4 — vscode.languages API ⬜ À FAIRE
**Objectif :** Completion, hover, diagnostics, formatting branchés sur code_forge.

### Fichiers à créer
- [ ] `lib/extensions/language_feature_router.dart` — route les provider results → code_forge
- [ ] Intégration CompletionItemProvider → CodeForgeController
- [ ] Intégration DiagnosticCollection → décoration de l'éditeur
- [ ] Intégration HoverProvider → tooltip éditeur

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

*Dernière mise à jour : Phase 1 complétée — 2026-07-29*
