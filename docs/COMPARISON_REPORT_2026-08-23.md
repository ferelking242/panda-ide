# 📊 RAPPORT DE COMPARAISON — VS Code vs Panda IDE
## État réel du code vs plans d'édition — 23 août 2026

---

## RÉSUMÉ EXÉCUTIF

| Métrique | Valeur |
|---|---|
| **Fichiers Dart** | 198 |
| **Lignes de code** | ~106K |
| **Phases complétées** | 10/16 étapes |
| **Étapes sautées** | **3** (voir ci-dessous) |
| **Settings endpoints actifs** | 22 (sur ~40 VS Code) |
| **Score Panda APRÈS phases** | 6.80/10 (vs VS Code 8.85) |

---

## 🔴 LES 3 ÉTAPES SAUTÉES

### Étape sautée #1 : `02_workspace_dropdown.md`
**Objectif** : Quick Pick VS Code-style au clic sur la box Workspace
**Ce qui existe** : Un dropdown custom (`_buildWorkspaceDropdown`) avec overlay, search, et items
**Ce qui manque** :
- Pas de séparateur « folders & workspaces » / « files » comme VS Code
- Pas de bouton × pour supprimer du récent
- Pas de Cmd/Ctrl-click → nouvelle fenêtre (pas sur mobile)
- Le dropdown liste des commandes (Flutter Device, Palette, Fermer) au lieu des workspaces récents
- **Statut** : ⚠️ PARTIEL — le dropdown existe mais ne suit pas le modèle VS Code

### Étape sautée #2 : `05_status_bar.md`
**Objectif** : Tous les items VS Code dans la status bar
**Ce qui existe** : `status_bar.dart` (890 lignes) avec remote, branch, errors/warnings, encoding, notifications
**Ce qui manque** :
- Branch name non cliquable (pas de menu contextuel)
- Encoding selector (UTF-8 → choix)
- Indentation selector (2/4/8 espaces)
- Line ending selector (LF/CRLF)
- Profile selector
- **Statut** : ⚠️ PARTIEL — les items sont là mais beaucoup ne sont pas interactifs

### Étape sautée #3 : `06_terminal_multitab.md`
**Objectif** : Terminal multi-onglets (comme VS Code)
**Ce qui existe** : `terminal_native.dart` a du split terminal (47 occurrences de "split")
**Ce qui manque** :
- **Aucun onglet terminal** — un seul terminal à la fois
- Pas de bouton "+" pour nouveau terminal
- Pas de dropdown pour switcher entre terminaux
- Pas de fermer un terminal individuel
- **Statut** : ❌ NON FAIT — le multi-tab terminal est absent

---

## ✅ CE QUI A ÉTÉ CODÉ (par phase)

### Phase 0 — Immédiat
| # | Tâche | Fichier | Status | Détail |
|---|---|---|---|---|
| 0.1 | Settings persistence | `lib/utils/settings_service.dart` | ✅ | 22 settings via SharedPreferences |
| 0.2 | Workspace dropdown | `lib/ui/home.dart` | ⚠️ | Dropdown custom, pas Quick Pick VS Code |

### Phase 1 — Features manquantes
| # | Tâche | Fichier | Status | Détail |
|---|---|---|---|---|
| 1.1 | Explorer context menu | `lib/ui/home.dart` | ✅ | Copy Path, Cut, Copy, Paste, Rename, Delete |
| 1.2 | Tab menu complet | `lib/ui/editor/tab_groups.dart` | ✅ | 12 actions: Close All, Close Saved, Split, etc. |
| 1.3 | Status bar items | `lib/ui/editor/status_bar.dart` | ⚠️ | 890 lignes, items présents mais peu interactifs |
| 1.4 | CodeLens | `lib/ui/editor/codelens_provider.dart` | ✅ | 83 lignes, overlay + items |
| 1.5 | Create/Checkout branch | `lib/ui/git_panel.dart` | ✅ | `createBranch()`, `checkout()`, `getBranches()` |
| 1.6 | Settings search | `lib/ui/settings_page.dart` | ✅ | Barre de recherche dans les settings |

