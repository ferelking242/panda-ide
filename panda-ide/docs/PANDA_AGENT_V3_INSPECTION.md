# Panda Agent V3 — Inspection Complète du Code Existant

## 1. Architecture Actuelle

### Fichiers Agent (5451 lignes total)

| Fichier | Lignes | Rôle |
|---|---|---|
| `lib/ui/agent_runner.dart` | 1261 | Runner principal + tool dispatch + system prompt |
| `lib/utils/agentic_tools.dart` | 3247 | Implémentations de tous les tools |
| `lib/utils/agentic_tool_catalog.dart` | 120 | Définitions des tools (AgenticToolSpec) |
| `lib/utils/subagent_orchestrator.dart` | 659 | Multi-agent rooms / conference |
| `lib/utils/subagent_runner.dart` | 46 | Stub subagent (simulé, pas réel) |
| `lib/mcp/mcp_client.dart` | 109 | Client MCP HTTP basique |
| `lib/mcp/mcp_registry.dart` | 27 | Persistance serveurs MCP |
| `lib/mcp/mcp_tool_catalog.dart` | 102 | Catalogue tools MCP |
| `lib/utils/agent_settings_service.dart` | 80 | Prompt/rules/secrets/skills |
| `lib/utils/agent_approval_rules.dart` | 50 | Règles d'auto-approval |
| `lib/utils/agent_checkpoint_manager.dart` | 80 | Snapshots fichiers pour rollback |
| `lib/utils/agent_history_service.dart` | 80 | Persistance sessions |
| `lib/utils/agent_thinking_parser.dart` | 80 | Parse <think> tags |
| `lib/ui/agent/agent_models.dart` | 215 | AgentActivityEvent + Controller |
| `lib/ui/agent/agent_widgets.dart` | 1601 | 29 widgets agent |
| `lib/ui/agent/flow_ui/` | — | Flow UI components utilisés par l'agent |

### Ce qui Existe et Fonctionne

| Composant | État | Notes |
|---|---|---|
| **AgentRunner** | ✅ Fonctionnel | Streaming + tool loop + retry basique |
| **30+ Tools** | ✅ Fonctionnels | readFile, writeFile, editFile, shell, search, git, web |
| **Approval System** | ✅ Fonctionnel | Auto-approval rules + user confirmation |
| **Session/History** | ✅ Fonctionnel | SharedPreferences persistence |
| **MCP Client** | ✅ Basique | HTTP only, pas de stdio |
| **Subagent Orchestrator** | ⚠️ Partiel | Conference rooms mais pas de vrai subagent |
| **Thinking Parser** | ✅ Fonctionnel | Parse <think>, <thought>, <reasoning> |
| **Checkpoint Manager** | ✅ Fonctionnel | File snapshots pour rollback |
| **Activity Feed** | ✅ Fonctionnel | AgentActivityController + widgets |
| **Flow UI Components** | ✅ Intégrés | Messages, markdown, code, réflexion, erreurs et composer |

### Doublons Identifiés

| Doublon | Fichier 1 | Fichier 2 | Problème |
|---|---|---|---|
| SubAgent types | `subagent_orchestrator.dart` (SubAgentConfig) | `subagent_runner.dart` (SubagentTask) | Deux systèmes différents |
| Tool dispatch | `agent_runner.dart` (_dispatchTool switch) | `agentic_tools.dart` (AgenticTools methods) | Logique dupliquée |
| Activity tracking | `agent_models.dart` (AgentActivityController) | `home.dart` (activityCtrl) | Même logique, deux endroits |
| MCP tools | `mcp_tool_catalog.dart` | `agentic_tool_catalog.dart` | Pas de pont entre les deux |

### Composants à Conserver Tels Quels

| Composant | Raison |
|---|---|
| `AgentRunner._buildSystemPrompt()` | Prompt système complet et bien structuré |
| `AgenticTools` (toutes les implémentations) | 30+ tools fonctionnels |
| `AgentCheckpointManager` | Rollback fonctionnel |
| `AgentThinkingParser` | Parse complet |
| `AgentHistoryService` | Persistance sessions |
| `AgentSettingsService` | Configuration agent |
| `AgentActivityController` | State machine activity feed |

### Composants à Refactorer

| Composant | Changement |
|---|---|
| `AgentRunner._dispatchTool()` | Extraire en ToolRegistry + ToolExecutor |
| `AgentRunner._run()` | Ajouter AgentEventBus pour découpler UI |
| `SubagentOrchestrator` | Remplacer par SubagentManager V3 |
| `SubagentRunner` | Supprimer (stub inutile) |
| `McpClient` | Étendre (ajouter stdio transport) |
| `AgenticToolSpec` | Remplacer par ToolDefinition typé |

