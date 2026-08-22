# 🔍 Analyse Complète — VS Code vs Zed vs Panda IDE

**Date :** 22 août 2026
**Codebase Panda IDE :** 168 fichiers Dart, ~98K lignes
**Objectif :** Identifier les vrais gaps, pas les détails cosmetiques

---

## 1. Architecture de VS Code (ce qu'on ne voit pas)

### 1.1 Les 3 processus

```
┌──────────────────────────────────────────────────────────────┐
│                    VS Code Electron                            │
│                                                                │
│  ┌──────────────────┐                                         │
│  │  Renderer Process │  Chromium — l'UI                       │
│  │  (HTML/CSS/JS)    │  Menus, éditeur, sidebar, panels       │
│  └────────┬─────────┘                                         │
│           │ IPC (JSON-RPC)                                     │
│  ┌────────┴─────────┐                                         │
│  │  Main Process     │  Node.js — orchestration               │
│  │  (Node.js)        │  FileSystem, Terminal, Git, IPC        │
│  └────────┬─────────┘                                         │
│           │ IPC (JSON-RPC)                                     │
│  ┌────────┴─────────┐                                         │
│  │  Extension Host   │  Node.js séparé — les extensions       │
│  │  (Node.js)        │  Sandbox isolé, timeout, restart       │
│  └──────────────────┘                                         │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 Le Workspace Model (ce qui manque à Panda)

VS Code a un **Workspace Model** qui est le cœur de tout :

```typescript
// Ce que VS Code gère en interne
interface Workspace {
  folders: WorkspaceFolder[];     // Multi-root workspace
  configuration: WorkspaceConfiguration;
  textDocuments: TextDocument[];  // Tous les fichiers ouverts
  diagnostics: DiagnosticCollection;
  edit: WorkspaceEdit;            // Edits multi-fichiers atomiques
  fileSystem: FileSystem;
  searchedFiles: FileSearchResult[];
}
```

**Ce que Panda IDE a :**
- `PandaWorkspaceManager` — juste un nom + folders + settings + openTabs
- `PandaFileSystemProvider` — read/write basique
- Pas de DiagnosticCollection
- Pas de WorkspaceEdit (edits multi-fichiers atomiques)
- Pas de FileSearchResult

**Ce qui manque :**
- ❌ **Multi-root workspace** (ouvrir 2+ dossiers indépendants)
- ❌ **Workspace settings** (.vscode/settings.json par dossier)
- ❌ **Workspace tasks** (tasks.json)
- ❌ **Workspace launch configs** (launch.json)
- ❌ **Workspace extensions** (.vscode/extensions.json)
- ❌ **Workspace snippets** (.vscode/snippets/)
- ❌ **Workspace keybindings** (.vscode/keybindings.json)

### 1.3 Le Text Editor Model (le vrai éditeur)

VS Code utilise un éditeur **custom** (pas un WebView) :

```typescript
// VS Code TextEditor — pas un textarea
interface TextEditor {
  document: TextDocument;          // Buffer complet
  selection: Selection;            // Curseur(s)
  selections: Selection[];         // Multi-cursor
  visibleRanges: Range[];         // Zones visibles
  options: TextEditorOptions;     // Tab size, font, etc.
  edit(callback, options): Promise<boolean>;  // Edits atomiques
  insertSnippet(snippet, location): Promise<void>;
  setDecorations(type, ranges): void;  // Highlights, gutter
  revealRange(range, revealType): void;
  show(column): void;
  hide(): void;
}
```

**Ce que Panda IDE a :**
- `EditorPage` — un CodeForge widget (wrapper Flutter)
- `CodeForge` — éditeur basique Flutter

**Ce qui manque :**
- ❌ **Multi-cursor** (Alt+Click, Ctrl+D, Ctrl+Shift+L)
- ❌ **Column selection** (Shift+Alt+Drag)
- ❌ **Snippet insertion** depuis les extensions
- ❌ **Code actions** (quick fixes, refactorings inline)
- ❌ **Inlay hints** (types inférés affichés inline)
- ❌ **Inline completions** (Copilot ghost text)
- ❌ **Sticky scroll** (header du scope visible)
- ❌ **Breadcrumbs** dans l'éditeur
- ❌ **Minimap** (overview du fichier)
- ❌ **Bracket pair colorization**
- ❌ **Indent guides** (lignes verticales)
- ❌ **Render whitespace** (dots, arrows)
- ❌ **Word wrap** configurable
- ❌ **Folding** (plier/déplier les scopes)
- ❌ **Split editor** (2 vues côte à côte)
- ❌ **Editor groups** (onglets de vue multiples)

### 1.4 LSP (Language Server Protocol)

VS Code supporte **28 types de providers** LSP :

```
CompletionProvider          ✅ Panda a
HoverProvider               ✅ Panda a
DefinitionProvider          ✅ Panda a
DeclarationProvider         ✅ Panda a
ReferenceProvider           ✅ Panda a
DocumentHighlightProvider   ❌ Panda manque
DocumentSymbolProvider      ❌ Panda manque
WorkspaceSymbolProvider     ❌ Panda manque
CodeActionProvider          ❌ Panda manque
CodeLensProvider            ❌ Panda manque
DocumentFormattingProvider  ✅ Panda a
DocumentRangeFormatting     ✅ Panda a
OnTypeFormatting            ✅ Panda a
RenameProvider              ✅ Panda a
FoldingRangeProvider        ❌ Panda manque
SelectionRangeProvider      ❌ Panda manque
SignatureHelpProvider       ✅ Panda a
CompletionItemProvider      ✅ Panda a
HoverProvider               ✅ Panda a
TypeDefinitionProvider      ✅ Panda a
ImplementationProvider      ✅ Panda a
DocumentLinkProvider        ❌ Panda manque
ColorProvider               ❌ Panda manque
DeclarationProvider         ✅ Panda a
InlayHintProvider           ❌ Panda manque
CallHierarchyProvider       ❌ Panda manque
LinkedEditingRangeProvider  ❌ Panda manque
DiagnosticProvider          ❌ Panda manque
```

**Score : 14/28 — Panda supporte 50% des features LSP**

### 1.5 Debugging (le plus gros gap)

VS Code a un système de debugging complet :

```
Debug Adapter Protocol (DAP)
    │
    ├── Launch configurations (launch.json)
    ├── Breakpoints (conditional, logpoints, function)
    ├── Call stack inspection
    ├── Variables watch
    ├── Debug console (REPL)
    ├── Step over/in/out
    ├── Exception breakpoints
    ├── Multi-target debugging
    ├── Replay debugging
    ├── Inline values
    ├── Suggest (auto-complete in debug console)
    └── Terminal integration
