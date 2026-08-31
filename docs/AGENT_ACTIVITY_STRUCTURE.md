# Panda Agent Activity Structure — Plan d'Implémentation

> Architecture UI pour l'agent Panda avec animations temps réel, Flux UI natif et activity dock

---

## 1. Objectif

Créer une expérience utilisateur fluide et professionnelle pour l'agent Panda IDE, avec :

- **Animations temps réel** pendant le raisonnement et l'exécution
- **Activity dock** fixe au-dessus du composer
- **Timeline historique** avec transitions animées
- **Flow UI natif** sans dépendances externes

---

## 2. Règles Fondamentales

### Règle 1 : Toujours commencer par `thinking`
L'agent doit **toujours** commencer par afficher un indicateur de réflexion avant toute action.

```
🐼 thinking          ← Toujours en premier (orbs animation)
   Analyse de la demande
```

### Règle 2 : Les actions montent en haut
Les éléments terminés **remontent** dans la timeline. Les nouveaux éléments arrivent par le bas.

### Règle 3 : L'activité active reste en bas
L'activité active reste **fixe** au-dessus du composer. L'historique scroll au-dessus.

### Règle 4 : Pas de texte statique pendant une action
Toujours utiliser `FlowShimmerText` ou `FlowThinkingIndicator` pendant les actions.

### Règle 5 : FlowComposer unique
Utiliser uniquement `FlowComposer` de Flow UI, pas de champ maison.

---

## 3. Flux Obligatoire (chaque réponse)

### Réponse simple (sans outil)
```
🐼 thinking          → FlowThinkingIndicator (orbs)
   Analyse de la demande

🐼 working           → FlowShimmerText
   Préparation de la réponse

Réponse Markdown finale
```

### Réponse avec outils
```
🐼 thinking          → FlowThinkingIndicator (orbs)
   Analyse de la demande

🐼 working           → FlowShimmerText
   Cloning dépôt

🐼 execute cmd       → FlowShimmerText + commande
   git clone https://github.com/...

🐼 working           → FlowShimmerText
   Installation des dépendances

🐼 execute cmd       → FlowShimmerText + commande
   flutter pub get

Réponse Markdown finale
```

### Réponse avec approbation
```
🐼 thinking          → FlowThinkingIndicator (orbs)
   Analyse de la demande

🐼 working           → FlowShimmerText
   Préparation de la suppression

🐼 approval          → Carte d'approbation
   L'agent souhaite exécuter :
   rm -rf build/
   [Autoriser] [Toujours] [Refuser]

(Après approbation)
🐼 execute cmd       → FlowShimmerText + commande
   rm -rf build/

Réponse Markdown finale
```

---

## 4. Machine à États

```
idle
  ↓
thinking          → FlowThinkingIndicator (orbs)
  ↓
planning          → FlowThinkingIndicator + texte d'analyse
  ↓
working           → FlowShimmerText
  ↓
toolRunning       → FlowShimmerText + commande
  ↓
toolCompleted     → Remonte dans l'historique
  ↓
working (next)
  ↓
done              → Message Markdown final
```

### Branches supplémentaires
- `toolRunning → approvalRequired → toolRunning`
- `toolRunning → error`

### Tableau des états

| État interne | Affichage |
|---|---|
| `thinking` | FlowThinkingIndicator + animation Thinking Orbs |
| `planning` | Thinking Indicator + texte d'analyse |
| `working` | Shimmer Text avec l'action actuelle |
| `toolRunning` | Shimmer Text + commande en cours |
| `toolCompleted` | Action terminée déplacée dans la timeline supérieure |
| `approvalRequired` | Carte Flow UI avec Autoriser / Toujours autoriser / Refuser |
| `error` | Composant d'erreur Flow UI |
| `done` | Message Markdown final |

---

## 5. Composants Flow UI à Utiliser

### Composants officiels

| Composant | Usage | Source |
|---|---|---|
| `FlowThinkingIndicator` | État thinking/orbs | flow_ui |
| `FlowShimmerText` | État working/actions | flow_ui |
| `FlowComposer` | Champ d'envoi | flow_ui |
| `FlowThread` | Timeline des messages | flow_ui |
| `FlowMessage` | Messages user/assistant | flow_ui |
| `FlowCustomPart` | Événements activity | flow_ui |
| `FlowMarkdown` | Rendu Markdown | flow_ui |
| `FlowCodeBlock` | Blocs de code | flow_ui |
| `FlowMessageActions` | Actions copier/retry | flow_ui |

### Composants Panda (créer)

| Composant | Usage |
|---|---|
| `PandaActivityDock` | Dock fixe au-dessus du composer |
| `PandaActivityRow` | Ligne d'activité (active/historique) |
| `PandaApprovalCard` | Carte d'approbation |

