# Panda Agent — Architecture Finale (v2)

> Analyse comparative de 12+ coding agents open-source → Architecture Flutter/Dart pour Panda IDE
> Corrigé : MCP reconsidéré, détection ressources device, intégration multi-langage

---

## 0. Corrections de la v1

### MCP n'est PAS lourd

MCP (Model Context Protocol) est un **protocole JSON léger** — pas un framework lourd.

| Composant | Taille | RAM | CPU |
|---|---|---|---|
| MCP protocol (JSON over stdio) | ~10 KB | ~1 MB | Négligeable |
| MCP server simple (filesystem) | ~50 KB | ~5 MB | Négligeable |
| MCP server complexe (browser) | ~500 KB | ~50 MB | Modéré |
| **Total pour 3-4 MCP servers** | **~600 KB** | **~60 MB** | **Faible** |

**60 MB = 7.5% de 8 GB RAM.** C'est rien.

Ce qui est lourd, c'est pas le protocole, c'est le **contenu** du serveur MCP (ex: un browser headless). Mais ça, c'est un choix par serveur, pas un problème de protocole.

**Décision : Panda supporte MCP.** Les serveurs MCP tournent comme des Dart isolates ou des processus natifs.

### Détection Ressources Device

Au démarrage, Panda détecte les ressources disponibles et configure dynamiquement :

```dart
class DeviceCapabilities {
  final int totalRamMB;
  final int availableRamMB;
  final int cpuCores;
  final double batteryPercent;
  final NetworkType network; // wifi, mobile, none
  final int storageAvailableMB;
  
  // Calculé automatiquement
  int get maxConcurrentAgents {
    if (totalRamMB >= 8192) return 3;  // 8GB+ : 3 agents
    if (totalRamMB >= 6144) return 2;  // 6GB : 2 agents
    if (totalRamMB >= 4096) return 2;  // 4GB : 2 agents
    return 1;                           // <4GB : 1 agent
  }
  
  int get maxContextTokens {
    if (availableRamMB >= 2048) return 120000;  // 2GB+ libre : 120k tokens
    if (availableRamMB >= 1024) return 80000;   // 1GB libre : 80k tokens
    if (availableRamMB >= 512) return 40000;    // 512MB libre : 40k tokens
    return 20000;                                // <512MB : 20k tokens
  }
  
  int get maxToolOutputTokens {
    if (availableRamMB >= 1024) return 4000;
    return 2000;
  }
  
  bool get allowVerification {
    return batteryPercent > 20 && network != NetworkType.none;
  }
  
  bool get allowSubagents {
    return maxConcurrentAgents > 1 && batteryPercent > 15;
  }
}
```

### Exemple : Galaxy S21 (8GB RAM, 8 cores)

| Ressource | Valeur | Impact |
|---|---|---|
| RAM totale | 8192 MB | maxConcurrentAgents = 3 |
| RAM disponible (typique) | ~3000 MB | maxContextTokens = 120k |
| CPU cores | 8 | Isolates Dart = 4-6 threads utiles |
| Batterie (typique) | 70% | allowVerification = true |
| Réseau | WiFi/5G | Appels LLM rapides |

**Avec un S21, Panda peut faire tourner 3 agents simultanés + MCP + vérification.**

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

---

## 2. Critique de l'Ancienne Proposition (v1)

| Erreur v1 | Correction v2 |
|---|---|
| « MCP trop lourd pour mobile » | **Faux.** MCP = 60 MB RAM pour 3-4 serveurs. Un S21 a 8 GB. |
| « Pas de parallélisme mobile » | **Faux.** Dart isolates + 8 cores = 3-4 agents possibles. |
| « Max 1 subagent » | **Faux.** Avec détection device, on peut aller à 3 sur device haut de gamme. |
| « Pas de Rust/C/Go » | **À réévaluer.** Dart FFI permet d'appeler du code natif pour les tâches critiques. |
| « 80k tokens max contexte » | **Dépend du device.** S21 = 120k tokens possibles. |

---

## 3. Intégration Multi-Langage

### 3.1 Pourquoi ?

Dart est excellent pour :
- UI Flutter
- Async/Isolates
- Communication réseau
- State management (BLoC)