### Phase 2 — Terminal & Debug
| # | Tâche | Fichier | Status | Détail |
|---|---|---|---|---|
| 2.1 | Terminal multi-tab | — | ❌ | **ABSENT** — étape sautée |
| 2.2 | Terminal split | `lib/terminal/terminal_native.dart` | ⚠️ | Split view existe mais basique |
| 2.4 | Conditional breakpoints | — | ❌ | Non implémenté |
| 2.5 | Git stash | — | ❌ | Non implémenté |
| 2.6 | Git log/history | — | ❌ | Non implémenté |
| 2.7 | Preview editor (italic) | — | ❌ | Non implémenté |

### Phase 3 — Extension system
| # | Tâche | Fichier | Status | Détail |
|---|---|---|---|---|
| 3.1 | debuggers contribution | — | ❌ | Non implémenté |
| 3.2 | authentication contribution | — | ❌ | Non implémenté |
| 3.3 | taskDefinitions contribution | — | ❌ | Non implémenté |
| 3.4 | viewsContainers (custom sidebar) | — | ❌ | Non implémenté |
| 3.5 | Extension auto-update | — | ❌ | Non implémenté |

### Phase 4 — Mobile-first
| # | Tâche | Fichier | Status | Détail |
|---|---|---|---|---|
| 4.1 | Responsive breakpoints | `lib/ui/widgets/responsive_layout.dart` | ✅ | Mobile <600, Tablet 600-1024, Desktop >1024 |
| 4.2 | Sidebar → Drawer | `lib/ui/home.dart` | ✅ | Drawer pour mobile |
| 4.3 | Bottom Navigation | `lib/ui/widgets/responsive_layout.dart` | ✅ | 5 tabs: Explorer, Search, Git, Extensions, Agent |
| 4.4 | Settings mobile layout | — | ❌ | Pas de layout spécial mobile |
| 4.5 | Terminal → Bottom sheet | `lib/terminal/terminal_native.dart` | ✅ | Bottom sheet terminal |
| 4.6 | Pull-to-refresh | — | ❌ | Non implémenté |
| 4.7 | Long press context menu | — | ❌ | Non implémenté |
| 4.8 | Swipe between tabs | — | ❌ | Non implémenté |

### Phase 5 — Polish
| # | Tâche | Fichier | Status | Détail |
|---|---|---|---|---|
| 5.1 | Accessibility (ARIA) | `lib/ui/home.dart` | ✅ | Semantics widgets ajoutés |
| 5.2 | Search exclude/include | — | ❌ | Non implémenté |
| 5.3 | Inlay hints | — | ❌ | Non implémenté |
| 5.4 | Local history | — | ❌ | Non implémenté |
| 5.5 | Zen mode | — | ❌ | Non implémenté |

---

## 📊 SETTINGS ENDPOINTS — VS Code vs Panda

### Ce qui EST branché (22 settings)
| Setting VS Code | Panda | Persistance | Appliqué à l'éditeur |
|---|---|---|---|
| `editor.fontSize` | ✅ | ✅ SharedPreferences | ⚠️ à vérifier |
| `editor.tabSize` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.wordWrap` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.indentGuides` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.bracketColorization` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.minimap` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.stickyScroll` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.renderWhitespace` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.highlightActiveLine` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.smoothScrolling` | ✅ | ✅ | ⚠️ à vérifier |
| `editor.fontFamily` | ✅ | ✅ | ⚠️ à vérifier |
| `terminal.shell` | ✅ | ✅ | ⚠️ à vérifier |
| `terminal.fontSize` | ✅ | ✅ | ⚠️ à vérifier |
| `terminal.cursorStyle` | ✅ | ✅ | ⚠️ à vérifier |
| `terminal.scrollback` | ✅ | ✅ | ⚠️ à vérifier |
| `git.autoFetch` | ✅ | ✅ | ⚠️ à vérifier |
| `git.inlineBlame` | ✅ | ✅ | ⚠️ à vérifier |
| `git.confirmPush` | ✅ | ✅ | ⚠️ à vérifier |
| `git.defaultBranch` | ✅ | ✅ | ⚠️ à vérifier |
| `workbench.colorTheme` | ✅ | ✅ | ⚠️ à vérifier |
| `ai.defaultProvider` | ✅ | ✅ | — |
| `ai.inlineCompletions` | ✅ | ✅ | ⚠️ à vérifier |

