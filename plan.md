# 🐼 Plan d'Implémentation : Panda AI UI (Inspiré de Beautiful UI)

Ce document dresse le plan architectural, visuel et technique pour réimplémenter les composants haut de gamme de **Beautiful UI** (habituellement conçus en React + Tailwind) directement dans l'écosystème **Flutter** de **Panda IDE**.

L'objectif est d'offrir à l'utilisateur de **Panda Agent** une interface de chat ultra-fluide, vivante, dotée de micro-interactions organiques et de transitions physiques fidèles aux standards du web moderne.

---

## 🎨 Philosophie de Design : "Beautiful UI" en Flutter

1. **Fluidité Organique (Spring Physics) :** Abandonner les animations linéaires rigides pour des courbes de type ressort (`Curves.easeOutQuart`, `Curves.elasticOut`, ou l'utilisation de `PhysicsParentData`).
2. **Esthétique Glassmorphic & Sombre :** Utilisation de semi-transparences, de bordures irisées ultra-fines (0.5 à 1.0 px), de flous d'arrière-plan (`BackdropFilter`) et de dégradés profonds qui s'adaptent dynamiquement au thème de Panda IDE.
3. **Micro-Feedback Visuel :** Chaque interaction (survol, tap, expansion) s'accompagne d'un retour haptique subtil ou d'une transition lumineuse.

---

## 📂 Structure du Répertoire `panda_ai_ui/`

Les nouveaux widgets autonomes seront regroupés de manière modulaire sous `lib/ui/panda_ai_ui/` :

```text
lib/ui/panda_ai_ui/
├── text/
│   └── streaming_text.dart         # Révélation de caractères avec fading-reveal
├── activity/
│   ├── thinking.dart               # Indicateur de pensée Gemini-style à dégradé fluide
│   └── task.dart                   # Listes de sous-tâches rétractables & animées
├── code/
│   ├── code_block.dart             # Éditeur/Visualiseur de code épuré avec copie
│   └── diff_view.dart              # Diff git coloré avec lignes ajoutées/supprimées
├── interaction/
│   └── approval.dart               # Panneaux interactifs d'approbation d'actions
└── message/
    └── message_bubble.dart         # Bulles de chat avec physique d'entrée fluide
```

---

## 🧩 Spécifications Détaillées des Composants

### 1. `StreamingText` (Composant de Révélation de Texte)

*   **Utilité :** Affiche les réponses de Panda Agent caractère par caractère ou mot par mot, non pas de manière saccadée, mais avec un effet d'opacité progressive (*fade-in slide*) très élégant.
*   **Schéma Conceptuel :**
    ```text
    [P] [a] [n] [d] [a]   <- Caractères opaques à 100%
                [A]       <- Caractère en cours d'affichage (Opacité: 60%, Décalage Y: +2px)
                    [g]   <- Caractère futur (Opacité: 0%)
    ```
*   **Spécifications Visuelles :**
    *   Pas de saut de ligne brusque lors de la révélation.
    *   Curseur de frappe stylisé (petite barre verticale animée en pulsation).
*   **Animations & Courbes :**
    *   Transition d'opacité : de `0.0` à `1.0` via `Curves.easeOut`.
    *   Déplacement vertical (Slide-up) de 4px vers 0px pour chaque mot révélé.
*   **Props Flutter Proposées :**
    ```dart
    class StreamingText extends StatefulWidget {
      final String text;
      final TextStyle? style;
      final Duration wordDuration; // Vitesse de révélation
      final VoidCallback? onComplete;
    }
    ```

---

### 2. `Thinking` (Indicateur de Réflexion)

*   **Utilité :** Affiche l'état "Panda Agent réfléchit..." de façon moderne avec un dégradé de couleur en rotation infinie, un panneau extensible pour afficher les détails du raisonnement de l'agent.
*   **Schéma Conceptuel :**
    ```text
    ┌────────────────────────────────────────────────────────┐
    │  🌀  Panda réfléchit...                   [ 00:14 ]  ▼ │  <- Dégradé animé (Bleu/Violet/Rose)
    ├────────────────────────────────────────────────────────┤
    │  > Lecture de lib/ui/home.dart                         │  <- Contenu déroulant (raisonnement)
    │  > Analyse des importations d'icônes                   │
    └────────────────────────────────────────────────────────┘
    ```
*   **Spécifications Visuelles :**
    *   Conteneur sombre semi-transparent (`Color(0x0dffffff)`) avec une bordure dégradée irisée.
    *   Minuteur de réflexion précis en haut à droite.
*   **Animations & Courbes :**
    *   Expansion/Rétraction fluide utilisant un `SizeTransition` ou un `AnimatedContainer` avec `Curves.easeInOutCubic`.
    *   Rotation continue du gradient central : `RotationTransition` sur 360° en 3 secondes.
*   **Props Flutter Proposées :**
    ```dart
    class ThinkingIndicator extends StatefulWidget {
      final List<String> steps;      // Les étapes déjà réalisées
      final String currentStep;      // L'étape en cours
      final bool isExpanded;         // Statut de déroulement initial
      final Duration elapsed;        // Temps écoulé
    }
    ```

---

### 3. `Task` (Suivi de Tâches Applicatives)

*   **Utilité :** Représente graphiquement la liste des sous-tâches ou commandes système exécutées par l'agent pendant son travail.
*   **Schéma Conceptuel :**
    ```text
    [ ✔ ] Compiler le projet flutter           (Success - Vert émeraude)
    [ 🌀 ] Exécuter les tests unitaires        (In Progress - Rotation)
    [ ⏳ ] Mettre à jour les dépendances        (Pending - Muted grey)
    ```
*   **Spécifications Visuelles :**
    *   Success Pill : Vert émeraude brillant (`Color(0xff10b981)`) avec ombre douce.
    *   Ligne verticale de liaison entre les puces d'étapes (Timeline style).
*   **Animations & Courbes :**
    *   Transition d'état d'icône (de sablier vers coche verte) via un fondu croisé `AnimatedSwitcher` avec une courbe de rebond (`Curves.elasticOut`).
*   **Props Flutter Proposées :**
    ```dart
    class TaskItem {
      final String label;
      final TaskStatus status; // enum { pending, running, success, failed }
    }
    ```

---

### 4. `CodeBlock` (Lecteur de Code Épuré)

*   **Utilité :** Affiche les extraits de code générés par Panda Agent avec un look VS Code sombre ultra-premium, détection de syntaxe, et un bouton "Copier" interactif.
*   **Schéma Conceptuel :**
    ```text
    ┌── widgets.dart ───────────────────────────── [ Copier ] ─┐
    │ 1 |  Widget build(BuildContext context) {                 │
    │ 2 |    return Container(                                  │
    │ 3 |      color: Theme.of(context).primaryColor,           │
    │ 4 |    );                                                 │
    │ 5 |  }                                                    │
    └───────────────────────────────────────────────────────────┘
    ```
*   **Spécifications Visuelles :**
    *   Header arborant le nom du fichier avec une icône de langage appropriée (Dart, JS, Rust, etc.).
    *   Gouttière latérale pour les numéros de ligne avec un contraste adouci.
    *   Arrière-plan sombre mat (`Color(0xff1e1e1e)`).
*   **Animations & Courbes :**
    *   L'icône "Copier" se transforme temporairement en coche verte ("Copié !") avec un effet de scale-down puis scale-up rapide (`Curves.bounceOut`).
*   **Props Flutter Proposées :**
    ```dart
    class CodeBlock extends StatelessWidget {
      final String code;
      final String language;
      final String? filename;
    }
    ```

---

### 5. `DiffView` (Comparateur de Code)

*   **Utilité :** Permet à l'utilisateur de visualiser précisément les modifications de code suggérées par l'agent avant de les appliquer au projet.
*   **Schéma Conceptuel :**
    ```text
    -  final String oldUrl = "http://localhost";  // Rouge délavé (Supprimé)
    +  final String newUrl = "https://api.sh";    // Vert forêt (Ajouté)
    ```
*   **Spécifications Visuelles :**
    *   Lignes supprimées : Fond rouge translucide (`Color(0x26ef4444)`) avec un `-` rouge sur le côté.
    *   Lignes ajoutées : Fond vert translucide (`Color(0x2610b981)`) avec un `+` vert sur le côté.
*   **Animations & Courbes :**
    *   Révélation progressive des lignes modifiées via un effet de slide horizontal.

---

### 6. `Approval` (Boîte d'Approbation Interactive)

*   **Utilité :** Demande explicitement l'autorisation de l'utilisateur pour appliquer un correctif, exécuter une commande terminal sensible, ou modifier un fichier.
*   **Schéma Conceptuel :**
    ```text
    ┌──────────────────────────────────────────────────────────┐
    │ ⚠️  Autoriser l'exécution de la commande ?                 │
    │                                                          │
    │ $ git commit -m "fix: compilation errors"                │
    │                                                          │
    │               [ Refuser ]   [  ✓ Autoriser  ]            │
    └──────────────────────────────────────────────────────────┘
    ```
*   **Spécifications Visuelles :**
    *   Bouton "Autoriser" doté d'un effet pulsé ou d'un dégradé de fond actif.
    *   Bouton "Refuser" discret en bordure rouge estompée.
*   **Animations & Courbes :**
    *   Apparition par translation verticale rebondissante (`Curves.easeOutBack`).
    *   Effet de clic physiques (réduction de taille de 5% au tap grâce à un `GestureDetector` + `AnimatedScale`).

---

### 7. `MessageBubble` (Entrées de Chat)

*   **Utilité :** Présente les conversations entre l'utilisateur et Panda Agent de façon asymétrique et spacieuse.
*   **Schéma Conceptuel :**
    ```text
    [👤 Utilisateur]
    "Peux-tu corriger le bug de compilation ?"
                                                 [🐼 Panda Agent]
                                   "Certainement, j'analyse le..."
    ```
*   **Spécifications Visuelles :**
    *   Avatar de l'utilisateur ou du panda arrondi avec bordure lumineuse active si en cours d'écriture.
    *   Bulles de message aux coins adoucis et asymétriques (ex: bord inférieur gauche ou droit pointu).
*   **Animations & Courbes :**
    *   Chaque message entre dans le flux avec un effet d'échelle progressif (`ScaleTransition`) et une translation vers le haut (`SlideTransition`) pour simuler un flot physique.

---

## 🚀 Plan d'Intégration Progressif

Pour éviter toute régression ou blocage de compilation, l'intégration suivra cette feuille de route rigoureuse :

1. **Phase 1 : Création de la bibliothèque isolée (`lib/ui/panda_ai_ui/`)**
   * Création de chaque composant de manière autonome avec des fichiers de démonstration épurés.
2. **Phase 2 : Couplage avec le bloc `AppTheme`**
   * S'assurer que tous les gradients, bordures et flous d'arrière-plan réagissent en temps réel lors du passage du mode clair au mode sombre.
3. **Phase 3 : Remplacement progressif dans `home.dart`**
   * Substitution des widgets existants par les nouveaux composants `Panda AI UI`.
   * Activation des animations de transition.
