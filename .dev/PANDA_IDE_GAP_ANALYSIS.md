# Audit Complet & Analyse des Lacunes : Panda IDE vs VS Code

## 1. Diagnostics Globaux de Panda IDE

Panda IDE a franchi de grandes étapes dans son développement en devenant un éditeur de code mobile-first ambitieux avec support Flutter/Dart, terminal, extensions et agent IA. Cependant, une analyse comparative approfondie avec l'écosystème VS Code révèle plusieurs axes majeurs d'amélioration et de fonctionnalités manquantes.

---

## 2. Analyse Comparative par Domaine

### A. Gestion du Workspace (Workspace Management)
- **Lacunes Actuelles dans Panda IDE**:
  - Support d'un **seul dossier racine unique** à la fois (`workspacePath`). Impossible d'ouvrir des espaces multi-dossiers (*Multi-root workspaces* `.code-workspace`).
  - Absence de fichier de configuration de projet d'espace de travail (`.panda-workspace` ou `.vscode/settings.json`) pour harmoniser les paramètres d'équipe ou de projet.
  - Sauvegarde limitée de la session (onglets ouverts restaurés de manière élémentaire, pas de mémorisation de l'état des sous-dossiers dépliés ou de la disposition des fenêtres fractionnées).
- **Standards VS Code**:
  - Prise en charge transparente des espaces multi-racines avec paramètres de dossier locaux.
  - Persistance granulaire de la session (état d'expansion de l'arbre de fichiers, curseurs actifs, historique d'annulation).

---

### B. Système de Fichiers & Stockage (`FileSystemProvider`)
- **Lacunes Actuelles dans Panda IDE**:
  - Dépendance forte au système de fichiers physique Android local ou à des abstractions web rudimentaires (`_virtualContentMap`).
  - Absence d'un fournisseur unifié d'URI (`file://`, `github://`, `s3://`, `ssh://`).
  - Gestion fragile des permissions Android SAF (*Storage Access Framework*) et All Files Access lors des basculements d'applications.
- **Standards VS Code**:
  - API polymorphe `vscode.workspace.fs` gérant nativement des systèmes de fichiers locaux, mémoire, virtuels et distants.

---

### C. Moteur d'Édition & Expérience Éditeur (Code Editor Engine)
- **Lacunes Actuelles dans Panda IDE**:
  - Absences notables de fonctionnalités avancées de code :
    - Pas de **Minimap** (carte thermique visuelle du code).
    - Support partiel du **Breadcrumb** (chemin de navigation de symboles `src > main > app.dart > class App`).
    - Pliage de code (*Code Folding*) basique ou dépendant de regex simples.
    - Pas de recherche globale multi-fichiers optimisée avec filtres de répertoires d'exclusion (`node_modules`, `.git`, `build`).
    - Absence de surlignage des paires de crochets arc-en-ciel (*Rainbow Bracket Pair Colorization*).
- **Standards VS Code**:
  - Buffer Piece Table haute performance.
  - Sémantique complète Tree-sitter / LSP pour le formatage, le refactoring et le diagnostic d'erreurs en temps réel.

---

### D. Système de Terminal & Exécution (`Terminal & Shell`)
- **Lacunes Actuelles dans Panda IDE**:
  - Intégration partielle de PTY natif Android (Shizuku, ADB, Termux).
  - Comportement parfois instable lors de la réorientation de l'écran ou de l'arrière-plan Android.
  - Absence de multiplexage d'onglets de terminaux multiples (un seul terminal actif).
- **Standards VS Code**:
  - Multi-terminaux concurrents, split de terminal, profils configurables (Bash, Zsh, Node.js REPL), persistance de session PTY.

---

### E. Intégration IA & Moteur Agentic (`Panda Agent / Copilot / MCP`)
- **Points Forts Actuels**:
  - Panda Agent intègre déjà la sélection de modèles (Gemini, Ollama, Llama.cpp), le protocole MCP, et la gestion d'approbation d'outils.
- **Lacunes à Combler**:
  - **Inline Completion (Ghost Text)**: Absence de suggestions automatiques en filigrane directement pendant la frappe dans l'éditeur.
  - **Indexation Sémantique & Vectorielle du Workspace (RAG)**: Pas d'indexation locale automatique des déclarations de classes et méthodes du projet pour nourrir le contexte de l'agent.
  - **Gestion des Checkpoints & Rollback**: Manque d'un système de *git tree checkpoint* automatique permettant à l'utilisateur de restaurer le projet en un clic si l'agent fait une erreur.

---

### F. Système d'Extensions & Écosystème (`Open VSX / VSIX`)
- **Lacunes Actuelles dans Panda IDE**:
  - Le système d'extensions est en cours de structuration.
  - Absence d'un **Extension Host Worker** complètement isolé pour exécuter le code des extensions Tierce Partie en sécurité sans faire planter l'application mobile.
  - Registre Open VSX connecté mais nécessitant un meilleur gestionnaire de dépendances VSIX et de mises à jour.

---

### G. Contrôle de Source & Git (`SCM`)
- **Lacunes Actuelles dans Panda IDE**:
  - Support Git basé sur des commandes basiques.
  - Absence d'un visualiseur de **Gutter Indicators** (lignes vertes/rouges/bleues dans la marge pour voir les ajouts/suppressions en temps réel).
  - Absence d'une vue de **Diff côte-à-côte** interactive pour comparer les révisions avant commit.