---

## 6. Types d'Activité

```dart
enum PandaActivityKind {
  thinking,    // Orb animation
  working,     // Shimmer text
  tool,        // Shimmer text + commande
  approval,    // Carte approval
  result,      // Markdown final
  error,       // Message d'erreur
}

enum PandaActivityStatus {
  pending,           // En attente
  running,           // En cours (animé)
  completed,         // Terminé (pas d'animation)
  failed,            // Échoué
  waitingApproval,   // En attente d'approbation
}
```

---

## 7. Structure de Rendu

```
PandaAgentScreen
├── FlowThread
│   ├── UserMessage
│   ├── CompletedActivityParts    ← Historique (monte)
│   ├── ToolResultParts
│   └── AssistantMarkdownMessage  ← Réponse finale
│
├── PandaActivityDock             ← Fixe en bas
│   ├── ActiveThinkingOrbs       ← Si thinking actif
│   ├── ActiveShimmerText        ← Si working actif
│   └── ActiveApprovalCard       ← Si approval requis
│
└── FlowComposer                  ← Toujours visible
```

---

## 8. Animation de Transition

### Nouvelle action
- Position de départ : sous la zone active
- Position finale : zone active
- Animation : `Offset(0, 1) → Offset.zero`

### Ancienne action
- Position actuelle : zone active
- Position finale : au-dessus
- Animation : `Offset.zero → Offset(0, -1)`

### Paramètres
- Durée : 250-300 ms
- Curve : `Curves.easeOutCubic`
- Composants : `AnimatedSwitcher` + `SlideTransition` + `FadeTransition`
- Key : `ValueKey(event.id)`

---

## 9. Événement Normalisé

Tous les événements de l'agent doivent avoir une structure commune :

```dart
class PandaAgentActivity {
  final String id;
  final PandaActivityKind kind;
  final String label;
  final String? command;
  final String? output;
  final PandaActivityStatus status;
  final DateTime createdAt;
  final bool visible;
}
```

### Exemple JSON

```json
{
  "id": "activity-42",
  "kind": "working",
  "label": "Cloning dépôt",
  "status": "running",
  "visible": true
}
```

---

## 10. Contrôleur d'Activité

Le contrôleur conserve deux listes :

```dart
final List<PandaAgentActivity> completedActivities;
PandaAgentActivity? activeActivity;
```

### Comportement

1. `completedActivities` est affichée dans la partie supérieure (timeline)
2. `activeActivity` reste dans le dock fixe au-dessus du composer
3. Quand l'activité finit, elle est déplacée dans `completedActivities`
4. L'activité suivante devient `activeActivity`

---

## 11. Prompt Système Obligatoire

Le prompt système doit imposer un protocole d'activité :

```
Avant toute réponse ou action :

1. Émettre un événement thinking avec un résumé court :
   "Analyse de la demande"

2. Émettre un événement working décrivant l'action courante.

3. Avant chaque outil, annoncer l'action :
   "Cloning dépôt", "Lecture du fichier", "Installation des dépendances", etc.

4. Émettre un événement execute cmd quand une commande démarre.

5. Mettre à jour l'événement quand l'action termine.

6. Ne jamais lancer un outil sans avoir affiché son action.

7. Même sans outil, afficher thinking puis working avant la réponse finale.

8. Les événements doivent être courts, factuels et ne doivent jamais contenir
   la chaîne de pensée détaillée ou des raisonnements privés.
```

Le système doit donc produire :
```
thinking → working → tool → working → tool → final
```

et non simplement :
```
tool → final
```

---

## 12. Exemple Complet : Clone et Installation

### Demande utilisateur
```
Clone et installe puis lance le projet :
https://github.com/Dima011099/taskminimal-app
```

### Flux attendu

```
🐼 thinking
Analyse de la demande

L'agent détecte que le dépôt est Flutter.

🐼 working
Préparation de l'espace de travail

🐼 working
Cloning dépôt

🐼 execute cmd
git clone https://github.com/Dima011099/taskminimal-app

(Après succès)

🐼 working
Dépôt cloné

🐼 working
Analyse de la structure du projet

🐼 execute cmd
ls -la

Si Flutter est détecté :

🐼 working
Installation des dépendances Flutter

🐼 execute cmd
flutter pub get

Puis :

🐼 working
Vérification du projet

🐼 execute cmd
flutter analyze

Enfin :

🐼 working
Lancement du projet

🐼 execute cmd
flutter run

Réponse finale :

## Projet lancé

Le dépôt a été cloné et installé avec succès.

- Dépôt : `taskminimal-app`
- Type détecté : Flutter
- Dépendances : installées
- Analyse : réussie
- Lancement : terminé

Tu peux maintenant ouvrir le projet dans le terminal ou l'éditeur.
```