Mais il est **plus lent** que Rust/C pour :
- Parsing syntaxique (tree-sitter)
- Indexation de code
- Compression de contexte
- Opérations sur gros fichiers
- Calculs mathématiques

### 3.2 Ce qui change la donne

| Tâche | Dart seul | Dart + Rust (FFI) | Gain |
|---|---|---|---|
| Tree-sitter parse 10k lignes | ~200ms | ~20ms | **10x** |
| Indexation code complet | ~5s | ~500ms | **10x** |
| Compression contexte | ~500ms | ~50ms | **10x** |
| Search dans 1000 fichiers | ~2s | ~200ms | **10x** |
| JSON parse gros payload | ~100ms | ~10ms | **10x** |

### 3.3 Langages à intégrer

| Langage | Usage | Priorité | Complexité |
|---|---|---|---|
| **Rust** (via FFI) | Tree-sitter, indexation, compression | **P1** | Moyenne |
| **C** (via FFI) | Algorithmes existants (zlib, etc.) | **P2** | Faible |
| **Go** (via FFI ou process) | Networking, MCP servers | **P3** | Élevée |

### 3.4 Architecture FFI

```
┌─────────────────────────────────────────┐
│  Flutter/Dart (UI + Logic)              │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  Dart FFI Bridge                │   │
│  │  (dart:ffi + package:ffi)       │   │
│  └──────────┬──────────────────────┘   │
│             │                           │
│  ┌──────────▼──────────────────────┐   │
│  │  Native Libraries (.so/.dylib)  │   │
│  │                                 │   │
│  │  ├── libpanda_parser.so (Rust)  │   │ ← tree-sitter parsing
│  │  ├── libpanda_index.so (Rust)   │   │ ← code indexing
│  │  ├── libpanda_compress.so (C)   │   │ ← context compression
│  │  └── libpanda_search.so (Rust)  │   │ ← search engine
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### 3.5决择 : Faut-il vraiment Rust ?

**OUI, mais uniquement pour les tâches CPU-critiques.**

| Tâche | Dart suffit ? | Rust nécessaire ? | Pourquoi |
|---|---|---|---|
| UI Flutter | ✅ | ❌ | Dart est fait pour ça |
| Agent loop | ✅ | ❌ | Async Dart suffit |
| Tool execution | ✅ | ❌ | Process launch suffit |
| LLM API calls | ✅ | ❌ | HTTP client Dart suffit |
| **Tree-sitter parsing** | ❌ Lent | ✅ | 10x plus rapide en Rust |
| **Code indexing** | ❌ Lent | ✅ | 10x plus rapide en Rust |
| **Search dans gros projets** | ❌ Lent | ✅ | 10x plus rapide en Rust |
| **Context compression** | ⚠️ Acceptable | ✅ | 10x plus rapide en Rust |
| MCP servers | ✅ | ❌ | Dart isolates suffisent |

**Règle : Si ça tourne > 100ms en Dart, on utilise Rust.**

---

## 4. Architecture Conceptuelle Finale

```
┌─────────────────────────────────────────────────────────────┐
│                    PANDA AGENT v2                            │
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │   User   │───▶│  AgentRunner │───▶│  AgentEventBus   │   │
│  │  Input   │    │  (Main Loop) │    │  (Events → UI)   │   │
│  └──────────┘    └──────┬───────┘    └──────────────────┘   │
│                         │                                    │
│  ┌──────────────────────┼──────────────────────┐            │
│  │         DeviceCapabilities                  │            │
│  │  RAM → maxAgents, maxTokens                 │            │
│  │  CPU → parallelism level                    │            │
│  │  Battery → verification aggressiveness      │            │
│  │  Network → LLM timeout, retry strategy      │            │
│  └──────────────────────┼──────────────────────┘            │
│                         │                                    │
│              ┌──────────┼──────────┐                        │
│              ▼          ▼          ▼                        │
│     ┌────────────┐ ┌─────────┐ ┌──────────┐               │
│     │  Context   │ │  Tool   │ │  Model   │               │
│     │  Manager   │ │ Registry│ │ Provider │               │
│     └─────┬──────┘ └────┬────┘ └──────────┘               │
│           │             │                                   │
│     ┌─────▼──────┐ ┌────▼─────┐                            │
│     │  MCP       │ │  Tool    │                            │
│     │  Manager   │ │ Executor │                            │
│     │ (Isolates) │ │          │                            │
│     └────────────┘ └──────────┘                            │
│           │             │                                   │
│     ┌─────▼──────┐ ┌────▼─────┐ ┌──────────┐             │
│     │  SubAgent  │ │ Native   │ │  LLM     │             │
│     │  Manager   │ │ Bridge   │ │  API     │             │
│     │ (max N)    │ │ (Rust/C) │ │          │             │
│     └────────────┘ └──────────┘ └──────────┘             │
│           │             │           │                      │
│     ┌─────▼──────┐ ┌────▼─────┐ ┌──────────┐             │
│     │  Memory    │ │ Verifier │ │  Session │             │
│     │  System    │ │ (LSP+    │ │  Store   │             │
│     └────────────┘ │  native) │ └──────────┘             │
│                    └──────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Architecture des MCP Servers

