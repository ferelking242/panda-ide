---
name: Panda Agent — Roadmap decisions
description: Décisions de cadrage validées pour l'implémentation du ROADMAP Panda Agent.
---

## Décisions confirmées (06/08/2026)

### Checkpoints
Stocker dans `.panda/checkpoints/` à la racine du projet — versionné par git.

### Task History
Par projet — liée au dossier ouvert (pas globale).

### Diff Viewer
Style GitHub unifié (+/- sur une seule colonne), pas split.

### Mode UI Agent
Le panel est déjà full-ouvert sur l'éditeur — pas de changement de mode par défaut nécessaire.

### Ordre d'implémentation
- Features 1 par 1, avec push git après chaque feature complète
- Ordre : du plus facile au plus complexe (voir ranking ROADMAP.md)
- Top priorité déclarée : Context window + token counter

**Why:** L'utilisateur veut un historique propre, une feature par commit, pour pouvoir rollback facilement si besoin.

**How to apply:** Avant chaque feature, lire le ROADMAP.md, implémenter uniquement la feature ciblée, tester, push. Ne jamais grouper plusieurs features en un seul commit.
