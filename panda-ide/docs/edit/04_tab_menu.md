# 04 — Editor Tab "..." Menu (Phase 1 — Haute)

## Objectif
Le menu « ... » dans la barre d'onglets doit contenir toutes les actions VS Code.
Actuellement il a Close All, Close Saved, Split Editor — il manque beaucoup d'actions.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/ui/home.dart` | **MODIFIER** — Le menu "..." dans la tab bar |

## Actions complètes VS Code (source : editor.contribution.ts)

### EditorTitle (menu "..." au-dessus des onglets)
| Action | ID VS Code | Ordre |
|---|---|---|
| Inline View (diff toggle) | `toggleDiffSideBySide` | 10 |
| Show Opened Editors | `workbench.action.showOpenedEditors` | 10 |
| Close All | `workbench.action.closeAllEditors` | 10 |
| Close Saved | `workbench.action.closeAllEditorsSaving` | 20 |
| Enable Preview Editors | `workbench.action.toggleEnablePreview` | 10 |

### EditorTitleContext (right-click sur un onglet)
| Action | ID VS Code | Raccourci | Groupe |
|---|---|---|---|
| Close | `workbench.action.closeActiveEditor` | Ctrl+W | 1_close |
| Close Others | `workbench.action.closeOtherEditors` | Ctrl+K Ctrl+W | 1_close |
| Close to the Right | `workbench.action.closeEditorsToTheRight` | — | 1_close |
| Close Saved | `workbench.action.closeAllEditorsSaving` | Ctrl+K U | 1_close |
| Close All | `workbench.action.closeAllEditors` | Ctrl+K W | 1_close |
| Reopen Editor With... | `workbench.action.reopenWith` | — | 1_open |
| Keep Open | `workbench.action.keepEditor` | — | 3_preview |
| Pin | `workbench.action.pinEditor` | — | 3_preview |
| Unpin | `workbench.action.unpinEditor` | — | 3_preview |
| Split Right | `workbench.action.splitEditor` | Ctrl+\ | 5_split |
| Split & Move | submenu | — | 5_split |
| Move into New Window | `workbench.action.moveEditorIntoNewWindow` | — | 7_new_window |
| Copy into New Window | `workbench.action.copyEditorIntoNewWindow` | — | 7_new_window |
| Share | submenu | — | 11_share |

## Menu actuel dans Panda

```dart
// home.dart — actuellement
_buildEditorMenu() {
  return Column(children: [
    _menuItem('Close All', Icons.close, 'Ctrl+K W'),
    _menuItem('Close Saved', Icons.save, 'Ctrl+K U'),
    _menuItem('Split Editor Right', Icons.vertical_split, 'Ctrl+\\'),
    Divider(),
    _menuItem('Show Opened Editors', Icons.tab, null),
    _menuItem('Reopen Editor With...', Icons.open_in_new, null),
    _menuItem('Enable Preview Editors', Icons.preview, null),
  ]);
}
```

## Menu corrigé (ajouts)

```dart
_buildEditorMenu() {
  return Column(children: [
    // Group 1_close
    _menuItem('Close', Icons.close, 'Ctrl+W'),
    _menuItem('Close Others', Icons.close_fullscreen, 'Ctrl+K Ctrl+W'),
    _menuItem('Close to the Right', Icons.arrow_right, null),
    _menuItem('Close Saved', Icons.save, 'Ctrl+K U'),
    _menuItem('Close All', Icons.close_fullscreen, 'Ctrl+K W'),
    Divider(),
    // Group 1_open
    _menuItem('Reopen Editor With...', Icons.open_in_new, null),
    Divider(),
    // Group 3_preview
    _menuItem('Keep Open', Icons.push_pin_outlined, null),
    _menuItem('Pin', Icons.push_pin, null),
    _menuItem('Unpin', Icons.push_pin_outlined, null),
    Divider(),
    // Group 5_split
    _menuItem('Split Right', Icons.vertical_split, 'Ctrl+\\'),
    _menuItem('Split & Move', Icons.swap_horiz, null),
    Divider(),
    // Group 7_new_window
    _menuItem('Move into New Window', Icons.open_in_new, null),
    _menuItem('Copy into New Window', Icons.copy, null),
    Divider(),
    // Group 11_share
    _menuItem('Share', Icons.share, null),
    Divider(),
    // Group 5_close (bottom)
    _menuItem('Show Opened Editors', Icons.tab, null),
    _menuItem('Close All', Icons.close_all, null),
    _menuItem('Close Saved', Icons.save_alt, null),
    Divider(),
    // Group 7_settings
    _menuItem('Enable Preview Editors', Icons.preview, null),
  ]);
}
```

## Priorité
**P1** — Interaction essentielle pour la gestion des onglets.

## Effort
3h
