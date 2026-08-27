# Panda Agent — Architecture Finale

> Analyse comparative de 12+ coding agents open-source → Architecture Flutter/Dart pour Panda IDE

---

## 1. Comparaison des Architectures

### 1.1 Tableau Comparatif

| Concept | Codebuff/Freebuff | OpenHands | Cline | Roo Code | Goose | Continue | SWE-agent | Aider | Gemini CLI |
|---|---|---|---|---|---|---|---|---|---|
| **Agent Loop** | Generator-based (`handleSteps`) | Event-driven (`AgentController`) | Async loop (`advanceTask`) | Single agent + mode switch | State machine (`goose-agent`) | Config-based | ReAct loop | Multi-file edit loop | Session + event stream |
| **Planner** | Thinker subagent | Embedded in agent | Plan/Act phases | Architect mode | No dedicated planner | No | Prompt-based | Repo map + planning | Plan mode |
| **Subagents** | ✅ `spawn_agents` tool, parallel | ✅ Skills/subagents | ✅ Subagent tool | ❌ Modes only | ❌ Single agent | ❌ | ❌ | ❌ | ✅ A2A protocol |
| **Agent Registry** | File-based (`agents/*.ts`) | Runtime registration | `AgentConfigLoader` | Mode configs | Extension system | Config files | Fixed | Fixed | Config + extensions |
| **Tool Registry** | Schema per agent | `Action` classes | `Tool` class hierarchy | Native tools + custom | MCP extensions | Config | Fixed set | Coder methods | `ToolRegistry` class |
| **Context Manager** | `context-pruner` agent | `Workspace` class | `ContextManager` | Token counting | Conversation state | `.continue/config` | `Trajectory` | `RepoMap` | `AgentSession` |
| **Context Pruning** | Dedicated subagent | `compact_history()` | Token budget | Condensing | No | No | No | Sliding window | Session cleanup |
| **History Compaction** | ✅ `compactContext: true` | ✅ In-process | ✅ Summary | ✅ Context condensing | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Code Indexing** | `code-searcher` + `file-picker` | LSP-based | File search | File search | Extension | `codebase` context | Embeddings | `RepoMap` | Extension |
| **Repo Map** | `file-picker` + `code-searcher` | `RepoMap` | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ `RepoMap` (tree-sitter) | ❌ |
| **Knowledge Files** | AGENTS.md, memory | `AGENT.md` | `.clinerules` | `.roo/` dir | `.goosehints` | `.continue/` | `SWE.toml` | `.aider.conf.yml` | `GEMINI.md` |
| **Memory** | `.panda/memory.md` | Persistent workspace | `TaskHistory` | `TaskHistory` | Session | Config | Trajectory | Git history | Session memory |
| **Plan Mode** | `base2-plan` agent | ❌ | ✅ Plan/Act | ✅ Architect mode | ❌ | ❌ | ❌ | ❌ | ✅ Plan mode |
| **Approval System** | Per-tool approval | Sandboxed | Permission system | Mode-based permissions | Sandboxed | Config | Sandboxed | Y/N prompts | Approval modes |
| **Tool Streaming** | ✅ Real-time | ✅ Events | ✅ Real-time | ✅ Real-time | ✅ Events | ✅ | ❌ | ❌ | ✅ Events |
| **Retry** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Verification** | Reviewer subagent | LSP + tests | LSP diagnostics | LSP | Extension | Checks | Test runner | Tests | Extension |
| **Review Agent** | ✅ Dedicated `reviewer` | ❌ | ❌ | ❌ | ❌ | ✅ Code review | ❌ | ❌ | ❌ |
| **MCP** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Skills** | Spawnable agents | Skills directory | ❌ | ❌ | Extensions | ❌ | ❌ | ❌ | ✅ Skills |
| **Git Integration** | ✅ Built-in | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ Auto-commit | ✅ |
| **LSP** | ✅ | ✅ | ✅ | ✅ | Extension | ✅ | ❌ | ❌ | Extension |
| **Browser** | ✅ `browser-use` | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Sandbox** | Server-side | Docker/Local | ❌ | ❌ | Docker | ❌ | Docker | ❌ | ❌ |
| **Event Bus** | Generator yields | Event system | UI events | BLoC-like | Event system | ❌ | ❌ | Callbacks | AgentEvent |
| **Sessions** | ✅ | ✅ Workspace | ✅ Task | ✅ Task | ✅ Session | ✅ | ✅ Trajectory | ✅ | ✅ AgentSession |
| **Parallel Execution** | ✅ Parallel spawns | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ A2A |

### 1.2 Architectures Type

**Architecture A — Single Agent (Aider, SWE-agent)**
```
User → Agent → Tools → Result
```
Simple, efficace, mais limité pour les tâches complexes.

**Architecture B — Agent + Subagents parallèles (Codebuff)**
```
Main Agent → spawn_agents → [FilePicker, Researcher, Editor, Reviewer, Thinker]
```
Le plus puissant. Les subagents sont des agents à part entière avec leur propre modèle et tools.

**Architecture C — Modes spécialisés (Roo Code)**
```
User → Mode Switch → Agent (même code, prompt/tools différents)
```
Pas de vrais subagents. Un seul agent avec configurations différentes par mode.

**Architecture D — Plan/Act (Cline)**
```
User → Plan Phase → Act Phase → Verify → Loop
```
Deux phases dans un même agent. Pas de subagents.

**Architecture E — Event-driven (OpenHands, Gemini CLI)**
```
User → AgentSession → Events → UI
```
Architecture réactive basée sur les événements.

---

## 2. Critique de l'Ancienne Proposition

L'ancienne proposition de Panda Agent avait ces défauts :