### 5.1 Pourquoi MCP dans Panda ?

MCP permet d'**étendre les tools de l'agent** sans modifier le code Dart. C'est exactement comme les extensions VSCode, mais pour les outils.

### 5.2 MCP Servers Panda

| Serveur MCP | Usage | RAM | Priorité |
|---|---|---|---|
| **filesystem** | Lecture/écriture fichiers | ~5 MB | P0 |
| **git** | Opérations git complètes | ~3 MB | P0 |
| **search** | Recherche dans le code | ~10 MB | P1 |
| **browser** | Navigation web | ~50 MB | P2 |
| **database** | SQLite local | ~5 MB | P2 |
| **android** | ADB, intents, device info | ~3 MB | P1 |
| **flutter** | Flutter SDK, build, test | ~5 MB | P0 |

### 5.3 Architecture MCP dans Dart

```dart
class McpManager {
  final Map<String, McpServer> _servers = {};
  final DeviceCapabilities _device;
  
  McpManager(this._device);
  
  /// Lance un serveur MCP comme Dart Isolate
  Future<void> startServer(String name, McpServerConfig config) async {
    if (!_device.allowMcpServer(name)) return;
    
    final isolate = await Isolate.spawn(
      _runMcpServer,
      config,
      debugName: 'mcp-$name',
    );
    _servers[name] = McpServer(isolate: isolate, config: config);
  }
  
  /// Appelle un outil MCP
  Future<McpResult> callTool(String server, String tool, Map<String, dynamic> args) async {
    final s = _servers[server];
    if (s == null) throw McpError('Server $server not running');
    return s.callTool(tool, args);
  }
  
  /// Arrête les serveurs低priorité si RAM insuffisante
  void trimToFit(int targetRamMB) {
    // Ordre de priorité : filesystem > git > search > android > flutter > browser > database
    final priority = ['filesystem', 'git', 'search', 'android', 'flutter', 'browser', 'database'];
    // Arrêter les moins prioritaires jusqu'à atteindre la cible
  }
}
```

### 5.4 MCP vs Tools Natifs

| Aspect | Tools Natifs (Dart) | MCP Servers |
|---|---|---|
| Performance | ⚡ Plus rapide (pas IPC) | 🔄 Overhead IPC ~1ms |
| Extensibilité | ❌ Recompiler | ✅ Plugins dynamiques |
| Isolation | ❌ Même processus | ✅ Isolates séparés |
| Crash isolation | ❌ Crash = crash app | ✅ Crash = restart isolate |
| RAM | 💚 Partagée | 🟡 ~5 MB par serveur |
| Complexité | 💚 Simple | 🟡 Plus de code |

**Décision : Les outils critiques (file read/write, shell) restent natifs. MCP pour l'extensibilité.**

---

## 6. Architecture Flutter/Dart Finale (mise à jour)

