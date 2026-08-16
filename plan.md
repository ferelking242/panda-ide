# 🐼 Plan d'Architecture & Bibliothèque Panda AI UI (Fidèle à Beautiful UI)

Ce plan définit la restructuration complète de l'interface de **Panda Agent** en s'inspirant directement de la bibliothèque interactive haut de gamme **[Beautiful UI](https://www.beautifului.dev/)**. 

Tous les composants seront réécrits de zéro en **Flutter** avec des animations fluides de type physique (ressorts), des effets de flou translucides (*glassmorphism*), et une intégration millimétrée au-dessus de la zone de saisie (*Prompt Bar*).

---

## 📁 Réorganisation des Fichiers de l'Agent

Tous les éléments de l'UI de Panda Agent actuellement dispersés ou intégrés dans `home.dart` seront déplacés et isolés de manière propre sous la structure suivante :

```text
lib/ui/panda_ai_ui/
├── core/
│   └── theme.dart                  # Constantes visuelles, ombres et gradients Beautiful UI
├── layout/
│   ├── chat_panel.dart             # Layout principal assemblant le chat, la prompt bar et les ancres
│   └── sidebar_nav.dart            # Barre latérale de navigation de l'agent
├── text/
│   └── streaming_text.dart         # Effet d'écriture progressive par estompage de mots
├── activity/
│   ├── loading_state.dart          # États de chargement et spinners squelettes
│   ├── thinking.dart               # Bloc de réflexion dynamique extensible
│   ├── tool_chips.dart             # Puces animées pour les opérations d'outils (file/terminal)
│   └── task_rows.dart              # Lignes de tâches d'agent ordonnées et connectées
├── code/
│   ├── code_block.dart             # Visualiseur de code avec numéros de lignes et copie rapide
│   ├── diff_table.dart             # Table de comparaison de fichiers (Diff) ultra-propre
│   ├── records_table.dart          # Affichage tabulaire des fichiers impactés
│   └── filter_table.dart           # Table de données interactive avec recherche/filtre
├── interaction/
│   ├── approval_card.dart          # Demande d'approbation (fichiers/commandes)
│   ├── prompt_bar.dart             # Barre de saisie unifiée
│   ├── selection_actions.dart      # Barre flottante d'actions rapides sur sélection de texte
│   └── fine_tune_card.dart         # Ajustement fin des prompts système et hyperparamètres
└── navigation/
    ├── recommendation_card.dart    # Cartes de suggestion de prompts rapides (Ask)
    ├── context_cards.dart          # Puces/Cartes de fichiers joints ou contextes actifs (Task/Context)
    └── insight_cards.dart          # Cartes de rapports d'analyse de performance ou d'erreurs
```

---

## 📐 Architecture de l'Espace de Saisie (Prompt & Docking Area)

Le design de **Beautiful UI** exige une intégration visuelle unifiée entre la saisie et les états de contexte/recommandations.

### Positionnement Physique de "Task" (Context/Tool Action) & "Ask" (Recommendations)

*   **Docking Collé :** Les composants de contexte (`Context Cards`), de suggestions (`Recommendation Cards`) et de suivi rapide (`Task Rows` réduits) se positionnent **juste au-dessus du composant `Prompt Bar`**, collés verticalement sans marge intermédiaire inutile.
*   **Rayon des Coins (Border Radius) Harmonisé :**
    *   **Le conteneur supérieur (Context / Recommendations) :** Coins supérieurs arrondis (`BorderRadius.vertical(top: Radius.circular(16))`), coins inférieurs droits et plats (`0.0`) où il fusionne avec la barre de prompt.
    *   **Le conteneur inférieur (Prompt Bar) :** Coins supérieurs plats (`0.0`) et coins inférieurs arrondis (`BorderRadius.vertical(bottom: Radius.circular(16))`).
    *   **Séparateur :** Une ligne de démarcation ultra-fine d'une opacité de `0.08` à `0.12` sépare visuellement les deux blocs pour un effet "Tableau de Bord intégré" sans couture.

#### Représentation Visuelle :
```text
┌─────────────────────────────────────────────────────────────┐  ▲
│  📂 Context: lib/main.dart [x]      📄 index.html [x]       │  │  "Task/Context Area"
│                                                             │  │  Coins sup. arrondis (16px)
│  💡 Ask: "Compile le projet"    "Répare l'erreur de build"  │  │  Coins inf. plats (0px)
├─────────────────────────────────────────────────────────────┤  ▼ ── Fusion sans couture
│  💬 Écrire un message à Panda Agent...             [ 📎 ] [▶] │  ▲  Coins sup. plats (0px)
│                                                             │  │  "Prompt Bar Area"
└─────────────────────────────────────────────────────────────┘  ▼  Coins inf. arrondis (16px)
```

---

## 🧩 Spécifications des 19 Composants (À l'Identique de Beautiful UI)

---

### 1. Loading State (État de Chargement Squelette)
*   **Utilité :** Placeholder d'attente animé pendant le chargement initial des historiques de chat ou des données de modèle.
*   **Spécifications Visuelles :** Lignes à bords arrondis de largeur variable, simulant des paragraphes ou des cartes de profil. Couleur de base grise (`Color(0xff2d2d2d)`) vers grise claire (`Color(0xff3d3d3d)`).
*   **Animations :** Balayage continu d'un gradient de gauche à droite (Effet Shimmer) sur une durée de `1.2s` via `Curves.easeInOut`.
*   **Code Flutter proposé (Props) :**
    ```dart
    class ShimmerLoading extends StatelessWidget {
      final double width;
      final double height;
      final BorderRadius borderRadius;
    }
    ```

---

### 2. Thinking (Indicateur de Réflexion)
*   **Utilité :** Indique le travail en arrière-plan avec affichage progressif de la pensée interne (Chine de pensées).
*   **Spécifications Visuelles :** Conteneur translucide à bordure lumineuse rotative. Un volet déroulant affiche les étapes textuelles en police monospace de taille `12`.
*   **Animations :** `SizeTransition` pour l'ouverture/fermeture du raisonnement avec `Curves.easeOutQuart`. Rotation continue du dégradé de couleur (bleu/rose/violet).
*   **Code Flutter proposé (Props) :**
    ```dart
    class ThinkingWidget extends StatefulWidget {
      final List<String> thoughts;
      final bool isExpanded;
      final Duration elapsedTime;
    }
    ```

---

### 3. Streaming Text (Texte de Révélation Temporelle)
*   **Utilité :** Animation d'apparition mot-par-mot/lettre-par-lettre haut de gamme.
*   **Spécifications Visuelles :** Les mots n'apparaissent pas de façon saccadée mais s'estompent doucement vers le haut tout en passant de transparent à opaque.
*   **Animations :** Révélation par décalage vertical (`4px` vers `0px`) et fondu d'opacité (`0.0` vers `1.0`) sur chaque lot de mots avec des délais asynchrones décalés (*Staggered animation*).
*   **Code Flutter proposé (Props) :**
    ```dart
    class StreamingTextView extends StatefulWidget {
      final String fullText;
      final Duration charSpeed;
      final TextStyle? style;
    }
    ```

---

### 4. Approval Card (Demande d'Approbation Contextuelle)
*   **Utilité :** Demander une validation explicite de l'utilisateur pour modifier un fichier ou lancer une commande terminal.
*   **Spécifications Visuelles :** Encadré à fond rouge/orange/vert discret. Deux boutons principaux contrastés. Le bouton "Confirmer" possède un effet lumineux de gradient pulsé.
*   **Animations :** Entrée par rebond (`Curves.easeOutBack`). Pulsation de mise au point.
*   **Code Flutter proposé (Props) :**
    ```dart
    class ApprovalCard extends StatelessWidget {
      final String actionTitle;
      final String actionDetails;
      final VoidCallback onApproved;
      final VoidCallback onRejected;
    }
    ```

---

### 5. Tool Chips (Opérateurs Système)
*   **Utilité :** Représentation des outils et fonctions appelés par l'agent (ex: `read_file`, `execute_command`).
*   **Spécifications Visuelles :** Puces miniatures élégantes avec fond sombre, bordure translucide fine, et petite icône rotative en cas de chargement ou coche en cas de succès.
*   **Animations :** Transition d'échelle lors de l'activation/fin de l'outil.
*   **Code Flutter proposé (Props) :**
    ```dart
    class ToolChip extends StatelessWidget {
      final String toolName;
      final String argumentSummary;
      final ToolStatus status; // { active, success, failed }
    }
    ```

---

### 6. Task Rows (Ligne de Tâches Alignées)
*   **Utilité :** Liste de sous-tâches détaillant le plan d'action de l'agent.
*   **Spécifications Visuelles :** Lignes horizontales fines, séparées, avec une icône de statut (coche, loader, sablier) alignée à gauche. Texte semi-brillant.
*   **Animations :** Glissement horizontal et fondu à l'apparition de chaque ligne l'une après l'autre.
*   **Code Flutter proposé (Props) :**
    ```dart
    class TaskRowsWidget extends StatelessWidget {
      final List<AgentTask> tasks;
    }
    ```

---

### 7. Chat (Fenêtre de Conversation)
*   **Utilité :** Conteneur de discussion principal gérant le défilement et l'empilement des bulles utilisateur et assistant.
*   **Spécifications Visuelles :** Zone de chat épurée sans barre de défilement apparente, défilement amorti par physique de rebond iOS (*BouncingScrollPhysics*).
*   **Animations :** Autoscroll fluide et progressif lors de la réception de nouvelles réponses de l'agent.
*   **Code Flutter proposé (Props) :**
    ```dart
    class ChatViewport extends StatefulWidget {
      final List<ChatMessage> messages;
      final ScrollController scrollController;
    }
    ```

---

### 8. Prompt Bar (Barre de Saisie Principale)
*   **Utilité :** Saisie textuelle de l'utilisateur avec sélecteur de fichiers contextuels intégrés.
*   **Spécifications Visuelles :** Barre ultra-clean, fond noir profond mat ou gris sombre mat, hauteur adaptative, bouton de soumission circulaire minimaliste doté d'une icône de flèche montante.
*   **Animations :** Transition d'état du bouton d'envoi (devient un bouton "Arrêter" carré lorsque l'agent génère sa réponse).
*   **Code Flutter proposé (Props) :**
    ```dart
    class PromptBar extends StatefulWidget {
      final TextEditingController controller;
      final VoidCallback onSubmitted;
      final bool isGenerating;
      final VoidCallback onCancel;
    }
    ```

---

### 9. Recommendation Card (Suggestions Rapides / Ask)
*   **Utilité :** Propose des raccourcis de prompts basés sur le contexte du projet ou les erreurs du terminal.
*   **Spécifications Visuelles :** Petites fiches horizontales réactives au survol, fond subtil, icône thématique (ex: bug, création, documentation).
*   **Animations :** Effet d'élévation et de grossissement au survol de `+2%` via un `AnimatedScale` de `0.1s`.
*   **Code Flutter proposé (Props) :**
    ```dart
    class RecommendationCard extends StatelessWidget {
      final String promptText;
      final IconData icon;
      final VoidCallback onTap;
    }
    ```

---

### 10. Context Cards (Puces d'Ancrage de Fichiers / Task)
*   **Utilité :** Indique les fichiers ou répertoires actuellement ciblés par la prochaine requête de l'utilisateur.
*   **Spécifications Visuelles :** Petites étiquettes à coins très arrondis, dotées d'un bouton de suppression rapide `x`. Positionnées juste au-dessus du champ de texte.
*   **Animations :** Suppression animée par rétraction horizontale progressive (`SizeTransition` horizontale).
*   **Code Flutter proposé (Props) :**
    ```dart
    class ContextCard extends StatelessWidget {
      final String fileName;
      final VoidCallback onRemove;
    }
    ```

---

### 11. Diff Table (Tableau de Comparaison Git)
*   **Utilité :** Visualisation des différences d'un fichier modifié.
*   **Spécifications Visuelles :** Présentation sous forme de grille compacte. Les lignes vertes reçoivent un dégradé subtil vert forêt translucide, les rouges un dégradé pourpre.
*   **Animations :** Changement de vue (mode unifié vs côte-à-côte) avec transition de fondu d'opacité.
*   **Code Flutter proposé (Props) :**
    ```dart
    class DiffTable extends StatelessWidget {
      final List<DiffLine> diffLines;
      final bool splitView;
    }
    ```

---

### 12. Records Table (Vue d'Impact des Fichiers)
*   **Utilité :** Tableau récapitulatif listant tous les fichiers modifiés, créés ou supprimés au cours de l'action de l'agent.
*   **Spécifications Visuelles :** Tableau épuré, bordures horizontales uniquement, puces de couleur pour le statut de chaque fichier (Vert = Créé, Jaune = Modifié, Rouge = Supprimé).
*   **Animations :** Révélation séquentielle des lignes du tableau.
*   **Code Flutter proposé (Props) :**
    ```dart
    class RecordsTable extends StatelessWidget {
      final List<FileRecord> records;
    }
    ```

---

### 13. Filter Table (Table interactive triable)
*   **Utilité :** Permet à l'utilisateur de trier et filtrer les variables d'environnement actives, les logs, ou les extensions disponibles.
*   **Spécifications Visuelles :** Champ de recherche discret intégré en en-tête de tableau, en-têtes de colonnes cliquables avec flèches de tri actives.
*   **Animations :** Réorganisation animée des lignes lors de l'application d'un tri.
*   **Code Flutter proposé (Props) :**
    ```dart
    class FilterTable extends StatefulWidget {
      final List<TableHeader> headers;
      final List<TableRowData> rows;
    }
    ```

---

### 14. Sidebar Nav (Menu de l'Agent)
*   **Utilité :** Navigation verticale interne à Panda Agent permettant d'alterner entre l'historique, les extensions et les configurations de l'agent.
*   **Spécifications Visuelles :** Menu fin sur la gauche avec icônes de type Outline/Broken. L'élément actif affiche une barre indicatrice lumineuse verticale collée sur son côté gauche.
*   **Animations :** Glissement fluide de l'indicateur actif d'un menu à un autre à l'aide de `AnimatedPositioned`.
*   **Code Flutter proposé (Props) :**
    ```dart
    class SidebarNav extends StatelessWidget {
      final int selectedIndex;
      final List<SidebarItem> items;
      final ValueChanged<int> onChanged;
    }
    ```

---

### 15. Search (Barre de Recherche Contextuelle)
*   **Utilité :** Filtre et recherche rapides dans l'historique des conversations ou des fichiers joints.
*   **Spécifications Visuelles :** Boîte de saisie épurée avec icône de loupe à gauche et raccourci clavier affiché de manière élégante à droite (ex: `⌘K` ou `Ctrl+K`).
*   **Animations :** Bords s'illuminant progressivement lors de la mise au point (*focus*).
*   **Code Flutter proposé (Props) :**
    ```dart
    class ContextSearch extends StatelessWidget {
      final ValueChanged<String> onQueryChanged;
      final String placeholder;
    }
    ```

---

### 16. Insight Cards (Cartes d'Analyses Métriques)
*   **Utilité :** Cartes affichant des diagnostics d'erreurs, des gains de performances de compilation ou des suggestions d'optimisations logicielles.
*   **Spécifications Visuelles :** Fonds dégradés lisses, contours adoucis, affichage de pourcentages ou de jauges en couleurs néon (Cyan / Violet).
*   **Animations :** Remplissage animé de la jauge au chargement de la carte (`TweenAnimationBuilder`).
*   **Code Flutter proposé (Props) :**
    ```dart
    class InsightCard extends StatelessWidget {
      final String title;
      final double score; // 0.0 à 1.0
      final String feedback;
    }
    ```

---

### 17. Code Block (Lecteur de Code)
*   **Utilité :** Affichage d'un bloc de code autonome généré au sein de la conversation.
*   **Spécifications Visuelles :** Coins supérieurs très arrondis, bouton "Copier" discret qui s'anime au clic. Sélection fluide du texte. Gouttière de lignes contrastée.
*   **Animations :** Transition d'état "Copier" -> "Copié !" avec un effet d'échelle rebondissant.
*   **Code Flutter proposé (Props) :**
    ```dart
    class CodeBlockWidget extends StatelessWidget {
      final String codeContent;
      final String fileExtension;
    }
    ```

---

### 18. Fine-tune Card (Configuration de l'Agent)
*   **Utilité :** Panneau d'ajustement du comportement de l'IA (choix du modèle, prompt système personnalisé, température).
*   **Spécifications Visuelles :** Curseurs à glissière personnalisés, listes déroulantes stylisées intégrées sans débordement de boîte, boutons à bascule à micro-vibrations visuelles.
*   **Animations :** Sliders de température s'animant de gauche à droite sur une courbe physique.
*   **Code Flutter proposé (Props) :**
    ```dart
    class FineTuneCard extends StatefulWidget {
      final AgentConfig currentConfig;
      final ValueChanged<AgentConfig> onConfigChanged;
    }
    ```

---

### 19. Selection Actions (Actions sur Sélection de Texte)
*   **Utilité :** Petite barre flottante d'options rapides apparaissant lorsque l'utilisateur sélectionne une portion de code dans son éditeur.
*   **Spécifications Visuelles :** Mini-barre horizontale noire semi-transparente flottante (`BackdropFilter`), dotée d'icônes d'actions rapides : "Expliquer", "Optimiser", "Créer un test".
*   **Animations :** Apparition par zoom-in amorti (`Curves.elasticOut`) pile au-dessus de la zone de sélection de texte.
*   **Code Flutter proposé (Props) :**
    ```dart
    class SelectionActionsOverlay extends StatelessWidget {
      final Offset position;
      final String selectedText;
      final Function(String action) onActionTriggered;
    }
    ```

---

## 🎨 Design System : Couleurs & Ombres "Beautiful UI"

Toutes ces classes s'appuieront sur un dictionnaire d'effets visuels stricts dans `core/theme.dart` :

```dart
// Exemple de configuration visuelle standardisée
class BeautifulUIDecorations {
  static const Color darkBg = Color(0xff0d0e12);
  static const Color cardBg = Color(0xff16171d);
  
  // Bordure irisée ou néon ultra fine pour le mode sombre
  static Border neonBorder(Color activeColor) {
    return Border.all(
      color: activeColor.withOpacity(0.15),
      width: 0.8,
    );
  }
  
  // Ombre portée diffuse style Beautiful UI
  static List<BoxShadow> softShadow() {
    return [
      BoxShadow(
        color: const Color(0xff000000).withOpacity(0.3),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
```
