# 🐼 Panda Agent — Roadmap d'amélioration complète

> **Analyse réalisée le 06/08/2026**
> Sources étudiées : code source Panda IDE (complet), Cline (open-source), Replit Agent (ce document), Cursor, Continue.dev, Aider, OpenHands
> Objectif : transformer Panda Agent en l'agent de code le plus puissant sur mobile

---

## 📊 État actuel de Panda Agent

### Ce qui existe aujourd'hui

| Composante | État | Notes |
|---|---|---|
| Multi-provider AI | ✅ | OpenAI, Claude, Gemini, DeepSeek, Grok, Groq, Mistral, TogetherAI, Perplexity, OpenRouter, FireWorks, Cohere, Cerebras, Copilot, Custom, LLaMA local |
| Tool calling | ✅ | 25 outils définis |
| Streaming + thinking | ✅ | Claude extended thinking, o1/o3 reasoning_content |
| Pending diff tracking | ✅ | Diffs avant application |
| Mémoire de projet | ✅ Basique | Notes statiques dans SharedPrefs |
| Subagents | ⚠️ UI seulement | Onglet Ready/Active/Draft = placeholder, aucune exécution réelle |
| Chat history | ⚠️ Basique | Scroll simple, pas de persistence cross-session |
| Web search | ✅ | DuckDuckGo HTML scraping |
| Web reader | ✅ | HTML parser, extraction de contenu |
| Modes chat | ⚠️ | ask/agent/plan — "plan" = label uniquement, pas de logique dédiée |
| Cancel | ✅ | `http.Client.close()` |
| Confirmations destructives | ✅ | Dialog pour delete/rename |
| Outils enable/disable | ✅ | Par outil via toggle |
| Context window | ❌ | Aucun suivi, aucune troncature automatique |
| Cost tracking | ❌ | Absent |
| Checkpoints | ❌ | Absent |
| Images/vision | ❌ | Absent |
| MCP | ❌ | Absent |
| Browser automation | ❌ | Absent |
| @mentions | ❌ | Absent |
| Auto-approval | ❌ | Absent |
| Task history | ❌ | Absent |
| Export conversation | ❌ | Absent |
| Diagnostics auto-feed | ❌ | Absent |
| .pandarules | ❌ | Absent |
| Code blocks syntaxiques dans chat | ❌ | Markdown rendu mais sans coloration syntaxique |
| Diff viewer complet | ❌ | Texte brut uniquement |

### Outils actuels (25)

```
readFile, writeFile, listFiles, editFile, deleteFile, rename, renamePath,
insertAtLine, replaceAllInFile, readFilesBatch, globSearchFiles, grepInFiles,
gitStatus, gitDiff, gitLog, searchInFiles, getPendingEditsForFile, getFileInfo,
openLinks, searchInWeb, runShellCommand, updateProjectMemory,
activeEditorFile, currentlySelectedText, getLspDiagnostics
```

---

## 🔬 Analyse comparative — Ce que les concurrents ont que Panda n'a pas

### Cline (open-source, référence)
- ✅ **Checkpoint system** : snapshot automatique avant chaque outil write, restauration en 1 clic
- ✅ **Auto-approval rules** : patterns glob pour auto-approuver lecture/écriture/commandes
- ✅ **Context window visuel** : barre de progression tokens, warning à 80%, auto-summarize
- ✅ **MCP (Model Context Protocol)** : plugins tiers (Playwright, GitHub, Slack, DB, etc.)
- ✅ **Browser automation** : screenshot Puppeteer, click, scroll, remplissage formulaire
- ✅ **Image/screenshot passés au modèle** : capture d'écran → vision API
- ✅ **Plan+Act séparé** : phase planning explicite avant exécution, switch en temps réel
- ✅ **@mentions dans l'input** : `@file`, `@folder`, `@problems`, `@url`, `@git`
- ✅ **Task history persistante** : liste toutes les conversations précédentes
- ✅ **Terminal output auto-feed** : la sortie terminal est automatiquement injectée
- ✅ **Conversation export** : JSON et Markdown
- ✅ **Cost tracking** : coût par message, total session, total cumulé
- ✅ **Custom instructions .clinerules** : règles projet, ignorées si absentes
- ✅ **Sliding window context** : résumé automatique quand > 80% context limit
- ✅ **Diff viewer riche** : syntaxe colorée, ligne par ligne, accept/reject par hunk
- ✅ **Model switch mid-conversation** : change le modèle sans perdre l'historique
- ✅ **Multi-diff view** : voir tous les fichiers modifiés en attente simultanément

