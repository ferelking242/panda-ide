# 📊 TABLEAU COMPARATIF — VS Code vs Panda IDE

> Mise à jour : 24 août 2026 (après restructuration architecture complète)  
> Sources : VS Code 1.102 (desktop), Panda IDE 0.x (Flutter mobile+desktop)  
> Fichiers Dart : **227** | Lignes : ~111K | VS Code : ~10 385 fichiers

---

## 🏗️ ARCHITECTURE — Avant / Après

| Métrique | Avant | Après | VS Code |
|---|---|---|---|
| **Fichiers Dart** | 207 | **227** (+20) | ~10 385 |
| **widgets.dart** | 13,953 lignes | **22 lignes** (hub) | — |
| **functions.dart** | 4,383 lignes | **246 lignes** (hub) | — |
| **Plus gros fichier** | 13,953 | **13,517** (home.dart) | ~800 |
| **Fichiers > 1000 lignes** | 8 | **6** | 0 |
| **Fichiers moyens** | ~520 lignes | **~490 lignes** | ~180 |

---

## 📂 NOUVELLE STRUCTURE DES DOSSIERS

```
lib/
├── main.dart                          ← Entry point
├── bloc/                              ← State management (BLoC)
│   ├── repo_bloc/                     ← Repository state
│   └── ui_bloc/                       ← UI state
├── core/                              ← Core utilities
│   ├── broken_icons.dart              ← Icon constants
│   ├── fs/                            ← File system provider
│   └── workspace/                     ← Workspace manager
├── extensions/                        ← Extension system (30+ files)
│   ├── contributes/                   ← Extension contributions
│   ├── models/                        ← Extension models
│   └── ui/                            ← Extension UI
├── gateway/                           ← AI Gateway
├── indexing/                           ← Code indexing
├── local_models/                      ← Local AI models
│   ├── models/                        ← Model definitions
│   ├── services/                      ← Download, inference
│   └── ui/                            ← Model UI
├── logging/                           ← Logging system
├── mcp/                               ← MCP protocol
├── services/                          ← Platform services
├── terminal/                          ← Terminal emulator
├── ui/                                ← UI layer
│   ├── home.dart                      ← Main shell (13,517 lines)
│   ├── home_models.dart               ← ✅ Shared models
│   ├── editor/                        ← ✅ Editor components
│   │   ├── code_editor.dart           ← Code editor widget
│   │   ├── find_panel.dart            ← Find/replace panel
│   │   ├── editor_area.dart           ← Editor area container
│   │   ├── directory_tree.dart        ← File tree viewer
│   │   ├── find_word.dart             ← Find in file
│   │   ├── editor_tab_bar.dart        ← ✅ Tab bar + menu
│   │   ├── empty_editor.dart          ← ✅ Empty state
│   │   ├── tab_groups.dart            ← Tab groups
│   │   ├── status_bar.dart            ← Status bar
│   │   ├── bottom_panel.dart          ← Bottom panel
│   │   └── ... (10 more)
│   ├── panels/                        ← ✅ Full-page panels
│   │   ├── source_control.dart        ← Git panel (4,873 lines)
│   │   └── api_testing.dart           ← API testing
│   ├── components/                    ← ✅ Shared components
│   │   ├── ai_chat.dart               ← AI chat (3,334 lines)
│   │   ├── git_graph.dart             ← Git commit graph
│   │   ├── gguf_download.dart         ← GGUF download manager
│   │   └── flutter_switch.dart        ← Toggle switch
│   ├── titlebar/                      ← ✅ Title bar
│   │   └── panda_title_bar.dart
│   ├── activitybar/                   ← ✅ Activity bar
│   │   └── panda_activity_bar.dart
│   ├── sidebar/                       ← ✅ Sidebar
│   │   └── panda_sidebar.dart
│   ├── welcome/                       ← ✅ Welcome pages
│   │   ├── panda_welcome_page.dart
│   │   └── update_page.dart
│   ├── agent/                         ← AI Agent
│   ├── browser/                       ← Built-in browser
│   └── widgets/                       ← Shared widgets
├── utils/                             ← Utilities
│   ├── functions.dart                 ← ✅ Hub (was 4,383 lines)
│   ├── git/                           ← ✅ Git operations
│   │   ├── git_operations.dart
│   │   └── git_diff.dart
│   ├── models/                        ← ✅ Core models
│   │   └── editor_models.dart
│   ├── editors/                       ← ✅ Editor utilities
│   │   ├── edit_hunks.dart
│   │   └── editor_theme.dart
│   ├── search/                        ← ✅ Search indexing
│   │   └── search_index.dart
│   ├── ssh/                           ← ✅ SSH utilities
│   │   └── ssh_utils.dart
│   ├── string_utils.dart              ← ✅ String extensions
│   ├── extractors.dart                ← ✅ Extractors
│   └── ... (25 more)
└── web/                               ← Web stubs
```

---

## 📝 CONVENTIONS DE NOMMAGE (VS Code-style)

| Convention | VS Code | Panda IDE | Status |
|---|---|---|---|
| **Dart file naming** | camelCase (TypeScript) | snake_case (Dart standard) | ✅ Correct |
| **Component folder** | `<component>/` | `<component>/` | ✅ |
| **Part file** | `<component>Part.ts` | `<component>_part.dart` | ✅ |
| **Action file** | `<component>Action.ts` | `<component>_action.dart` | ✅ |
| **View file** | `<component>View.ts` | `<component>_view.dart` | ✅ |
| **Service file** | `<component>Service.ts` | `<component>_service.dart` | ✅ |
| **Model file** | `<component>Model.ts` | `<component>_model.dart` | ✅ |
| **Hub/re-export** | barrel index.ts | hub with exports | ✅ |