```

**Ce que Panda IDE a :**
- `DebugBridge` — stub qui route vers Flutter
- `vscode.debug` — implémenté dans le shim

**Ce qui manque :**
- ❌ **DAP client** (pas de connexion aux debug adapters)
- ❌ **launch.json** parser
- ❌ **Breakpoints** UI
- ❌ **Variables** panel
- ❌ **Call stack** panel
- ❌ **Debug console** REPL
- ❌ **Step controls** (over/in/out)
- ❌ **Watch expressions**
- ❌ **Exception handling**
- ❌ **Multi-target debug**

### 1.6 Git Integration

VS Code a un client Git **complet** :

```
Git Features
    ├── Repository detection (.git/)
    ├── Branch switching
    ├── Commit (with message, co-authors, signing)
    ├── Push / Pull / Fetch
    ├── Staging (hunk-level, file-level)
    ├── Diff viewer (inline, side-by-side)
    ├── Merge conflict resolution
    ├── Stash
    ├── Cherry-pick
    ├── Rebase interactive
    ├── Tag management
    ├── Remote management
    ├── Log viewer
    ├── Blame (inline)
    └── Graph view
```

**Ce que Panda IDE a :**
- `ScmBridge` — route `vscode.scm.*` vers Flutter
- `ScmImpl` dans le shim — structure basique

**Ce qui manque :**
- ❌ **Git operations** (commit, push, pull, fetch)
- ❌ **Diff viewer** (inline, side-by-side)
- ❌ **Staging UI** (hunk, file)
- ❌ **Branch selector**
- ❌ **Merge conflict resolver**
- ❌ **Git blame** inline
- ❌ **Git log** viewer
- ❌ **Interactive rebase**

### 1.7 Terminal intégré

VS Code a un **vrai terminal** (pas un WebView) :

```
Terminal Features
    ├── xterm.js (terminal renderer)
    ├── Shell detection (bash, zsh, fish, powershell)
    ├── Split terminals
    ├── Terminal tabs
    ├── Task integration
    ├── Command detection (clickable links)
    ├── Profile selection
    ├── Env variables
    ├── Shell integration (prompt, marks)
    ├── Current working directory detection
    ├── Link detection (URLs, files, emails)
    └── Unicode/emoji support
