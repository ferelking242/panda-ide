# Panda IDE — Refonte des Paramètres

> **Inventaire complet + architecture proposée** inspirée de VS Code  
> Généré le 30/07/2026

---

## 📊 État actuel (5 sections plates)

```
Settings (5 948 lignes, tout dans un seul ListView)
├── General          → 1 option
├── Appearance       → 8 options  (+ dialogue thème custom très long)
├── Remote host and Termux  → ~15 options
├── AI Configuration → ~12 options
└── LSP Configuration → 2 options
```

Problèmes : tout est dans un seul `ListView`, sections non navigables, pas de sous-pages, design incohérent, pas d'icônes de section, longueur ingérable sur mobile.

---

## 🏗️ Architecture proposée (VS Code–style)

```
Settings
│
├── 🌐  Général
│   ├── Éditeur
│   │   ├── Auto Save                       (toggle)
│   │   ├── Taille de police               (slider 10–24 px)      ← nouveau
│   │   ├── Tabulation — espaces / tabs    (segmented)            ← nouveau
│   │   └── Taille d'indentation           (dropdown 2/4/8)       ← nouveau
│   ├── Fichiers
│   │   ├── Encodage par défaut            (dropdown UTF-8…)      ← nouveau
│   │   └── Fin de ligne                   (LF / CRLF / auto)    ← nouveau
│   └── Performance
│       └── Debounce completion (ms)       (slider)               ← nouveau
│
├── 🎨  Apparence
│   ├── Thème de l'application
│   │   ├── Thème clair / sombre            (toggle)
│   │   └── Suivre le système               (toggle)              ← nouveau
│   ├── Thème de l'éditeur
│   │   ├── Choisir un thème                (grille preview)
│   │   └── Créer un thème personnalisé     (sous-page →)
│   │       ├── Nom du thème                (text field)
│   │       ├── Couleur de fond             (color picker)
│   │       ├── Couleur de texte            (color picker)
│   │       └── Jetons syntaxiques          (liste expandable)
│   │           ├── [token]  couleur        (color picker)
│   │           ├── [token]  graisse        (dropdown Bold/Normal)
│   │           └── [token]  style          (dropdown Italic/Normal)
│   ├── Police de l'éditeur
│   │   ├── Famille de police               (grille preview)
│   │   ├── Ligature                        (toggle)              ← nouveau
│   │   └── Crénage                         (toggle)              ← nouveau
│   ├── Mise en page de l'éditeur
│   │   ├── Repères d'indentation           (toggle)
│   │   ├── Retour à la ligne               (toggle)
│   │   ├── Repliage du code                (toggle)
│   │   ├── Numéros de ligne                (toggle)              ← nouveau
│   │   ├── Règle de colonne               (toggle + valeur)     ← nouveau
│   │   └── Minimap                         (toggle)              ← nouveau
│   └── Terminal
│       ├── Thème du terminal               (grille preview)
│       ├── Police du terminal              (dropdown)            ← nouveau
│       └── Taille de police terminal       (slider)              ← nouveau
│
├── 🤖  Intelligence artificielle
│   ├── Modèles configurés
│   │   ├── [liste des modèles]             (cards avec Edit / Suppr)
│   │   ├── ＋ Ajouter un modèle            (sous-page →)
│   │   │   ├── Fournisseur                 (dropdown)
│   │   │   │   ├── Gemini
│   │   │   │   ├── OpenAI
│   │   │   │   ├── Claude / Anthropic
│   │   │   │   ├── Grok
│   │   │   │   ├── DeepSeek
│   │   │   │   ├── TogetherAI
│   │   │   │   ├── Perplexity
│   │   │   │   ├── OpenRouter
│   │   │   │   ├── FireWorks
│   │   │   │   ├── Custom (endpoint libre)
│   │   │   │   └── LocalLlama (GGUF)
│   │   │   ├── Identifiant API du modèle   (text field)
│   │   │   ├── Clé API                     (password field)
│   │   │   ├── [si Custom] URL endpoint    (text field)
│   │   │   ├── [si Custom] Méthode HTTP    (POST / GET)
│   │   │   ├── [si Custom] Protocole outils (dropdown)
│   │   │   │   ├── OpenAI-compatible
│   │   │   │   ├── Anthropic Messages
│   │   │   │   ├── Gemini Function Calling
│   │   │   │   └── Aucun
│   │   │   └── Surnom (optionnel)          (text field)
│   │   └── Modèles locaux (GGUF)           (sous-page →)
│   │       ├── Télécharger un modèle GGUF  (liste catalogue)
│   │       │   ├── Qwen2.5-Coder-3B
│   │       │   ├── Phi-3.5-mini
│   │       │   ├── Gemma-3-1B
│   │       │   ├── CodeLlama-7B
│   │       │   └── … (autres modèles)
│   │       └── Charger un fichier .gguf    (file picker)
│   ├── Complétion de code
│   │   ├── Activer la complétion IA        (toggle maître)
│   │   ├── Mode de complétion              (Auto / Manuel)
│   │   ├── Modèle de complétion            (selector)
│   │   └── Délai de déclenchement (ms)     (slider 500–3000)    ← nouveau
│   ├── Agent Panda
│   │   ├── Modèle de l'agent par défaut    (selector)           ← nouveau
│   │   ├── Longueur max du contexte        (slider)             ← nouveau
│   │   └── Prompt système personnalisé     (text area)          ← nouveau
│   └── GitHub Copilot
│       ├── Se connecter à GitHub Copilot   (bouton OAuth)
│       ├── Activer Copilot                 (toggle)
│       └── Se déconnecter                  (bouton)
│
├── 🖥️  Remote & Terminal
│   ├── Connexions SSH
│   │   ├── Mode de connexion               (Login / Clé privée)
│   │   ├── Hôtes enregistrés               (liste cards)
│   │   │   └── [par hôte] Nom, URL, Type, Connecter/Éditer/Suppr
│   │   └── Ajouter un hôte                 (sous-page →)
│   │       ├── Nom du serveur              (text field)
│   │       ├── URL SSH (ssh://user@host)   (text field + validation)
│   │       ├── [Login] Mot de passe        (password field)
│   │       └── [Clé] Générer / Régénérer   (bouton + avertissement)
│   ├── Clés SSH
│   │   ├── Générer une paire de clés       (bouton)
│   │   ├── Clé publique                    (affichage + copier)  ← nouveau
│   │   └── Régénérer (révoque les accès)   (bouton danger)
│   └── Termux
│       ├── Configuration initiale          (guide pas-à-pas)
│       ├── Nom d'utilisateur Termux        (text field)
│       └── Se connecter à Termux           (bouton)
│
└── 🔌  Langages & LSP
    ├── Activer le support LSP              (toggle maître)
    ├── Langages supportés                  (info — liste)       ← nouveau
    └── Fonctionnalités par langage         (sous-page →)
        └── [par langage] section expandable
            ├── Mise en évidence sémantique (checkbox)
            ├── Complétion de code          (checkbox)
            ├── Info-bulles (hover)         (checkbox)
            ├── Actions de code             (checkbox)
            ├── Aide à la signature         (checkbox)
            ├── Couleur de document         (checkbox)
            ├── Surbrillance du symbole     (checkbox)
            ├── Repliage de code (LSP)      (checkbox)
            ├── Indicateurs incrustés       (checkbox)
            ├── Aller à la définition       (checkbox)
            └── Renommer un symbole         (checkbox)
```

