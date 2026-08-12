# Panda IDE — Plan Workspace & Analyse Complète

> Généré le : 2026-08-06  
> Basé sur HEAD `9137da0` — analyse du code source complet  
> Ce document reprend là où l'agent précédent s'est arrêté (quota épuisé à mi-analyse).

---

## 1. État actuel du projet (ce qui fonctionne)

### Architecture générale
- **Flutter multi-plateforme** (Android/iOS/Web) — cible principale : Android ARM64
- **BLoC architecture** : `UiBloc` (état central), `RepoStatusBloc` (git), `ActiveEditorBloc`, `ChatSessionBloc`, `CopilotBloc`, `LocalLlamaBloc`
- **Éditeur** : `CodeForge` (éditeur de code natif Flutter, ex-CodeEditor)
- **Terminal** : `flutter_pty` + sessions multiples, support proot/Alpine/Android SDK
- **LSP** : Language Server Protocol pour Dart, Go, Python, C/C++, Bash, Java, Lua, Copilot, etc.
- **Extension Host** : Runtime Node.js embarqué, API vscode.* complète (phases 1–15 ✅)
- **Agent IA** : `AgentRunner` — Gemini, OpenAI, Anthropic, Copilot, Local Llama

### Features implémentées et fonctionnelles

#### UI principale (home.dart — 8 525 lignes)
| Feature | État |
|---------|------|
| Tabs d'éditeur (open/close/split) | ✅ Fonctionnel |
| Sidebar 11 rails (explorer, search, git, run/debug, tunnel, marketplace, copilot, gateway, browser, agent, local models) | ✅ Rails présents |
| Status bar (branche git cliquable, nom workspace, warnings/problems) | ✅ Fonctionnel depuis 8693da5 |
| Branch picker (switch branche local/remote) | ✅ Fonctionnel |
| File explorer avec `DirectoryTreeViewerCustom` | ✅ Persistant entre tabs |
| Workspace persistence (`_currentWorkspaceDir`) | ✅ Conservé lors du changement de tab |
| Terminal embarqué (`projectDir: _currentWorkspaceDir ?? '/'`) | ✅ Fixé |
| Panneau bottom (Terminal/Problems/Output/Debug) | ✅ Structuré (Problems/Output/Debug = stubs) |
| Split editor | ✅ Présent (pb de sync voir §3) |
| Agent panel complet (chat, sessions, modèles, outils) | ✅ Majoritairement fonctionnel |
| Browser panel | ✅ Flutter_inappwebview |
| Gateway panel | ✅ Gateway manager |

#### Git / SourceControl (widgets.dart — SourceControl à partir de ligne 4074)
| Feature | État |
|---------|------|
| Staged/Unstaged file lists | ✅ Réel, wired RepoStatusBloc |
| Stage / Unstage individual + all | ✅ `stageChange`, `stageAll`, `unstageChange`, `unstageAll` |
| Discard/Restore file | ✅ `gitRestoreFile` |
| Diff view (via callback `onOpenDiffView`) | ✅ |
| Commit (message + AI generation) | ✅ `gitCommit` + Gemini prompt |
| Commit + Push / Sync | ✅ `_handleCommit` + `_performPush` |
| Push standalone | ✅ `gitPush` |
| Pull + conflict dialog | ✅ `gitPull` |
| Fetch / Sync | ✅ `gitFetch`, `gitSync` |
| Commit History graph (collapsible) | ✅ `_buildCollapsibleCommitGraph` — hash, parents, author, message |
| Branch create/checkout/rename/delete/publish | ✅ Dialog + `gitCheckoutBranch`, etc. |
| Merge / Rebase | ✅ `gitMerge`, `gitRebase` |
| Stash (create/pop/apply/drop/list) | ✅ |
| Tags | ✅ |
| Remotes | ✅ |

#### Extension Host (phases 1–15 complètes)
| Phase | Contenu | État |
|-------|---------|------|
| 1 | Foundation IPC + models | ✅ |
| 2 | vscode.window API | ✅ |
| 3 | vscode.workspace API | ✅ |
| 4 | vscode.languages API | ✅ |
| 5 | vscode.commands + CommandPalette | ✅ |
| 6 | vscode.extensions | ✅ |
| 7 | vscode.env (clipboard, openExternal) | ✅ |
| 8 | Open VSX Marketplace UI | ✅ |
| 9 | WebView Panels | ✅ |
| 10 | vscode.scm | ✅ |
| 11 | vscode.tasks | ✅ |
| 12 | vscode.debug (DAP) | ✅ |
| 13 | Contributes statiques (themes, snippets, grammars, icons) | ✅ |
| 14 | Extension Settings UI | ✅ |
| 15 | CI/CD + Tests Jest | ✅ |
| Wiring main.dart | ExtensionHostSetup.init() | ✅ |