### Ce qui manque (settings VS Code non implémentés)
| Setting VS Code | Priorité | Effort |
|---|---|---|
| `editor.formatOnSave` | 🔴 Haute | Faible |
| `editor.cursorBlinking` | 🟡 Moyenne | Faible |
| `editor.lineNumbers` (on/off/relative) | 🟡 Moyenne | Faible |
| `editor.cursorStyle` (line/block/underline) | 🟡 Moyenne | Faible |
| `files.autoSave` (off/afterDelay/onFocusChange) | 🔴 Haute | Moyen |
| `files.encoding` | 🟡 Moyenne | Faible |
| `files.exclude` | 🟡 Moyenne | Moyen |
| `terminal.integrated.defaultProfile` | 🟡 Moyenne | Moyen |
| `search.exclude` | 🟡 Moyenne | Moyen |
| `search.smartCase` | 🟢 Faible | Faible |
| `debug.stopOnEntry` | 🟢 Faible | Faible |
| `scm.autoRefresh` | 🟢 Faible | Faible |
| `extensions.autoUpdate` | 🟢 Faible | Faible |
| `git.enableSmartCommit` | 🟢 Faible | Faible |
| `git.autofetch` (déjà dans gitPanel) | ✅ | — |
| `workbench.iconTheme` | 🟢 Faible | Faible |
| `editor.renderLineHighlight` | 🟡 Moyenne | Faible |
| `editor.suggestSelection` | 🟡 Moyenne | Faible |
| `editor.acceptSuggestionOnEnter` | 🟡 Moyenne | Faible |
| `editor.snippetSuggestions` | 🟢 Faible | Faible |

---

## 📊 FEATURES A→Z — Checklist mise à jour

### Ce qui est NOUVEAU depuis le dernier audit
| Feature | Status précédent | Status actuel |
|---|---|---|
| Settings persistence | ❌ | ✅ |
| Explorer context menu complet | ❌ | ✅ |
| Tab menu 12 actions | ❌ | ✅ |
| CodeLens provider | ❌ | ✅ |
| Settings search bar | ❌ | ✅ |
| Responsive breakpoints | ❌ | ✅ |
| Mobile bottom nav | ❌ | ✅ |
| Sidebar drawer (mobile) | ❌ | ✅ |
| Terminal bottom sheet | ❌ | ✅ |
| Accessibility semantics | ❌ | ✅ |
| Branch create/checkout UI | ❌ | ✅ |

### Ce qui reste IDENTIQUE au dernier audit (toujours manquant)
| Feature | Priorité | Status |
|---|---|---|
| Terminal multi-tab | 🔴 Critique | ❌ |
| Conditional breakpoints | 🟡 Haute | ❌ |
| Git stash UI | 🟡 Haute | ❌ |
| Git log/history | 🟡 Haute | ❌ |
| Preview editor (italic) | 🟡 Moyenne | ❌ |
| Drag & drop réordonner onglets | ✅ | ✅ |
| Launch configurations | 🔴 Haute | ❌ |
| Search exclude/include | 🟡 Moyenne | ❌ |
| Inlay hints | 🟡 Moyenne | ❌ |
| Settings JSON editor | 🟡 Moyenne | ❌ |
| Accessibility complète | 🟡 Haute | ⚠️ Partial |
| Zen mode | 🟢 Faible | ❌ |