### Cursor
- ✅ **Inline edits (Cmd+K)** : modification directe dans l'éditeur avec diff inline
- ✅ **Rules for AI** : fichier .cursorrules global + par projet
- ✅ **Background agents** : tâches asynchrones en parallèle
- ✅ **Indexation codebase** : embeddings du projet entier pour RAG
- ✅ **@codebase** : recherche sémantique sur tout le projet
- ✅ **Image drops** : glisser-déposer d'images dans le chat

### Continue.dev
- ✅ **Autocomplete inline** : ghost text dans l'éditeur
- ✅ **Slash commands** : `/edit`, `/explain`, `/fix`, `/tests`, `/commit`
- ✅ **Context providers** : `@file`, `@repo`, `@jira`, `@notion`, etc.
- ✅ **Docs RAG** : indexe la doc d'une bibliothèque en local

### Aider
- ✅ **Architect mode** : un modèle planifie, un autre code
- ✅ **Auto-lint/test loop** : corrige les erreurs de build automatiquement
- ✅ **Voice input** : dictée vocale
- ✅ **Watch mode** : surveille les fichiers et réagit aux TODO

### Replit Agent (moi-même)
- ✅ **Parallel tool calls** : plusieurs outils en même temps
- ✅ **Screenshot app** : capture l'app en live et analyse visuellement
- ✅ **Workflow management** : démarre/arrête les serveurs
- ✅ **Database queries** : exécute du SQL directement
- ✅ **Secrets management** : lit/écrit les secrets de façon sécurisée
- ✅ **Code review subagent** : délègue l'analyse architecturale
- ✅ **Design subagent** : délègue le travail UI/UX
- ✅ **Task planning system** : projets avec tâches persistantes
- ✅ **Deployment integration** : publie l'app directement
- ✅ **Integrations system** : connecte des APIs tierces (Stripe, GitHub, etc.)

---

## 🗺️ ROADMAP — Phases d'implémentation

### Légende priorité
- 🔴 **Critique** — manque fondamental, bloque la compétitivité
- 🟠 **Élevée** — grosse valeur ajoutée, effort raisonnable
- 🟡 **Moyenne** — améliore significativement l'UX
- 🟢 **Nice-to-have** — différenciation long terme

---

## PHASE 1 — Fondations solides de l'agent
> **Durée estimée : 3-4 semaines**
> Objectif : rendre Panda Agent fiable et compétitif sur les fondamentaux

### 1.1 🔴 Context Window Management

**Problème actuel :** L'historique de conversation grossit sans limite. Au-delà de la fenêtre du modèle → erreur silencieuse ou troncature arbitraire.

**Ce qu'il faut :**
- Compteur de tokens estimé (tiktoken-style pour OpenAI, approximation pour les autres)
- Barre de progression visuelle dans le header du chat (ex: `4 200 / 128 000 tokens`)
- Warning visuel quand > 70% de la limite
- **Auto-summarize** : quand > 80%, résumer les N premiers messages en un bloc `[Résumé de contexte]` et les remplacer dans `conversationMessages`
- Badge token count par message (tap pour voir le détail)

**Fichiers impactés :** `agent_runner.dart`, `agent_settings.dart` (header chat)

---

### 1.2 🔴 Task History persistante

**Problème actuel :** Fermer le panneau agent = conversation perdue.

**Ce qu'il faut :**
- Sauvegarder chaque conversation dans `SharedPreferences` avec un ID unique (timestamp)
- Liste de toutes les tâches passées (titre = premier message utilisateur, tronqué à 60 chars)
- Restaurer une conversation complète (messages + toolResults + phase)
- Bouton "Nouvelle conversation" qui archive l'actuelle
- Limite : garder les 50 dernières sessions

**Fichiers impactés :** `agent_settings.dart`, nouveau `lib/utils/agent_history_service.dart`

---

### 1.3 🔴 Plan/Act mode réel

**Problème actuel :** Le chip "Plan" existe dans l'UI mais n'a aucune logique différente.

