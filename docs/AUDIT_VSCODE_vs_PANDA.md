# AUDIT COMPLET : VS Code vs Panda IDE
## Rapport de comparaison, gap analysis, et plan d'implémentation

**Date** : 23 août 2026  
**Référence VS Code** : microsoft/vscode (main branch, commit du 23/08/2026)  
**Référence Panda** : ferelking242/panda-ide (v2.3.3, commit 83fbeaa)

---

## TABLE DES MATIÈRES

1. [Chiffres clés](#1-chiffres-clés)
2. [Architecture](#2-architecture)
3. [UI Layout : comparaison visuelle](#3-ui-layout)
4. [Features A→Z : checklist complète](#4-features-a-z)
5. [Settings / Préférences](#5-settings)
6. [Extension System](#6-extension-system)
7. [Terminal](#7-terminal)
8. [Debug](#8-debug)
9. [Git / SCM](#9-git-scm)
10. [Search & Replace](#10-search-replace)
11. [Themes & Appearance](#11-themes)
12. [Accessibility](#12-accessibility)
13. [Adaptation Mobile](#13-adaptation-mobile)
14. [Plan d'implémentation par phase](#14-plan)
15. [Risques & Priorités](#15-risques)

---

## 1. CHIFFRES CLÉS

| Métrique | VS Code | Panda IDE | Ratio |
|---|---|---|---|
| **Fichiers source (src/)** | 10 385 | 193 | 54× |
| **Fichiers principaux** | 8 649 (.ts) | 193 (.dart) | 45× |
| **Lignes de code** | 2 708 444 | 106 801 | 25× |
| **Extensions built-in** | 106 | — | — |
| **Langages supportés** | 42 | 0 (via LSP only) | — |
| **Thèmes** | 9 (built-in) | 2 (dark/light) | 4.5× |
| **Contrib features** | 99 modules | 13 types | 7.6× |
| **Commands enregistrées** | 2 483 actions | ~104 (keybindings) | 24× |
| **Views (sidebar/panel)** | 2 366 registrations | ~15 | 158× |
| **Menus contextuels** | 252 MenuId | ~5 | 50× |
| **Settings IDs** | ~4 955 | ~30 (non branchés) | 165× |
| **Keybindings** | 289 registrations | 104 | 2.8× |
| **Pages UI** | ~200+ (contribution) | 64 fichiers | — |
| **Taille codebase** | 288 MB (source) | ~5 MB | 58× |

---

## 2. ARCHITECTURE

### VS Code — Architecture en couches

```
src/vs/
├── base/           → Utilitaires génériques (DOM, events, paths, workers)
├── platform/       → Services injectables (configuration, commands, dialogs, filesystem, etc.)
├── editor/         → Monaco Editor (le moteur d'édition)
├── workbench/      → L'application UI (layout, panels, vues)
│   ├── browser/    → Composants UI
│   ├── contrib/    → 99 modules feature (terminal, debug, git, search, etc.)
│   └── services/   → Services workbench (editor, terminal, etc.)
├── code/           → Points d'entrée (electron-main, browser, node)
└── server/         → Serveur LSP
```

### Panda IDE — Architecture modulaire Flutter

```
lib/
├── main.dart              → Point d'entrée
├── bloc/                  → State management (BLoC)
│   ├── repo_bloc/         → Bloc git/repository
│   └── ui_bloc/           → Bloc UI (thème, onglets, etc.)
├── core/                  → Utilitaires
├── extensions/            → Système d'extensions
│   ├── models/            → Manifest, types
│   ├── ui/                → Marketplace, command palette, etc.
│   └── *_bridge.dart      → IPC, LSP, FS, SCM, etc.
├── gateway/               → Remote Gateway (SSH/Tunnel)
├── local_models/          → IA locale (ollama, etc.)
├── logging/               → Logging
├── mcp/                   → MCP (Model Context Protocol)
├── services/              → Services Flutter (ADB, Flutter SDK, etc.)
├── terminal/              → Terminal (pty)
├── ui/                    → Toute l'UI
│   ├── editor/            → Éditeur (tabs, status bar, breadcrumbs, etc.)
│   ├── agent/             → AI Agent rooms
│   ├── browser/           → Navigateur intégré
│   ├── panda_ai_ui/       → Chat AI
│   ├── widgets/           → Composants réutilisables
│   └── *.dart             → Pages (home, settings, etc.)
├── utils/                 → Constantes, thèmes
└── web/                   → Web-specific
```

### Différences architecturales clés

| Aspect | VS Code | Panda |
|---|---|---|
| Langage | TypeScript | Dart (Flutter) |
| Editor engine | Monaco (C++ compilé en WASM) | Custom Flutter (text rendering) |
| State management | Observable pattern | BLoC |
| Extension isolation | Node.js process | Dart isolates |
| IPC | JSON-RPC over stdio | Custom message passing |
| Platform | Desktop + Web | Mobile + Web |
| Layout | Grid CSS (part system) | Flutter Row/Column/Stack |

---

## 3. UI LAYOUT : COMPARAISON

### Structure globale

```
VSCODE:                                    PANDA (mobile):
┌───┬──────┬────────────────────┐         ┌──────────────────────┐
│   │      │    TOP BAR          │         │   TOP BAR            │
│ A ├──────┤ [← →] [Workspace]  │         │ [← →] [Workspace]   │
│ C │      │       [icons]       │         │    [icons]           │
│ T │ SIDE ├────────────────────┤         ├──────┬───────────────┤
│ I │ BAR  │ TAB BAR             │         │      │              │
│ V ├──────┤ README.md × ...    │         │ ACT  │   EDITOR     │
│ I │      ├────────────────────┤         │ BAR  │              │
│ T │      │   EDITOR            │         │      │              │
│ Y │      │                     │         │      │              │
│   │      │                     │         │      │              │
│ B ├──────┤────────────────────┤         │      │              │
│ A │      │   BOTTOM PANEL      │         ├──────┤──────────────┤
│ R │      │ Terminal/Problems   │         │      │ BOTTOM PANEL │
│   ├──────┤────────────────────┤         │      │              │
│   │      │   STATUS BAR        │         ├──────┴──────────────┤
│   │      │ Ln 1, Col 1 UTF-8  │         │   STATUS BAR        │
└───┴──────┴────────────────────┘         └──────────────────────┘
```

### Top Bar
| Élément | VS Code | Panda | Status |
|---|---|---|---|
| Navigation (← →) | ✅ Flèches | ✅ Flèches | ✅ |
| Workspace box centrée | ✅ | ✅ (fixé) | ✅ |
| Layout icons (split) | ✅ 4 modes | ✅ 4 modes | ✅ |
| Menu hamburger | ❌ | ❌ | ✅ |

### Activity Bar (icônes latérales)
| Icône | VS Code | Panda | Status |
|---|---|---|---|
| Explorer (fichiers) | ✅ | ✅ | ✅ |
| Search | ✅ | ✅ | ✅ |
| Source Control (Git) | ✅ | ✅ | ✅ |
| Debug | ✅ | ✅ | ✅ |
| Extensions | ✅ | ✅ (Marketplace) | ✅ |
| Remote/Tunnel | ✅ | ✅ (Gateway) | ✅ |
| Panda Agent | ❌ | ✅ (unique) | ✅ Unique |
| AI Copilot | ✅ (extension) | ✅ (built-in) | ✅ |
| Navigateur | ❌ | ✅ (unique) | ✅ Unique |

### Tab Bar (onglets)
| Comportement | VS Code | Panda | Status |
|---|---|---|---|
| Onglets individuels | ✅ borderRadius par onglet | ✅ | ✅ |
| Pas de ligne de séparation bas | ✅ | ✅ (fixé) | ✅ |
| Menu "..." éditeur | ✅ Close All, Split, etc. | ✅ | ✅ |
| Drag & drop réordonner | ✅ | ❌ | ❌ |
| Onglet dirty (•) | ✅ | ✅ | ✅ |
| Preview mode (italique) | ✅ | ❌ | ❌ |

### Sidebar Panel
| Comportement | VS Code | Panda | Status |
|---|---|---|---|
| Pousse l'éditeur | ✅ | ✅ (fixé) | ✅ |
| Header "Explorer ⋯ ✕" | ✅ | ✅ | ✅ |
| Cards arrondies (borderRadius 8) | ✅ subtil | ✅ _SidebarCard | ✅ |
| Gap entre cartes | ✅ 8px | ✅ | ✅ |
| Fond subtil contrasté | ✅ | ✅ | ✅ |
| Resizable (drag border) | ✅ | ❌ | ❌ |

### Bottom Panel
| Comportement | VS Code | Panda | Status |
|---|---|---|---|
| Terminal tab | ✅ | ✅ | ✅ |
| Problems tab | ✅ | ✅ | ✅ |
| Output tab | ✅ | ✅ | ✅ |
| Debug Console tab | ✅ | ✅ | ✅ |
| Output Channels | ✅ (multiples) | ✅ (extension) | ✅ |
| Resizable height | ✅ (drag) | ✅ (drag handle) | ✅ |

### Workspace Box Click (dropdown)
| Élément | VS Code | Panda | Status |
|---|---|---|---|
| Quick Pick « Open Recent » | ✅ (folders + files séparés) | ✅ | ✅ |
| Séparateur « folders & workspaces » | ✅ | ❌ | P1 |
| Séparateur « files » | ✅ | ❌ | P1 |
| Supprimer du récent (×) | ✅ | ❌ | P2 |
| Workspace « dirty » indicator | ✅ | ❌ | P2 |
| Cmd/Ctrl-click → new window | ✅ | ❌ | P3 |
| Remove from recently opened | ✅ | ❌ | P2 |

### Editor Tab "..." Menu (MenuId.EditorTitle)
| Action | VS Code | Panda | Status |
|---|---|---|---|
| Show Opened Editors | ✅ | ❌ | P1 |
| Close All | ✅ | ✅ | ✅ |
| Close Saved | ✅ | ✅ | ✅ |
| Toggle Preview Editors | ✅ | ❌ | P2 |
| Inline View (diff) | ✅ | ❌ | P2 |

### Editor Tab Context Menu (MenuId.EditorTitleContext) — right-click on tab
| Action | VS Code | Panda | Status |
|---|---|---|---|
| Close | ✅ | ✅ | ✅ |
| Close Others | ✅ | ✅ | ✅ |
| Close to the Right | ✅ | ❌ | P1 |
| Close Saved | ✅ | ✅ | ✅ |
| Close All | ✅ | ✅ | ✅ |
| Reopen Editor With... | ✅ | ❌ | P2 |
| Keep Open (unpin preview) | ✅ | ❌ | P2 |
| Pin / Unpin | ✅ | ❌ | P2 |
| Split Right | ✅ | ✅ | ✅ |
| Split & Move submenu | ✅ | ❌ | P2 |
| Move into New Window | ✅ | ❌ (mobile) | P3 |
| Copy into New Window | ✅ | ❌ (mobile) | P3 |
| Share submenu | ✅ | ❌ | P2 |

### Explorer Context Menu (MenuId.ExplorerContext) — right-click on file/folder
| Action | VS Code | Panda | Status |
|---|---|---|---|
| New File... | ✅ | ✅ | ✅ |
| New Folder... | ✅ | ✅ | ✅ |
| Open With... | ✅ | ❌ | P2 |
| Copy Path | ✅ | ❌ | P1 |
| Copy Relative Path | ✅ | ❌ | P1 |
| Cut | ✅ | ❌ | P1 |
| Copy | ✅ | ❌ | P1 |
| Paste | ✅ | ❌ | P1 |
| Download | ✅ | ❌ | P2 |
| Upload | ✅ | ❌ | P2 |
| Add Root Folder | ✅ | ❌ | P2 |
| Remove Root Folder | ✅ | ❌ | P2 |
| Rename (F2) | ✅ | ❌ | P1 |
| Delete (Del) | ✅ | ❌ | P1 |
| Compare with Selected | ✅ | ❌ | P2 |
| Select for Compare | ✅ | ❌ | P2 |
| Reveal in OS | ✅ | ❌ | P3 |
| Open in Integrated Terminal | ✅ | ❌ | P2 |

### Sidebar View Header Menu (MenuId.ViewContainerTitleContext)
| Action | VS Code | Panda | Status |
|---|---|---|---|
| Toggle Primary Side Bar Visibility | ✅ | ✅ (toggle) | ✅ |
| Toggle Primary Side Bar Position (left/right) | ✅ | ❌ | P2 |
| Move Views to Another Side Bar | ✅ | ❌ | P3 |
| Hide Panel | ✅ | ✅ | ✅ |

### Status Bar
| Comportement | VS Code | Panda | Status |
|---|---|---|---|
| Couleur unie | ✅ (bleu par défaut) | ✅ (dark, fixé) | ✅ |
| Pas d'arrondi | ✅ | ✅ (fixé) | ✅ |
| Left items (branch, errors) | ✅ | ✅ | ✅ |
| Right items (encoding, line) | ✅ | ✅ | ✅ |
| Items cliquables (menus) | ✅ (128 registrations) | ✅ | ✅ |
| Remote indicator (SSH, etc) | ✅ | ✅ (Gateway) | ✅ |
| Branch name clickable | ✅ (branch menu) | ❌ | P1 |
| Error/warning counts clickable | ✅ (Problems panel) | ✅ | ✅ |
| Encoding selector | ✅ | ❌ | P2 |
| Line ending selector | ✅ | ❌ | P3 |
| Indentation selector | ✅ | ❌ | P2 |
| Notification bell | ✅ | ✅ | ✅ |
| Progress indicator | ✅ | ✅ | ✅ |
| Profile selector | ✅ | ❌ | P3 |
| Notification center | ✅ (toast + center) | ✅ | ✅ |

---

## 4. FEATURES A→Z : CHECKLIST COMPLÈTE

### A
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Accessibility (screen reader) | ✅ | ❌ | P2 |
| AI Chat (Copilot/Agent) | ✅ (extension) | ✅ (built-in 8 providers) | ✅ Unique |
| Auto-close brackets | ✅ | ✅ | ✅ |
| Auto-save | ✅ | ✅ | ✅ |

### B
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Breadcrumbs | ✅ | ✅ | ✅ |
| Bracket colorization | ✅ | ✅ | ✅ |
| Bracket pair colorizer | ✅ (built-in) | ✅ | ✅ |
| Built-in terminal | ✅ | ✅ | ✅ |

### C
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Code folding | ✅ | ✅ | ✅ |
| Code lens | ✅ | ❌ | P1 |
| Code Actions (quickfix) | ✅ | ✅ (LSP) | ✅ |
| Code formatting | ✅ | ✅ (LSP) | ✅ |
| Code completion | ✅ | ✅ (LSP + Ghost text) | ✅ |
| Command palette | ✅ | ✅ | ✅ |
| Comments / review | ✅ | ❌ | P2 |
| Custom editors | ✅ | ❌ | P3 |

### D
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Debug (breakpoints, step) | ✅ | ✅ | ✅ |
| Debug console | ✅ | ✅ | ✅ |
| Diff viewer (side-by-side) | ✅ | ✅ | ✅ |
| Diagnostics (problems) | ✅ | ✅ | ✅ |
| Dictionary / spellcheck | ✅ (extension) | ❌ | P3 |
| Drag & drop files | ✅ | ❌ | P2 |

### E
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Editor tabs | ✅ | ✅ | ✅ |
| Editor groups (split) | ✅ | ✅ | ✅ |
| Emmet | ✅ | ❌ | P2 |
| Extension marketplace | ✅ | ✅ (Open VSX) | ✅ |
| Extension auto-update | ✅ | ❌ | P2 |
| Extension dependencies | ✅ | ✅ (recursive) | ✅ |

### F
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Find & Replace (regex) | ✅ | ✅ | ✅ |
| Find in Files (global) | ✅ | ✅ | ✅ |
| File explorer (tree) | ✅ | ✅ | ✅ |
| File watching | ✅ | ✅ | ✅ |
| File icons | ✅ | ✅ (codicon) | ✅ |
| Font ligatures | ✅ | ❌ | P3 |
| Folders / workspace | ✅ | ✅ | ✅ |
| Formatting on save | ✅ | ✅ | ✅ |

### G
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Git (commit, push, pull) | ✅ | ✅ | ✅ |
| Git inline blame | ✅ (extension) | ✅ (setting) | ✅ |
| Git conflict resolution | ✅ | ✅ (diff viewer) | ✅ |
| Go to definition | ✅ | ✅ (LSP) | ✅ |
| Go to line (Ctrl+G) | ✅ | ✅ | ✅ |
| Go to symbol | ✅ | ✅ (symbol picker) | ✅ |
| Grammar (syntax highlighting) | ✅ (TextMate) | ✅ (custom) | ✅ |

### H
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Hover info | ✅ | ✅ (LSP) | ✅ |
| Highlight active line | ✅ | ✅ | ✅ |
| Highlight occurrences | ✅ | ✅ | ✅ |
| HTML preview | ✅ | ✅ (webview) | ✅ |
| Hex editor | ✅ (extension) | ❌ | P3 |

### I
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Inline completions (Copilot) | ✅ | ✅ (ghost text) | ✅ |
| Inlay hints | ✅ | ❌ | P2 |
| Indent guides | ✅ | ✅ | ✅ |
| Input box (palette) | ✅ | ✅ | ✅ |

### J-K
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| JSON schema support | ✅ | ✅ | ✅ |
| Keybindings editor | ✅ | ✅ | ✅ |
| Keybindings search by key | ✅ | ❌ | P2 |

### L
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Language support (LSP) | ✅ | ✅ | ✅ |
| Languages (built-in) | 42 | 0 (via extensions) | P2 |
| List/tree views | ✅ | ✅ | ✅ |
| Local history | ✅ | ❌ | P2 |
| Log output channels | ✅ | ✅ | ✅ |

### M
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Minimap | ✅ | ✅ | ✅ |
| Multi-cursor | ✅ | ✅ | ✅ |
| Markdown preview | ✅ | ✅ | ✅ |
| Merge editor | ✅ | ❌ | P2 |
| MCP support | ✅ (via chat) | ✅ (built-in) | ✅ Unique |

### N
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Notification system | ✅ | ✅ | ✅ |
| New file/folder | ✅ | ✅ | ✅ |
| Notebook support | ✅ | ❌ | P3 |
| Notification actions | ✅ | ✅ | ✅ |

### O
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Open file | ✅ | ✅ | ✅ |
| Open recent | ✅ | ✅ | ✅ |
| Open folder/workspace | ✅ | ✅ | ✅ |
| Outline (symbols) | ✅ | ✅ (symbol picker) | ✅ |

### P
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Problems panel | ✅ | ✅ | ✅ |
| Preview editor | ✅ | ❌ | P1 |
| Profiles | ✅ | ❌ | P3 |
| Process explorer | ✅ | ❌ | P3 |

### Q
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Quick open (Ctrl+P) | ✅ | ✅ | ✅ |
| Quick pick | ✅ | ✅ | ✅ |
| Quick fix | ✅ | ✅ (LSP) | ✅ |

### R
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| References (find all) | ✅ | ✅ (LSP) | ✅ |
| Rename symbol | ✅ | ✅ (LSP) | ✅ |
| Replace in files | ✅ | ✅ | ✅ |
| Remote (SSH, Container) | ✅ | ✅ (Gateway) | ✅ |
| Run without debug | ✅ | ❌ | P2 |
| Resize panels | ✅ | ✅ | ✅ |

### S
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Search (files) | ✅ | ✅ | ✅ |
| Settings UI | ✅ (JSON + GUI) | ✅ (GUI only) | P1 |
| Settings search | ✅ | ❌ | P1 |
| Settings sync | ✅ | ❌ | P3 |
| Snippets | ✅ | ✅ | ✅ |
| Split editor | ✅ | ✅ | ✅ |
| Sticky scroll | ✅ | ✅ | ✅ |
| Source control panel | ✅ | ✅ | ✅ |
| Status bar items | ✅ | ✅ | ✅ |
| Syntax highlighting | ✅ | ✅ | ✅ |
| Symbols (outline) | ✅ | ✅ | ✅ |

### T
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Terminal (integrated) | ✅ | ✅ | ✅ |
| Terminal profiles | ✅ | ✅ (shell picker) | ✅ |
| Terminal split | ✅ | ❌ | P2 |
| Terminal tabs | ✅ | ❌ | P2 |
| Timeline | ✅ | ❌ | P3 |
| Tab groups | ✅ | ✅ | ✅ |
| Task runner | ✅ | ✅ | ✅ |
| Theme (dark/light) | ✅ | ✅ | ✅ |
| Theme (custom colors) | ✅ | ✅ (per-school) | ✅ |

### U-V
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| URI handler | ✅ | ❌ | P2 |
| View containers | ✅ | ✅ | ✅ |
| View badges | ✅ | ❌ | P2 |

### W-X-Y-Z
| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Welcome page / walkthrough | ✅ | ✅ (start screen) | ✅ |
| Word wrap | ✅ | ✅ | ✅ |
| Zen mode | ✅ | ❌ | P3 |
| Zoom in/out | ✅ | ✅ | ✅ |

---

## 5. SETTINGS / PRÉFÉRENCES

### VS Code Settings (50 catégories principales, ~4 955 IDs)

| Catégorie | Exemples de settings | Panda equivalent |
|---|---|---|
| `editor.*` (187+) | fontSize, fontFamily, wordWrap, minimap, formatOnSave, tabSize, renderWhitespace, cursorStyle, lineNumbers, smoothScrolling, bracketPairColorization, stickyScroll | ✅ ~10/187 |
| `workbench.*` (30+) | colorTheme, iconTheme, editor.*Layout, sideBar.* | ✅ ~3/30 |
| `terminal.*` (12+) | integrated.fontSize, integrated.defaultProfile, integrated.scrollback | ✅ ~4/12 |
| `files.*` (5+) | autoSave, encoding, exclude, associations | ❌ 0/5 |
| `git.*` (10+) | autorefresh, confirmSync, enableSmartCommit, decorations.* | ✅ ~4/10 |
| `debug.*` (15+) | allowBreakpointsEverywhere, console, inline.* | ✅ ~2/15 |
| `search.*` (8+) | exclude, include, useIgnoreFiles, smartCase | ✅ ~2/8 |
| `extensions.*` (5+) | autoUpdate, ignoreRecommendations | ❌ 0/5 |
| `scm.*` (5+) | autoRefresh, decorations.* | ❌ 0/5 |
| `notebook.*` (20+) | (tout) | ❌ 0/20 |
| `markdown.*` (15+) | preview.*, editor.* | ✅ ~1/15 |
| `http.*` | proxy, systemCertificates | ❌ |
| `security.*` | workspace.* | ❌ |
| `telemetry.*` | telemetryLevel | ❌ |
| `update.*` | channel, mode | ❌ |
| `accessibility.*` | settings | ❌ |

### Panda Settings actuels (8 sections, ~30 settings)

```
Editor:      Font Size, Tab Size, Word Wrap, Indent Guides, Bracket Colorization,
             Minimap, Sticky Scroll, Whitespace, Highlight Line, Smooth Scrolling

Terminal:    Shell, Font Size, Cursor Style, Scroll Back

Git:         Auto Fetch, Inline Blame, Confirm Push, Default Branch

Extensions:  List installed (manage per extension)

AI:          Provider, Gateway URL, Token, Inline Completions

Appearance:  Theme (dark/light/system), Icon Theme, Font Family

Keybindings: 13 shortcuts listed (read-only)

About:       Version, repo, license
```

### Gap Settings : ce qui manque

| Setting VS Code | Panda | Impact |
|---|---|---|
| `editor.fontSize` persistant | ❌ (stepper non branché) | Critique |
| `editor.fontFamily` persistant | ❌ | Haute |
| `editor.formatOnSave` | ❌ | Haute |
| `editor.cursorBlinking` | ❌ | Moyenne |
| `editor.cursorStyle` | ❌ | Moyenne |
| `editor.lineNumbers` (on/off/relative) | ❌ | Moyenne |
| `editor.renderWhitespace` (boundary/all) | ❌ | Faible |
| `editor.bracketPairColorization.enabled` | ❌ | Faible |
| `editor.minimap.enabled` | ❌ (switch non branché) | Moyenne |
| `editor.stickyScroll.enabled` | ❌ | Faible |
| `workbench.colorTheme` persistant | ❌ | Critique |
| `workbench.iconTheme` | ❌ | Faible |
| `files.autoSave` (off/afterDelay/onFocusChange) | ❌ | Critique |
| `files.encoding` | ❌ | Moyenne |
| `terminal.integrated.fontSize` | ❌ | Haute |
| `terminal.integrated.defaultProfile.osx` | ❌ (shell picker non branché) | Moyenne |
| `git.autofetch` persistant | ❌ | Moyenne |
| `git.enableSmartCommit` | ❌ | Faible |
| `search.exclude` | ❌ | Moyenne |
| `debug.stopOnEntry` | ❌ | Faible |
| `scm.autoRefresh` | ❌ | Faible |
| `extensions.autoUpdate` | ❌ | Faible |
| JSON settings editor | ❌ | P2 |

**Total gap : ~22 settings critiques/hautes non branchés** — les Switches dans la page Settings sont purement visuels, ils ne sauvegardent pas.

---

## 6. EXTENSION SYSTEM

### VS Code Contribution Types (24 types)

| # | Type | Count extensions | Panda |
|---|---|---|---|
| 1 | `commands` | 30 | ✅ |
| 2 | `views` | 4 | ✅ (sidebar + panel) |
| 3 | `viewsContainers` | 2 | ❌ |
| 4 | `viewsWelcome` | 3 | ❌ |
| 5 | `menus` | 15 | ✅ |
| 6 | `keybindings` | 4 | ✅ |
| 7 | `configuration` | 103 | ✅ |
| 8 | `languages` | 56 | ✅ |
| 9 | `grammars` | 51 | ✅ |
| 10 | `snippets` | 17 | ✅ |
| 11 | `themes` | 10 | ✅ |
| 12 | `icons` | 1 | ✅ |
| 13 | `debuggers` | 2 | ❌ |
| 14 | `authentication` | 2 | ❌ |
| 15 | `taskDefinitions` | 6 | ❌ |
| 16 | `problemPatterns` | 2 | ❌ |
| 17 | `notebooks` | 2 | ❌ |
| 18 | `chatParticipants` | 2 | ❌ |
| 19 | `languageModelTools` | 3 | ❌ |
| 20 | `terminalProfiles` | 1 | ❌ |
| 21 | `semanticTokenTypes` | 1 | ❌ |
| 22 | `colors` | 2 | ❌ |
| 23 | `localizations` | 1 | ❌ |
| 24 | `resourceFileFormats` | 1 | ❌ |

### Panda Unique Extension Features (pas dans VS Code standard)

| Feature | Description |
|---|---|
| `services` | Extensions exposant des services Dart |
| `listeners` | Extensions écoutant des événements |
| `webviews` | WebView panels avancés |
| `permissions` | Système de permissions par extension |
| `native_extension_loader` | Chargement via `dart:isolate` |
| `marketplace_open_vsx` | Open VSX au lieu du marketplace Microsoft |
| `extension_host_isolate` | Isolation complète par isolate Dart |

### Activation Events

| VS Code | Panda | Status |
|---|---|---|
| `*` / `onStartup` | `on_startup` | ✅ |
| `onStartupFinished` | `onStartupFinished` | ✅ |
| `onCommand:<id>` | `onCommand:<id>` | ✅ |
| `onLanguage:<id>` | `onLanguage:<id>` | ✅ |
| `onUri` | ❌ | ❌ |
| `workspaceContains` | ✅ (via `workspaceContains`) | ✅ |
| `onDebug` | ❌ | ❌ |
| `onFileSystem` | ❌ | ❌ |
| `onNotebookSerializer` | ❌ | ❌ |

### Extension Bridges (VS Code ↔ Panda)

| Bridge | Panda | VS Code equivalent |
|---|---|---|
| `ipc_bridge.dart` | ✅ | JSON-RPC over stdio |
| `lsp_bridge.dart` | ✅ | LSP client |
| `fs_bridge.dart` | ✅ | FileSystemProvider |
| `scm_bridge.dart` | ✅ | SourceControl API |
| `tasks_bridge.dart` | ✅ | TaskProvider |
| `workspace_bridge.dart` | ✅ | Workspace API |
| `debug_bridge.dart` | ✅ | DebugAdapterDescriptorFactory |
| `extension_api_router.dart` | ✅ | vscode.* namespace |

---

## 7. TERMINAL

| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Intégré (pty) | ✅ | ✅ | — |
| Multi-terminal (tabs) | ✅ | ❌ | P1 |
| Split terminal | ✅ | ❌ | P2 |
| Shell profiles | ✅ (bash/zsh/powershell) | ✅ (bash/zsh/sh) | ✅ |
| Terminal fontSize | ✅ | ✅ | ✅ |
| Terminal theme (color) | ✅ | ❌ | P2 |
| Terminal scrollbar | ✅ | ✅ | ✅ |
| Terminal bell | ✅ | ❌ | P3 |
| Terminal links (clickable) | ✅ | ❌ | P2 |
| Terminal search (Ctrl+F) | ✅ | ❌ | P2 |
| Terminal send text (programmatic) | ✅ | ✅ | ✅ |
| Terminal process | Node.js PTY | Alpine PTY | — |

---

## 8. DEBUG

| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Breakpoints (set/remove) | ✅ | ✅ | ✅ |
| Conditional breakpoints | ✅ | ❌ | P1 |
| Logpoints | ✅ | ❌ | P2 |
| Start/Stop/Restart | ✅ | ✅ | ✅ |
| Step over/into/out | ✅ | ✅ | ✅ |
| Continue/Pause | ✅ | ✅ | ✅ |
| Variables panel | ✅ | ✅ | ✅ |
| Watch expressions | ✅ | ❌ | P2 |
| Call stack panel | ✅ | ✅ | ✅ |
| Debug console | ✅ | ✅ | ✅ |
| Launch configurations | ✅ (launch.json) | ❌ | P1 |
| Multi-session debug | ✅ | ❌ | P3 |
| Debug adapters (DAP) | ✅ | ✅ (via bridge) | ✅ |

---

## 9. GIT / SCM

| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Commit | ✅ | ✅ | ✅ |
| Push / Pull | ✅ | ✅ | ✅ |
| Fetch | ✅ | ✅ | ✅ |
| Branch management | ✅ (sidebar) | ✅ (git panel) | ✅ |
| Staging (hunks/files) | ✅ | ✅ | ✅ |
| Discard changes | ✅ | ✅ | ✅ |
| Diff view | ✅ (inline + side) | ✅ (side-by-side) | ✅ |
| Merge conflicts | ✅ | ✅ | ✅ |
| Inline blame | ✅ (GitLens ext) | ✅ (setting) | ✅ |
| Create branch | ✅ | ❌ | P1 |
| Checkout branch | ✅ | ❌ | P1 |
| Git log / history | ✅ (Timeline) | ❌ | P2 |
| Stash | ✅ | ❌ | P2 |
| Cherry-pick | ❌ (CLI) | ❌ | P3 |
| Rebase UI | ❌ (CLI) | ❌ | P3 |
| Auto-fetch | ✅ | ✅ | ✅ |
| Git decorations (colors) | ✅ | ✅ | ✅ |

---

## 10. SEARCH & REPLACE

| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Search in current file | ✅ | ✅ | ✅ |
| Search in files (global) | ✅ | ✅ | ✅ |
| Regex search | ✅ | ✅ | ✅ |
| Case sensitive toggle | ✅ | ✅ | ✅ |
| Whole word toggle | ✅ | ✅ | ✅ |
| Replace single | ✅ | ✅ | ✅ |
| Replace all | ✅ | ✅ | ✅ |
| Search exclude patterns | ✅ | ❌ | P2 |
| Search include patterns | ✅ | ❌ | P2 |
| Search history | ✅ | ❌ | P2 |
| Results tree view | ✅ (file → match) | ✅ | ✅ |
| Open in editor (search editor) | ✅ | ❌ | P3 |

---

## 11. THEMES & APPEARANCE

| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Dark theme | ✅ | ✅ | ✅ |
| Light theme | ✅ | ✅ | ✅ |
| System theme (auto) | ✅ | ✅ | ✅ |
| Custom color themes | ✅ (TextMate) | ✅ (Flutter theme) | ✅ |
| Per-school accent color | ❌ | ✅ (unique) | ✅ Unique |
| Icon themes | ✅ (many) | ✅ (default) | ✅ |
| Product icon themes | ✅ | ❌ | P3 |
| Font family (editor) | ✅ | ✅ | ✅ |
| Font size | ✅ | ✅ | ✅ |
| Font ligatures | ✅ | ❌ | P3 |
| Custom CSS (via extension) | ✅ | ❌ | P3 |
| Window title | ✅ | ❌ | P3 |
| Zoom level | ✅ | ✅ | ✅ |

---

## 12. ACCESSIBILITY

| Feature | VS Code | Panda | Priorité |
|---|---|---|---|
| Screen reader announcements | ✅ (ARIA) | ❌ | P2 |
| Keyboard navigation (Tab) | ✅ | ✅ | ✅ |
| Focus indicators | ✅ | ✅ | ✅ |
| High contrast theme | ✅ | ❌ | P2 |
| Reduced motion | ✅ | ❌ | P3 |
| Accessibility settings | ✅ | ❌ | P2 |
| Voice control | ✅ (via extension) | ❌ | P3 |

---

## 13. ADAPTATION MOBILE

### Stratégie VS Code sur mobile (vscode.dev)

VS Code sur mobile utilise :
- **Responsive layout** : sidebar réduite en icônes, bottom bar adaptée
- **Touch targets** : min 44px (Apple) / 48px (Material)
- **Bottom sheets** au lieu de menus déroulants
- **Drawer navigation** au lieu de sidebar fixe
- **Gestures** : swipe pour ouvrir/fermer sidebar
- **Toolbar contextuelle** : les boutons changent selon le contexte

### Panda sur mobile — ce qui existe déjà

| Composant | Panda | Status |
|---|---|---|
| `mobile_touch_toolbar.dart` | ✅ | Unique — toolbar tactile contextuelle |
| `adb_setup_page.dart` | ✅ | Unique — setup via WiFi ADB |
| Responsive layout (mobile/desktop) | ✅ (Flutter responsive) | ✅ |
| Bottom sheet panels | ✅ | ✅ |
| Swipe gestures | ✅ (some) | ⚠️ Partiel |
| Touch-friendly buttons | ✅ (Material) | ✅ |

### Ce qu'il faut ajouter pour mobile

| Feature | Priorité | Effort | Description |
|---|---|---|---|
| **Responsive breakpoints** | P0 | 4h | Définir breakpoints: <600px (mobile), 600-1024 (tablet), >1024 (desktop) |
| **Sidebar → Drawer** | P0 | 8h | Sur mobile, la sidebar devient un Drawer (swipe left) |
| **Bottom Navigation** | P0 | 6h | Sur mobile: tabs en bas au lieu de activity bar à gauche |
| **Pull-to-refresh** | P1 | 3h | Pull down pour refresh file tree, git status |
| **Long press context menu** | P1 | 4h | Long press sur fichier → menu contextuel |
| **Swipe between tabs** | P1 | 3h | Swipe left/right pour changer d'onglet |
| **Pinch-to-zoom editor** | P2 | 4h | Zoom dans l'éditeur |
| **Haptic feedback** | P2 | 2h | Vibration sur actions importantes |
| **Keyboard shortcuts overlay** | P2 | 4h | Overlay touch pour les raccourcis clavier |
| **Floating action button** | P2 | 3h | FAB pour actions fréquentes (new file, save, etc.) |
| **Split view (tablet)** | P2 | 6h | Sur tablet: sidebar + éditeur côte à côte |
| **Bottom panel → sheet** | P1 | 3h | Terminal en bottom sheet draggable |
| **Settings mobile layout** | P1 | 4h | Settings en liste pleine largeur (pas de sidebar split) |
| **Notification drawer** | P1 | 2h | Notifications en slide-in depuis le haut |

### Adaptation UI par breakpoint

```
MOBILE (<600px)                     TABLET (600-1024px)           DESKTOP (>1024px)
┌──────────────┐                    ┌────┬──────────┐           ┌──┬────┬──────────┐
│  TOP BAR     │                    │    │  TOP BAR  │           │AC│ SB │  TOP BAR  │
├──────────────┤                    │ SB ├──────────┤           │TI├────┤──────────┤
│  EDITOR      │                    │    │  EDITOR   │           │V │ ED │ TABS     │
│  (full)      │                    │    │           │           │I ├────┤──────────┤
│              │                    │    │           │           │B │    │ EDITOR   │
├──────────────┤                    ├────┤──────────┤           │A │    │          │
│  BOTTOM NAV  │                    │NAV │  BOTTOM   │           │R ├────┤──────────┤
│ ⚙️ 🔍 📁 🤖  │                    │    │  PANEL    │           │  │    │ BOTTOM   │
│              │                    │    │           │           │  │    │ PANEL    │
├──────────────┤                    ├────┴──────────┤           ├──┴────┼──────────┤
│  STATUS BAR  │                    │  STATUS BAR   │           │  STATUS BAR      │
└──────────────┘                    └───────────────┘           └──────────────────┘
Sidebar → Drawer                     Sidebar réduite            Sidebar complète
Bottom nav (5 items)                 Bottom nav (icônes)        Activity bar
Tabs → scroll horizontal             Tabs normaux               Tabs normaux
Terminal → Bottom sheet              Terminal panel             Terminal panel
Settings → liste pleine              Settings split             Settings split
```

---

## 14. PLAN D'IMPLÉMENTATION PAR PHASE

### Phase 0 : Immédiat (cette semaine) — Fix les bugs actuels
| # | Tâche | Effort | Status |
|---|---|---|---|
| 0.1 | Brancher les Settings Switches (persist via SharedPreferences) | 4h | ❌ |
| 0.2 | Fix build web (shouldReclip) | 1h | ✅ |
| 0.3 | Status bar dark + no rounded corners | 2h | ✅ |
| 0.4 | Sidebar cards + push layout | 3h | ✅ |
| 0.5 | Tab bar rounded per tab + no divider | 2h | ✅ |

### Phase 1 : Settings fonctionnelles (semaine 2)
| # | Tâche | Effort | Impact |
|---|---|---|---|
| 1.1 | Créer `SettingsService` (SharedPreferences) | 6h | Critique |
| 1.2 | Brancher Editor settings → éditeur réel | 8h | Critique |
| 1.3 | Brancher Terminal settings → terminal réel | 4h | Haute |
| 1.4 | Brancher Git settings → git réel | 4h | Haute |
| 1.5 | Brancher Appearance settings → thème | 4h | Haute |
| 1.6 | Settings search (barre de recherche) | 4h | Haute |
| 1.7 | JSON settings editor (texte brut) | 6h | Moyenne |

### Phase 2 : Features manquantes critiques (semaine 3-4)
| # | Tâche | Effort | Impact |
|---|---|---|---|
| 2.1 | Code Lens (actions inline) | 8h | Haute |
| 2.2 | Preview editor (italique) | 6h | Moyenne |
| 2.3 | Drag & drop réordonner onglets | 6h | Haute |
| 2.4 | Terminal multi-tab | 12h | Critique |
| 2.5 | Terminal split | 8h | Moyenne |
| 2.6 | Create/Checkout branch (UI) | 8h | Haute |
| 2.7 | Launch configurations (debug.json) | 12h | Haute |
| 2.8 | Conditional breakpoints | 4h | Moyenne |
| 2.9 | Git stash UI | 6h | Moyenne |
| 2.10 | Git log / history | 8h | Moyenne |

### Phase 3 : Extension system complet (semaine 5-6)
| # | Tâche | Effort | Impact |
|---|---|---|---|
| 3.1 | `debuggers` contribution type | 12h | Haute |
| 3.2 | `authentication` contribution | 8h | Moyenne |
| 3.3 | `taskDefinitions` contribution | 8h | Moyenne |
| 3.4 | `viewsContainers` (custom sidebar) | 12h | Moyenne |
| 3.5 | `viewsWelcome` (welcome views) | 4h | Faible |
| 3.6 | `problemPatterns` | 4h | Faible |
| 3.7 | Extension auto-update | 8h | Moyenne |
| 3.8 | `onDebug` activation event | 4h | Moyenne |

### Phase 4 : Mobile-first (semaine 7-8)
| # | Tâche | Effort | Impact |
|---|---|---|---|
| 4.1 | Responsive breakpoints + layout engine | 8h | Critique |
| 4.2 | Sidebar → Drawer (mobile) | 8h | Critique |
| 4.3 | Bottom Navigation (5 tabs) | 6h | Critique |
| 4.4 | Settings mobile layout (pleine largeur) | 4h | Haute |
| 4.5 | Terminal → Bottom sheet | 4h | Haute |
| 4.6 | Pull-to-refresh (file tree) | 3h | Moyenne |
| 4.7 | Long press context menu | 4h | Haute |
| 4.8 | Swipe between editor tabs | 3h | Moyenne |
| 4.9 | Floating action button (new/save) | 3h | Moyenne |
| 4.10 | Haptic feedback | 2h | Faible |
| 4.11 | Keyboard overlay (raccourcis) | 4h | Moyenne |

### Phase 5 : Polish & Parity (semaine 9-12)
| # | Tâche | Effort | Impact |
|---|---|---|---|
| 5.1 | Search exclude/include patterns | 6h | Moyenne |
| 5.2 | Inlay hints | 8h | Moyenne |
| 5.3 | Local history | 8h | Faible |
| 5.4 | Accessibility (ARIA, screen reader) | 12h | Haute |
| 5.5 | Settings sync (cloud) | 20h | Faible |
| 5.6 | Zen mode | 4h | Faible |
| 5.7 | Process explorer | 6h | Faible |
| 5.8 | Custom editors | 20h | P3 |
| 5.9 | Notebook support | 40h | P3 |
| 5.10 | Hex editor (extension) | 16h | P3 |

### Estimation totale

| Phase | Effort | Durée estimée |
|---|---|---|
| Phase 0 (bugs) | 12h | 1-2 jours |
| Phase 1 (settings) | 36h | 1 semaine |
| Phase 2 (features) | 84h | 2 semaines |
| Phase 3 (extensions) | 68h | 1.5 semaines |
| Phase 4 (mobile) | 49h | 1 semaine |
| Phase 5 (polish) | 140h | 3 semaines |
| **TOTAL** | **389h** | **~9 semaines** |

---

## 15. RISQUES & PRIORITÉS

### Risques techniques

| Risque | Impact | Mitigation |
|---|---|---|
| Monaco Editor pas optimisé pour mobile (touch) | Critique | Utiliser le custom Flutter editor actuel, pas Monaco |
| Terminal PTY limité sur mobile | Haute | Utiliser Shizuku/ADB pour accès natif |
| Extension isolation (isolates) = pas de Node.js | Haute | Bridge custom, ne pas porter les extensions Node |
| Performance Flutter sur gros fichiers (>10k lignes) | Haute | Virtual scrolling, lazy loading |
| Build web (dart2js) lent | Moyenne | Tree shaking agressif, deferred imports |

### Priorités recommandées

1. **P0 — Immédiat** : Brancher les Settings Switches (tout est visuel, rien ne persiste)
2. **P0 — Immédiat** : Fix mobile layout (sidebar drawer, bottom nav)
3. **P1 — Haute** : Terminal multi-tab, Code Lens, Create/Checkout branch
4. **P2 — Moyenne** : Extension types manquants, accessibility, polish
5. **P3 — Faible** : Notebook, hex editor, settings sync

### Ce que Panda fait MIEUX que VS Code

| Feature | Panda | VS Code |
|---|---|---|
| AI intégré (8 providers) | ✅ natif | ❌ extension séparée |
| MCP natif | ✅ | ❌ |
| Flutter SDK management | ✅ | ❌ |
| ADB/Shizuku | ✅ | ❌ |
| Mobile-first UI | ✅ | ❌ (desktop first) |
| Extension permissions | ✅ | ❌ |
| Extension host isolé (Dart) | ✅ | ⚠️ (Node.js process) |
| Open VSX marketplace | ✅ | ❌ (Microsoft only) |
| Per-school accent color | ✅ | ❌ |
| Gateway/Remote natif | ✅ | ✅ |

---

---

## ANNEXE : DÉTAILS UI VS CODE (source code analysis)

### Workspace Box — Comportement au clic
Quand on clique sur le nom du workspace dans la top bar :
1. **Quick Pick** s'ouvre (pas un dropdown classique)
2. Séparateur « **folders & workspaces** » : liste tous les dossiers/workspaces récents
3. Séparateur « **files** » : liste les fichiers récemment ouverts
4. Chaque entrée a un bouton **×** pour supprimer du récent
5. Les workspaces « dirty » (fichiers non sauvegardés) ont un indicateur
6. **Cmd/Ctrl-click** → ouvre dans une nouvelle fenêtre
7. **Alt/Option-click** → ouvre dans la même fenêtre

### Command Palette (Ctrl+Shift+P)
- **1 971 actions** enregistrées dans MenuId.CommandPalette
- Filtre en temps réel par nom de commande
- Raccourcis affichés à côté de chaque commande

### Editor Tab "..." Menu
Group 1_close: Close (Ctrl+W), Close Others, Close to Right, Close Saved, Close All
Group 1_open: Reopen Editor With...
Group 3_preview: Keep Open, Pin / Unpin
Group 5_split: Split Right/Down (Ctrl+\), Split & Move
Group 7_new_window: Move/Copy into New Window
Group 11_share: Share submenu

### Editor Title Bar Actions
Group 1_diff: Inline View toggle
Group 3_open: Show Opened Editors
Group 5_close: Close All, Close Saved
Group 7_settings: Enable Preview Editors toggle

### Explorer Context Menu
Group navigation: New File, New Folder, Open With, Copy Path, Copy Relative Path
Group 3_compare: Compare with Selected, Select for Compare
Group 5_cutcopypaste: Cut, Copy, Paste, Download, Upload
Group 6_remove: Remove/Add Root Folder
Group 7_modify: Rename (F2), Delete (Del)
Group 8_open: Open in Terminal, Reveal in OS, Open to Side

### Sidebar View Header Menu
Toggle Position (left/right), Move Views, Hide Panel

### Status Bar Items
Left: Remote indicator, Branch, Sync, Errors/Warnings
Right: Ln/Col, Indentation, Encoding, Line ending, Notifications

---

*Rapport généré le 23 août 2026 par Codebuff — audit complet de 10 385 fichiers VS Code vs 193 fichiers Panda IDE.*