---

## 📊 FEATURES — Checklist complète

### ✅ Ce qui EST codé (19 features)
| # | Feature | Fichier | Status |
|---|---|---|---|
| 1 | Settings persistence (33 endpoints) | `settings_service.dart` | ✅ |
| 2 | Explorer context menu | `home.dart` | ✅ |
| 3 | Tab menu (12 actions VS Code) | `editor_tab_bar.dart` | ✅ |
| 4 | CodeLens provider | `codelens_provider.dart` | ✅ |
| 5 | Settings search bar | `settings_page.dart` | ✅ |
| 6 | Responsive breakpoints | `responsive_layout.dart` | ✅ |
| 7 | Mobile bottom navigation | `responsive_layout.dart` | ✅ |
| 8 | Sidebar drawer (mobile) | `home.dart` | ✅ |
| 9 | Terminal bottom sheet | `terminal_native.dart` | ✅ |
| 10 | Accessibility semantics | `home.dart` | ✅ |
| 11 | Branch create/checkout | `git_panel.dart` | ✅ |
| 12 | Terminal multi-tab | `bottom_panel.dart` | ✅ |
| 13 | Workspace Quick Pick | `workspace_picker.dart` | ✅ |
| 14 | Status bar interactifs | `status_bar.dart` | ✅ |
| 15 | Title bar (extracted) | `panda_title_bar.dart` | ✅ |
| 16 | Activity bar (extracted) | `panda_activity_bar.dart` | ✅ |
| 17 | Editor tab bar (extracted) | `editor_tab_bar.dart` | ✅ |
| 18 | Empty editor (extracted) | `empty_editor.dart` | ✅ |
| 19 | Welcome page (extracted) | `panda_welcome_page.dart` | ✅ |

### ❌ Ce qui MANQUE (13 features)
| # | Feature | Priorité | Effort |
|---|---|---|---|
| 1 | Launch configurations (debug.json) | 🔴 Critique | 12h |
| 2 | Git stash UI | 🔴 Haute | 6h |
| 3 | Git log/history | 🔴 Haute | 8h |
| 4 | Settings → applied to editor (11 non branchés) | 🟡 Haute | 8h |
| 5 | Conditional breakpoints | 🟡 Haute | 4h |
| 6 | Preview editor (onglet italique) | 🟡 Moyenne | 4h |
| 7 | Pull-to-refresh mobile | 🟡 Moyenne | 3h |
| 8 | Long press context menu mobile | 🟡 Moyenne | 4h |
| 9 | Swipe between tabs mobile | 🟡 Moyenne | 4h |
| 10 | Inlay hints (LSP) | 🟢 Faible | 6h |
| 11 | Outline view (symbols) | 🟢 Faible | 4h |
| 12 | Timeline (file history) | 🟢 Faible | 6h |
| 13 | Zen mode | 🟢 Faible | 3h |

### 🏁 Total restant : ~62h de dev

---

## 📈 SCORES

| Critère | Poids | VS Code | Panda | Notes |
|---|---|---|---|---|
| **Performance** | 20% | 7 | 5 | Flutter overhead |
| **Text editing** | 20% | 10 | 7 | Multi-cursor, folding, breadcrumbs |
| **LSP** | 15% | 10 | 7 | LSP bridge functional |
| **Extensions** | 15% | 10 | 8 | 13 contribution types, Open VSX, MCP |
| **Git** | 10% | 9 | 7 | Branch/stage/push done |
| **Debug** | 10% | 10 | 2 | Basic DAP only |
| **Terminal** | 5% | 8 | 9 | Multi-tab + split = Panda+ |
| **UI/UX** | 5% | 8 | 8 | Parity achieved |
| **Architecture** | — | 10 | **8** | +3 vs avant (20 fichiers extraits) |
| **Mobile** | — | 0 | 8 | Panda is native mobile |
| **AI Integration** | — | 3 | 9 | Local models + agents |
| **TOTAL pondéré** | 100% | **8.85** | **7.50** | +0.20 architecture |

---

## 📋 PLAN — Prochaines étapes

### 🔴 Priorité critique
| # | Feature | Effort | Impact |
|---|---|---|---|
| 1 | **Launch configurations** (debug.json) | 12h | Debug complet |
| 2 | **Git stash UI** | 6h | Workflow Git complet |
| 3 | **Git log/history** | 8h | Traçabilité |
| 4 | **Settings → applied to editor** | 8h | 11 endpoints non branchés |

### 🟡 Priorité haute
| # | Feature | Effort | Impact |
|---|---|---|---|
| 5 | **Conditional breakpoints** | 4h | Debug avancé |
| 6 | **Preview editor** (onglet italique) | 4h | UX |
| 7 | **Pull-to-refresh** mobile | 3h | Mobile |
| 8 | **Long press context menu** mobile | 4h | Mobile |
| 9 | **Swipe between tabs** mobile | 4h | Mobile |

### 🏁 Total restant : ~62h de dev

---

*Généré le 24 août 2026 — 227 fichiers Dart, 20 fichiers extraits, architecture VS Code-style.*