**Ce qu'il faut :**
- **Plan mode** : le modèle reçoit un system prompt différent, axé sur la planification (pas d'outil write autorisé, seulement read + listFiles + gitStatus). Réponse = liste d'étapes numérotées.
- **Act mode** : tous les outils disponibles, exécution normale
- **Switch Plan→Act** : bouton "▶ Exécuter ce plan" qui convertit le mode et envoie un prompt de continuation
- Indicateur visuel clair dans le header (badge `PLAN` orange vs `ACT` bleu)

**Fichiers impactés :** `agent_runner.dart` (system prompt conditionnel), `agent_settings.dart`

---

### 1.4 🔴 Auto-loop LSP + Build errors

**Problème actuel :** L'agent peut écrire du code cassé et s'arrêter. Il faut relancer manuellement.

**Ce qu'il faut :**
- Après chaque `writeFile`/`editFile`/`replaceAllInFile`, appeler automatiquement `getLspDiagnostics`
- Si des erreurs sont trouvées → injecter dans la prochaine itération : `"LSP errors after your edit: [...]"` → continuer automatiquement
- Optionnel configurable : `autoFixErrors: true/false` dans les settings
- Après `runShellCommand` sur une commande de build → si exit code ≠ 0 → injecter la stderr et continuer

**Fichiers impactés :** `agent_runner.dart` (boucle outil post-write)

---

### 1.5 🟠 .pandarules — Règles projet personnalisées

**Problème actuel :** Aucun mécanisme pour définir des conventions projet que l'agent doit respecter.

**Ce qu'il faut :**
- Lire `.panda/rules.md` (ou `.pandarules`) à la racine du projet au démarrage
- Injecter son contenu dans le system prompt : `"Project rules:\n[contenu]"`
- Si absent → comportement normal, pas d'erreur
- UI dans Settings → onglet "Rules" : éditeur de texte simple pour créer/éditer ce fichier

**Fichiers impactés :** `agent_runner.dart` (`_buildSystemPrompt`), `agent_settings.dart`

---

### 1.6 🟠 Cost Tracking

**Ce qu'il faut :**
- Estimation du coût par message basée sur les prix publics des modèles (tableau statique, mis à jour manuellement)
- Affichage coût session en cours (badge dans le header : `~$0.12`)
- Coût cumulé total dans Settings → Provider card
- Pas de connexion à une API de billing, pure estimation côté client

**Fichiers impactés :** nouveau `lib/utils/agent_cost_tracker.dart`, `agent_settings.dart`

---

### 1.7 🟠 Terminal output → Agent context

**Problème actuel :** Quand l'agent lance `runShellCommand`, il voit stdout/stderr. Mais si l'utilisateur tape dans le terminal manuel → l'agent n'en sait rien.

**Ce qu'il faut :**
- Option "Feed terminal à l'agent" dans Tools : si activé, capture les dernières N lignes du terminal PTY et les ajoute au contexte au prochain envoi
- Outil `getTerminalOutput` : lit les N dernières lignes du PTY actif
- Button "Envoyer ce terminal" dans la barre du terminal réduit

**Fichiers impactés :** `agent_settings.dart`, `agentic_tools.dart`, `terminal_native.dart` (buffer PTY)

---

## PHASE 2 — UX Agent moderne
> **Durée estimée : 2-3 semaines**
> Objectif : interface comparable à Cursor/Cline

### 2.1 🔴 Diff Viewer riche (accept/reject par hunk)

**Problème actuel :** Les diffs en attente sont affichés en texte brut, sans interaction granulaire.

**Ce qu'il faut :**
- Vue diff côte-à-côte ou unifiée avec coloration syntaxique (vert/rouge)
- Pour chaque hunk : boutons "✓ Accepter" / "✗ Rejeter"
- "Tout accepter" / "Tout rejeter" en un clic
- Badge dans l'onglet Tools : nombre de fichiers avec diffs en attente
- Bouton "Voir tous les diffs" → page dédiée listant tous les fichiers modifiés

**Fichiers impactés :** nouveau `lib/ui/agent_diff_viewer.dart`, `agent_settings.dart`

---

### 2.2 🔴 @mentions dans l'input

**Problème actuel :** L'utilisateur ne peut pas cibler précisément un fichier ou un problème.

**Ce qu'il faut :**
- Typer `@` dans l'input chat → dropdown autocomplete
- `@file:<chemin>` → injecte le contenu du fichier dans le contexte
- `@folder:<chemin>` → injecte l'arborescence du dossier
- `@problems` → injecte les diagnostics LSP courants
- `@git` → injecte le diff git actuel
- `@terminal` → injecte la sortie terminal récente
- Chips visuels dans l'input (comme dans Cursor/Continue)

**Fichiers impactés :** `agent_settings.dart` (input field), nouveau `lib/ui/agent_mention_picker.dart`

---

### 2.3 🟠 Code blocks avec syntaxe colorée dans le chat

**Problème actuel :** Le markdown est rendu, mais les blocs de code n'ont pas de coloration syntaxique.

**Ce qu'il faut :**
- Utiliser `re_highlight` (déjà dans pubspec) ou `code_forge` pour colorier les blocs ` ```dart `, ` ```python `, etc.
- Bouton "Copier" sur chaque bloc
- Bouton "Appliquer" sur les blocs qui correspondent à un fichier ouvert (détecté par le chemin en commentaire)
- Icône langage dans le coin du bloc

**Fichiers impactés :** `agent_settings.dart` (`_buildChatMessages`), nouveau widget `AgentCodeBlock`

---

### 2.4 🟠 Image/Screenshot dans le chat

**Problème actuel :** Aucun support vision. Sur mobile, c'est pourtant très naturel (screenshot de l'app, photo d'une maquette).

**Ce qu'il faut :**
- Bouton 📎 dans l'input → `ImagePicker` → encode en base64 → injecte dans le message
- Capture d'écran de l'app (screenshot du terminal/browser intégré) → direct dans le chat
- Support multimodal pour les providers compatibles (OpenAI GPT-4o, Claude 3.5, Gemini 1.5)
- Affichage miniature dans la bulle de message

**Fichiers impactés :** `agent_settings.dart`, `agent_runner.dart` (messages avec `image_url`)

---

### 2.5 🟡 Multi-diff view — Vue d'ensemble des changements

**Ce qu'il faut :**
- Page "Changements en attente" accessible depuis un bouton flottant ou l'onglet Tools
- Liste de tous les fichiers avec diffs en attente (chemin + nb de lignes modifiées)
- Accept/reject global ou par fichier
- Badge numérique sur l'icône Panda Agent dans l'activity bar

**Fichiers impactés :** `agent_settings.dart`, `agentic_tools.dart`

---

### 2.6 🟡 Conversation export

**Ce qu'il faut :**
- Menu "⋮" dans le header chat → "Exporter en Markdown" / "Exporter en JSON"
- Markdown = messages formatés, code blocks, tool results résumés
- JSON = format complet pour réimporter ou analyser
- Partage via `Share` native Android

**Fichiers impactés :** `agent_settings.dart`, nouveau `lib/utils/agent_export_service.dart`

---

### 2.7 🟡 Slash commands

**Ce qu'il faut :**
- Typer `/` dans l'input → dropdown des commandes disponibles
- `/fix` → "Fixe les erreurs LSP dans le fichier actif"
- `/explain` → "Explique le fichier actif"
- `/tests` → "Génère des tests pour le fichier actif"
- `/commit` → "Génère un message de commit pour le diff actuel"
- `/review` → "Code review du diff actuel"
- `/docs` → "Génère la documentation du fichier actif"
- Commandes custom via `.pandarules`

**Fichiers impactés :** `agent_settings.dart` (input + autocomplete), `agent_runner.dart`

---

## PHASE 3 — Outils avancés
> **Durée estimée : 3-4 semaines**
> Objectif : outillage comparable à Cline et Replit Agent

### 3.1 🔴 Checkpoint System

**Problème actuel :** L'agent peut casser du code. Sans checkpoint, le seul recours est git.

**Ce qu'il faut :**
- Avant chaque opération write (writeFile, editFile, deleteFile, rename), snapshot automatique du fichier dans `.panda/checkpoints/<timestamp>/<fichier>`
- UI "Checkpoints" dans l'onglet Tools → liste chronologique
- Restaurer un checkpoint : dialog de confirmation + copie inverse
- Option : checkpoint uniquement sur demande explicite vs automatique
- Nettoyage : garder les 20 derniers checkpoints par fichier

**Fichiers impactés :** `agentic_tools.dart` (wrapper pre-write), nouveau `lib/utils/agent_checkpoint_service.dart`, `agent_settings.dart`

---

### 3.2 🟠 Auto-approval rules

**Problème actuel :** Chaque outil destructif demande une confirmation → friction si l'agent est fiable.

**Ce qu'il faut :**
- Settings → "Auto-approve" : règles configurables
  - Toujours approuver `runShellCommand` si la commande match un pattern (ex: `flutter build *`, `npm install *`)
  - Toujours approuver `writeFile` pour les extensions `.dart`, `.ts`, etc.
  - Toujours approuver `deleteFile` uniquement si dans `.panda/tmp/`
  - Jamais approuver automatiquement (mode sécurisé)
- UI : liste de règles avec add/remove, pattern glob ou regex

**Fichiers impactés :** `agentic_tools.dart` (`_confirmDestructive`), nouveau `lib/utils/agent_approval_rules.dart`, `agent_settings.dart`

---

### 3.3 🟠 Nouveaux outils essentiels

**Outils manquants critiques :**

| Outil | Description |
|---|---|
| `getTerminalOutput` | Lit les N dernières lignes du PTY actif |
| `takeScreenshot` | Screenshot de la WebView ou de l'app courante → base64 |
| `openFile` | Ouvre un fichier dans l'éditeur (navigation) |
| `createDirectory` | Crée un répertoire |
| `copyFile` | Copie un fichier |
| `moveFile` | Déplace (différent de rename cross-dir) |
| `getClipboard` | Lit le presse-papiers |
| `setClipboard` | Écrit dans le presse-papiers |
| `gitCommit` | Commit avec message |
| `gitCheckout` | Checkout d'une branche |
| `gitCreateBranch` | Crée une branche |
| `gitPush` | Push vers origin |
| `findSymbol` | Cherche une classe/fonction via LSP (go-to-definition) |
| `httpRequest` | Appel HTTP externe (tester une API) |
| `readPandaMemory` | Lit explicitement la mémoire projet |
| `appendPandaMemory` | Ajoute à la mémoire sans réécrire |

**Fichiers impactés :** `agentic_tools.dart`, `agentic_tool_catalog.dart`

---

### 3.4 🟠 Mémoire de projet améliorée

**Problème actuel :** `updateProjectMemory` écrase tout à chaque fois. La mémoire est un champ texte libre peu structuré.

**Ce qu'il faut :**
- Mémoire stockée en `.panda/memory.md` (fichier projet, dans git)
- Structure : sections Markdown (`## Décisions`, `## Architecture`, `## Bugs connus`, `## Préférences`)
- Outil `appendPandaMemory(section, content)` → ajoute à une section sans écraser
- Outil `readPandaMemory()` → retourne le contenu formaté
- UI dédiée dans Settings → Mémoire : éditeur Markdown avec preview
- Injection automatique au démarrage de chaque conversation (premier message système)
- Historique de modifications de la mémoire (5 dernières versions)

**Fichiers impactés :** `agentic_tools.dart`, `agent_settings.dart`, `agent_runner.dart`

---

### 3.5 🟡 Subagents réels

**Problème actuel :** L'onglet Subagents est un placeholder visuel. Aucune tâche ne s'exécute.

**Ce qu'il faut :**
- Une tâche = une conversation agent isolée avec son propre historique et ses propres outils
- Exécution en arrière-plan (Dart Isolate ou simple Future avec état sauvegardé)
- Communication inter-agent : l'agent principal peut lancer un sous-agent avec `spawnSubagent(taskDescription)` et lire son résultat avec `getSubagentResult(id)`
- UI : badge animé sur les tâches actives, log en temps réel
- Limite : max 3 sous-agents simultanés

**Fichiers impactés :** `agent_settings.dart` (`_buildSubagentsTab`), `agentic_tools.dart`, nouveau `lib/utils/subagent_runner.dart`

---

### 3.6 🟡 Voice input

**Ce qu'il faut :**
- Bouton microphone dans l'input agent → enregistrement vocal → transcription via `speech_to_text` package (on-device sur Android, pas de cloud)
- Fallback : envoi à Whisper API si on-device indisponible
- Annulation par double-tap

**Fichiers impactés :** `agent_settings.dart` (input bar), nouveau `lib/utils/agent_voice_input.dart`

---

## PHASE 4 — MCP & Intégrations externes
> **Durée estimée : 4-5 semaines**
> Objectif : écosystème de plugins, différenciation forte

### 4.1 🟠 MCP (Model Context Protocol) — support basique

**Ce qu'il faut :**
- Support des serveurs MCP via HTTP/SSE (protocole JSON-RPC standardisé par Anthropic)
- Registre de serveurs MCP configurables par l'utilisateur (URL + headers d'auth)
- Discovery automatique des tools exposés par un serveur MCP
- Injection des tools MCP dans le tool catalog de l'agent
- Exemples de serveurs MCP compatibles : Playwright (browser), GitHub, Filesystem distant, PostgreSQL, Slack
- UI : Settings → "MCP Servers" → add/remove serveurs + toggle des outils