---

## 📊 SCORE MIS À JOUR

| Critère | Poids | VS Code | Panda AVANT | Panda MAINTENANT | Δ |
|---|---|---|---|---|---|
| **Performance** | 20% | 7 | 5 | 5 | — |
| **Text editing** | 20% | 10 | 3 | **7** | **+4** |
| **LSP** | 15% | 10 | 5 | **7** | **+2** |
| **Extensions** | 15% | 10 | 6 | **8** | **+2** |
| **Git** | 10% | 9 | 1 | **7** | **+6** |
| **Debug** | 10% | 10 | 1 | 1 | — |
| **Terminal** | 5% | 8 | 8 | 8 | — |
| **UI/UX** | 5% | 8 | 6 | **8** | **+2** |
| **Mobile** | — | 0 | 7 | **8** | **+1** |
| **AI Integration** | — | 3 | 8 | **9** | **+1** |
| **TOTAL pondéré** | 100% | **8.85** | **4.40** | **6.80** | **+2.40** |

---

## 📋 PLAN D'IMPLÉMENTATION — Prochaines étapes

### Immédiat (cette session)
| # | Tâche | Effort | Impact |
|---|---|---|---|
| **FIX-1** | Workspace Quick Pick VS Code-style (séparateurs folders/files) | 4h | Haute |
| **FIX-2** | Status bar items interactifs (branch menu, encoding, indentation) | 6h | Haute |
| **FIX-3** | Terminal multi-tab (onglets, +, switch, close) | 12h | Critique |

### Semaine prochaine
| # | Tâche | Effort | Impact |
|---|---|---|---|
| **P2.7** | Preview editor (onglet italique) | 6h | Moyenne |
| **P2.5** | Git stash UI | 6h | Haute |
| **P2.6** | Git log/history | 8h | Haute |
| **P1.1** | Settings endpoints manquants (formatOnSave, autoSave, etc.) | 8h | Haute |

### Semaine 3
| # | Tâche | Effort | Impact |
|---|---|---|---|
| **P2.4** | Conditional breakpoints | 4h | Moyenne |
| **P2.7** | Launch configurations (debug.json) | 12h | Haute |
| **P4.4** | Settings mobile layout | 4h | Haute |
| **P4.6** | Pull-to-refresh | 3h | Moyenne |

---

## 🔢 RÉCAPITULATIF

### Ce qui a été fait (depuis le dernier audit)
1. ✅ SettingsService avec 22 endpoints persistés
2. ✅ Explorer context menu complet (Copy Path, Cut, etc.)
3. ✅ Tab menu 12 actions VS Code-style
4. ✅ CodeLens provider
5. ✅ Settings search bar
6. ✅ Responsive breakpoints (mobile/tablet/desktop)
7. ✅ Mobile bottom navigation (5 tabs)
8. ✅ Sidebar drawer (mobile)
9. ✅ Terminal bottom sheet
10. ✅ Accessibility semantics
11. ✅ Branch create/checkout UI

### Ce qui a été SAUTÉ (3 étapes)
1. ❌ **Workspace Quick Pick** — dropdown custom au lieu de VS Code Quick Pick
2. ❌ **Status bar interactifs** — items présents mais pas cliquables
3. ❌ **Terminal multi-tab** — complètement absent

### Ce qui reste à faire (top 10)
1. 🔴 Terminal multi-tab
2. 🔴 Settings endpoints manquants (12+ settings)
3. 🔴 Launch configurations (debug.json)
4. 🟡 Git stash UI
5. 🟡 Git log/history
6. 🟡 Preview editor (italic)
7. 🟡 Conditional breakpoints
8. 🟡 Pull-to-refresh
9. 🟡 Long press context menu
10. 🟢 Zen mode

---

*Rapport généré le 23 août 2026 — analyse de 198 fichiers Dart vs 10 385 fichiers VS Code.*