1. **Trop de subagents** — 5-6 subagents est excessif pour un mobile IDE. Chaque subagent = appels LLM supplémentaires = tokens + latence + batterie.
2. **Pas d'événements** — L'UI est couplée au moteur via des callbacks directs au lieu d'un bus d'événements.
3. **Pas de context pruning** — Le contexte croît indéfiniment jusqu'à overflow.
4. **Pas de vérification** — Aucune étape de vérification automatique après les modifications.
5. **Pas de code map** — L'agent n'a pas de vue globale du projet.
6. **Architecture monolithique** — Tout est dans `home.dart` (corrigé avec l'extraction récente).

---

## 3. Synthèse — Ce qui Est Vraiment Utile pour Panda

### 3.1 De Codebuff/Freebuff (LE MEILLEUR MODÈLE)
- **Architecture subagents parallèles** avec `spawn_agents`
- **Context pruner** comme subagent dédié
- **Reviewer** comme subagent post-tâche
- **File picker** + **code searcher** pour naviguer le projet
- **Agent definitions** typées avec input/output schemas

### 3.2 De Cline
- **Plan/Act phases** dans un même agent
- **LSP diagnostics** comme feedback loop
- **Checkpoints** pour rollback

### 3.3 De Roo Code
- **Modes** (Ask, Plan, Agent) — PAS des subagents
- **Tool restrictions** par mode
- **Context condensing** automatique

### 3.4 De Aider
- **RepoMap** — arbre syntaxique du projet
- **Auto-commit** après chaque modification

### 3.5 De Gemini CLI
- **AgentSession** — wrapper event-driven
- **Skills** — procédures réutilisables
- **Memory** persistante

### 3.6 De Goose
- **Extensions MCP** — extensibilité
- **Provider abstraction** — multi-modèles

---

## 4. Architecture Conceptuelle de Panda Agent

```
┌─────────────────────────────────────────────────────────────┐
│                    PANDA AGENT                               │
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │   User   │───▶│  AgentRunner │───▶│  AgentEventBus   │   │
│  │  Input   │    │  (Main Loop) │    │  (Events → UI)   │   │
│  └──────────┘    └──────┬───────┘    └──────────────────┘   │
│                         │                                    │
│              ┌──────────┼──────────┐                        │
│              ▼          ▼          ▼                        │
│     ┌────────────┐ ┌─────────┐ ┌──────────┐               │
│     │  Context   │ │  Tool   │ │  Model   │               │
│     │  Manager   │ │ Registry│ │ Provider │               │
│     └────────────┘ └─────────┘ └──────────┘               │
│              │          │          │                        │
│              ▼          ▼          ▼                        │
│     ┌────────────┐ ┌─────────┐ ┌──────────┐               │
│     │  SubAgent  │ │  Tool   │ │  LLM     │               │
│     │  Manager   │ │Executor │ │  API     │               │
│     └────────────┘ └─────────┘ └──────────┘               │
│              │          │          │                        │
│              ▼          ▼          ▼                        │
│     ┌────────────┐ ┌─────────┐ ┌──────────┐               │
│     │  Memory    │ │ Verifier│ │  Session │               │
│     │  System    │ │ (LSP+  │ │  Store   │               │
│     └────────────┘ │ Tests)  │ └──────────┘               │
│                    └─────────┘                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.1 Agents vs Modes vs Skills vs Tools vs Subagents

| Concept | Définition | Panda |
|---|---|---|
| **Tool** | Capacité unitaire (read_file, run_shell, etc.) | ✅ Existe déjà |
| **Skill** | Procédure réutilisable (flutter-dev, git-workflow) | 🆕 Nouveau |
| **Mode** | Configuration comportementale (Ask, Plan, Agent) | ✅ Existe déjà |
| **Agent** | Instance qui raisonne et appelle des tools | ✅ Existe déjà |
| **Subagent** | Agent lancé par un autre agent | 🆕 Nouveau |

**Décision : Panda utilise les DEUX — modes ET subagents.**
- Les **modes** changent le comportement de l'agent principal (prompt, tools autorisés)
- Les **subagents** sont lancés par l'agent principal pour des sous-tâches spécifiques

---

## 5. Architecture Flutter/Dart Finale

```
lib/
├── agent/
│   ├── core/
│   │   ├── agent_runner.dart          # Boucle principale de l'agent
│   │   ├── agent_state.dart           # État de l'agent (idle, thinking, streaming, etc.)
│   │   ├── agent_event_bus.dart       # Bus d'événements pour découpler UI/moteur
│   │   └── agent_config.dart          # Configuration globale de l'agent
│   │
│   ├── agents/
│   │   ├── agent_definition.dart      # Définition typée d'un agent (comme Codebuff)
│   │   ├── agent_registry.dart        # Registre des agents disponibles
│   │   ├── main_agent.dart            # Agent principal (celui que l'utilisateur voit)
│   │   ├── thinker_agent.dart         # Agent de réflexion profonde (sans tools)
│   │   ├── reviewer_agent.dart        # Agent de review post-tâche
│   │   └── context_pruner_agent.dart  # Agent de compression du contexte
│   │
│   ├── subagents/
│   │   ├── subagent_manager.dart      # Lance et suit les subagents
│   │   └── subagent_task.dart         # Tâche d'un subagent (input/output)
│   │
│   ├── tools/
│   │   ├── tool_registry.dart         # Registre des tools disponibles
│   │   ├── tool_executor.dart         # Exécuteur de tools avec permissions
│   │   ├── tool_permission.dart       # Système de permissions par mode
│   │   ├── file_tools.dart            # readFile, writeFile, editFile, etc.
│   │   ├── terminal_tools.dart        # runShellCommand, getTerminalOutput
│   │   ├── search_tools.dart          # searchInFiles, grepInFiles, globSearch
│   │   ├── editor_tools.dart          # activeEditorFile, insertAtLine, etc.
│   │   ├── git_tools.dart             # git operations
│   │   └── web_tools.dart             # fetch, browser
│   │
│   ├── context/
│   │   ├── context_manager.dart       # Gère ce qui est envoyé au LLM
│   │   ├── code_map.dart              # Arbre syntaxique du projet (comme Aider)
│   │   ├── project_tree.dart          # Structure des fichiers
│   │   ├── relevant_files.dart        # Fichiers pertinents pour la tâche
│   │   └── context_pruner.dart        # Compresse le contexte quand il déborde
│   │
│   ├── memory/
│   │   ├── project_memory.dart        # .panda/memory.md
│   │   ├── knowledge_files.dart       # .panda/rules.md, .panda/skills/
│   │   └── session_memory.dart        # Mémoire de la session en cours
│   │
│   ├── verification/
│   │   ├── verification_pipeline.dart # Pipeline de vérification adaptative
│   │   ├── lsp_checker.dart           # Vérifie les diagnostics LSP
│   │   ├── analyzer_checker.dart      # dart analyze / flutter analyze
│   │   └── test_runner.dart           # Lance les tests ciblés
│   │
│   ├── events/
│   │   ├── agent_event.dart           # Types d'événements
│   │   ├── agent_event_bus.dart       # Bus d'événements
│   │   └── event_handlers.dart        # Gestionnaires d'événements
│   │
│   ├── models/
│   │   ├── agent_message.dart         # Message de conversation
│   │   ├── tool_call.dart             # Appel d'outil
│   │   ├── tool_result.dart           # Résultat d'outil
│   │   ├── agent_result.dart          # Résultat final de l'agent
│   │   └── agent_phase.dart           # Phases de l'agent
│   │
│   └── modes/
│       ├── agent_mode.dart            # Mode Agent (autonomie totale)
│       ├── ask_mode.dart              # Mode Ask (questions/réponses)
│       ├── plan_mode.dart             # Mode Plan (planification)
│       └── mode_registry.dart         # Registre des modes
│
├── features/
│   └── agent_ui/
│       ├── activity_feed/             # Feed d'activités (existant, à déplacer)
│       ├── plan_viewer/               # Visualiseur de plans
│       ├── tool_viewer/               # Visualiseur d'outils en cours
│       ├── prompt_input/              # Barre de saisie
│       └── model_selector/            # Sélecteur de modèle
│
└── (fichiers existants conservés)
    ├── ui/agent/beui/                 # Composants Beautiful UI (à intégrer)
    ├── ui/agent/agent_models.dart     # Modèles extraits
    └── ui/agent/agent_widgets.dart    # Widgets extraits
```

---

## 6. Liste des Nouveaux Fichiers

| Fichier | Responsabilité | Utilisé par | Appelle | État |
|---|---|---|---|---|
| `core/agent_runner.dart` | Boucle principale de l'agent | UI, AgentEventBus | ContextManager, ToolExecutor, AgentRegistry | **Existant** (à refactorer) |
| `core/agent_state.dart` | État de l'agent | AgentRunner, UI | — | **Existant** (à extraire) |
| `core/agent_event_bus.dart` | Bus d'événements | Tous | — | **Nouveau** |
| `core/agent_config.dart` | Configuration globale | AgentRunner, Tools | SharedPreferences | **Nouveau** |
| `agents/agent_definition.dart` | Définition typée d'un agent | AgentRegistry | — | **Nouveau** |
| `agents/agent_registry.dart` | Registre des agents | AgentRunner, SubagentManager | AgentDefinition | **Nouveau** |
| `agents/main_agent.dart` | Agent principal | AgentRunner | ToolRegistry, ContextManager | **Nouveau** |
| `agents/thinker_agent.dart` | Réflexion profonde | SubagentManager | LLM (sans tools) | **Nouveau** |
| `agents/reviewer_agent.dart` | Review post-tâche | SubagentManager | LLM (sans tools) | **Nouveau** |
| `agents/context_pruner_agent.dart` | Compression contexte | AgentRunner | LLM | **Nouveau** |
| `subagents/subagent_manager.dart` | Lance/suit les subagents | AgentRunner | AgentRegistry, AgentRunner | **Nouveau** |
| `subagents/subagent_task.dart` | Tâche d'un subagent | SubagentManager | — | **Nouveau** |
| `tools/tool_registry.dart` | Registre des tools | ToolExecutor, AgentRunner | Tool | **Nouveau** |
| `tools/tool_executor.dart` | Exécuteur de tools | AgentRunner | Tool, ToolPermission | **Nouveau** |
| `tools/tool_permission.dart` | Permissions par mode | ToolExecutor | ModeRegistry | **Nouveau** |
| `tools/file_tools.dart` | Outils fichiers | ToolExecutor | — | **Nouveau** |
| `tools/terminal_tools.dart` | Outils terminal | ToolExecutor | PTY | **Nouveau** |
| `tools/search_tools.dart` | Outils recherche | ToolExecutor | — | **Nouveau** |
| `tools/editor_tools.dart` | Outils éditeur | ToolExecutor | CodeForge | **Nouveau** |
| `tools/git_tools.dart` | Outils git | ToolExecutor | — | **Nouveau** |
| `tools/web_tools.dart` | Outils web | ToolExecutor | http | **Nouveau** |
| `context/context_manager.dart` | Gère le contexte LLM | AgentRunner | CodeMap, ProjectTree, Memory | **Nouveau** |
| `context/code_map.dart` | Arbre syntaxique | ContextManager | analyzer | **Nouveau** |
| `context/project_tree.dart` | Structure fichiers | ContextManager | dart:io | **Nouveau** |
| `context/relevant_files.dart` | Fichiers pertinents | ContextManager | CodeMap | **Nouveau** |
| `context/context_pruner.dart` | Compresse le contexte | ContextManager | LLM | **Nouveau** |
| `memory/project_memory.dart` | .panda/memory.md | ContextManager | dart:io | **Nouveau** |
| `memory/knowledge_files.dart` | .panda/rules.md | ContextManager | dart:io | **Nouveau** |
| `memory/session_memory.dart` | Mémoire session | ContextManager | SharedPreferences | **Nouveau** |
| `verification/verification_pipeline.dart` | Pipeline adaptatif | AgentRunner | LSP, Analyzer, Tests | **Nouveau** |
| `verification/lsp_checker.dart` | Diagnostics LSP | VerificationPipeline | LSP | **Nouveau** |
| `verification/analyzer_checker.dart` | dart analyze | VerificationPipeline | PTY | **Nouveau** |
| `verification/test_runner.dart` | Tests ciblés | VerificationPipeline | PTY | **Nouveau** |
| `events/agent_event.dart` | Types d'événements | AgentEventBus | — | **Nouveau** |
| `events/agent_event_bus.dart` | Bus d'événements | AgentRunner, UI | StreamController | **Nouveau** |
| `events/event_handlers.dart` | Gestionnaires | AgentEventBus | ActivityFeed | **Nouveau** |
| `models/agent_message.dart` | Message conversation | AgentRunner | — | **Nouveau** |
| `models/tool_call.dart` | Appel d'outil | AgentRunner | — | **Nouveau** |
| `models/tool_result.dart` | Résultat d'outil | AgentRunner | — | **Nouveau** |
| `models/agent_result.dart` | Résultat final | AgentRunner | — | **Nouveau** |
| `models/agent_phase.dart` | Phases agent | AgentRunner | — | **Existant** (à déplacer) |
| `modes/agent_mode.dart` | Mode Agent | ModeRegistry | ToolPermission | **Nouveau** |
| `modes/ask_mode.dart` | Mode Ask | ModeRegistry | ToolPermission | **Nouveau** |
| `modes/plan_mode.dart` | Mode Plan | ModeRegistry | ToolPermission | **Nouveau** |
| `modes/mode_registry.dart` | Registre modes | AgentRunner, ToolPermission | ModeConfig | **Nouveau** |

---

## 7. Fichiers Existants à Modifier

| Fichier | Modification | Priorité |
|---|---|---|
| `lib/ui/agent_runner.dart` | Extraire AgentPhase, refactorer en AgentRunner pur (pas de UI) | P0 |
| `lib/ui/home.dart` | Remplacer callbacks directs par AgentEventBus | P1 |
| `lib/ui/agent/agent_models.dart` | Renommer en `core/agent_state.dart` | P1 |
| `lib/ui/agent/agent_widgets.dart` | Déplacer dans `features/agent_ui/` | P2 |
| `lib/ui/agent/beui/` | Intégrer les 15 composants non utilisés | P2 |
| `lib/ui/agent_settings.dart` | Ajouter configuration modes/skills | P1 |

---

## 8. Flux Main Agent — Tâche Complète

### Exemple : « Ajoute une page de login avec Firebase »

```
User: "Ajoute une page de login avec Firebase"
  ↓
AgentRunner.start(text: "Ajoute une page de login avec Firebase")
  ↓
AgentEventBus.emit(AgentStarted)
  ↓
ContextManager.buildContext()
  ├── ProjectTree.scan(workspacePath)
  ├── RelevantFiles.find("login", "firebase", "auth")
  ├── CodeMap.analyze(workspacePath)          ← arbre syntaxique
  ├── ProjectMemory.load(".panda/memory.md")
  ├── KnowledgeFiles.load(".panda/rules.md")
  └── ConversationHistory.get(last 20 messages)
  ↓
AgentRunner.run(systemPrompt, context, messages)
  ↓
MainAgent.process()
  ├── Phase 1: THINKING
  │   └── AgentEventBus.emit(ThinkingStarted)
  │       "Je dois créer une page de login avec Firebase Auth..."
  │
  ├── Phase 2: TOOL CALLS (itératif)
  │   ├── readFile("lib/ui/home.dart")         ← comprendre l'architecture
  │   ├── readFile("pubspec.yaml")             ← vérifier les dépendances
  │   ├── searchInFiles("firebase")            ← chercher si déjà installé
  │   │
  │   ├── SUBAGENT: ContextPruner si tokens > 40k
  │   │   └── Compresse l'historique
  │   │
  │   ├── runShellCommand("flutter pub add firebase_auth firebase_core")
  │   │   └── Si erreur "command not found" → auto-install flutter
  │   │
  │   ├── writeFile("lib/ui/login_page.dart", code)
  │   │   └── AgentEventBus.emit(FileChanged, path: "lib/ui/login_page.dart")
  │   │
  │   └── editFile("lib/ui/home.dart", navigation)
  │       └── AgentEventBus.emit(FileChanged, path: "lib/ui/home.dart")
  │
  ├── Phase 3: VERIFICATION
  │   └── VerificationPipeline.run(changedFiles: ["lib/ui/login_page.dart", "lib/ui/home.dart"])
  │       ├── LspChecker.check()               ← diagnostics LSP
  │       ├── AnalyzerChecker.run("dart analyze")
  │       ├── Si erreurs → Agent corrige automatiquement
  │       └── AgentEventBus.emit(VerificationPassed)
  │
  ├── Phase 4: REVIEW (optionnel, pour tâches > 5 fichiers)
  │   └── SubagentManager.spawn(ReviewerAgent, prompt: "Review login page")
  │       └── AgentEventBus.emit(ReviewCompleted, feedback: "...")
  │
  └── Phase 5: DONE
      └── AgentEventBus.emit(AgentFinished, result: "Page de login créée")
  ↓
UI met à jour via AgentEventBus listeners
  ├── Activity Feed se remplit
  ├── Messages s'affichent
  └── Plan viewer montre les étapes cochées
```

---

## 9. Flux Subagent

```
MainAgent needs help with subtask
  ↓
SubagentManager.spawn(agentId: "thinker", prompt: "Analyse la meilleure approche")
  ↓
AgentRegistry.get("thinker") → AgentDefinition
  ↓
SubagentTask created:
  - input: { prompt: "...", filePaths: [...] }
  - agent: ThinkerAgent
  - context: subset du contexte parent
  ↓
AgentRunner.run(subagentTask)         ← même boucle, agent différent
  ↓
ThinkerAgent.process()                ← pas de tools, juste réflexion
  ↓
SubagentTask.result = { message: "..." }
  ↓
MainAgent reçoit le résultat et continue
```

---

## 10. Flux Tool

```
AgentRunner receives tool call from LLM
  ↓
ToolRegistry.get("readFile") → ToolDefinition
  ↓
ToolPermissionManager.check(tool, currentMode)
  ├── Mode Agent: tous les tools autorisés
  ├── Mode Ask: lecture seule
  ├── Mode Plan: lecture seule + search
  └── Si refusé → retourne "Blocage: tool non autorisé en mode X"
  ↓
ToolExecutor.execute(tool, args)
  ├── file_tools.readFile(path)
  ├── terminal_tools.runShellCommand(cmd)
  ├── search_tools.searchInFiles(query)
  └── etc.
  ↓
ToolResult { success, data, error }
  ↓
AgentRunner adds result to conversation
  ↓
AgentEventBus.emit(ToolFinished, toolId, result)
  ↓
Activity Feed met à jour
```

---

## 11. Flux Verification

```
Agent modifies files
  ↓
VerificationPipeline.run(changedFiles)
  ↓
Stratégie adaptative:
  ├── Si 1 fichier Dart modifié:
  │   └── LspChecker.check(file) + AnalyzerChecker.run("dart analyze lib/")
  │
  ├── Si dépendances modifiées (pubspec.yaml):
  │   └── AnalyzerChecker.run("flutter pub get && dart analyze")
  │
  ├── Si +5 fichiers modifiés:
  │   ├── LspChecker.checkAll(changedFiles)
  │   ├── AnalyzerChecker.run("dart analyze")
  │   └── TestRunner.run("flutter test")  ← tests ciblés
  │
  └── Si build critique (main.dart, navigation):
      ├── AnalyzerChecker.run("flutter build apk --debug")
      └── TestRunner.run("flutter test")
  ↓
Si erreurs:
  └── Agent reçoit les erreurs et corrige automatiquement
      └── Loop jusqu'à PASS ou max 3 tentatives
  ↓
AgentEventBus.emit(VerificationPassed/Failed)
```

---

## 12. Flux Context

```
ContextManager.buildContext()
  ↓
┌─────────────────────────────────────────┐
│ 1. ProjectTree                          │
│    → structure des fichiers du projet   │
│    → Dart: pubspec.yaml, lib/, etc.     │
├─────────────────────────────────────────┤
│ 2. CodeMap                              │
│    → arbre syntaxique (classes, funcs)  │
│    → basé sur dart:analyzer             │
│    → taille max: 4k tokens              │
├─────────────────────────────────────────┤
│ 3. RelevantFiles                        │
│    → fichiers liés à la tâche           │
│    → trouvés par searchInFiles + glob   │
│    → max: 10 fichiers                   │
├─────────────────────────────────────────┤
│ 4. ActiveFile                           │
│    → fichier actuellement ouvert        │
│    → contenu complet                    │
├─────────────────────────────────────────┤
│ 5. GitDiff                              │
│    → modifications non commitées        │
│    → git diff HEAD                      │
├─────────────────────────────────────────┤
│ 6. LspDiagnostics                       │
│    → erreurs/warnings en cours          │
│    → diagnostics des fichiers ouverts   │
├─────────────────────────────────────────┤
│ 7. ProjectMemory                        │
│    → .panda/memory.md                   │
│    → préférences utilisateur            │
├─────────────────────────────────────────┤
│ 8. KnowledgeFiles                       │
│    → .panda/rules.md                    │
│    → instructions spécifiques           │
├─────────────────────────────────────────┤
│ 9. ToolOutputs                          │
│    → sorties des tools précédents       │
│    → max: 2k tokens par sortie          │
├─────────────────────────────────────────┤
│ 10. ConversationHistory                 │
│    → derniers 20 messages               │
│    → compresse si > 40k tokens          │
└─────────────────────────────────────────┘
  ↓
Taille totale max: 80k tokens (pour laisser de la place à la réponse)
  ↓
Si dépassement → ContextPruner compresse
```

---

## 13. Flux Event → Activity Feed

```
AgentEventBus (Stream<AgentEvent>)
  ↓
┌──────────────────────────────────────────┐
│ Event Types:                             │
│  ├── AgentStarted                        │
│  ├── ThinkingStarted                     │
│  ├── ThinkingFinished                    │
│  ├── ToolStarted(toolId, toolName, args) │
│  ├── ToolFinished(toolId, result)        │
│  ├── ToolFailed(toolId, error)           │
│  ├── SubAgentStarted(agentId)            │
│  ├── SubAgentFinished(agentId, result)   │
│  ├── FileChanged(path)                   │
│  ├── VerificationStarted                 │
│  ├── VerificationPassed                  │
│  ├── VerificationFailed(errors)          │
│  ├── StreamingChunk(text)                │
│  ├── AgentFinished(result)               │
│  └── AgentError(error)                   │
└──────────────────────────────────────────┘
  ↓
UI listens via StreamBuilder/StreamSubscription
  ↓
AgentActivityFeed (widget) → met à jour automatiquement
  ↓
Pas de couplage UI/moteur via callbacks
```

---

## 14. Architecture Mémoire

```
.panda/
├── memory.md              # Mémoire persistante du projet
│                          # (préférences, conventions, décisions)
│
├── rules.md               # Règles spécifiques au projet
│                          # (style, patterns, interdictions)
│
├── skills/                # Compétences réutilisables
│   ├── flutter-dev.md     # Guide développement Flutter
│   ├── git-workflow.md    # Workflow Git du projet
│   ├── testing.md         # Stratégie de tests
│   └── debugging.md       # Guide de debug
│
└── knowledge/             # Connaissance du projet
    ├── architecture.md    # Architecture du projet
    └── api.md             # API documentation
```

Comparaison :
| Projet | Fichier | Contenu |
|---|---|---|
| Codebuff | `AGENTS.md` | Instructions pour l'agent |
| Cline | `.clinerules` | Règles comportementales |
| Roo | `.roo/` | Modes + rules + settings |
| Continue | `.continue/` | Config + context |
| Gemini | `GEMINI.md` | Instructions + mémoire |
| **Panda** | **`.panda/`** | **Memory + Rules + Skills + Knowledge** |

---

## 15. Architecture Mobile (Android)

### Contraintes

| Ressource | Limite | Justification |
|---|---|---|
| **RAM** | 512 MB max pour l'agent | Android tue les apps > 512MB en background |
| **CPU** | 1 subagent à la fois | Éviter le throttle CPU |
| **Batterie** | Max 3 appels LLM par tâche | Limiter les appels réseau |
| **Réseau** | Timeout 30s par appel | Connexions mobiles instables |
| **Tokens** | 80k contexte max | Modèles mobiles limités |
| **Tool output** | 2k tokens max par sortie | Éviter le flooding du contexte |
| **Steps** | 20 max par tâche | Éviter les boucles infinies |
| **Subagents** | 1 à la fois | RAM/CPU limités |
| **Historique** | 20 messages max | Compresse au-delà |

### Stratégie

1. **Un seul subagent à la fois** (pas de parallélisme massif)
2. **Context pruning automatique** quand > 40k tokens
3. **Tool output tronqué** à 2k tokens
4. **Timeout 30s** sur tous les appels réseau
5. **Retry max 3 fois** sur erreurs réseau
6. **Session recovery** après interruption app
7. **Modèles distants** uniquement (pas de local sur mobile sauf Llama si disponible)

---

## 16. Tableau Comparatif Final — Gaps de Panda

### Déjà excellent dans Panda

| Fonctionnalité | Évaluation | Source |
|---|---|---|
| Agent / Ask / Plan modes | ✅ | Inspiré de Cline/Roo |
| Activity Feed | ✅ | Original |
| Tool system (read/write/edit/shell/search) | ✅ | Complet |
| Approval system | ✅ | Inspiré de Cline |
| Mémoire (.panda/memory.md) | ✅ | Inspiré de Gemini/Cline |
| LSP diagnostics | ✅ | Inspiré de Cline |
| Git integration | ✅ | Standard |
| PTY terminal | ✅ | Original |

### À améliorer

| Fonctionnalité | Problème | Solution | Source |
|---|---|---|---|
| Agent loop | Monolithique, pas d'événements | Event-driven avec AgentEventBus | Gemini CLI |
| Context management | Pas de pruning | ContextPruner agent | Codebuff |
| Tool permissions | Basique | Mode-based permission matrix | Roo Code |
| UI coupling | Callbacks directs | Stream-based events | Gemini CLI |
| Vérification | Aucune | VerificationPipeline adaptatif | Cline |
| Agent definitions | Hardcodées | Typed definitions avec schemas | Codebuff |
| Skills | Aucune | .panda/skills/ directory | Gemini CLI |

### Manquant

| Fonctionnalité | Pourquoi | Solution | Source | Priorité |
|---|---|---|---|---|
| Subagents | Tâches complexes nécessitent spécialisation | SubagentManager + ThinkerAgent + ReviewerAgent | Codebuff | **P1** |
| Code map | L'agent n'a pas de vue globale du projet | CodeMap basé sur dart:analyzer | Aider | **P1** |
| Context pruning | Le contexte déborde | ContextPruner subagent | Codebuff | **P1** |
| Verification pipeline | Pas de vérification post-modification | LSP + Analyzer + Tests adaptatifs | Cline | **P1** |
| Review agent | Pas de review automatique | ReviewerAgent post-tâche | Codebuff | **P2** |
| Knowledge files | Pas de rules/skills | .panda/rules.md + .panda/skills/ | Gemini/Cline/Roo | **P2** |
| Event bus | UI couplée au moteur | AgentEventBus avec StreamController | Gemini CLI | **P1** |
| Tool permissions fines | Permissions basiques | Permission matrix par mode | Roo Code | **P2** |

### Inutile pour Panda

| Fonctionnalité | Pourquoi |
|---|---|
| MCP (Model Context Protocol) | Panda est un IDE mobile, pas un extension host |
| Docker sandbox | Android n'a pas Docker |
| Browser automation | secondaire sur mobile |
| A2A (Agent-to-Agent) | Trop complexe pour mobile |

### À adapter au mobile

| Fonctionnalité | Adaptation |
|---|---|
| Subagents | Max 1 à la fois, timeout 30s |
| Context pruning | Plus agressif (80k max au lieu de 200k+) |
| Code map | Lazy loading, pas de cache complet |
| Verification | Pas de `flutter build` complet, juste `dart analyze` |
| Parallel execution | Désactivé sur mobile |

### À ne surtout pas copier

| Fonctionnalité | Projet | Pourquoi |
|---|---|---|
| Docker sandboxing | OpenHands, SWE-agent | Impossible sur Android |
| Electron UI | Cline, Roo | Desktop only |
| MCP extensions | Cline, Goose | Trop lourd pour mobile |
| Local inference | Goose | RAM insuffisante |

---

## 17. Faut-il Réellement Plusieurs Agents ?

### Réponse : OUI, mais modéré.

**Architecture recommandée pour Panda :**

```
MainAgent (1)
  ├── spawn → ThinkerAgent (0-1, sans tools, réflexion profonde)
  ├── spawn → ReviewerAgent (0-1, sans tools, post-tâche)
  └── spawn → ContextPrunerAgent (0-1, compresse le contexte)
```

**Pourquoi PAS 5-6 subagents :**
1. Chaque subagent = 1 appels LLM supplémentaire = tokens + latence
2. Sur Android, la RAM est limitée (512 MB)
3. Les modèles distants ont des timeouts
4. La plupart des tâches ne nécessitent pas de spécialisation

**Pourquoi quand même des subagents :**
1. Le **Thinker** permet une réflexion profonde sans polluer le contexte principal
2. Le **Reviewer** permet une vérification objective post-tâche
3. Le **ContextPruner** compresse le contexte sans interrompre l'agent principal

---

## 18. Architecture des Subagents

### Quels subagents ?

| Subagent | Quand | Tools | Contexte | Modèle |
|---|---|---|---|---|
| **ThinkerAgent** | Tâche complexe nécessitant réflexion | Aucun | Historique complet | LLM puissant |
| **ReviewerAgent** | Post-tâche (> 3 fichiers modifiés) | Aucun | Historique + fichiers modifiés | LLM puissant |
| **ContextPrunerAgent** | Tokens > 40k | Aucun | Historique complet | LLM rapide |

### Communication

```
MainAgent
  ├── spawn(ThinkerAgent, prompt: "...", filePaths: [...])
  │   └── result → MainAgent reçoit le raisonnement
  │
  ├── spawn(ReviewerAgent, prompt: "Review les changements")
  │   └── result → MainAgent corrige si nécessaire
  │
  └── spawn(ContextPrunerAgent, params: { maxTokens: 40k })
      └── result → Historique compressé
```

### Partage de contexte

- Les subagents reçoivent un **sous-ensemble** du contexte (pas tout)
- Le Thinker reçoit l'historique complet mais pas les tool outputs
- Le Reviewer reçoit les fichiers modifiés + la tâche originale
- Le ContextPruner reçoit tout l'historique pour le compresse

### Conflits

- Pas de conflit possible : les subagents sont **lecture seule** (sauf ContextPruner qui compresse)
- Seul le MainAgent peut modifier les fichiers

---

## 19. Architecture des Tools

### Structure

```
Agent
  ↓
ToolRegistry.get(toolName) → ToolDefinition
  ↓
ToolPermissionManager.check(tool, mode) → allowed?
  ↓
ToolExecutor.execute(tool, args) → ToolResult
  ↓
Agent
```

### ToolDefinition

```dart
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema
  final bool isMutating; // true = modify files/shell
  final ToolCategory category;
}
```

### ToolPermissionMatrix

| Tool | Agent Mode | Ask Mode | Plan Mode |
|---|---|---|---|
| readFile | ✅ | ✅ | ✅ |
| writeFile | ✅ | ❌ | ❌ |
| editFile | ✅ | ❌ | ❌ |
| runShellCommand | ✅ | ❌ | ❌ |
| searchInFiles | ✅ | ✅ | ✅ |
| git operations | ✅ | ❌ | ❌ |
| getTerminalOutput | ✅ | ✅ | ✅ |
| getLspDiagnostics | ✅ | ✅ | ✅ |

---

## 20. Architecture Event Bus

```dart
class AgentEventBus {
  final _controller = StreamController<AgentEvent>.broadcast();
  