```
lib/
├── agent/
│   ├── core/
│   │   ├── agent_runner.dart          # Boucle principale
│   │   ├── agent_state.dart           # État de l'agent
│   │   ├── agent_event_bus.dart       # Bus d'événements
│   │   ├── agent_config.dart          # Configuration
│   │   └── device_capabilities.dart   # 🆕 Détection ressources device
│   │
│   ├── agents/
│   │   ├── agent_definition.dart      # Définition typée
│   │   ├── agent_registry.dart        # Registre des agents
│   │   ├── main_agent.dart            # Agent principal
│   │   ├── thinker_agent.dart         # Réflexion profonde
│   │   ├── reviewer_agent.dart        # Review post-tâche
│   │   └── context_pruner_agent.dart  # Compression contexte
│   │
│   ├── subagents/
│   │   ├── subagent_manager.dart      # Gestion dynamique basée sur device
│   │   └── subagent_task.dart         # Tâche d'un subagent
│   │
│   ├── tools/
│   │   ├── tool_registry.dart         # Registre des tools
│   │   ├── tool_executor.dart         # Exécuteur
│   │   ├── tool_permission.dart       # Permissions par mode
│   │   ├── file_tools.dart            # Outils fichiers (natifs)
│   │   ├── terminal_tools.dart        # Outils terminal (natifs)
│   │   ├── search_tools.dart          # Outils recherche (natifs)
│   │   ├── editor_tools.dart          # Outils éditeur (natifs)
│   │   ├── git_tools.dart             # Outils git (natifs)
│   │   └── web_tools.dart             # Outils web (MCP)
│   │
│   ├── mcp/                           # 🆕 MCP Support
│   │   ├── mcp_manager.dart           # Gestionnaire MCP
│   │   ├── mcp_server.dart            # Serveur MCP (isolate)
│   │   ├── mcp_tool_bridge.dart       # Bridge tools natifs ↔ MCP
│   │   └── servers/
│   │       ├── filesystem_server.dart
│   │       ├── git_server.dart
│   │       ├── search_server.dart
│   │       ├── android_server.dart
│   │       └── flutter_server.dart
│   │
│   ├── context/
│   │   ├── context_manager.dart       # Gestion du contexte
│   │   ├── code_map.dart              # Arbre syntaxique (Rust FFI)
│   │   ├── project_tree.dart          # Structure fichiers
│   │   ├── relevant_files.dart        # Fichiers pertinents
│   │   └── context_pruner.dart        # Compression (Rust FFI)
│   │
│   ├── native/                        # 🆕 Pont FFI vers code natif
│   │   ├── native_bridge.dart         # Bridge Dart ↔ Rust/C
│   │   ├── tree_sitter_parser.dart    # Parser tree-sitter (Rust)
│   │   ├── code_indexer.dart          # Indexeur de code (Rust)
│   │   └── search_engine.dart         # Moteur de recherche (Rust)
│   │
│   ├── memory/
│   │   ├── project_memory.dart        # .panda/memory.md
│   │   ├── knowledge_files.dart       # .panda/rules.md + skills
│   │   └── session_memory.dart        # Mémoire session
│   │
│   ├── verification/
│   │   ├── verification_pipeline.dart # Pipeline adaptatif
│   │   ├── lsp_checker.dart           # Diagnostics LSP
│   │   ├── analyzer_checker.dart      # dart analyze
│   │   ├── native_checker.dart        # 🆕 Vérification via Rust (rapide)
│   │   └── test_runner.dart           # Tests ciblés
│   │
│   ├── events/
│   │   ├── agent_event.dart           # Types d'événements
│   │   ├── agent_event_bus.dart       # Bus d'événements
│   │   └── event_handlers.dart        # Gestionnaires
│   │
│   ├── models/
│   │   ├── agent_message.dart         # Message conversation
│   │   ├── tool_call.dart             # Appel d'outil
│   │   ├── tool_result.dart           # Résultat d'outil
│   │   ├── agent_result.dart          # Résultat final
│   │   └── agent_phase.dart           # Phases agent
│   │
│   └── modes/
│       ├── agent_mode.dart            # Mode Agent
│       ├── ask_mode.dart              # Mode Ask
│       ├── plan_mode.dart             # Mode Plan
│       └── mode_registry.dart         # Registre modes
│
├── native/                            # 🆕 Code Rust/C source
│   ├── rust/
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── parser.rs              # tree-sitter parser
│   │   │   ├── indexer.rs             # code indexer
│   │   │   ├── searcher.rs            # search engine
│   │   │   └── compressor.rs          # context compressor
│   │   └── target/                    # Compiled .so pour Android
│   │       ├── aarch64-linux-android/
│   │       └── armv7-linux-android/
│   └── c/
│       ├── zlib压缩.c                  # compression (si besoin)
│       └── Makefile
│
└── features/
    └── agent_ui/
        ├── activity_feed/
        ├── plan_viewer/
        ├── tool_viewer/
        ├── prompt_input/
        └── model_selector/
```