---

## 🎨 Design proposé — layout VS Code

### Navigation (gauche, 56 px de large)
```
┌──────────────────────────────────────────────────────────┐
│ ⚙  Paramètres                                            │
├──────┬───────────────────────────────────────────────────┤
│  🌐  │  ▶  Général                                       │
│  🎨  │     ├─ Éditeur                                    │
│  🤖  │     ├─ Fichiers                                   │
│  🖥️  │     └─ Performance                               │
│  🔌  │                                                   │
│      │  [ Contenu de la sous-section sélectionnée ]     │
│      │                                                   │
└──────┴───────────────────────────────────────────────────┘
```

Sur **mobile** (< 600 px) : navigation plein écran liste → pousse sous-page.  
Sur **tablette / desktop** (≥ 600 px) : panneau latéral fixe + contenu côte à côte.

### Composants UI à utiliser (packages déjà présents)

| Composant | Package | Usage |
|---|---|---|
| Section header | custom `settingsType()` → améliorer | Titres de groupe |
| Toggle | `FlutterSwitch` → `Switch.adaptive` | Tous les on/off |
| Color picker | `flutter_colorpicker` ✓ | Thème custom |
| Icons sections | `font_awesome_flutter` ✓ + Broken ✓ | Icônes nav |
| Slider | `Slider` Material | Font size, debounce |
| Dropdown | `DropdownButtonFormField` | Provider, encodage |
| File picker | `file_picker` ✓ | GGUF, clés |
| Segmented | `SegmentedButton` M3 | Mode connexion, LF/CRLF |
| Search bar | `SearchBar` M3 | Filtre de thèmes/fonts |
| Chip | `FilterChip` | Tags de langages |
| ExpansionTile | `ExpansionTile` | Per-language LSP |
| Breadcrumb | custom `Row + Icon` | Sous-navigation |
| Card | `Card` M3 + `ListTile` | Cards de modèles/hôtes |
| Snackbar | `ScaffoldMessenger` | Confirmations |
| Danger button | `OutlinedButton` rouge | Régénérer clé, supprimer |

### Tokens de couleurs à garder cohérents avec l'éditeur