#### Local AI Marketplace (phases P1–P4 complètes)
| Phase | Contenu | État |
|-------|---------|------|
| P1 | Models + DeviceProfiler + CatalogService + ModelDownloadManager | ✅ |
| P2 | LocalModelDetailPage + recommandations | ✅ |
| P3 | InferenceConfigService + ModelActivationService | ✅ |
| P4 | LRU Cache + ModelSelectorService + Notifications Android + 50 modèles | ✅ |

---

## 2. Bugs confirmés (HEAD 9137da0)

### 🔴 Critiques — Cassent une feature visible

#### B1. `buildWhen` trop restrictif dans editor_page.dart:2035
```dart
// Actuel (ligne 2035-2037) — NE PAS LAISSER
buildWhen: (p, c) => p.activeEditors.length != c.activeEditors.length,
```
**Impact** : changer l'onglet actif, modifier le titre, marquer "dirty" ne provoque aucun rebuild UI de l'éditeur. L'onglet semble figé.  
**Fix** : comparer aussi `activeEditorIndex`, `activeEditors[i].isDirty`, `activeEditors[i].title`.

#### B2. `_ProblemsPanel` toujours vide (home.dart:8478)
```dart
final isEmpty = true; // TODO: wire to real diagnostics
```
**Impact** : le panneau "Problèmes" affiche toujours "No problems detected" même avec des erreurs LSP réelles.  
**Fix** : brancher sur les diagnostics LSP du `LanguageFeatureRouter` ou d'un `DiagnosticsBloc`.

#### B3. Rails sidebar sans titre (home.dart:1629-1637)
Les rails 7 (Gateway), 8 (Browser), 10 (Agent), 11 (Local Models) sont absents de la map des titres → la barre de titre de la sidebar est vide quand ces panels sont ouverts.  
**Fix** : ajouter les 4 entrées manquantes dans la map.

#### B4. Split editor non synchronisé avec `ActiveEditorBloc`
Les instances `EditorPage` dans la vue split sont créées indépendamment. L'onglet actif, dirty-tracking et sauvegarde ne sont pas partagés entre les deux volets.  
**Fix** : partager l'`ActiveEditorBloc` parent, utiliser le même état.

#### B5. `CloseActiveEditor` ne dispose pas les ressources
La fermeture d'un onglet ne libère pas les `CodeForgeController`, `ScrollController` et listeners LSP.  
**Fix** : appeler `dispose()` sur les controllers dans le handler.

### 🟠 Importants — Features incomplètes

#### B6. Panneau Output et Debug Console — stubs permanents
Texte placeholder, non branché sur aucun flux réel (process stdout, debug adapter).

#### B7. `_allowImmediatePop` jamais réinitialisé (editor_page.dart)
Après un pop forcé, reste `true` — la prochaine navigation permettrait de quitter sans confirmation même avec fichiers non sauvegardés.

#### B8. Commit history sans date
`getGraph()` parse `%H%x01%P%x01%an%x01%s` — pas de `%ad` (author date). Le graphe de commits n'affiche pas la date.  
**Fix** : ajouter `%x01%ad` au format et parser le champ dans `GitCommitGraph`.

#### B9. `ChatSessionBloc._onSelectSession` — `firstWhere` sans `orElse`
Lève une exception `StateError` si l'ID de session est invalide/corrompu.  
**Fix** : ajouter `orElse: () => state.sessions.first`.

#### B10. Fonctions git ignorent les exit codes subprocess
`stageChange`, `unstageAll`, `gitRestoreFile`, `getGitDiff`, `gitStashShow` ne vérifient pas le code de retour du processus. Les erreurs git sont silencieuses.  
**Fix** : vérifier `result.exitCode != 0` et propager l'erreur.

#### B11. `_shouldUseTools` mort dans `agent_runner.dart:949`
La méthode analyse le message pour décider si les outils doivent être injectés, mais n'est jamais appelée par `_run`. Les outils sont toujours injectés.  
**Fix** : appeler `_shouldUseTools()` dans `_run` avant d'injecter les tools.