  Stream<AgentEvent> get events => _controller.stream;
  
  void emit(AgentEvent event) => _controller.add(event);
  
  void dispose() => _controller.close();
}

// Types d'événements
sealed class AgentEvent {
  const AgentEvent();
}

class AgentStarted extends AgentEvent { final String taskId; }
class ThinkingStarted extends AgentEvent {}
class ThinkingFinished extends AgentEvent { final String thinking; }
class ToolStarted extends AgentEvent { final String toolId; final String toolName; final Map<String, dynamic> args; }
class ToolFinished extends AgentEvent { final String toolId; final String? result; }
class ToolFailed extends AgentEvent { final String toolId; final String error; }
class SubAgentStarted extends AgentEvent { final String agentId; }
class SubAgentFinished extends AgentEvent { final String agentId; final String result; }
class FileChanged extends AgentEvent { final String path; }
class VerificationStarted extends AgentEvent { final List<String> files; }
class VerificationPassed extends AgentEvent {}
class VerificationFailed extends AgentEvent { final List<String> errors; }
class StreamingChunk extends AgentEvent { final String text; }
class AgentFinished extends AgentEvent { final String result; }
class AgentError extends AgentEvent { final String error; }
```

### UI listens

```dart
// Dans le widget agent
StreamBuilder<AgentEvent>(
  stream: agentEventBus.events,
  builder: (context, snapshot) {
    final event = snapshot.data;
    if (event is ToolStarted) return ToolCard(event);
    if (event is StreamingChunk) return TypingIndicator(event.text);
    // ...
  },
)
```

---

## 21. Roadmap d'Implémentation

### P0 — Architecture Fondamentale (2-3 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| AgentEventBus | `core/agent_event_bus.dart` | Bus d'événements |
| AgentState | `core/agent_state.dart` | État de l'agent (extraire de home.dart) |
| AgentRunner refactor | `core/agent_runner.dart` | Utiliser AgentEventBus au lieu de callbacks |
| ToolRegistry | `tools/tool_registry.dart` | Registre des tools |
| ToolExecutor | `tools/tool_executor.dart` | Exécuteur de tools |
| ModeRegistry | `modes/mode_registry.dart` | Registre des modes |

### P1 — Fonctionnalités Indispensables (3-4 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| ContextManager | `context/context_manager.dart` | Gestion du contexte |
| ContextPruner | `context/context_pruner.dart` | Compression du contexte |
| SubagentManager | `subagents/subagent_manager.dart` | Gestion des subagents |
| ThinkerAgent | `agents/thinker_agent.dart` | Agent de réflexion |
| VerificationPipeline | `verification/verification_pipeline.dart` | Pipeline de vérification |
| LspChecker | `verification/lsp_checker.dart` | Vérification LSP |
| AgentDefinition | `agents/agent_definition.dart` | Définitions typées |
| CodeMap | `context/code_map.dart` | Arbre syntaxique |

### P2 — Améliorations (2-3 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| ReviewerAgent | `agents/reviewer_agent.dart` | Agent de review |
| KnowledgeFiles | `memory/knowledge_files.dart` | .panda/rules.md + skills |
| ToolPermission | `tools/tool_permission.dart` | Permissions fines |
| ToolPermissions file tools | `tools/file_tools.dart` | Extraction des tools fichiers |
| ToolPermissions terminal tools | `tools/terminal_tools.dart` | Extraction des tools terminal |
| ToolPermissions search tools | `tools/search_tools.dart` | Extraction des tools recherche |
| BeUI integration | `features/agent_ui/` | Intégration des 15 composants |
| AnalyzerChecker | `verification/analyzer_checker.dart` | dart analyze |
| TestRunner | `verification/test_runner.dart` | Tests ciblés |

### P3 — Avancé (3-4 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| SessionRecovery | `core/session_recovery.dart` | Reprise après interruption |
| RetryManager | `core/retry_manager.dart` | Gestion des retries |
| ErrorClassifier | `core/error_classifier.dart` | Classification des erreurs |
| Skills system | `memory/skills/` | Système de compétences |
| SessionStore | `core/session_store.dart` | Persistance des sessions |
| ModelCapabilities | `core/model_capabilities.dart` | Capacités par modèle |

---

## 22. Exemple de Flow Complet — Dart/Flutter

### Fichier : `lib/agent/core/agent_event_bus.dart`

```dart
import 'dart:async';

