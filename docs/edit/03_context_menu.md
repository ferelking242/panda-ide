# 03 — Explorer Context Menu Complet (Phase 1 — Haute)

## Objectif
Le menu contextuel (long press / right click) sur un fichier/dossier dans l'Explorer
doit contenir toutes les actions VS Code, pas juste New File/Folder.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/ui/home.dart` | **MODIFIER** — Le GestureDetector du file tree |
| `lib/ui/widgets/context_menu.dart` | **CRÉER** — Widget réutilisable pour les menus contextuels |
| `lib/services/file_operations.dart` | **CRÉER** — Service pour rename, delete, copy, etc. |

## Actions VS Code (source : fileActions.contribution.ts)

### Groupe navigation (ordre 1-10)
| Action | ID VS Code | Raccourci |
|---|---|---|
| New File... | `explorer.newFile` | Ctrl+N |
| New Folder... | `explorer.newFolder` | — |
| Open With... | `explorer.openWith` | — |
| Copy Path | `filesExplorer.copyPath` | Shift+Alt+C |
| Copy Relative Path | `filesExplorer.copyRelativePath` | Shift+Alt+R |

### Groupe compare (ordre 20-30)
| Action | ID VS Code |
|---|---|
| Compare with Selected | `compareFiles` |
| Select for Compare | `compareFiles.selectForCompare` |
| Compare Selected | `compareFiles.compareSelected` |

### Groupe cut/copy/paste (ordre 8-20)
| Action | ID VS Code | Raccourci |
|---|---|---|
| Cut | `filesExplorer.cut` | Ctrl+X |
| Copy | `filesExplorer.copy` | Ctrl+C |
| Paste | `filesExplorer.paste` | Ctrl+V |
| Download | `workbench.files.action.downloadFile` | — |
| Upload | `workbench.files.action.uploadFile` | — |

### Groupe remove (ordre 10-20)
| Action | ID VS Code |
|---|---|
| Remove Folder from Workspace | `removeFolderFromWorkspace` |
| Add Root Folder to Workspace | `addRootFolder` |

### Groupe modify (ordre 10-20)
| Action | ID VS Code | Raccourci |
|---|---|---|
| Rename | `filesExplorer.rename` | F2 |
| Delete | `filesExplorer.delete` | Del |

### Groupe open (ordre 10-20)
| Action | ID VS Code |
|---|---|
| Open in Integrated Terminal | `filesExplorer.openInIntegratedTerminal` |
| Reveal in OS | `filesExplorer.revealInOS` |
| Open to the Side | `explorer.openToSide` |

## Code : ContextMenu widget

```dart
class ContextMenuItem {
  final String label;
  final IconData? icon;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool isSeparator;
  final bool isDestructive;

  const ContextMenuItem({
    required this.label,
    this.icon,
    this.shortcut,
    this.onTap,
    this.isSeparator = false,
    this.isDestructive = false,
  });

  const ContextMenuItem.separator()
      : label = '', icon = null, shortcut = null, onTap = null,
        isSeparator = true, isDestructive = false;
}

class ContextMenu extends StatelessWidget {
  final List<ContextMenuItem> items;

  const ContextMenu({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black54)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          if (item.isSeparator) return Divider(height: 1);
          return ListTile(
            dense: true,
            leading: item.icon != null ? Icon(item.icon, size: 16) : null,
            title: Text(item.label, style: TextStyle(
              fontSize: 13,
              color: item.isDestructive ? Colors.red : null,
            )),
            trailing: item.shortcut != null
                ? Text(item.shortcut!, style: TextStyle(fontSize: 11, color: Colors.grey))
                : null,
            onTap: () {
              item.onTap?.call();
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}
```

## Usage dans le file tree

```dart
GestureDetector(
  onLongPressStart: (details) => _showContextMenu(
    context,
    details.globalPosition,
    filePath,
  ),
  child: _buildFileTile(file),
),

void _showContextMenu(BuildContext context, Offset position, String filePath) {
  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
    items: [
      PopupMenuItem(child: Text('New File...'), onTap: () => _newFile(filePath)),
      PopupMenuItem(child: Text('New Folder...'), onTap: () => _newFolder(filePath)),
      PopupMenuItem(child: Text('Open With...'), onTap: () => _openWith(filePath)),
      PopupMenuDivider(),
      PopupMenuItem(child: Text('Copy Path'), onTap: () => _copyPath(filePath)),
      PopupMenuItem(child: Text('Copy Relative Path'), onTap: () => _copyRelativePath(filePath)),
      PopupMenuDivider(),
      PopupMenuItem(child: Text('Cut'), onTap: () => _cut(filePath)),
      PopupMenuItem(child: Text('Copy'), onTap: () => _copy(filePath)),
      PopupMenuItem(child: Text('Paste'), onTap: () => _paste(filePath)),
      PopupMenuDivider(),
      PopupMenuItem(child: Text('Rename'), onTap: () => _rename(filePath)),
      PopupMenuItem(
        child: Text('Delete', style: TextStyle(color: Colors.red)),
        onTap: () => _delete(filePath),
      ),
      PopupMenuDivider(),
      PopupMenuItem(child: Text('Open in Terminal'), onTap: () => _openInTerminal(filePath)),
    ],
  );
}
```

## Priorité
**P1 — Haute** — Interaction fondamentale pour naviguer les fichiers.

## Effort
6h