---

## 13. Exemple avec Approbation

Pour une commande dangereuse :

```
🐼 thinking
Analyse de la demande

🐼 working
Préparation de la suppression

🐼 approval
L'agent souhaite exécuter :
rm -rf build/

[Autoriser] [Toujours autoriser] [Refuser]

(Après décision)

🐼 execute cmd
rm -rf build/

La carte d'approbation doit rester l'action active en bas.
Une fois la décision prise, elle remonte dans l'historique.
```

---

## 14. Intégration des Animations Open Source

### Aucune dépendance supplémentaire

Le code doit être intégré directement, pas en dépendance.

### Structure recommandée

```
lib/ui/agent/flow_ui/
├── animations/
│   ├── thinking_orbs.dart
│   ├── thinking_orb_painter.dart
│   └── thinking_orb_controller.dart
├── widgets/
│   ├── flow_composer.dart
│   ├── flow_message.dart
│   ├── flow_thread.dart
│   ├── flow_thinking_indicator.dart
│   ├── flow_shimmer_text.dart
│   └── flow_activity_dock.dart
├── models/
│   ├── flow_message_data.dart
│   ├── flow_message_part.dart
│   └── flow_attachment.dart
└── panda_agent_flow_widgets.dart
```

### Licences

Le code Thinking Orbs doit être intégré directement dans `thinking_orbs.dart`, en conservant les notices et mentions de licence du projet source.

Même principe pour le Shimmer Text : intégrer le rendu et l'animation dans Flow UI au lieu d'ajouter une dépendance externe.

---

## 15. Plan d'Implémentation

### Étape 1 — Protocole d'activité
- Définir les types `thinking`, `working`, `tool`, `approval`, `error`
- Ajouter un contrôleur d'activité
- Convertir les événements de AgentRunner vers ce protocole
- Garantir qu'un événement thinking est toujours émis au début

### Étape 2 — Thinking Orbs
- Copier proprement l'animation open source
- Créer `FlowThinkingIndicator`
- Ajouter les états actif, terminé et erreur
- Ne pas afficher le raisonnement privé, uniquement le statut

### Étape 3 — Shimmer Text
- Intégrer directement le composant Shimmer Text
- Utiliser Shimmer Text pour tous les éléments working
- Interdire un texte statique pendant une action active

### Étape 4 — Activity Dock
- Créer le panneau fixe au-dessus de FlowComposer
- Ajouter la transition entrée par le bas / sortie par le haut
- Maintenir une hauteur stable
- Empêcher la timeline de faire sauter le composer

### Étape 5 — Timeline Flow
- Convertir les événements terminés en FlowCustomPart
- Utiliser FlowThread et FlowMessage
- Utiliser le Markdown Flow UI pour les réponses finales
- Utiliser les blocs de code Flow UI
- Utiliser FlowMessageActions pour copier et réessayer

### Étape 6 — Outils et approbations
- `execute cmd` devient une carte Flow UI
- Les sorties de commande sont repliables
- Les actions d'approbation utilisent les boutons Flow UI
- Les résultats d'outils sont déplacés dans l'historique après exécution

### Étape 7 — Erreurs
Chaque erreur doit suivre le même modèle :
```
thinking
working
execute cmd
error
```

Puis afficher :
- le message d'erreur ;
- la commande concernée ;
- le bouton copier ;
- le bouton réessayer ;
- éventuellement l'ouverture du terminal.

### Étape 8 — Vérification
Tester au minimum :
- Demande simple sans outil
- Clone d'un dépôt
- Installation Flutter
- Commande longue avec streaming
- Plusieurs commandes successives
- Approbation obligatoire
- Refus d'une commande
- Échec réseau
- Pièce jointe seule
- Retry d'un message échoué
- Rotation ou redimensionnement mobile
- Scrolling pendant une génération

---

## 16. Structure Finale du Rendu

```
PandaAgentScreen
├── FlowThread
│   ├── UserMessage
│   ├── CompletedActivityParts
│   ├── ToolResultParts
│   └── AssistantMarkdownMessage
├── PandaActivityDock
│   ├── ActiveThinkingOrbs
│   ├── ActiveShimmerText
│   └── ActiveApprovalCard
└── FlowComposer
```

**Point central** : ne pas mélanger le message final et l'activité en cours. Le message final appartient à FlowThread, tandis que thinking, working et l'action actuelle appartiennent au PandaActivityDock, qui reste fixe au-dessus du champ de saisie.

---

*Document créé le 31/08/2026*
*Version 1.0*