#### B12. Approval mode agent non appliqué
Le paramètre "Approval mode" (bypass/autopilot/default) visible dans l'UI n'est pas passé à `AgentRunner`. Les approbations sont ignorées.

#### B13. Race condition client/cancel dans `agent_runner.dart:391`
Un `_client` mutable partagé entre runs : un `cancel()` peut interrompre le run suivant si deux requêtes se chevauchent.

#### B14. Gemini function-call IDs incohérents (agent_runner.dart:475-485)
Appels répétés au même outil peuvent avoir des IDs synthétisés incohérents, cassant le matching outil↔résultat.

#### B15. Local Llama mode dans AgentRunner — `"unsupported mode"`
`agent_runner.dart:371` retourne toujours une erreur pour le mode local. Le modèle local ne peut pas être utilisé comme agent.

### 🟡 Qualité / Technique

#### B16. `withOpacity` déprécié — massivement utilisé
`home.dart`, `editor_page.dart`, `widgets.dart` → des centaines d'occurrences. Flutter 3.27+ impose `withValues(alpha:)`.  
**Fix** : remplacement global.

#### B17. `createFile` (functions.dart) — web swallows errors + path traversal
Sur web, supprime les erreurs silencieusement et retourne un `File` même si la création a échoué. Pas de validation du nom (`../` traversal possible).

#### B18. `pickDir` — null sur toutes plates-formes sauf Android
Pas de fallback `file_picker` pour desktop/web.

#### B19. `DownloadPortBloc` — ne supprime pas le mapping existant avant register
Plusieurs instances peuvent perdre des événements de téléchargement.

#### B20. Fond du panneau bottom non redimensionnable
Hauteur fixe `220px` (home.dart:2834), ni redimensionnable par l'utilisateur ni persistée.

#### B21. Localisation mixte français/anglais
Messages utilisateur mélangent les deux langues sans système i18n.

#### B22. `normalizeRecentEntry` dupliqué
Défini à la fois dans `_SelectTypeState` (home.dart) et `_EditorPageState` (editor_page.dart). Devrait être une fonction utilitaire commune dans `functions.dart`.

#### B23. Extension lookup case-sensitive
`language.extension.contains(ext)` est sensible à la casse — `.Dart`, `.PY` tombent sur Plaintext.

#### B24. Vite preview URL hardcodée `localhost` (editor_page.dart:304)
Sur Android, `localhost` ne fonctionne pas dans WebView. Devrait utiliser `127.0.0.1` ou l'IP réelle.

#### B25. Détection Git trop naïve (home.dart:1934)
Vérifie uniquement `.git/` — échoue pour les worktrees git, submodules, et dépôts bare.

---

## 3. Features manquantes / Boutons non-op

| Feature | Localisation | État actuel |
|---------|-------------|-------------|
| Microphone dans le chat agent | home.dart:3691 | Stub — popup "bientôt disponible" |
| Bouton "+ Agent" | home.dart:3865 | Handler vide |
| Sessions agent persistées | home.dart:4555 | Mémoire seulement — non persistées |
| Double-création de session agent | home.dart:6163-6214 | `UpdateCurrentSession` + `CreateNewSession` peuvent dupliquer |
| Titre généré automatiquement de session | — | Jamais envoyé via `UpdateSessionTitle` |
| Boutons Back/Forward navigation | home.dart:2593, 2632 | No-ops |
| "Collapse All" et "More Actions" dans Problems | home.dart:2931, 2951 | No-ops |
| "View documentation" dans onboarding | home.dart:4687 | Handler vide |
| Code Editing settings | home.dart:4380-4397 | "Coming soon" — toggles ne persistent rien |
| Advanced Developer Settings | home.dart:4380-4397 | "Coming soon" |
| Panneau Output | bottom panel tab 2 | Placeholder texte statique |
| Panneau Debug Console | bottom panel tab 3 | Placeholder texte statique |
| Diagnostics LSP dans Problems | _ProblemsPanel | Toujours vide (B2) |
| Date dans commit history | GitCommitGraph | Non parsée (B8) |
| Panneau bottom redimensionnable | home.dart:2834 | Hauteur fixe 220px (B20) |

---

## 4. Ce que l'agent précédent avait fait (résumé)

### Session 1 — Analyse (commit antérieur à 8693da5)
- Analyse complète de ~40 problèmes dans le codebase
- Aucun code écrit

