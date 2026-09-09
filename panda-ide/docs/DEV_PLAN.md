# 🐼 Plan de Développement Panda IDE — 2 Agents

**Date :** 22 août 2026
**Objectif :** Transformer Panda IDE de "jouet" en IDE sérieux
**Durée estimée :** 4 semaines (2 devs simultanés)

---

## Rôles

| Agent | Rôle | Focus |
|-------|------|-------|
| **Agent A** | Architecte Feature | Éditeur, Git, LSP, Workspace, Quick Open |
| **Agent B** | Builder & Fixer | Build system, CI, Tests, Performance, Android |

---

## Semaine 1 — Fondations

### Agent A (Moi) — Éditeur + Navigation

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| A1 | **Quick Open (Ctrl+P)** | 🔴 | `lib/ui/quick_open.dart` | Fuzzy search sur tous les fichiers du workspace. Résultats triés par pertinence + récence. Sélection via clavier. |
| A2 | **Multi-cursor** | 🔴 | `lib/ui/editor/cursor_manager.dart` | Ctrl+D = sélection suivante, Ctrl+Shift+L = tous les matching, Alt+Click = nouveau curseur |
| A3 | **Code folding** | 🔴 | `lib/ui/editor/folding.dart` | Plier/déplier les scopes (classes, fonctions, if/else). Indentation guides. |
| A4 | **Word wrap toggle** | 🟡 | `lib/ui/editor_page.dart` | Ajouter le toggle word-wrap dans les settings de l'éditeur |
| A5 | **Indent guides** | 🟡 | `lib/ui/editor/indent_guides.dart` | Lignes verticales pour chaque niveau d'indentation |
| A6 | **Bracket pair colorization** | 🟡 | `lib/ui/editor/bracket_colorizer.dart` | Couleurs différentes pour () {} [] imbriqués |

### Agent B — Build + CI

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| B1 | **Fix build rouge** | 🔴 | Divers | Corriger toutes les erreurs de compilation Flutter (dart:io, web compat, imports cassés) |
| B2 | **CI Flutter** | 🔴 | `.github/workflows/ci.yml` | Ajouter un job Flutter build check (flutter analyze + flutter build) |
| B3 | **Tests unitaires** | 🟡 | `test/` | Tests pour les modules critiques: extension_manifest, command_registry, panda_manifest |
| B4 | **Hot reload** | 🟡 | Dev setup | Vérifier que le hot reload fonctionne correctement sur Android |
| B5 | **APK cleanup** | 🟡 | `android/` | Nettoyer le build Android (remove unused features, optimize size) |

---

## Semaine 2 — Git + Diff

### Agent A — Git intégré + Diff

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| A7 | **Git operations** | 🔴 | `lib/ui/git_panel.dart` | Panel Git: commit, push, pull, fetch. Input message + staged files list |
| A8 | **Diff viewer inline** | 🔴 | `lib/ui/editor/diff_viewer.dart` | Afficher les diffs inline dans l'éditeur (lignes ajoutées/supprimées en couleur) |
| A9 | **Staging UI** | 🔴 | `lib/ui/git/staging.dart` | Staging hunk-level et file-level. Checkbox par hunk. |
| A10 | **Branch selector** | 🟡 | `lib/ui/git/branch_selector.dart` | Dropdown pour switcher de branche. Créer nouvelle branche. |
| A11 | **Git blame inline** | 🟢 | `lib/ui/editor/git_blame.dart` | Afficher l'auteur + date dans la gutter de l'éditeur |

### Agent B — Workspace + Settings

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| B6 | **Multi-root workspace** | 🔴 | `lib/core/workspace/` | Supporter 2+ dossiers dans un workspace. UI pour ajouter/retirer des folders |
| B7 | **.vscode/settings.json** | 🟡 | `lib/core/workspace/` | Lire/écrire les settings par workspace (tab size, font, theme, etc.) |
| B8 | **Settings UI** | 🟡 | `lib/ui/settings_page.dart` | Page settings complète avec sections: Editor, Terminal, Git, Extensions, AI |
| B9 | **Keybindings custom** | 🟢 | `lib/core/keybindings.dart` | Parser keybindings.json, mapper les raccourcis clavier |
| B10 | **Workspace persistence** | 🟡 | `lib/core/workspace/` | Sauvegarder/restaurer l'état du workspace (onglets ouverts, splits, etc.) |

---

## Semaine 3 — LSP Complet + Debug