**Fichiers impactés :** nouveau `lib/mcp/mcp_client.dart`, `lib/mcp/mcp_registry.dart`, `agentic_tool_catalog.dart`, `agent_settings.dart`

---

### 4.2 🟡 Codebase Indexing (RAG local)

**Ce qu'il faut :**
- Index des embeddings du projet stocké localement (`.panda/index/`)
- Modèle d'embedding léger (nomic-embed-text ou all-MiniLM via llama.cpp)
- Outil `semanticSearch(query)` → retourne les N extraits de code les plus pertinents
- `@codebase` mention → recherche sémantique avant de répondre
- Mise à jour incrémentale de l'index (sur save de fichier)
- UI : Settings → "Indexation" → progress bar, taille index, re-indexer

**Fichiers impactés :** nouveau `lib/indexing/`, `agentic_tools.dart`

---

### 4.3 🟡 Architect mode (double modèle)

**Ce qu'il faut :**
- Inspiré d'Aider : un modèle "architecte" (fort, ex: Claude Sonnet) planifie, un modèle "worker" (rapide, ex: DeepSeek V3) implémente
- L'architecte génère un plan structuré en JSON : `[{file, action, description}]`
- Le worker reçoit chaque étape une par une et l'implémente
- L'architecte valide le résultat du worker après chaque étape
- UI : Settings → "Mode Architect" → sélection des deux modèles

