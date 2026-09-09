# 🐼 ROADMAP MAÎTRESSE : Feuille de Route Panda IDE (2026 - 2027)

> **Vision** : Faire de Panda IDE le premier environnement de développement mobile-first et hybride au monde, combinant l'ergonomie et la puissance de VS Code avec une architecture d'Agents IA autonome et légère.

---

## 🎯 Axes Stratégiques Majeurs

```
+-----------------------------------------------------------------------------------+
|                            PANDA IDE ARCHITECTURE 2.0                             |
+-----------------------------------------------------------------------------------+
|  1. VS Code Core Parity   |  2. Agentic AI & Copilot   |  3. Mobile-First UX  |
|  - Multi-Root Workspaces  |  - Ghost Text (Inline)     |  - Adaptive Layouts  |
|  - Virtual File System    |  - Workspace Indexer RAG   |  - Touch Gestures    |
|  - LSP / DAP / TreeSitter |  - MCP Tool Calling        |  - Quick Action Bar  |
|  - SCM Gutter & Diff      |  - Checkpoint & Rollback   |  - Termux / PTY      |
+-----------------------------------------------------------------------------------+
```

---

## 🗺️ Roadmap Étape par Étape

### Phase 1 : Consolidation du Cœur Éditeur & Espaces de Travail (Q3 2026)
- [ ] **Système de Fichiers Virtuel (`PandaFileSystemProvider`)** :
  - Abstraire l'accès aux fichiers derrière une API d'URI polymorphe (`file://`, `memory://`, `github://`, `saf://`).
  - Résoudre définitivement les limitations de permissions Android SAF et assurer une compatibilité 100% web.
- [ ] **Multi-Root Workspaces (`.panda-workspace`)** :
  - Permettre l'ouverture simultanée de plusieurs répertoires racines dans l'arbre de projet.
  - Sauvegarder la disposition des onglets, l'état d'expansion de l'arborescence et les sous-panneaux.
- [ ] **Surlignage & Navigation Avancée dans l'Éditeur** :
  - Intégrer les indicateurs de modification Git dans la marge (*Gutter Indicators*).
  - Ajouter les chemins de symboles dans l'en-tête (*Breadcrumbs* : `lib > src > app.dart`).
  - Ajouter la recherche globale optimisée avec filtres d'inclusion et d'exclusion.

---

### Phase 2 : Copilot Inline Text & Agent IA Avancé (Q4 2026)
- [ ] **Moteur d'Autocomplétion Ghost Text (Inline Completion API)** :
  - Intégrer un moteur de prédiction en filigrane ultra-rapide (<100ms) déclenché à la frappe.
  - Utiliser la proximité AST et les onglets ouverts pour enrichir le prompt contextuel.
- [ ] **Indexation Sémantique Locale (Workspace RAG & AST Indexer)** :
  - Indexer les classes, méthodes, variables et commentaires du workspace dans une base vectorielle ou un index SQLite léger embarqué.
  - Offrir à l'Agent Panda une connaissance à 360° du projet sans surcharger les tokens.
- [ ] **Checkpoints & Reversion Sécurisée (Agent Safety Protocol)** :
  - Créer des instantanés automatiques (checkpoints Git ou copies d'état) avant chaque modification de code par l'Agent.
  - Interface visuelle de rollback à un clic si les modifications ne conviennent pas.
- [ ] **Amélioration du Protocole MCP (Model Context Protocol)** :
  - Étendre le catalogue d'outils disponibles pour l'Agent (Terminal, Git, Recherche Web, Tests unitaires, Compilation).

---

### Phase 3 : Écosystème d'Extensions & Isolation WebWorker/Processus (Q1 2027)
- [ ] **Extension Host Isolé** :
  - Exécuter les extensions dans un WebWorker isolé (Web) ou dans un processus Isolate/Service distinct (Android).
  - Prévenir tout gel de l'IHM principale en cas d'erreur dans une extension.
- [ ] **Intégration Complète d'Open VSX Marketplace** :
  - Explorer, installer, désactiver et mettre à jour des extensions VSIX directement depuis l'interface de Panda IDE.
- [ ] **Moteur LSP & DAP Générique** :
  - Permettre le raccordement de serveurs de langage (Language Servers pour Python, Rust, JavaScript, Flutter/Dart) via WebSockets ou PTY.

---

### Phase 4 : Expérience Mobile Multi-Écran & Synchronisation Cloud (Q2 2027)
- [ ] **Mode Passerelle & Server Remote (`Panda Gateway`)** :
  - Permettre à Panda IDE exécuté sur Android d'exposer une session web sécurisée pour continuer à coder depuis un PC ou une tablette.
  - Reconnexion automatique avec persistance de session PTY terminal.
- [ ] **Visualiseur Diff Côte-à-Côte & Interface SCM Enrichie** :
  - Interface tactile de comparaison de branches et de résolutions de conflits de fusion (Merge Conflicts).
- [ ] **Optimisation Ergonomique Mobile-First** :
  - Clavier de raccourcis personnalisable pour développeurs sur écran tactile.
  - Support natif des stylets, souris et claviers physiques (Samsung DeX, tablettes Android).

---

## 📊 Indicateurs de Succès (KPIs)

1. **Temps de Réponse Autocomplétion (Ghost Text)** : < 120ms.
2. **Temps de Démarrage Cold Start Mobile** : < 1.5 seconde.
3. **Stabilité de l'Agent IA** : 0 crash du fil principal lors de l'exécution de boucles de modification complexes.
4. **Taux d'Acceptation des Modifs Agent** : > 85% d'acceptation par l'utilisateur.
