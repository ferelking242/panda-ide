# 05 — Status Bar Items (Phase 1 — Haute)

## Objectif
La status bar doit montrer les bons items et chaque item doit être cliquable avec un menu.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/ui/editor/status_bar.dart` | **MODIFIER** — Ajouter les items manquants |
| `lib/ui/home.dart` | **MODIFIER** — Brancher les clics status bar |

## Items VS Code (source : 128 registrations)

### Gauche (StatusBarAlignment.Left)
| Item | Clic | Panda actuel |
|---|---|---|
| Remote indicator (🖥 SSH) | Menu remote | ✅ (Gateway indicator) |
| Branch name (⎇ main) | Menu git (branches) | ✅ |
| Sync (🔄 0↓ 0↑) | Pull + Push | ❌ manque |
| Error/warning counts (❌ 0 ⚠ 0) | Ouvre Problems panel | ✅ |
| CodeLens count | Navigue vers les lenses | ❌ manque |

### Droite (StatusBarAlignment.Right)
| Item | Clic | Panda actuel |
|---|---|---|
| Ln 1, Col 1 | Go to Line/Column | ✅ |
| Spaces: 4 / Tab Size | Indentation settings | ❌ manque |
| UTF-8 | Encoding selector | ❌ manque |
| CRLF / LF | Line ending selector | ❌ manque |
| Prettier 📋 | Formatting status | ❌ manque |
| Notifications bell 🔔 | Notification center | ✅ |

## Menu contextuel de la status bar (source : StatusBarRemoteIndicatorMenu)

```
Branch menu:
  Create Branch...
  Delete Branch...
  Checkout Branch...
  ...
  Pull
  Push
  Sync
```

## Code : Ajouter les items manquants

```dart
// Ajouter à _buildStatusBarItems()
// Gauche
_statusBarItem(
  icon: Icons.sync,
  label: '0↓ 0↑',
  onTap: () => _syncGit(),
),
_statusBarItem(
  icon: Icons.remove_red_eye,
  label: 'Codelens',
  onTap: () => _showCodeLens(),
),

// Droite
_statusBarItem(
  label: 'Spaces: ${_tabSize}',
  onTap: () => _showIndentPicker(),
),
_statusBarItem(
  label: 'UTF-8',
  onTap: () => _showEncodingPicker(),
),
_statusBarItem(
  label: _lineEnding == 'CRLF' ? 'CRLF' : 'LF',
  onTap: () => _toggleLineEnding(),
),
_statusBarItem(
  label: 'Prettier',
  onTap: () => _formatDocument(),
),
```

## Priorité
**P1** — Items manquants pour l'expérience standard.

## Effort
4h
