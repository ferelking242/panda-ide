# 🏗️ Architecture Analysis: Coding Agent Systems

## For Panda Agent — Reference Architecture Study

Analyse des meilleurs systèmes d'agents de coding open-source pour améliorer Panda Agent.

---

## 📊 Table of Contents

1. [Freebuff/Codebuff](#1-freebuffcodebuff) — Le framework multi-agent
2. [OpenHands](#2-openhands) — L'agent runtime complet
3. [Comparaison avec Panda Agent](#3-comparaison-avec-panda-agent)
4. [8 Composants Clés Identifiés](#4-8-composants-clés)
5. [Recommandations pour Panda Agent](#5-recommandations)

---

## 1. Freebuff/Codebuff

**Repo** : `github.com/CodebuffAI/freebuff`
**Stack** : TypeScript, Bun, OpenTUI + React CLI
**Philosophie** : Agents spécialisés + orchestration + contexte projet

### Architecture Fichier par Fichier

```
freebuff/
├── agents/                          # Définitions des agents (le cœur)
│   ├── base-chat.ts                 # Agent chat généraliste
│   ├── base3.ts                     # Agent coding principal (Buffy)
│   ├── base3-lite.ts                # Agent coding léger
│   ├── thinker.ts                   # Agent réflexion (raisonnement)
│   ├── researcher/                  # Agent recherche web
│   ├── reviewer/                    # Agent review de code
│   ├── librarian/                   # Agent gestion bibliothèques
│   ├── editor/                      # Agent édition fichiers
│   ├── file-explorer/               # Agent exploration fichiers
│   ├── general-agent/               # Agent généraliste
│   ├── browser-use/                 # Agent navigation web
│   ├── context-pruner.ts            # Élagage automatique du contexte
│   └── types/
│       ├── agent-definition.ts      # Type AgentDefinition (publique)
│       └── secret-agent-definition.ts # Type SecretAgentDefinition (interne)
│
├── packages/
│   ├── agent-runtime/               # Le moteur d'exécution
│   │   ├── src/
│   │   │   ├── run-agent-step.ts    # Boucle principale: 1 step = 1 appel LLM
│   │   │   ├── main-prompt.ts       # Point d'entrée principal
│   │   │   ├── compact-history.ts   # Compaction de l'historique
│   │   │   ├── system-prompt/       # Construction du prompt système
│   │   │   │   ├── prompts.ts       # Prompt principal + knowledge files
│   │   │   │   └── truncate-file-tree.ts
│   │   │   ├── tools/               # Système d'outils
│   │   │   │   ├── tool-executor.ts # Exécution des tool calls
│   │   │   │   ├── stream-parser.ts # Parse le stream LLM → tool calls
│   │   │   │   ├── prompts.ts       # Génération des tool schemas
│   │   │   │   └── handlers/        # Handlers par tool
│   │   │   ├── templates/           # Templates d'agents
│   │   │   │   └── agent-registry.ts
│   │   │   └── util/                # Utilitaires (tokens, cache, etc.)
│   │   │
│   ├── code-map/                    # Indexation du code source
│   │   ├── src/
│   │   │   ├── parse.ts             # Parsing AST (tree-sitter)
│   │   │   ├── languages.ts         # Support multi-langages
│   │   │   └── tree-sitter-queries/ # Queries par langage
│   │   └── types.ts
│   │
│   └── llm-providers/               # Fournisseurs LLM
│       └── src/openai-compatible/   # Client OpenAI-compatible
│
├── common/                          # Types, tools, schemas partagés
│   └── src/
│       ├── tools/
│       │   ├── list.ts              # Liste de TOUS les outils disponibles
│       │   ├── constants.ts         # Noms des tools
│       │   ├── params/              # Paramètres par tool
│       │   └── compile-tool-definitions.ts
│       ├── types/
│       │   ├── session-state.ts     # État de session (AgentTemplateType, etc.)
│       │   └── messages/            # Types de messages
│       └── util/                    # Utilitaires partagés
│
├── cli/                             # Client TUI (terminal)
├── sdk/                             # SDK JS/TS
└── freebuff/                        # CLI Freebuff + e2e tests
```

### Agent Loop (comment ça marche)

```typescript
// Simplifié depuis run-agent-step.ts
async function* loopAgentSteps(params) {
  while (true) {
    // 1. Compacter l'historique si trop long
    await maybeCompactHistory(messages, tokenBudget);
    
    // 2. Construire le prompt système (avec contexte projet)
    const systemPrompt = buildSystemPrompt({
      projectRoot, fileTree, knowledgeFiles, toolsPrompt, currentStep,
    });
    
    // 3. Appeler le LLM avec les tools
    const stream = await promptAiSdk({ model, messages, tools, system: systemPrompt });
    
    // 4. Parser le stream → tool calls
    const result = await processStream(stream);
    
    // 5. Exécuter les tool calls
    for (const toolCall of result.toolCalls) {
      const output = await executeToolCall(toolCall);
      messages.push(toolMessage(output));
    }
    
    // 6. Si pas de tool call → on a la réponse finale
    if (result.finished) break;
  }
}
```

### Outils Disponibles (Codebuff)

| Tool | Description |
|------|-------------|
| `read_files` | Lire un ou plusieurs fichiers |
| `write_file` | Créer/écraser un fichier |
| `str_replace` | Remplacement de chaîne dans un fichier |
| `run_terminal_command` | Exécuter une commande shell |
| `code_search` | Recherche dans le code (ripgrep) |
| `glob` | Recherche par pattern de fichiers |
| `list_directory` | Lister le contenu d'un dossier |
| `write_todos` | Planifier des tâches |

### Sub-Agents (spécialisés)

| Agent | Rôle |
|-------|------|
| `base3` (Buffy) | Agent coding principal |
| `thinker` | Réflexion approfondie (reasoning) |
| `researcher-web` | Recherche sur internet |
| `reviewer` | Review de code |
| `librarian` | Gestion des dépendances |
| `context-pruner` | Élagage du contexte (auto) |
| `editor` | Édition de fichiers |
| `file-explorer` | Exploration de l'arborescence |

### Points Forts

- ✅ **Agents spécialisés** : chaque tâche a son agent expert
- ✅ **Contexte projet** : file tree + knowledge files + git changes
- ✅ **Compaction automatique** : l'historique est compressé quand trop long
- ✅ **Tool streaming** : parse le stream LLM en temps réel
- ✅ **Code map** : indexation AST pour compréhension du code
- ✅ **Knowledge files** : mémoire persistante par dossier (AGENTS.md)
- ✅ **Sub-agents** : spawn d'agents spécialisés en parallèle
- ✅ **Retry/résilience** : auto-recovery sur erreurs réseau

---

## 2. OpenHands

**Repo** : `github.com/All-Hands-AI/OpenHands`
**Stack** : Python SDK + TypeScript Frontend
**Philosophie** : Agent runtime complet avec sandbox

### Architecture Multi-Repo

```
OpenHands (4 repos)
├── OpenHands/OpenHands          # Frontend React/TypeScript
├── OpenHands/software-agent-sdk # Python SDK + Agent Server
├── OpenHands/typescript-client  # Client TS généré
└── OpenHands/extensions         # Skills & automations
```

### Agent Runtime (Python)

```
software-agent-sdk/
├── openhands/
│   ├── agent/
│   │   ├── controller/          # Boucle agent principale
│   │   ├── lyr/                 # Layer system (middleware)
│   │   └── task.py              # Tâche de l'agent
│   ├── runtime/
│   │   ├── docker/              # Sandbox Docker
│   │   ├── local/               # Exécution locale
│   │   └── e2b/                 # Sandbox E2B
│   ├── events/
│   │   ├── action/              # Actions de l'agent
│   │   └── observation/         # Résultats des actions
│   ├── controller/
│   │   └── agent_controller.py  # Contrôleur principal
│   └── security/
│       └── sanitize.py          # Sécurité des commandes
```

### Points Forts

- ✅ **Sandbox isolé** : Docker/E2B pour exécution sécurisée
- ✅ **Event-driven** : architecture en events (Action → Observation)
- ✅ **Multi-runtime** : Docker, local, E2B
- ✅ **Skills/extensions** : système de plugins
- ✅ **Browser tools** : navigation web intégrée
- ✅ **Workspace management** : gestion de l'espace de travail

---

## 3. Comparaison avec Panda Agent

### Ce que Panda Agent a déjà ✅

| Composant | Panda Agent | Codebuff | OpenHands |
|-----------|-------------|----------|-----------|
| **Agent loop** | ✅ `AgentRunner._run()` | ✅ `loopAgentSteps()` | ✅ `AgentController` |
| **Tool calling** | ✅ `AgenticTools` + `runShellCommand` | ✅ Tool handlers | ✅ Actions/Observations |
| **read_file** | ✅ `readFile` | ✅ `read_files` | ✅ `ReadAction` |
| **write_file** | ✅ `writeFile` | ✅ `write_file` | ✅ `WriteAction` |
| **edit_file** | ✅ `editFile` + `replaceAllInFile` | ✅ `str_replace` | ✅ `EditAction` |
| **terminal** | ✅ `runShellCommand` | ✅ `run_terminal_command` | ✅ `RunAction` |
| **search** | ✅ `searchInFiles` + `grepInFiles` | ✅ `code_search` | ✅ `SearchAction` |
| **list_files** | ✅ `listFiles` + `globSearchFiles` | ✅ `glob` + `list_directory` | ✅ `ListAction` |
| **System prompt** | ✅ `_buildSystemPrompt()` | ✅ `system-prompt/prompts.ts` | ✅ System prompt |
| **Historique** | ✅ `_agentMessages` | ✅ Messages array | ✅ Event history |
| **Modes** | ✅ Agent/Ask/Plan | ❌ | ❌ |
| **Mémoire projet** | ✅ `.panda/memory.md` | ✅ `AGENTS.md` knowledge files | ❌ |
| **UI activity feed** | ✅ `AgentActivityController` | ✅ Print mode events | ✅ Event stream |

### Ce qui MANQUE à Panda Agent ❌

| Composant | Panda Agent | Codebuff | OpenHands | Impact |
|-----------|-------------|----------|-----------|--------|
| **Sub-agents** | ❌ **Rien** | ✅ 8+ agents spécialisés | ✅ Layers/middleware | 🔴 CRITIQUE |
| **Context pruning** | ❌ Seulement >40k tokens | ✅ `context-pruner.ts` auto | ✅ Auto | 🔴 Important |
| **Code map / AST** | ❌ **Rien** | ✅ `code-map` (tree-sitter) | ❌ | 🟡 Important |
| **Knowledge files** | ⚠️ `.panda/memory.md` (basique) | ✅ Multi-niveaux + auto-update | ❌ | 🟡 Utile |
| **Tool streaming** | ❌ Attend fin de réponse | ✅ Parse en temps réel | ✅ Event stream | 🟡 UX |
| **Retry/résilience** | ❌ **Rien** | ✅ Auto-recovery 3x | ✅ | 🔴 Important |
| **History compaction** | ⚠️ Simple (>40k tokens) | ✅ Intelligent par budget | ✅ | 🟡 Utile |
| **Plan mode** | ✅ (basique) | ❌ | ❌ | ✅ Point fort Panda |
| **Approval mode** | ✅ | ❌ (auto) | ❌ | ✅ Point fort Panda |
| **Mobile-first** | ✅ | ❌ (desktop) | ❌ | ✅ Point fort Panda |

---

## 4. Les 8 Composants Clés

```
Agent
 ├── 1. Context / Codebase indexing
 ├── 2. Planner
 ├── 3. Tool registry
 │    ├── read_file
 │    ├── write_file
 │    ├── edit_file
 │    ├── terminal
 │    └── search
 ├── 4. Agent loop
 ├── 5. State / History
 ├── 6. Subagents
 ├── 7. Sandbox / Execution
 └── 8. Review / Verification
```

### Détail par composant

#### 1. Context / Codebase Indexing
| Système | Implémentation |
|---------|----------------|
| **Codebuff** | `code-map` (tree-sitter AST) + file tree + knowledge files + git changes |
| **OpenHands** | Workspace scanning + file reading |
| **Panda Agent** | `_buildSystemPrompt()` envoie le file tree (25 entrées max) |

**Manque Panda Agent** : Pas d'indexation AST, pas de compréhension structurelle du code.

#### 2. Planner
| Système | Implémentation |
|---------|----------------|
| **Codebuff** | `write_todos` tool + sub-agent `thinker` |
| **OpenHands** | Task decomposition dans le controller |
| **Panda Agent** | Mode Plan dédié (excellent !) + `write_todos` |

**Point fort Panda Agent** : Le mode Plan est un vrai avantage.

#### 3. Tool Registry
| Système | Nb tools | Tools |
|---------|----------|-------|
| **Codebuff** | 8+ | read_files, write_file, str_replace, run_terminal_command, code_search, glob, list_directory, write_todos |
| **OpenHands** | 10+ | Read, Write, Edit, Run, Search, List, Browse, Think, Finish, Delegate |
| **Panda Agent** | 12+ | readFile, writeFile, editFile, runShellCommand, searchInFiles, grepInFiles, listFiles, globSearchFiles, readFilesBatch, insertAtLine, replaceAllInFile, activeEditorFile, getTerminalOutput, getLspDiagnostics |

**Point fort Panda Agent** : Le plus riche en outils ! Mais pas de `spawn_agents`.

#### 4. Agent Loop
| Système | Architecture |
|---------|-------------|
| **Codebuff** | Generator function `handleSteps()` + `loopAgentSteps()` |
| **OpenHands** | `AgentController` event-driven |
| **Panda Agent** | `AgentRunner._run()` avec `StreamSubscription` |

**Manque Panda Agent** : Pas de retry automatique, pas de streaming tool parse.

#### 5. State / History
| Système | Implémentation |
|---------|----------------|
| **Codebuff** | `SessionState` + `AgentTemplateType` + compact history |
| **OpenHands** | Event history + session persistence |
| **Panda Agent** | `_agentMessages` (List<Map>) + SharedPreferences |

**Manque Panda Agent** : Pas de compaction intelligente, pas de persistence serveur.

#### 6. Subagents ⭐
| Système | Implémentation |
|---------|----------------|
| **Codebuff** | `spawn_agents` tool + 8+ agents spécialisés |
| **OpenHands** | Layer system (middleware) + delegation |
| **Panda Agent** | ❌ **RIEN** — tout passe par un seul agent |

**C'est LE gap principal.** Codebuff utilise des agents spécialisés :
- `thinker` pour le raisonnement
- `researcher-web` pour la recherche
- `reviewer` pour la review
- `librarian` pour les dépendances
- `context-pruner` pour l'élagage

#### 7. Sandbox / Execution
| Système | Implémentation |
|---------|----------------|
| **Codebuff** | Terminal PTY natif |
| **OpenHands** | Docker/E2B sandbox isolé |
| **Panda Agent** | Terminal PTY (flutter_pty) |

**Manque Panda Agent** : Pas de sandbox isolé (mais acceptable pour mobile).

#### 8. Review / Verification
| Système | Implémentation |
|---------|----------------|
| **Codebuff** | Sub-agent `reviewer` + build verification |
| **OpenHands** | Test execution + verification |
| **Panda Agent** | ❌ Pas de review automatique |

**Manque Panda Agent** : Pas de vérification post-modification.

---

## 5. Recommandations pour Panda Agent

### Priorité 1 — CRITIQUE (impact immédiat)

#### 1.1 Ajouter `spawn_agents` (sub-agents)
```dart
// Nouvel outil à ajouter à AgentRunner
'spawn_agents': SpawnAgentsTool(
  availableAgents: [
    'thinker',      // Raisonnement approfondi
    'researcher',   // Recherche web
    'reviewer',     // Review de code
    'librarian',    // Dépendances
  ],
),
```

**Pourquoi** : C'est le gap le plus critique. Un seul agent ne peut pas être expert en tout. Les sub-agents permettent de spécialiser.

#### 1.2 Ajouter retry/résilience
```dart
// Dans AgentRunner._run()
const maxRetries = 3;
for (int attempt = 0; attempt < maxRetries; attempt++) {
  try {
    return await _executeStep(messages, tools);
  } catch (e) {
    if (attempt == maxRetries - 1) rethrow;
    await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
  }
}
```

**Pourquoi** : Les erreurs réseau sur mobile sont fréquentes. Sans retry, l'agent plante.

#### 1.3 Améliorer la compaction de l'historique
```dart
// Au lieu de: if (tokens > 40000) compress()
// Faire: compaction par budget proportionnel au modèle
int tokenBudget = model.contextWindow * 0.4; // 40% du window
if (_estimateTokens(_agentMessages) > tokenBudget) {
  await _compressOldMessages(model);
}
```

**Pourquoi** : La compaction actuelle est trop basique. Codebuff compactionne intelligemment par budget.

### Priorité 2 — IMPORTANT

#### 2.1 Ajouter Context Pruning automatique
```dart
// Nouveau sub-agent: context-pruner
final prunedContext = await ContextPruner.prune(
  messages: messages,
  fileTree: fileTree,
  currentFocus: currentFile,
  tokenBudget: tokenBudget,
);
```

#### 2.2 Ajouter Knowledge Files (multi-niveaux)
```
.panda/
├── memory.md           # Mémoire globale (existe déjà)
├── AGENTS.md           # Connaissances agent (nouveau)
└── docs/
    └── knowledge.md    # Connaissances par dossier (nouveau)
```

#### 2.3 Ajouter Tool Streaming
```dart
// Parser le stream en temps réel
stream.listen((chunk) {
  if (isToolCall(chunk)) {
    executeToolCall(chunk); // Exécuter immédiatement
  }
});
```

### Priorité 3 — BONUS

#### 3.1 Code Map (AST indexing)
#### 3.2 Review Agent automatique

---

## 📐 Architecture Cible Panda Agent

```
Panda Agent (amélioré)
├── Core
│   ├── AgentRunner.ts              # Boucle principale (existe)
│   │   └── + retry + resilience
│   └── ContextPruner.ts           # NOUVEAU: élagage contexte
│
├── Agents (spécialisés)
│   ├── base-agent.ts               # Agent principal (existe)
│   ├── thinker-agent.ts            # NOUVEAU: raisonnement
│   ├── researcher-agent.ts         # NOUVEAU: recherche web
│   ├── reviewer-agent.ts           # NOUVEAU: review code
│   └── librarian-agent.ts          # NOUVEAU: dépendances
│
├── Tools
│   ├── file-tools.ts               # read, write, edit (existe)
│   ├── terminal-tool.ts            # shell command (existe)
│   ├── search-tools.ts             # grep, glob (existe)
│   ├── spawn-agents-tool.ts        # NOUVEAU: spawn sub-agents
│   └── context-tools.ts            # NOUVEAU: code map, AST
│
├── Context
│   ├── file-tree.ts                # Arborescence (existe)
│   ├── knowledge-files.ts          # NOUVEAU: AGENTS.md multi-niveaux
│   ├── git-changes.ts              # NOUVEAU: diffs git
│   └── code-map.ts                 # NOUVEAU: indexation AST
│
├── State
│   ├── session-state.ts            # État session (existe)
│   ├── history-compaction.ts       # + intelligent
│   └── memory-persistence.ts       # NOUVEAU: persistence serveur
│
└── UI
    ├── agent-panel.tsx             # Panel agent (existe)
    ├── activity-feed.tsx           # Feed activités (existe)
    ├── plan-viewer.tsx             # Vue plan (existe)
    └── tool-stream-viewer.tsx      # NOUVEAU: stream temps réel
```

---

## 🎯 Résumé Exécutif

| Action | Priorité | Effort | Impact |
|--------|----------|--------|--------|
| Ajouter `spawn_agents` (sub-agents) | 🔴 P1 | Moyen | 🔴 Énorme |
| Ajouter retry/résilience | 🔴 P1 | Faible | 🔴 Énorme |
| Améliorer compaction historique | 🔴 P1 | Faible | 🟡 Important |
| Ajouter context pruning auto | 🟡 P2 | Moyen | 🟡 Important |
| Ajouter knowledge files multi-niveaux | 🟡 P2 | Faible | 🟡 Utile |
| Ajouter tool streaming | 🟡 P2 | Moyen | 🟡 UX |
| Ajouter code map (AST) | 🟢 P3 | Fort | 🟡 Qualité |
| Ajouter review agent | 🟢 P3 | Moyen | 🟡 Qualité |

**Le gap le plus critique est l'absence de sub-agents.** Codebuff utilise 8+ agents spécialisés. Panda Agent fait tout avec un seul agent. C'est comme demander à un seul développeur d'être expert en tout — ça ne marche pas.

**La seconde priorité est la résilience.** Sans retry, sans compaction intelligente, sans context pruning, l'agent plante dès que le contexte dépasse un certain taille ou qu'il y a une erreur réseau.

---

*Analyse réalisée le 27 août 2026*
*Sources : Freebuff/Codebuff (github.com/CodebuffAI/freebuff), OpenHands (github.com/All-Hands-AI/OpenHands)*