---

## 7. Limits Dynamiques par Device

### 7.1 Grille de Configuration

| Device Category | RAM | CPU | maxAgents | maxTokens | maxToolOutput | allowMcp | allowRust | allowVerification |
|---|---|---|---|---|---|---|---|---|
| **Flagship** (S21+, Pixel 7+) | 8GB+ | 8 cores | 3 | 120k | 4k | ✅ Full | ✅ | ✅ Full |
| **Mid-range** (A52+, Nord) | 6GB | 8 cores | 2 | 80k | 3k | ✅ Limited | ✅ | ✅ Light |
| **Budget** (A32, older) | 4GB | 4-6 cores | 2 | 40k | 2k | ✅ Minimal | ❌ | ⚠️ Basic only |
| **Low-end** (< 4GB) | <4GB | 4 cores | 1 | 20k | 1k | ❌ | ❌ | ❌ |

### 7.2 Détection au Démarrage

```dart
class DeviceDetector {
  static Future<DeviceCapabilities> detect() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final battery = await Battery().batteryLevel;
    final connectivity = await Connectivity().checkConnectivity();
    
    return DeviceCapabilities(
      totalRamMB: info.totalRam ~/ (1024 * 1024),
      availableRamMB: await _getAvailableRam(),
      cpuCores: info.physicalCpu ?? 4,
      batteryPercent: battery,
      network: _networkFromConnectivity(connectivity),
      storageAvailableMB: await _getStorageAvailable(),
      deviceModel: info.model,
      androidVersion: info.version.sdkInt,
    );
  }
  
  static Future<int> _getAvailableRam() async {
    // /proc/meminfo ou ActivityManager
    // ...
  }
}
```

### 7.3 Adaptation Dynamique

```dart
class AgentRunner {
  late final DeviceCapabilities _device;
  
  Future<void> start(String text) async {
    _device = await DeviceDetector.detect();
    
    // Adapter le comportement selon le device
    final maxAgents = _device.maxConcurrentAgents;
    final maxTokens = _device.maxContextTokens;
    
    // Si device faible, réduire la complexité
    if (_device.totalRamMB < 4096) {
      // Pas de subagents, pas de MCP, contexte réduit
      _config = AgentConfig.simple();
    } else if (_device.totalRamMB < 6144) {
      // 1 subagent possible, MCP limité
      _config = AgentConfig.moderate();
    } else {
      // Full features
      _config = AgentConfig.full();
    }
  }
}
```

---

## 8. Architecture MCP dans Panda

### 8.1 Serveurs MCP Intégrés

| Serveur | Description | Outils exposés | RAM |
|---|---|---|---|
| **panda-filesystem** | Lecture/écriture fichiers | readFile, writeFile, listDir, watchFile | ~5 MB |
| **panda-git** | Opérations git | commit, push, pull, diff, log, branch | ~3 MB |
| **panda-search** | Recherche code | grep, glob, ripgrep, ast-search | ~10 MB |
| **panda-android** | Device Android | adb, intents, device-info, install | ~3 MB |
| **panda-flutter** | Flutter SDK | analyze, build, test, pub-get | ~5 MB |
| **panda-browser** | Navigation web | navigate, screenshot, extract-text | ~50 MB |

### 8.2 Avantages de MCP pour Panda

1. **Extensibilité** : Les utilisateurs peuvent ajouter leurs propres MCP servers
2. **Isolation** : Un crash de serveur MCP ne crash pas l'app
3. **Performance** : Les serveurs lourds (browser) tournent en arrière-plan
4. **Compatibilité** : Les MCP servers existants fonctionnent directement
5. **Sécurité** : Chaque serveur a ses propres permissions

### 8.3 Intégration avec l'Agent

