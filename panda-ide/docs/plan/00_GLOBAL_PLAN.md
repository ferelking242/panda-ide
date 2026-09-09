# PLAN GLOBAL — Panda IDE vs VS Code Parity

## Référence
- Audit : `docs/AUDIT_VSCODE_vs_PANDA.md`
- Éditions : `docs/edit/`

## Phases

### Phase 0 — Immédiat (1-2 jours)
| # | Tâche | Effort | Fichier edit |
|---|---|---|---|
| 0.1 | Settings persistence (SharedPreferences) | 6h | `docs/edit/01_settings_persistence.md` |
| 0.2 | Workspace dropdown (Quick Pick) | 4h | `docs/edit/02_workspace_dropdown.md` |

### Phase 1 — Features manquantes (semaine 2)
| # | Tâche | Effort | Fichier edit |
|---|---|---|---|
| 1.1 | Explorer context menu complet | 6h | `docs/edit/03_context_menu.md` |
| 1.2 | Editor tab "..." menu complet | 3h | `docs/edit/04_tab_menu.md` |
| 1.3 | Status bar items manquants | 4h | `docs/edit/05_status_bar.md` |
| 1.4 | Code Lens | 8h | `docs/edit/07_code_lens.md` |
| 1.5 | Create/Checkout branch UI | 8h | — |
| 1.6 | Settings search bar | 4h | — |

### Phase 2 — Terminal & Debug (semaine 3-4)
| # | Tâche | Effort | Fichier edit |
|---|---|---|---|
| 2.1 | Terminal multi-tab | 12h | `docs/edit/06_terminal_multitab.md` |
| 2.2 | Terminal split | 8h | — |
| 2.3 | Launch configurations (debug.json) | 12h | — |
| 2.4 | Conditional breakpoints | 4h | — |
| 2.5 | Git stash UI | 6h | — |
| 2.6 | Git log / history | 8h | — |
| 2.7 | Preview editor (italique) | 6h | — |

### Phase 3 — Extension system (semaine 5-6)
| # | Tâche | Effort |
|---|---|---|
| 3.1 | debuggers contribution type | 12h |
| 3.2 | authentication contribution | 8h |
| 3.3 | taskDefinitions contribution | 8h |
| 3.4 | viewsContainers (custom sidebar) | 12h |
| 3.5 | Extension auto-update | 8h |

### Phase 4 — Mobile-first (semaine 7-8)
| # | Tâche | Effort | Fichier edit |
|---|---|---|---|
| 4.1 | Responsive breakpoints + layout engine | 8h | `docs/edit/08_mobile_layout.md` |
| 4.2 | Sidebar → Drawer (mobile) | 8h | `docs/edit/08_mobile_layout.md` |
| 4.3 | Bottom Navigation (5 tabs) | 6h | `docs/edit/08_mobile_layout.md` |
| 4.4 | Settings mobile layout | 4h | `docs/edit/08_mobile_layout.md` |
| 4.5 | Terminal → Bottom sheet | 4h | `docs/edit/08_mobile_layout.md` |
| 4.6 | Pull-to-refresh | 3h | — |
| 4.7 | Long press context menu | 4h | — |
| 4.8 | Swipe between tabs | 3h | — |

### Phase 5 — Polish (semaine 9-12)
| # | Tâche | Effort |
|---|---|---|
| 5.1 | Accessibility (ARIA, screen reader) | 12h |
| 5.2 | Search exclude/include patterns | 6h |
| 5.3 | Inlay hints | 8h |
| 5.4 | Local history | 8h |
| 5.5 | Zen mode | 4h |

## Estimation totale

| Phase | Effort | Durée |
|---|---|---|
| Phase 0 | 10h | 1-2 jours |
| Phase 1 | 33h | 1 semaine |
| Phase 2 | 56h | 1.5 semaines |
| Phase 3 | 48h | 1 semaine |
| Phase 4 | 40h | 1 semaine |
| Phase 5 | 38h | 1 semaine |
| **TOTAL** | **225h** | **~6 semaines** |

## Commande de démarrage

Pour commencer à coder, je recommande :

```
Phase 0 → Phase 1 → Phase 4 (mobile) → Phase 2 → Phase 3 → Phase 5
```

La Phase 4 (mobile) devrait venir plus tôt car Panda est un IDE mobile.
