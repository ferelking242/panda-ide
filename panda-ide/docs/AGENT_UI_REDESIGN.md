# 🎨 Panda Agent — UI Redesign Spec
> Style inspiré : Replit Agent + GitHub Copilot Chat
> Analysé depuis : screenshots 23:37-23:39 du 06/08/2026
> Statut : SPEC — ne pas coder avant validation

---

## 1. Principes directeurs (depuis les screenshots)

| Principe | Replit Agent (observé) | Panda Agent actuel | Cible |
|---|---|---|---|
| Avatar utilisateur | ❌ Aucun | ❌ Aucun | ❌ Aucun |
| Avatar agent | ❌ Aucun | ❌ Aucun | ❌ Aucun |
| Message utilisateur | Bulle bleue, droite | Bulle simple | Bulle bleue, droite, multi-para |
| Message agent | Texte brut, gauche, pas de fond | Markdown rendu, léger fond | Texte brut, gauche, NO fond |
| Actions | Groupes collapsibles avec icône | Cards individuelles fixes | Groupes collapsibles, count |
| Timing | "Worked for Xs" par groupe | Absent | Badge timer sur chaque groupe |
| Icônes actions | ⚙️ skill / >_ shell / ⊞ file | Tick circle uniform | Icônes distinctes par type |
| Input | Multi-ligne, chips, voix | Single-line | Multi-ligne, expand, chips |

---

## 2. Anatomie du nouveau chat — vue complète

```
┌──────────────────────────────────────────────────────────┐
│  🐼 Panda Agent                    [ask] [agent] [plan]  │
│  claude-3.5-sonnet · 4 200 / 128k · ~$0.03         [⋮]  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ──── 06/08/2026, 23:37 ─────────────────────────────── │
│                                                          │
│                           ╔══════════════════════════╗  │
│                           ║ Tu va clone panda-ide de ║  │
│                           ║ ferelking242 sur github   ║  │
│                           ║ le pat est dans le secret ║  │
│                           ║ ...                       ║  │
│                           ╚══════════════════════════╝  │
│                                            1 minute ago  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │ ⚙ Analyzing capabilities and planning roadmap ↓ │   │
│  ├──────────────────────────────────────────────────┤   │
│  │  ⚙ Loaded skill environment-secrets              │   │
│  │  ⚙ Loaded skill git-remote                      │   │
│  │  ⚙ Analyzing tools and planning development     │   │
│  │  <> Vérification des secrets disponibles        │   │
│  │  ⚙ Initializing and cloning repository          │   │
│  │  >_ Listed files                                 │   │
│  │  ⚙ Requesting missing GitHub PAT secret         │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Je vais d'abord lire les skills nécessaires et          │
│  configurer l'accès GitHub, puis cloner et analyser      │
│  le projet.                                              │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │ 🔑 Add secrets                                  │    │
│  │ GITHUB_PAT                      [Secret provided]│    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  ╔ Worked for 28s ╗  ╔ Cloning the repository ╗        │
│                                                          │
│  Parfait, je clone le repo maintenant.                   │
│                                                          │
│  ┌───────────────────────────────────────────────┐      │
│  │ >_ 4 actions                               ↓  │      │
│  └───────────────────────────────────────────────┘      │
│                                                          │
│  Repo cloné (1.2 GB). Je lance maintenant une            │
│  exploration parallèle profonde...                        │
│                                                          │
│  ┌───────────────────────────────────────────────┐      │
│  │ ⊞ 3 actions  ·  Counted lines, Read files ↓  │      │
│  └───────────────────────────────────────────────┘      │
│                                                          │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐  │
│  │ @  Décris ta tâche...                    📎  🎙️  │  │
│  └────────────────────────────────────────────────────┘  │
│  [+]  [Ask]  [Agent ✓]  [Plan]  ···  Economy ↕          │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Composants détaillés

### 3.1 Header du chat

```
┌──────────────────────────────────────────────────────────┐
│  🐼  claude-3.5-sonnet         4 200 / 128k  ~$0.03  ⋮  │
└──────────────────────────────────────────────────────────┘
```

**Éléments :**
- Icône Panda (petit, 16px) + nom du modèle actif (tap → picker modèle)
- Token counter : `4 200 / 128k` avec barre de progression inline (fond coloré qui grandit)
  - Vert < 50%, Orange 50-80%, Rouge > 80%
- Coût estimé : `~$0.03` (tap → détail par message)
- `⋮` menu : Nouvelle conversation / Exporter / Historique / Settings

**Flutter :**
```dart
// Header row
Row([
  Icon(Panda, size: 16, color: accent),
  Expanded(child: ModelDropdown(selected: model, onChanged: onModelChange)),
  TokenProgressChip(used: 4200, limit: 128000),
  CostBadge(cost: 0.03),
  IconButton(icon: Icon(Broken.more), onPressed: showMenu),
])
```

---

### 3.2 Message utilisateur (User Bubble)

```
                              ╔════════════════════════╗
                              ║ Tu va clone panda-ide  ║
                              ║ de ferelking242...     ║
                              ╚════════════════════════╝
                                            1 minute ago