```
AgentRunner
  ↓
ToolRegistry.get("mcp:panda-git:commit")
  ↓
McpManager.callTool("panda-git", "commit", { message: "..." })
  ↓
McpServer (Dart Isolate)
  ↓
Exécute git commit
  ↓
Résultat → AgentRunner
```

---

## 9. Flux avec Détection Device

### Exemple : S21 (8GB RAM, 70% batterie, WiFi)

```
User: "Ajoute une page de login avec Firebase"
  ↓
DeviceDetector.detect() → { ram: 8192, cores: 8, battery: 70, network: wifi }
  ↓
Config: maxAgents=3, maxTokens=120k, allowMcp=true, allowRust=true
  ↓
AgentRunner.start()
  ├── ContextManager.buildContext(maxTokens: 120k)
  │   ├── CodeMap.analyze() → Rust FFI (~50ms au lieu de 500ms)
  │   ├── ProjectTree.scan()
  │   ├── RelevantFiles.find()
  │   └── ProjectMemory.load()
  │
  ├── MainAgent.process()
  │   ├── Tool: readFile (natif, 2ms)
  │   ├── Tool: mcp:panda-flutter:pub-add(firebase_auth) (MCP, 200ms)
  │   ├── Tool: writeFile (natif, 1ms)
  │   │
  │   ├── SubAgent: ThinkerAgent (parallèle, Analyse approfondie)
  │   │   └── Result → MainAgent continue
  │   │
  │   └── Tool: editFile (natif, 1ms)
  │
  ├── VerificationPipeline.run()
  │   ├── LspChecker (natif, 50ms)
  │   ├── AnalyzerChecker (MCP:panda-flutter, 2s)
  │   └── Result: PASS
  │
  └── SubAgent: ReviewerAgent (post-tāche)
      └── "La page de login est bien structurée, ajoute la validation email"
          → MainAgent corrige
  ↓
AgentFinished → UI met à jour
```

### Exemple : A32 (4GB RAM, 40% batterie, 4G)

```
User: "Ajoute une page de login avec Firebase"
  ↓
DeviceDetector.detect() → { ram: 4096, cores: 4, battery: 40, network: mobile }
  ↓
Config: maxAgents=2, maxTokens=40k, allowMcp=minimal, allowRust=false
  ↓
AgentRunner.start()
  ├── ContextManager.buildContext(maxTokens: 40k)
  │   ├── ProjectTree.scan() → Dart seul (~500ms)
  │   ├── RelevantFiles.find()
  │   └── ProjectMemory.load()
  │
  ├── MainAgent.process()
  │   ├── Tool: readFile (natif, 2ms)
  │   ├── Tool: runShellCommand("flutter pub add firebase_auth") (natif)
  │   ├── Tool: writeFile (natif, 1ms)
  │   └── Tool: editFile (natif, 1ms)
  │
  ├── VerificationPipeline.run()
  │   └── AnalyzerChecker (natif, 5s au lieu de 2s via MCP)
  │
  └── PAS de subagent (device trop faible)
  ↓
AgentFinished → UI met à jour
```

---

## 10. Gaps Finaux de Panda

### Déjà Excellent

| Fonctionnalité | Évaluation |
|---|---|
| Agent / Ask / Plan modes | ✅ Complet |
| Activity Feed | ✅ Original |
| Tool system | ✅ Complet |
| Approval system | ✅ |
| Mémoire | ✅ |
| LSP diagnostics | ✅ |
| Git integration | ✅ |
| PTY terminal | ✅ |

### À Améliorer

| Fonctionnalité | Solution | Priorité |
|---|---|---|
| Agent loop | Event-driven avec AgentEventBus | P0 |
| Context management | ContextManager + ContextPruner | P0 |
| Device detection | DeviceCapabilities au démarrage | P0 |
| Tool permissions | Permission matrix par mode | P1 |
| UI coupling | Stream-based events | P1 |
| Verification | Pipeline adaptatif | P1 |
| Agent definitions | Typed definitions | P1 |

### Manquant