```

**Ce que Panda IDE a :**
- `TerminalNative` — 92K lignes (!!!) — le plus gros fichier
- `TerminalBridge` — communication Flutter ↔ Alpine

**Ce qui manque :**
- ⚠️ Le terminal est **le meilleur composant** de Panda IDE
- Mais manque : split terminals, terminal tabs, command detection

---

## 2. Architecture de Zed (ce qui le rend rapide)

### 2.1 Pourquoi Zed est ultra-rapide

```
Zed Architecture (Rust)
    │
    ├── GPU Rendering (Metal/Vulkan/DirectX)
    │   └── Pas de Chromium = pas de DOM = pas de layout reflow
    │
    ├── Tree-sitter (parsing incrémental)
    │   └── Parse complet en <1ms pour un fichier de 10K lignes
    │   └── Re-parse incrémental = 0ms sur les changements
    │
    ├── CRDT (Conflict-free Replicated Data Types)
    │   └── Collaboration temps réel sans conflits
    │   └── Operational transformation = zéro merge conflict
    │
    ├── Rope data structure (pour les gros fichiers)
    │   └── Insert/delete en O(log n) au lieu de O(n)
    │   └── 100K lignes = même performance que 100 lignes
    │
    ├── Multi-process
    │   ├── Renderer (GPU)
    │   ├── Server (LSP, Git, collaboration)
    │   └── Extension host (WASM isolates)
    │
    └── Zero-copy serialization
        └── Pas de JSON parsing = pas de IPC overhead