```

**Règles :**
- Aligné à droite, pas jusqu'au bord (margin: 48px gauche)
- Fond : `Color(0xff3a5a8c)` (bleu foncé Panda accent)
- BorderRadius : `BorderRadius.only(topLeft: 16, topRight: 4, bottomLeft: 16, bottomRight: 16)`
- Texte : blanc, 14sp, line-height 1.5
- Multi-paragraphe : `\n\n` → séparation visuelle dans la même bulle
- Timestamp discret en dessous à droite : `x min ago`, 11sp, muted
- Long press → menu : Copier / Citer / Modifier

**Flutter :**
```dart
class UserBubble extends StatelessWidget {
  // Aligné à droite, fond bleu, coins asymétriques
  // Markdown simple (gras, italique, code inline) mais PAS de blocs code
}
```

---

### 3.3 Message agent (Agent Text — NO bubble)

```
Je vais d'abord lire les skills nécessaires et
configurer l'accès GitHub, puis cloner et analyser
le projet.
```

**Règles :**
- Texte brut gauche, **aucun fond, aucune bulle, aucune bordure**
- Padding : `EdgeInsets.symmetric(horizontal: 16, vertical: 6)`
- Texte : couleur normale (fg), 14sp, line-height 1.6
- Markdown rendu complet : titres, gras, listes, tables, blocs de code
- Blocs de code : fond sombre `Color(0xff1a1a2e)`, police mono, syntaxe colorée, bouton [📋] copy
- Long press → menu : Copier tout / Citer

---

### 3.4 Groupe d'actions (Action Group — collapsible)

```dart
// Collapsed (défaut)
┌──────────────────────────────────────────────┐
│  ⚙  Analyzing capabilities...  · 7 actions  ▼ │
└──────────────────────────────────────────────┘

// Expanded (tap)
┌──────────────────────────────────────────────┐
│  ⚙  Analyzing capabilities...  · 7 actions  ▲ │
├──────────────────────────────────────────────┤
│   ⚙  Loaded skill environment-secrets        │
│   ⚙  Loaded skill git-remote                │
│   ⚙  Analyzing tools and planning...        │
│   <>  Vérification des secrets disponibles  │
│   ⚙  Initializing and cloning repository    │
│   >_  Listed files                           │
│   ⚙  Requesting missing GitHub PAT secret   │
└──────────────────────────────────────────────┘
```

**Règles :**
- Fond : `Color(0xff1e1e2e)` (légèrement différent du fond chat)
- BorderRadius : 8px
- Border : 1px `Color(0xff2a2a3e)`
- Header : toujours visible, tap → toggle expanded
- Icône groupe : type dominant des actions (⚙ skill, >_ shell, ⊞ file, 🌐 web)
- Count : `. 7 actions` en muted
- Sous-items : 36px de hauteur, icon 14px + label 13sp + éventuellement résultat tronqué
- Animation : `AnimatedSize` + `AnimatedCrossFade` (0.2s ease)

**Icônes par type d'action :**
```
⚙  Broken.setting_2       → skill load, config, analyze
>_ Broken.code_1           → shell command
⊞  Broken.document         → read/write file
🔍 Broken.search_normal    → search/grep/glob
🌐 Broken.global           → web search / web read
📝 Broken.edit             → write/edit file
🗑  Broken.trash           → delete
🔗 Broken.link             → git operations
💾 Broken.save_2           → checkpoint/memory
❓ Broken.question          → ask question / form
```

**Flutter :**
```dart
class ActionGroup extends StatefulWidget {
  final String title;
  final List<ActionItem> items;
  final ActionGroupType type; // determines icon
  final Duration? workedFor;
  // ...
  