### Agent A — LSP + Debug

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| A12 | **DocumentSymbol** | 🟡 | `lib/extensions/language_feature_router.dart` | Symbol picker pour naviguer dans le fichier (Ctrl+Shift+O) |
| A13 | **CodeActionProvider** | 🔴 | `lib/extensions/language_feature_router.dart` | Quick fixes (light bulb), refactorings (rename, extract) |
| A14 | **CodeLens** | 🟡 | `lib/ui/editor/code_lens.dart` | "3 references" au-dessus des fonctions, "Run test" au-dessus des tests |
| A15 | **DiagnosticProvider** | 🔴 | `lib/ui/editor/diagnostics.dart` | erreurs/warnings/info inline + Problems panel |
| A16 | **InlayHintProvider** | 🟢 | `lib/ui/editor/inlay_hints.dart` | Types inférés affichés inline (x: int = |
| A17 | **FoldingRange** | 🟡 | Intégré dans A3 | Depuis le LSP, pas du tree-sitter |

### Agent B — Performance + Android

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| B11 | **Virtual scrolling** | 🔴 | `lib/ui/editor_page.dart` | Ne renderer que les lignes visibles (perf sur 10K+ lignes) |
| B12 | **Lazy tab loading** | 🟡 | `lib/ui/editor_page.dart` | Charger les onglets uniquement quand ils sont visibles |
| B13 | **File watcher natif** | 🟡 | `lib/core/fs/` | Utiliser un watcher natif au lieu de polling pour les changements de fichiers |
| B14 | **APK optimization** | 🟡 | `android/` | R8/ProGuard, shrink resources, split APKs by ABI |
| B15 | **Memory profiling** | 🟢 | Dev tools | Outil pour mesurer la RAM utilisée par l'app |

---

## Semaine 4 — Polish + Release

### Agent A — UI/UX Final

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| A18 | **Minimap** | 🟢 | `lib/ui/editor/minimap.dart` | Overview du fichier à droite de l'éditeur |
| A19 | **Breadcrumbs** | 🟢 | `lib/ui/editor/breadcrumbs.dart` | Fil d'Ariane dans l'éditeur (namespace > class > method) |
| A20 | **Sticky scroll** | 🟢 | `lib/ui/editor/sticky_scroll.dart` | Header du scope toujours visible en haut |
| A21 | **Command palette v2** | 🟡 | `lib/extensions/ui/command_palette.dart` | Fuzzy search, catégories, récentes, contextuelles |
| A22 | **Tab groups** | 🟡 | `lib/ui/editor_page.dart` | Split horizontal/vertical, drag & drop tabs |

### Agent B — Testing + Release

| # | Task | Priorité | Fichiers | Description |
|---|------|----------|----------|-------------|
| B16 | **Integration tests** | 🟡 | `test/` | Tests end-to-end: ouvrir fichier, éditer, sauvegarder, Git commit |
| B17 | **Performance benchmarks** | 🟡 | `test/benchmarks/` | Mesurer: temps ouverture fichier, latency LSP, RAM usage |
| B18 | **Release workflow** | 🔴 | `.github/workflows/` | Automatiser la release: version bump, changelog, APK signé |
| B19 | **Documentation** | 🟡 | `docs/` | README complet, guide d'installation, guide de contribution |
| B20 | **Android polish** | 🟡 | `android/` | Splash screen, app icon, notification channels, foreground service |

---

## Matrice de Dépendances

```
A1 (Quick Open)          → indépendant
A2 (Multi-cursor)        → indépendant
A3 (Code folding)        → indépendant
A7 (Git operations)      → dépend de B6 (multi-root)
A8 (Diff viewer)         → dépend de A7 (Git)
A12 (DocumentSymbol)     → dépend de B1 (build fixé)
A13 (CodeAction)         → dépend de B1 (build fixé)
A15 (Diagnostics)        → dépend de B1 (build fixé)

B1 (Fix build)           → PRIORITÉ #1 — tout dépend de ça
B2 (CI Flutter)          → dépend de B1
B6 (Multi-root)          → indépendant
B11 (Virtual scrolling)  → indépendant
B18 (Release workflow)   → dépend de B2
```

## Règles de Travail

1. **Pas de fichier partagé** — Agent A ne touche pas aux fichiers Android/CI, Agent B ne touche pas à l'éditeur
2. **Branches séparées** — Agent A sur `feature/editor-ux`, Agent B sur `fix/build-system`
3. **Merge hebdo** — Chaque vendredi, merge dans main
4. **Pas de force push** — Jamais sur main
5. **Tests avant merge** — `flutter analyze` + `flutter test` doivent passer
6. **Commit messages** — Format: `feat(scope): description` ou `fix(scope): description`

## Ce qu'on NE fait PAS

- ❌ Copier le debugging de VS Code (trop complexe, 3 semaines minimum)
- ❌ Ajouter la collaboration CRDT (6 mois de dev)
- ❌ Réécrire l'éditeur en Rust (pas le scope)
- ❌ Implémenter les 28 providers LSP (14 suffisent pour le mobile)
- ❌ Ajouter un navigateur web complet (on a déjà un browser intégré)