```dart
// Dans _SettingsState ou via AppTheme
final sectionHeaderColor  = isDark ? Color(0xffbbbbbb) : Color(0xff444444);
final cardBg              = isDark ? Color(0xff2d2d2d) : Color(0xfff5f5f5);
final cardBorder          = isDark ? Color(0xff3a3a3a) : Color(0xffdddddd);
final accentColor         = Color(0xff007ACC);   // bleu VS Code
final dangerColor         = Color(0xffF44747);   // rouge erreurs VS Code
final sectionDivider      = isDark ? Color(0xff3c3c3c) : Color(0xffe0e0e0);
```

---

## 📋 Plan d'implémentation (ordre recommandé)

### Phase 1 — Navigation & scaffold (1 session)
- [ ] Refactoriser `Settings` pour afficher un `Row` (sidebar + contenu)
- [ ] Créer widget `_SettingsSidebar` avec 5 icônes navigables
- [ ] Créer widget `_SettingsContentArea` avec `AnimatedSwitcher`
- [ ] Responsive : `LayoutBuilder` → sidebar fixe ≥ 600 px / push mobile

### Phase 2 — Général + Apparence (1 session)
- [ ] Implémenter sous-section **Éditeur** avec les nouveaux contrôles (taille police, tabulation)
- [ ] Implémenter sous-section **Terminal** avec font + size slider
- [ ] Améliorer la grille de thèmes (preview card, filtre de recherche déjà là)
- [ ] Améliorer la grille de fonts

### Phase 3 — IA (1 session)
- [ ] Refaire la liste de modèles en **cards** avec avatar icône fournisseur
- [ ] Sous-page **Ajouter un modèle** avec stepper (fournisseur → credentials → test)
- [ ] Sous-page **Modèles locaux GGUF** séparée
- [ ] Section **Agent Panda** avec prompt système + modèle par défaut

### Phase 4 — Remote & LSP (1 session)
- [ ] Refaire la liste d'hôtes en cards avec statut connecté / déconnecté
- [ ] Clés SSH : afficher clé publique avec bouton copier
- [ ] LSP : remplacer le dialogue par un `ExpansionTile` inline

### Phase 5 — Polish (1 session)
- [ ] Breadcrumb de navigation (ex. : *Apparence › Éditeur*)
- [ ] Champ de recherche global dans les paramètres
- [ ] Animations de transition entre sections
- [ ] Test responsive sur toutes les tailles d'écran

---

## 🗂️ Structure de fichiers suggérée

```
lib/ui/settings/
├── settings_page.dart          ← widget racine + router
├── settings_sidebar.dart       ← navigation icônes
├── sections/
│   ├── general_section.dart
│   ├── appearance_section.dart
│   │   ├── theme_picker.dart
│   │   ├── custom_theme_editor.dart
│   │   └── font_picker.dart
│   ├── ai_section.dart
│   │   ├── model_card.dart
│   │   ├── add_model_page.dart
│   │   └── gguf_section.dart
│   ├── remote_section.dart
│   │   ├── ssh_host_card.dart
│   │   └── termux_section.dart
│   └── lsp_section.dart
└── widgets/
    ├── settings_tile.dart       ← tile réutilisable amélioré
    ├── settings_section.dart    ← header + divider
    ├── settings_switch.dart     ← switch adaptatif
    ├── settings_dropdown.dart
    └── settings_search_bar.dart
```

---

## 🔑 Nouvelles options à ajouter (absentes aujourd'hui)

| Option | Section | Impact |
|---|---|---|
| Taille de police (slider) | Apparence › Éditeur | Confort lecture |
| Numéros de ligne | Apparence › Éditeur | Standard IDE |
| Règle de colonne (80/120) | Apparence › Éditeur | Clean code |
| Suivi du thème système | Apparence | UX moderne |
| Ligatures de police | Apparence › Police | Fira Code etc. |
| Police terminal | Apparence › Terminal | Confort terminal |
| Encodage fichiers | Général › Fichiers | Compatibilité |
| Fin de ligne LF/CRLF | Général › Fichiers | Cross-platform |
| Prompt système agent | IA › Agent Panda | Personnalisation |
| Modèle agent par défaut | IA › Agent Panda | UX agent |
| Contexte max agent | IA › Agent Panda | Perf/coût |
| Délai completion (ms) | IA › Complétion | Perf |
| Afficher clé publique SSH | Remote › Clés SSH | DevOps |
| Langages LSP supportés | Langages | Info utilisateur |

---

## 📦 Packages supplémentaires optionnels

| Package | Usage | Taille |
|---|---|---|
| `flutter_animate` | Animations fluides entre sections | ~50 KB |
| `grouped_list` | Listes groupées par catégorie | ~20 KB |
| `two_dimensional_scrollables` | Table de tokens thème custom | ~30 KB |

> Les packages existants (`flutter_colorpicker`, `font_awesome_flutter`, `file_picker`, `shared_preferences`, `xterm`, `re_highlight`) couvrent déjà l'essentiel. Les ajouts sont optionnels.