sealed class AgentEvent {
  const AgentEvent();
}

class AgentStarted extends AgentEvent {
  final String taskId;
  const AgentStarted({required this.taskId});
}

class ThinkingStarted extends AgentEvent {
  const ThinkingStarted();
}

class ToolStarted extends AgentEvent {
  final String toolId;
  final String toolName;
  final Map<String, dynamic> args;
  const ToolStarted({required this.toolId, required this.toolName, required this.args});
}

class ToolFinished extends AgentEvent {
  final String toolId;
  final String? result;
  const ToolFinished({required this.toolId, this.result});
}

class StreamingChunk extends AgentEvent {
  final String text;
  const StreamingChunk({required this.text});
}

class AgentFinished extends AgentEvent {
  final String result;
  const AgentFinished({required this.result});
}

class AgentEventBus {
  final _controller = StreamController<AgentEvent>.broadcast();
  
  Stream<AgentEvent> get events => _controller.stream;
  
  void emit(AgentEvent event) => _controller.add(event);
  
  void dispose() => _controller.close();
}
```

### Fichier : `lib/agent/agents/agent_definition.dart`

```dart
class AgentDefinition {
  final String id;
  final String displayName;
  final String model;
  final String systemPrompt;
  final List<String> toolNames;
  final List<String> spawnableAgents;
  final bool inheritParentSystemPrompt;
  final bool includeMessageHistory;
  final Map<String, dynamic>? inputSchema;
  
  const AgentDefinition({
    required this.id,
    required this.displayName,
    required this.model,
    required this.systemPrompt,
    this.toolNames = const [],
    this.spawnableAgents = const [],
    this.inheritParentSystemPrompt = false,
    this.includeMessageHistory = false,
    this.inputSchema,
  });
}
```

### Fichier : `lib/agent/tools/tool_registry.dart`

```dart
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final bool isMutating;
  final Future<ToolResult> Function(Map<String, dynamic> args) execute;
  
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.isMutating,
    required this.execute,
  });
}

class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};
  
  void register(ToolDefinition tool) => _tools[tool.name] = tool;
  
  ToolDefinition? get(String name) => _tools[name];
  
  List<Map<String, dynamic>> getSchemas() => _tools.values.map((t) => {
    'function': {
      'name': t.name,
      'description': t.description,
      'parameters': t.parameters,
    }
  }).toList();
}
```

---

*Document généré par Buffy (Codebuff) — Analyse de 12+ coding agents open-source*
*Repos analysés : Freebuff/Codebuff, OpenHands, Cline, Roo Code, Goose, Continue, SWE-agent, Aider, Gemini CLI*