  @override
  Widget build(context) {
    return AnimatedContainer(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: groupBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column([
        _GroupHeader(title, items.length, type, expanded, onTap),
        if (expanded) _GroupItems(items),
      ]),
    );
  }
}
```

---

### 3.5 Timer badge (Worked for Xs)

```
┌─────────────────┐  ┌─────────────────────────┐
│  ⏱ Worked 28s  │  │  🔄 Cloning repository  │
└─────────────────┘  └─────────────────────────┘
```

**Règles :**
- Chips horizontaux, scrollables
- Fond : `Color(0xff252535)`, BorderRadius 20px
- Icône + texte court
- Apparaissent entre deux blocs de texte agent
- Row avec `SingleChildScrollView` horizontal

---

### 3.6 Formulaire inline (Secrets, Questions)

```
┌────────────────────────────────────────────┐
│ 🔑 Add secrets                             │
│ GITHUB_PAT                 [Secret provided]│
└────────────────────────────────────────────┘
```

**Règles :**
- Card avec fond légèrement surélevé
- Icône pertinente (🔑 secret, ❓ question, ⚙️ config)
- Inline dans le flux, pas de dialog/modal
- État : `waiting` (champ vide), `provided` (badge vert), `error` (badge rouge)

---

### 3.7 Input bar — redesign complet

```
┌─────────────────────────────────────────────────┐
│  @file:/lib/main.dart  ×                        │
│  ─────────────────────────────────────────────  │
│  Décris ta tâche ou ajoute des @mentions...     │
│                                            📎 🎙 │
└─────────────────────────────────────────────────┘
[+]  [Ask]  [Agent ✓]  [Plan]  ···  Economy ↕
```

**Éléments :**
- **Chips de contexte** (rangée au-dessus du champ) : `@file:main.dart ×`, `@problems ×`, `@git ×`
- **TextField multi-ligne** : min 1 ligne, max 8 lignes, puis scroll interne
- **Bouton 📎** : menu contextuel → Image, Fichier, Screenshot app, Terminal output
- **Bouton 🎙** : voice input (hold to record)
- **Mode bar** : Ask / Agent (checked = actif) / Plan
- **Economy/Pro** : dropdown coût
- Placeholder intelligent : change selon le mode (`Ask: Pose une question` / `Agent: Décris ta tâche` / `Plan: Que veux-tu planifier ?`)

---

### 3.8 Séparateurs de date/session

```
─────────────────── 06/08/2026, 23:37 ───────────────────
```

**Règles :**
- `Row(children: [Divider, Text, Divider])`
- Texte 11sp, muted, centré
- Apparaît au début de chaque session + au début de chaque jour

---

### 3.9 "Scroll to latest" badge

```
              ↓ Scroll to latest