| Fonctionnalité | Solution | Source | Priorité |
|---|---|---|---|
| Subagents | SubagentManager dynamique | Codebuff | P1 |
| Code map | Rust FFI tree-sitter | Aider | P1 |
| MCP support | McpManager + serveurs | Goose/Cline | P1 |
| Native bridge | Dart FFI → Rust | — | P1 |
| Review agent | ReviewerAgent | Codebuff | P2 |
| Knowledge files | .panda/rules.md + skills | Gemini/Cline | P2 |
| Event bus | AgentEventBus | Gemini CLI | P0 |
| Tool permissions | Mode-based matrix | Roo Code | P2 |

### Inutile pour Panda

| Fonctionnalité | Pourquoi |
|---|---|
| Docker sandbox | Android n'a pas Docker |
| Electron UI | Desktop only |
| Local inference (LLaMA) | RAM insuffisante pour un modèle complet |
| A2A protocol | Trop complexe, MCP suffit |

### À Adapter au Mobile

| Fonctionnalité | Adaptation |
|---|---|
| Subagents | Dynamique selon RAM (1-3) |
| MCP servers | Démarrent à la demande, pas tous en même temps |
| Context pruning | Plus agressif si RAM faible |
| Verification | Pas de build complet, juste analyze |
| Native code | FFI uniquement, pas de process Go |
| Parallel execution | Dart isolates, pas de threads |

---

## 11. Roadmap d'Implémentation (mise à jour)

### P0 — Fondations (2-3 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| AgentEventBus | `core/agent_event_bus.dart` | Bus d'événements |
| DeviceCapabilities | `core/device_capabilities.dart` | Détection ressources |
| AgentState | `core/agent_state.dart` | État agent (extraire) |
| AgentRunner refactor | `core/agent_runner.dart` | Utiliser EventBus + DeviceConfig |
| ToolRegistry | `tools/tool_registry.dart` | Registre tools |
| ToolExecutor | `tools/tool_executor.dart` | Exécuteur tools |
| ModeRegistry | `modes/mode_registry.dart` | Registre modes |

### P1 — Fonctionnalités Indispensables (3-4 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| ContextManager | `context/context_manager.dart` | Gestion contexte |
| ContextPruner | `context/context_pruner.dart` | Compression (Dart d'abord, Rust P2) |
| SubagentManager | `subagents/subagent_manager.dart` | Gestion dynamique |
| ThinkerAgent | `agents/thinker_agent.dart` | Réflexion profonde |
| VerificationPipeline | `verification/verification_pipeline.dart` | Pipeline adaptatif |
| LspChecker | `verification/lsp_checker.dart` | Diagnostics LSP |
| McpManager | `mcp/mcp_manager.dart` | Gestion MCP |
| McpServer | `mcp/mcp_server.dart` | Serveur MCP isolate |
| AgentDefinition | `agents/agent_definition.dart` | Définitions typées |

### P2 — Améliorations (2-3 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| ReviewerAgent | `agents/reviewer_agent.dart` | Review post-tâche |
| KnowledgeFiles | `memory/knowledge_files.dart` | Rules + skills |
| ToolPermission | `tools/tool_permission.dart` | Permissions fines |
| NativeBridge | `native/native_bridge.dart` | FFI bridge |
| Rust parser | `native/rust/src/parser.rs` | tree-sitter |
| Rust indexer | `native/rust/src/indexer.rs` | code indexer |
| MCP servers | `mcp/servers/*.dart` | filesystem, git, search |
| Flow UI integration | `lib/ui/agent/flow_ui/` | Composants de chat et composer |

### P3 — Avancé (3-4 semaines)

| Tâche | Fichier | Description |
|---|---|---|
| SessionRecovery | `core/session_recovery.dart` | Reprise interruption |
| RetryManager | `core/retry_manager.dart` | Gestion retries |
| ErrorClassifier | `core/error_classifier.dart` | Classification erreurs |
| Skills system | `memory/skills/` | Compétences |
| SessionStore | `core/session_store.dart` | Persistance sessions |
| MCP browser | `mcp/servers/browser_server.dart` | Navigation web |
| MCP android | `mcp/servers/android_server.dart` | Device Android |
| Rust searcher | `native/rust/src/searcher.rs` | Moteur recherche |

---

*Document v2 — Corrigé : MCP reconsidéré, détection device, multi-langage*
*Analyse de 12+ coding agents open-source*