### Composants Manquants

| Composant | Priorité | Description |
|---|---|---|
| **AgentEventBus** | P0 | Bus d'événements pour découpler UI/moteur |
| **ToolRegistry** | P0 | Registre formel des tools |
| **ToolExecutor** | P0 | Exécuteur avec permissions |
| **ToolPermission** | P1 | Matrice permissions par mode |
| **ModeRegistry** | P1 | Registre des modes (Agent/Ask/Plan) |
| **ContextManager** | P1 | Construction intelligente du contexte |
| **ContextPruner** | P1 | Compression du contexte |
| **HistoryCompactor** | P1 | Compaction de l'historique |
| **AgentRegistry** | P2 | Registre des agents (Main/Thinker/Reviewer) |
| **AgentDefinition** | P2 | Définition typée d'un agent |
| **SubagentManager** | P2 | Gestion dynamique des subagents |
| **VerificationPipeline** | P2 | LSP + analyzer + tests |
| **EnvironmentManager** | P2 | Détection outils installés |
| **SessionManager** | P3 | Start/pause/resume/recover |
| **RetryManager** | P3 | Gestion retries intelligentes |
| **ErrorClassifier** | P3 | Classification des erreurs |
| **DeviceCapabilities** | P3 | Détection ressources device |
| **CodeMap** | P3 | Arbre syntaxique du projet |

---

## 2. Plan de Migration

### Phase 1 — Fondations (AgentEventBus + ToolRegistry + ModeRegistry)

**Objectif** : Créer les fondations sans casser existant.

1. Créer `lib/agent/events/agent_event.dart` + `agent_event_bus.dart`
2. Créer `lib/agent/tools/tool_definition.dart` + `tool_registry.dart`
3. Créer `lib/agent/modes/mode_registry.dart`
4. Adapter `AgentRunner` pour émettre des événements
5. Pont ToolRegistry ↔ AgenticTools existant

### Phase 2 — Context Manager

**Objectif** : Construction intelligente du contexte.

1. Créer `lib/agent/context/context_manager.dart`
2. Créer `lib/agent/context/context_budget.dart`
3. Créer `lib/agent/context/context_pruner.dart`
4. Créer `lib/agent/context/history_compactor.dart`
5. Intégrer dans AgentRunner

### Phase 3 — Agent Registry + Subagents

**Objectif** : Système d'agents extensible.

1. Créer `lib/agent/agents/agent_definition.dart`
2. Créer `lib/agent/agents/agent_registry.dart`
3. Créer `lib/agent/subagents/subagent_manager.dart`
4. Créer `lib/agent/agents/thinker_agent.dart`
5. Adapter SubagentOrchestrator existant

### Phase 4 — Verification + Reviewer

**Objectif** : Vérification automatique post-modification.

1. Créer `lib/agent/verification/verification_pipeline.dart`
2. Créer `lib/agent/verification/lsp_checker.dart`
3. Créer `lib/agent/verification/analyzer_checker.dart`
4. Créer `lib/agent/agents/reviewer_agent.dart`

### Phase 5 — Environment + Process

**Objectif** : Détection outils système.

1. Créer `lib/agent/environment/environment_manager.dart`
2. Créer `lib/agent/environment/executable_detector.dart`
3. Créer `lib/agent/environment/process_runner.dart`

### Phase 6 — MCP Amélioré

**Objectif** : MCP complet avec stdio + HTTP.

1. Étendre `lib/mcp/mcp_client.dart` (ajouter stdio)
2. Créer `lib/agent/mcp/mcp_tool_bridge.dart`
3. Pont MCP tools ↔ ToolRegistry

### Phase 7 — Session + Retry

**Objectif** : Résilience et reprise.

1. Créer `lib/agent/sessions/session_manager.dart`
2. Créer `lib/agent/runtime/retry_manager.dart`
3. Créer `lib/agent/runtime/error_classifier.dart`

### Phase 8 — CodeMap (optionnel)

**Objectif** : Indexation syntaxique.

1. Créer `lib/agent/context/code_map.dart`
2. Interface abstraite + implémentation Dart
3. Rust FFI uniquement si benchmark le justifie

### Phase 9 — UI Integration

**Objectif** : Étendre l'intégration Flow UI.

1. Connecter AgentEventBus → Activity Feed
2. Étendre les parties personnalisées Flow UI dans l'agent UI
3. Ajouter Subagent Viewer + Verification Viewer