```

**Règles :**
- Apparaît quand le scroll n'est pas en bas ET qu'un nouveau message arrive
- Centré horizontalement, bottom: 80px (au-dessus de l'input)
- Fond : accent, BorderRadius 20px
- Tap → smooth scroll jusqu'en bas
- Disparaît automatiquement quand l'utilisateur scroll en bas

---

### 3.10 État "Agent génère" (inline, pas de bulle)

```
🐼  ·  ·  ·                    [⬜ Stop]
```

**Règles :**
- Icône panda animée (pulse) + 3 dots animés
- Pas de bulle — juste une ligne dans le flux
- Bouton [Stop] aligné à droite → `runner.cancel()`
- Phase "thinking" : `🧠 Réflexion...` avec fond légèrement différent

---

## 4. Thèmes couleurs

### Dark (défaut Panda)
```dart
static const chatBg        = Color(0xff0f0f1a);
static const userBubbleBg  = Color(0xff1a3a5c);  // bleu foncé
static const agentText     = Color(0xffd0d0e0);   // text normal
static const actionGroupBg = Color(0xff1a1a2a);
static const actionItemBg  = Color(0xff151520);
static const borderColor   = Color(0xff2a2a3a);
static const chipBg        = Color(0xff252535);
static const codeBlockBg   = Color(0xff0d1117);  // GitHub dark
static const muted         = Color(0xff606070);
static const accent        = Color(0xff5090c8);
static const accentGreen   = Color(0xff4caf7d);
static const accentOrange  = Color(0xfff5a623);
static const accentRed     = Color(0xffe05252);
```

### Light
```dart
static const chatBg        = Color(0xfff6f8fa);  // GitHub light
static const userBubbleBg  = Color(0xff0969da);  // GitHub blue
static const agentText     = Color(0xff1f2328);
static const actionGroupBg = Color(0xffffffff);
static const borderColor   = Color(0xffd0d7de);
static const codeBlockBg   = Color(0xfff6f8fa);
```

---

## 5. Animations

| Élément | Animation | Durée |
|---|---|---|
| Action group expand | `AnimatedSize` height + `AnimatedCrossFade` | 200ms ease |
| User bubble appear | `SlideTransition` (droite→position) + `FadeTransition` | 150ms |
| Agent text appear | `FadeTransition` | 100ms |
| Scroll to latest badge | `FadeTransition` + `SlideTransition` (bas→haut) | 200ms |
| Panda thinking dots | `AnimationController` repeat 600ms | continu |
| Token bar fill | `AnimatedContainer` width | 500ms ease |
| Code block copy flash | `FadeTransition` sur "Copied!" | 1.5s |

---

## 6. Comportements scrolling

- **Auto-scroll** : si l'utilisateur était déjà en bas → auto-scroll à chaque nouveau token
- **Scroll libre** : si l'utilisateur a scrollé manuellement vers le haut → arrêter l'auto-scroll
- **Scroll to latest** : badge apparaît dès que l'utilisateur quitte le bas et qu'un message génère
- **Scroll position mémoire** : restaurer la position quand on revient sur une vieille conversation

---

## 7. Différences clés vs UI actuelle

| Point | UI actuelle (`agent_settings.dart`) | Nouvelle UI |
|---|---|---|
| Messages agent | Fond coloré `card` | **Aucun fond** |
| Tool calls | `_ToolStatusCard` : card fixe, jamais collapsible | **Groupes collapsibles** avec count |
| Thinking | Bloc texte simple | **Bloc collapsible** distinct avec icône 🧠 |
| Input | `TextField` simple 1 ligne | **Multi-ligne auto-expand** + chips |
| Modes | Chips `ask/agent/plan` dans l'input | **Barre de mode séparée** sous l'input |
| Token display | Absent | **Dans le header** avec barre de progression |
| Cost | Absent | **Badge `~$0.03`** dans header |
| Separator | Absent | **Date separator** entre sessions |
| Scroll badge | Absent | **"Scroll to latest"** badge |
| Timestamp | Phase label | **`x min ago`** sous les bulles user |
| Code blocks | `markdown_widget` sans action | **Fond GitHub dark** + [📋 Copy] + [Apply] |

---

## 8. Fichiers Flutter à créer / modifier

### Nouveaux fichiers
```
lib/ui/agent/
├── agent_chat_view.dart          # Widget principal (remplace _buildChatTab)
├── agent_header.dart             # Header avec token/cost/model picker
├── agent_input_bar.dart          # Input multi-ligne + mode bar
├── agent_user_bubble.dart        # Bulle utilisateur
├── agent_text_block.dart         # Texte agent (no bubble)
├── agent_action_group.dart       # Groupe collapsible d'actions
├── agent_action_item.dart        # Sous-item dans un groupe
├── agent_timer_chips.dart        # "Worked for Xs" chips
├── agent_inline_form.dart        # Secrets / questions inline
├── agent_code_block.dart         # Code avec syntaxe + copy + apply
├── agent_thinking_block.dart     # Bloc reasoning collapsible
└── agent_scroll_badge.dart       # "Scroll to latest" badge
```

### Fichiers modifiés
```
lib/ui/agent_settings.dart        # Intégrer les nouveaux widgets
lib/ui/agent_runner.dart          # Émettre ActionGroup chunks
lib/utils/agent_cost_tracker.dart # NEW: estimation coût
```

---

## 9. Nouveau format de chunks AgentRunner

Pour supporter les groupes d'actions, `AgentChunk` doit évoluer :

```dart
// ACTUEL
enum AgentPhase { idle, thinking, toolRunning, toolDone, streaming, done, error }

// NOUVEAU — ajouter :
enum AgentPhase {
  idle,
  thinking,
  toolGroupStart,  // début d'un groupe (title, count estimé)
  toolRunning,     // tool en cours DANS le groupe
  toolDone,        // tool terminé DANS le groupe
  toolGroupEnd,    // fin du groupe (workedFor)
  streaming,
  done,
  error,
}

class AgentChunk {
  final AgentPhase phase;
  final String text;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final String? toolResult;
  final String? groupTitle;      // NEW: titre du groupe
  final Duration? workedFor;     // NEW: timer du groupe
  final ActionType? actionType;  // NEW: icône à afficher
}

enum ActionType { skill, shell, fileRead, fileWrite, search, web, git, memory, question }
```

---

## 10. Questions ouvertes

1. **Persistance des groupes** : quand on recharge une conversation depuis l'historique, les groupes d'actions sont-ils reconstruits depuis les messages bruts ou stockés tels quels ?

2. **Groupement automatique** : le groupement se fait-il par tour LLM (une requête = un groupe) ou par type d'outil (tous les shell = un groupe) ?

3. **Taille max groupe** : si l'agent exécute 50 outils en une réponse, le groupe devient-il scrollable en interne ou se coupe-t-il ?

4. **Code blocks "Apply"** : comment détecter qu'un bloc de code correspond à un fichier ouvert dans l'éditeur ?

---

*Design spec rédigé après analyse des screenshots Replit Agent (23:37-23:39)*
*Prêt pour implémentation Flutter dès validation*