### Session 2 — Corrections (commit `8693da5`)
Commit "fix: workspace persistence, git panel wiring, status bar branch picker, terminal path, closeTab workspace cleanup, AnimationStatus syntax"

**Confirmé réellement fixé :**
- ✅ `AnimationStatus.dismissed` syntax (editor_page.dart:70)
- ✅ Status bar : `><` remplacé par branch name cliquable avec `_showBranchPicker`
- ✅ Terminal `projectDir` : hardcode `/` → `_currentWorkspaceDir ?? '/'`
- ✅ Workspace persistence : file explorer reste visible en changeant de tab

**Non fixé malgré les intentions :**
- ❌ `buildWhen` restrictif (editor_page.dart:2035) — toujours cassé
- ❌ `_ProblemsPanel isEmpty = true` — toujours hardcodé
- ❌ Titres des rails 7, 8, 10, 11 — toujours absents
- ❌ Dispose des ressources éditeur dans `CloseActiveEditor`
- ❌ Commit history sans date

### Session 3 — Inachevée (quota épuisé)
L'agent avait commencé à vérifier le panel git et la persistance des fichiers mais le quota journalier a été atteint avant tout code ou push.

**Dernier état git :** HEAD = origin/main (`9137da0`) — tout est déjà pushé.

---

## 5. Plan de travail priorisé

### Priorité 1 — Bugs UI critiques visibles (à faire en premier)
1. **[B1] Fixer `buildWhen`** — editor_page.dart:2035  
   Comparer `activeEditorIndex` + `activeEditors[i].isDirty` + `activeEditors[i].title`

2. **[B3] Ajouter titres rails 7, 8, 10, 11** — home.dart:1629-1637  
   Ajouter `7: 'Gateway'`, `8: 'Browser'`, `10: 'Agent'`, `11: 'Local Models'`

3. **[B2] Brancher `_ProblemsPanel` sur diagnostics LSP réels**  
   Utiliser `LanguageFeatureRouter.instance.diagnostics` ou créer un `DiagnosticsBloc`

4. **[B8] Ajouter date dans commit history**  
   Modifier le format `getGraph()` : `%H%x01%P%x01%an%x01%s%x01%ad` + parser `GitCommitGraph`

### Priorité 2 — Stabilité agent et éditeur
5. **[B9] `ChatSessionBloc._onSelectSession`** — ajouter `orElse`
6. **[B7] Reset `_allowImmediatePop`** après usage
7. **[B5] Dispose ressources dans `CloseActiveEditor`**
8. **[B4] Synchroniser split editor avec `ActiveEditorBloc`**
9. **[B11] Appeler `_shouldUseTools()`** dans `_run`
10. **[B12] Passer `approvalMode`** à `AgentRunner`

### Priorité 3 — Features manquantes importantes
11. **Sessions agent persistées** — utiliser SharedPreferences / SQLite
12. **Panneau Output branché** — brancher sur stdout du process en cours d'exécution
13. **Panneau bottom redimensionnable** — `ResizableBox` / drag handle
14. **[B24] Vite preview** — remplacer `localhost` par `127.0.0.1`
15. **[B25] Détection git améliorée** — chercher `.git` file (worktrees) + `.git` dir

### Priorité 4 — Qualité technique
16. **[B16] Remplacer tous `withOpacity()`** — script sed global + vérification manuelle
17. **[B10] Vérifier exit codes** dans les fonctions git
18. **[B22] Dédupliquer `normalizeRecentEntry`** — extraire dans `functions.dart`
19. **[B23] Extension lookup case-insensitive** — `ext.toLowerCase()`
20. **[B13, B14] Race condition + IDs Gemini** dans AgentRunner
21. **[B15] Local Llama agent mode** — implémenter le cas manquant dans AgentRunner

### Priorité 5 — Features "bientôt disponible"
22. **Microphone agent** — intégration `speech_to_text` Flutter
23. **Back/Forward navigation** — implémenter l'historique de navigation éditeur
24. **Code Editing / Advanced Settings** — implémenter les toggles (format on save, etc.)
25. **"+ Agent" button** — créer un nouveau thread agent
26. **Collapse All dans Problems** — replier tous les groupes de diagnostics

---

## 6. Architecture workspace (comportement voulu vs actuel)