```

### 2.2 Ce que Zed a que Panda n'a pas

| Feature | Zed | Panda | Impact |
|---------|-----|-------|--------|
| GPU rendering | ✅ Metal/Vulkan | ❌ Flutter (Skia) | Zed 2x plus rapide sur gros fichiers |
| Tree-sitter | ✅ Natif | ❌ Pas de parsing syntaxique | Zed = highlighting parfait, 0 lag |
| CRDT | ✅ Collaboration | ❌ Pas de collaboration | Zed = multi-user temps réel |
| Rope data structure | ✅ Natif | ❌ String Dart (O(n)) | Zed = 100K lignes sans lag |
| Multi-cursor | ✅ GPU-native | ❌ Pas | Zed = editing puissant |
| Inline completions | ✅ Agent intégré | ⚠️ Agent Panda | Zed = AI intégré au flux |
| Git inline blame | ✅ Natif | ❌ Pas | Zed = contexte immédiat |
| Diff viewer | ✅ GPU-native | ❌ Pas | Zed = review de code intégré |
| Search全局 | ✅ Regex + GPU | ⚠️ Basique | Zed = recherche ultra-rapide |
| Workspace roots | ✅ Multi-root | ⚠️ Single root | Zed = projets complexes |
| Task runner | ✅ Natif | ❌ Pas | Zed = build/test intégrés |
| Quick open (Ctrl+P) | ✅ Fuzzy + recent | ❌ Pas | Zed = navigation rapide |
| Command palette | ✅ Fuzzy | ⚠️ Basique | Zed = tout accessible |
| Keybindings | ✅ Personnalisables | ❌ Fixe | Zed = productivité |
| Settings UI | ✅ JSON + UI | ⚠️ Basique | Zed = configurabilité |
| Color themes | ✅ Natif | ⚠️ Basique | Zed = personnalisation |
| File watcher | ✅ Native (notify) | ⚠️ Polled | Zed = réactivité |
| Encoding detection | ✅ ICU | ❌ Pas | Zed = universalité |
| Right-to-left | ✅ Natif | ❌ Pas | Zed = international |

---

## 3. Ce que Panda IDE a VRAIMENT (honnête)

### 3.1 Ce qui marche bien

| Feature | Status | Qualité |
|---------|--------|---------|
| Alpine Linux (rootfs complet) | ✅ | ⭐⭐⭐⭐ |
| Terminal natif (proot) | ✅ | ⭐⭐⭐⭐⭐ |
| 8 providers AI (ChatGPT, Claude, etc.) | ✅ | ⭐⭐⭐⭐ |
| Extension system (Node.js + VS Code shim) | ✅ | ⭐⭐⭐⭐ |
| Marketplace (Open VSX) | ✅ | ⭐⭐⭐ |
| File manager | ✅ | ⭐⭐⭐ |
| Browser intégré | ✅ | ⭐⭐⭐ |
| Gateway AI (proxy) | ✅ | ⭐⭐⭐⭐ |
| Agent/Chat AI | ✅ | ⭐⭐⭐ |
| Local models (Ollama) | ✅ | ⭐⭐⭐ |
| Android native (APK) | ✅ | ⭐⭐⭐⭐ |
| LSP bridge (14 providers) | ✅ | ⭐⭐⭐ |
| WebView panels | ✅ | ⭐⭐⭐ |
| SCM bridge | ⚠️ | ⭐⭐ |
| Debug bridge | ⚠️ | ⭐ |

### 3.2 Ce qui est vraiment cassé ou absent

| Feature | Status | Impact | Effort |
|---------|--------|--------|--------|
| **Multi-root workspace** | ❌ Absent | 🔴 Critique | Moyen |
| **Git operations** (commit, push, pull) | ❌ Absent | 🔴 Critique | Moyen |
| **Diff viewer** (inline, side-by-side) | ❌ Absent | 🔴 Critique | Fort |
| **Breakpoints UI** | ❌ Absent | 🔴 Critique | Fort |
| **Debug console** | ❌ Absent | 🟡 Important | Fort |
| **Multi-cursor** | ❌ Absent | 🟡 Important | Fort |
| **Folding** (code folding) | ❌ Absent | 🟡 Important | Moyen |
| **Quick Open** (Ctrl+P fuzzy) | ❌ Absent | 🟡 Important | Moyen |
| **Command palette améliorée** | ⚠️ Basique | 🟡 Important | Faible |
| **Settings UI** (JSON + UI) | ❌ Absent | 🟢 Utile | Faible |
| **Keybindings custom** | ❌ Absent | 🟢 Utile | Faible |
| **Minimap** | ❌ Absent | 🟢 Utile | Moyen |
| **Breadcrumbs** | ❌ Absent | 🟢 Utile | Moyen |
| **Search global** (regex, files) | ⚠️ Basique | 🟡 Important | Moyen |
| **Workspace tasks** (build, test) | ❌ Absent | 🟡 Important | Fort |
| **Inline completions** (ghost text) | ❌ Absent | 🟡 Important | Fort |
| **Inlay hints** (types inférés) | ❌ Absent | 🟢 Utile | Fort |
| **Bracket pair colorization** | ❌ Absent | 🟢 Utile | Faible |
| **Indent guides** | ❌ Absent | 🟢 Utile | Faible |
| **Sticky scroll** | ❌ Absent | 🟢 Utile | Moyen |
| **Word wrap** configurable | ❌ Absent | 🟢 Utile | Faible |
| **Split editor** | ❌ Absent | 🟡 Important | Fort |
| **Tab groups** | ❌ Absent | 🟡 Important | Moyen |
| **Collaboration** (multi-user) | ❌ Absent | 🟢 Futur | Très fort |

---

## 4. Comparaison Scores

### 4.1 Critères pondérés

| Critère | Poids | VS Code | Zed | Panda |
|---------|-------|---------|-----|-------|
| **Performance** | 20% | 7/10 | 10/10 | 5/10 |
| **Text editing** | 20% | 10/10 | 10/10 | 3/10 |
| **LSP integration** | 15% | 10/10 | 9/10 | 5/10 |
| **Extensions** | 15% | 10/10 | 4/10 | 6/10 |
| **Git integration** | 10% | 9/10 | 8/10 | 1/10 |
| **Debugging** | 10% | 10/10 | 3/10 | 1/10 |
| **Terminal** | 5% | 8/10 | 7/10 | 8/10 |
| **UI/UX** | 5% | 8/10 | 9/10 | 6/10 |
| **TOTAL** | 100% | **8.85** | **7.35** | **4.40** |

### 4.2 Verdict

| Rang | IDE | Score | Verdict |
|------|-----|-------|---------|
| 🥇 | **VS Code** | 8.85/10 | Le standard — complet mais lourd |
| 🥈 | **Zed** | 7.35/10 | Le plus rapide — mais pas d'extensions matures |
| 🥉 | **Panda IDE** | 4.40/10 | Le plus ambitieux — mais pas fini |

---

## 5. Plan d'Action — Priorités

### Phase 1 : Rendre l'éditeur utilisable (2 semaines)

| Task | Effort | Impact |
|------|--------|--------|
| Multi-cursor (Ctrl+D, Ctrl+Shift+L) | Fort | 🔴 |
| Code folding | Moyen | 🔴 |
| Quick Open (Ctrl+P fuzzy) | Moyen | 🔴 |
| Word wrap configurable | Faible | 🟡 |
| Indent guides | Faible | 🟡 |
| Bracket pair colorization | Faible | 🟡 |
| Minimap | Moyen | 🟢 |

### Phase 2 : Git intégré (2 semaines)

| Task | Effort | Impact |
|------|--------|--------|
| Git operations (commit, push, pull) | Moyen | 🔴 |
| Diff viewer (inline) | Fort | 🔴 |
| Staging UI (hunk, file) | Fort | 🔴 |
| Branch selector | Faible | 🟡 |
| Merge conflict resolver | Fort | 🟡 |
| Git blame inline | Faible | 🟢 |

### Phase 3 : Workspace complet (2 semaines)

| Task | Effort | Impact |
|------|--------|--------|
| Multi-root workspace | Moyen | 🔴 |
| .vscode/settings.json | Faible | 🟡 |
| Workspace tasks (tasks.json) | Fort | 🟡 |
| Workspace launch configs (launch.json) | Fort | 🟡 |
| Global search (regex, files) | Moyen | 🟡 |
| Command palette améliorée | Faible | 🟡 |

### Phase 4 : LSP complet (2 semaines)

| Task | Effort | Impact |
|------|--------|--------|
| DocumentSymbolProvider | Faible | 🟡 |
| WorkspaceSymbolProvider | Moyen | 🟡 |
| CodeActionProvider | Fort | 🔴 |
| CodeLensProvider | Moyen | 🟡 |
| FoldingRangeProvider | Faible | 🟡 |
| InlayHintProvider | Fort | 🟢 |
| CallHierarchyProvider | Fort | 🟢 |
| DiagnosticProvider | Moyen | 🔴 |

### Phase 5 : Debug (3 semaines)

| Task | Effort | Impact |
|------|--------|--------|
| DAP client (connexion aux adapters) | Très fort | 🔴 |
| Breakpoints UI | Fort | 🔴 |
| Variables panel | Fort | 🔴 |
| Call stack panel | Fort | 🟡 |
| Debug console REPL | Fort | 🟡 |
| Step controls | Moyen | 🟡 |

### Phase 6 : Performance (2 semaines)

| Task | Effort | Impact |
|------|--------|--------|
| Lazy loading des onglets | Moyen | 🔴 |
| Virtual scrolling (gros fichiers) | Fort | 🔴 |
| Background parsing (Tree-sitter) | Très fort | 🔴 |
| File watcher natif | Moyen | 🟡 |
| Cache des LSP responses | Faible | 🟡 |

---

## 6. Conclusion

### Ce qu'il faut comprendre

Panda IDE est **ambitieux** — il essaie de combiner :
1. Un IDE complet (VS Code-like)
2. Un gateway AI (8 providers)
3. Un terminal Linux (Alpine)
4. Un client mobile (Android)
5. Un agent AI intégré

**Le problème :** Chaque domaine est à 40-60% de completion. Aucun n'est à 100%.

### La stratégie recommandée

**Ne pas essayer d'être VS Code.** VS Code a 500+ développeurs et 8 ans de développement.

**Être le meilleur IDE pour le mobile/AI :**
1. ✅ Terminal Linux natif (déjà fait)
2. ✅ Gateway AI 8 providers (déjà fait)
3. ✅ Extensions VS Code (déjà fait)
4. ➡️ **Git intégré** (priorité 1)
5. ➡️ **Quick Open + multi-cursor** (priorité 2)
6. ➡️ **Diff viewer** (priorité 3)
7. ➡️ **Workspace complet** (priorité 4)

**Ce qu'il ne faut PAS faire :**
- ❌ Essayer de copier le debugging de VS Code (trop complexe)
- ❌ Essayer d'égaler la performance de Zed (pas en Dart)
- ❌ Ajouter la collaboration temps réel (CRDT = 6 mois de dev)
- ❌ Copier tous les 28 providers LSP (inutile pour le mobile)

### Le vrai gap

**VS Code a 2M+ lignes de code.** Panda IDE en a 98K. C'est 20x moins.

**Zed a 500K+ lignes de Rust.** Panda IDE est en Dart (plus lent).

**Le gap n'est pas technique — c'est de scope.** Panda IDE couvre trop de domaines sans en maîtriser aucun.

**La priorité #1 :** Rendre l'éditeur de code **utilisable** (multi-cursor, folding, quick open) avant d'ajouter plus de features AI.