**Fichiers impactés :** `agent_runner.dart`, `agent_settings.dart`

---

## PHASE 5 — UI Redesign Agent
> **Durée estimée : 2-3 semaines**
> Objectif : interface fluide, moderne, pensée mobile

### 5.1 🔴 Panel agent redimensionnable / modes d'affichage

**Problème actuel :** L'agent occupe une colonne fixe à droite. Sur mobile → trop étroit ou trop grand.

**Ce qu'il faut :**
- Mode **Drawer** (actuel) : slide depuis la droite
- Mode **Split** : panel côte à côte avec l'éditeur, hauteur libre
- Mode **Fullscreen** : occuper tout l'écran (idéal pour une longue tâche)
- Mode **Floating** : mini bulle draggable sur l'écran (tap pour agrandir)
- Switch entre modes via bouton dans le header agent
- Persistance du mode choisi

**Fichiers impactés :** `home.dart`, `agent_settings.dart`

---

### 5.2 🟠 Chat input amélioré

**Ce qu'il faut :**
- Input multi-ligne avec auto-expand (jusqu'à 8 lignes, puis scroll)
- `@` → picker contextuel de fichiers/mentions (voir 2.2)
- `/` → autocomplete des slash commands
- Drag & drop d'images et de fichiers
- Bouton 📎 → menu : Image, Fichier, Screenshot, Terminal output
- Indicateur "En cours de génération…" avec animation dans l'input (pas seulement dans les bulles)
- Historique des inputs (↑/↓ pour naviguer les messages précédents)
- Count de tokens en temps réel sur l'input actuel

**Fichiers impactés :** `agent_settings.dart` (input field widget)

---

### 5.3 🟠 Bulles de messages redesignées

**Ce qu'il faut :**
- Messages utilisateur : bulle arrondie à droite, couleur accent
- Messages agent : fond légèrement différent, icône Panda à gauche
- Code blocks : fond sombre avec syntaxe colorée, bouton copie, bouton "Apply to [fichier]"
- Tool calls : carte compacte expandable avec icône outil, nom, args résumés, résultat
- Thinking/reasoning : bloc collapsible avec icône "cerveau", fond différent
- Timestamps discrets sur chaque bulle
- Long press → menu contextuel (copier, citer, signaler)
- Smooth scroll avec animation lors d'un nouveau message

**Fichiers impactés :** `agent_settings.dart` (`_buildChatMessages`), nouveaux widgets `AgentBubble`, `AgentToolCard`, `AgentThinkingBlock`

---

### 5.4 🟡 Indicateur d'activité et statut agent

**Ce qu'il faut :**
- Badge sur l'icône Panda dans l'activity bar : point vert = actif, orange = attend confirmation, rouge = erreur
- Dans le chat header : `[ modèle ] [ 4 200 tokens ] [ ~$0.03 ]`
- Animation de loading distinguant "thinking", "calling tool", "generating text"
- Toast non-intrusif quand un outil s'exécute en arrière-plan

**Fichiers impactés :** `home.dart` (activity bar), `agent_settings.dart` (header)

---

### 5.5 🟡 Quick actions flottantes

**Ce qu'il faut :**
- Quand du texte est sélectionné dans l'éditeur → petit FAB apparaît : "Expliquer", "Améliorer", "Fixer", "Documenter", "Tests"
- L'action ouvre l'agent avec le texte sélectionné pré-injecté + le prompt approprié
- Inspiré de Cursor inline edit (adapté touch)

**Fichiers impactés :** `editor_page.dart`, `home.dart`

---

## PHASE 6 — Provider & modèles avancés
> **Durée estimée : 1-2 semaines**
> Objectif : couverture provider maximale, local AI optimisé

### 6.1 🟠 Model switch mid-conversation

**Ce qu'il faut :**
- Dropdown de sélection du modèle directement dans le header du chat (pas seulement dans Settings)
- Changer de modèle sans perdre l'historique
- Le nouveau modèle reçoit l'historique complet à sa prochaine requête
- Indicateur visuel quand le modèle change dans le fil de conversation

**Fichiers impactés :** `agent_settings.dart`

---

### 6.2 🟠 LLaMA local — amélioration de l'intégration

**Problème actuel :** LLaMA local fonctionne mais sans tool calling natif ni streaming fin.

**Ce qu'il faut :**
- Support du format de tool calling `<tool_call>` pour les modèles qui le supportent (Qwen2.5-Coder, Llama-3.2)
- Streaming token-by-token (actuellement en batch ?)
- Preset de paramètres par modèle (temperature, top_p, context_length optimaux)
- Indicateur de vitesse tokens/s dans le chat
- Support du function calling via grammar (llama.cpp GBNF)

**Fichiers impactés :** `llama_wrapper_native.dart`, `agent_runner.dart`

---

### 6.3 🟡 Ollama support

**Ce qu'il faut :**
- Provider "Ollama" dans la liste : URL configurable (défaut : `http://localhost:11434`)
- Discovery automatique des modèles installés via `GET /api/tags`
- Compatible avec les modèles OpenAI-compat d'Ollama
- Utile pour connexion SSH vers un serveur home

**Fichiers impactés :** `ai.dart`, `agent_settings.dart`

---

## PHASE 7 — Qualité & sécurité
> **Durée estimée : continu**

### 7.1 🔴 Sécurité du tool calling

**Problème actuel :** `runShellCommand` peut exécuter n'importe quoi. Sur mobile, les risques sont moindres mais pas nuls.

**Ce qu'il faut :**
- Sandboxing de `runShellCommand` : liste noire de commandes dangereuses (`rm -rf /`, `chmod 777 /`, etc.)
- Timeout configurable par commande (défaut : 30s)
- Limite de taille stdout/stderr (défaut : 50KB, troncature avec `[TRUNCATED]`)
- Rate limiting : max N runShellCommand par minute
- Log de tous les outils exécutés dans `.panda/agent_log.jsonl`

**Fichiers impactés :** `agentic_tools.dart`

---

### 7.2 🟠 Tests de l'agent

**Ce qu'il faut :**
- Suite de tests pour chaque outil (mock filesystem, mock http)
- Test de régression : donner une tâche simple → vérifier les outils appelés
- CI : `flutter test` sur les utils de l'agent

**Fichiers impactés :** nouveau `test/agent/`

---

### 7.3 🟡 Telemetry opt-in

**Ce qu'il faut :**
- Opt-in explicite (désactivé par défaut)
- Collecter : nb de messages, outils utilisés (anonymisés), erreurs agent, providers utilisés
- Envoyer vers Argos (la plateforme observabilité maison)
- Dashboard d'utilisation dans l'app pour l'utilisateur lui-même

**Fichiers impactés :** `agent_runner.dart`, nouveau `lib/utils/agent_telemetry.dart`

---

## 📋 Récapitulatif des questions à te poser

Avant d'implémenter, j'ai besoin de tes réponses sur ces points :

1. **Checkpoints** : stocker dans le projet (`.panda/checkpoints/`, dans git) ou dans la mémoire interne Android (hors git) ?

2. **Task History** : cross-projet (même liste globale peu importe le dossier ouvert) ou par projet ?

3. **Plan mode** : dois-tu pouvoir éditer le plan avant de l'exécuter, ou l'exécution est immédiate après approbation ?

4. **MCP** : as-tu des serveurs MCP déjà configurés ou c'est pour plus tard ?

5. **Voice input** : on-device uniquement (pas de clé API externe) ou Whisper API acceptable ?

6. **Diff viewer** : style GitHub (unifié) ou style IntelliJ (côte-à-côte split) ?

7. **UI Agent** : continuer avec le drawer latéral ou passer fullscreen (style ChatGPT app) comme mode par défaut ?

8. **LLaMA tool calling** : tu utilises déjà des modèles avec function calling natif ? Lesquels ?

9. **Codebase indexing** : acceptable que l'index prenne 200-500MB sur un grand projet ?

10. **Architect mode** : feature souhaitée immédiatement ou phase ultérieure ?

---

## 🔢 Ordre d'implémentation recommandé (vote par impact/effort)

```
Phase 1 → Phase 2 (diff + @mentions) → Phase 3 (checkpoints + outils) → Phase 5 (UI) → Phase 6 → Phase 4
```

| Priorité | Feature | Impact | Effort |
|---|---|---|---|
| 1 | Context window management | ⭐⭐⭐⭐⭐ | 🔨🔨 |
| 2 | Task history persistante | ⭐⭐⭐⭐⭐ | 🔨🔨 |
| 3 | Plan/Act mode réel | ⭐⭐⭐⭐ | 🔨 |
| 4 | Auto-loop LSP+build | ⭐⭐⭐⭐ | 🔨🔨 |
| 5 | .pandarules | ⭐⭐⭐⭐ | 🔨 |
| 6 | Diff viewer riche | ⭐⭐⭐⭐ | 🔨🔨🔨 |
| 7 | @mentions | ⭐⭐⭐⭐ | 🔨🔨 |
| 8 | Code blocks syntaxiques | ⭐⭐⭐ | 🔨 |
| 9 | Checkpoint system | ⭐⭐⭐⭐⭐ | 🔨🔨🔨 |
| 10 | Auto-approval rules | ⭐⭐⭐ | 🔨🔨 |
| 11 | Nouveaux outils git+http | ⭐⭐⭐⭐ | 🔨🔨 |
| 12 | Mémoire améliorée | ⭐⭐⭐ | 🔨🔨 |
| 13 | Cost tracking | ⭐⭐⭐ | 🔨 |
| 14 | Terminal output feed | ⭐⭐⭐ | 🔨🔨 |
| 15 | Slash commands | ⭐⭐⭐ | 🔨🔨 |
| 16 | Images/vision | ⭐⭐⭐ | 🔨🔨 |
| 17 | Voice input | ⭐⭐ | 🔨🔨🔨 |
| 18 | Model switch mid-chat | ⭐⭐⭐ | 🔨 |
| 19 | Panel redimensionnable | ⭐⭐⭐ | 🔨🔨🔨 |
| 20 | Quick actions éditeur | ⭐⭐⭐ | 🔨🔨 |
| 21 | Subagents réels | ⭐⭐⭐⭐ | 🔨🔨🔨🔨 |
| 22 | Conversation export | ⭐⭐ | 🔨 |
| 23 | Ollama support | ⭐⭐⭐ | 🔨 |
| 24 | LLaMA tool calling | ⭐⭐⭐ | 🔨🔨🔨 |
| 25 | MCP support | ⭐⭐⭐⭐⭐ | 🔨🔨🔨🔨 |
| 26 | Codebase indexing | ⭐⭐⭐⭐ | 🔨🔨🔨🔨🔨 |
| 27 | Architect mode | ⭐⭐⭐ | 🔨🔨🔨 |

**Légende :** ⭐ = impact utilisateur | 🔨 = effort développement

---

## 📁 Fichiers de référence dans ce repo

| Fichier | Rôle |
|---|---|
| `lib/ui/agent_runner.dart` | Moteur de streaming agent (1131 lignes) |
| `lib/ui/agent_settings.dart` | UI principale agent — Chat/Tools/Subagents (2325 lignes) |
| `lib/utils/agentic_tools.dart` | 25 outils agent (2726 lignes) |
| `lib/utils/agentic_tool_catalog.dart` | Specs + filtrage des outils |
| `lib/utils/ai.dart` | Providers, tool calling, streaming |
| `lib/utils/copilot_chat.dart` | Intégration GitHub Copilot |
| `lib/utils/panda_log.dart` | Logging |
| `.agents/memory/` | Mémoire de session précédentes |
| `.dev/plan.md` | Plan VSCode Extension Host |
| `PLAN_LOCAL_AI_MARKETPLACE.md` | Plan Local AI Marketplace |
| `argos-unified-platform-plan.md` | Plan plateforme observabilité |

---

*Roadmap généré par analyse comparative Panda IDE vs Cline/Cursor/Continue.dev/Aider/Replit Agent.*
*Prêt pour implémentation dès validation des questions ci-dessus.*