### Comportement voulu (style VSCode)
```
┌─ Barre de statut bottom ──────────────────────────────────────────┐
│ [⎇ main ▼] [⚠ 3] [✗ 1]              [Dart] [UTF-8] [LF] [Ln 42] │
└───────────────────────────────────────────────────────────────────┘

Règles :
- Pas de projet ouvert → icône générique (dossier) + "Ouvrir un dossier"
- Projet ouvert → nom de branche cliquable → branch picker
- Nom du workspace dans le titre sidebar = nom du dossier du projet
- File explorer persiste sur tous les onglets tant que le projet est ouvert
- "Espace de travail" → remplacé par le nom du projet dès qu'un projet est ouvert
- Fermer le projet → revenir à l'état vide (sans projet)
```

### État actuel (après fix 8693da5)
```
✅ Status bar : branch name cliquable quand projet ouvert
✅ Status bar : fallback icône dossier + _currentWorkspaceName quand pas de branche
✅ File explorer : persiste lors du changement de tab
✅ Terminal : s'ouvre dans _currentWorkspaceDir
❌ "Espace de travail" non remplacé par nom projet dans tous les contextes
❌ Fermeture explicite d'un projet non implémentée ("Close Folder" command manquante)
❌ Panneau Problems non branché sur diagnostics LSP
```

---

## 7. Architecture Git Panel (comportement voulu vs actuel)

### Ce que le panel SourceControl a déjà (réel, wired)
- Staged/Unstaged lists + actions individuelles et globales
- Diff view callback
- Commit + AI commit message generation
- Commit + Push / Sync
- Push seul / Pull seul / Fetch / Sync
- Commit history graph (sans date)
- Branch management (create/checkout/rename/delete/merge/rebase/publish)
- Stash (create/pop/apply/drop/show)
- Tags
- Remotes

### Ce qui manque encore dans le panel Git
| Feature | Effort | Priorité |
|---------|--------|----------|
| Date dans le graphe de commits | Faible | Haute |
| Diff inline (hunk-level) dans le panneau | Moyen | Haute |
| Affichage upstream/behind/ahead dans la barre | Faible | Haute |
| Résolution de conflits UI | Élevé | Moyenne |
| `git blame` ligne par ligne dans l'éditeur | Élevé | Basse |
| Gutter diff indicators (lignes modifiées) | Moyen | Haute |
| GitHub PR panel | Très élevé | Basse |

---

## 8. Fichiers clés à modifier par priorité

```
lib/ui/editor_page.dart          — B1 (buildWhen), B7 (_allowImmediatePop), B24 (vite localhost)
lib/ui/home.dart                 — B2 (ProblemsPanel), B3 (rail titles), B4 (split sync), B5 (dispose)
lib/ui/widgets.dart              — B8 (commit history date), git panel améliorations
lib/utils/functions.dart         — B8 (getGraph format), B10 (exit codes), B17 (createFile), B22 (normalizeRecentEntry)
lib/ui/agent_runner.dart         — B11 (_shouldUseTools), B12 (approval mode), B13 (race condition), B14 (Gemini IDs), B15 (local llama)
lib/bloc/ui_bloc/ui_bloc.dart    — B5 (dispose), B9 (orElse), B12 (approval mode)
lib/bloc/repo_bloc/repo_bloc.dart — cleanup
lib/terminal/terminal_native.dart — vérifier B7 pattern similaire
```

---

## 9. Checklist des actions immédiates

- [ ] Fix B1 : buildWhen éditeur
- [ ] Fix B3 : titres rails manquants
- [ ] Fix B8 : date dans commit graph
- [ ] Fix B9 : ChatSession orElse
- [ ] Fix B7 : reset _allowImmediatePop
- [ ] Fix B2 : wirer ProblemsPanel sur diagnostics LSP
- [ ] Fix B10 : exit codes fonctions git
- [ ] Fix B16 : remplacer withOpacity (script automatisé)
- [ ] Fix B23 : extension lookup case-insensitive
- [ ] Fix B24 : Vite URL localhost → 127.0.0.1
- [ ] Fix B22 : dédupliquer normalizeRecentEntry
- [ ] Fix B25 : détection git worktrees
- [ ] Implémenter : "Close Folder" command
- [ ] Implémenter : panneau Output branché sur process stdout
- [ ] Implémenter : panneau bottom redimensionnable
- [ ] Implémenter : sessions agent persistées
- [ ] Implémenter : gutter diff indicators dans éditeur
- [ ] Implémenter : commit date dans GitCommitGraph

---

*Document généré par analyse statique complète du code — HEAD 9137da0 — 2026-08-06*
