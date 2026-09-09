# 02 — Workspace Dropdown (Phase 0 — Haute)

## Objectif
Quand on clique sur la box « Workspace » dans la top bar, un Quick Pick s'ouvre
avec les workspaces/récent. Comme VS Code : séparateurs folders/files, supprimable.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/ui/home.dart` | **MODIFIER** — Le GestureDetector de la workspace box ouvre un Quick Pick |
| `lib/ui/quick_open.dart` | **MODIFIER** — Ajouter le mode "workspace picker" |
| `lib/ui/widgets/workspace_picker.dart` | **CRÉER** — Widget dédié au dropdown workspace |

## Comportement VS Code (source : windowActions.ts)

```
1. Cliquer sur « Workspace » dans la top bar
2. Quick Pick s'ouvre avec :
   - Séparateur « folders & workspaces »
   - Liste des dossiers/workspaces récents (avec path complet)
   - Séparateur « files »
   - Liste des fichiers récemment ouverts
3. Chaque entrée a un bouton × (remove from recently opened)
4. Sélection = ouvrir ce workspace/dossier
5. Cmd/Ctrl-click = ouvrir dans une nouvelle fenêtre (pas sur mobile)
```

## Code AVANT (home.dart)

```dart
// La box workspace est un GestureDetector statique
GestureDetector(
  onTap: () { /* ouvre dropdown basique ou rien */ },
  child: Container(
    // ...
    child: Text(workspaceName),
  ),
),
```

## Code APRÈS

```dart
GestureDetector(
  onTap: () => _showWorkspacePicker(context),
  child: Container(
    // ...
    child: Row(
      children: [
        Text(workspaceName),
        Icon(Icons.keyboard_arrow_down, size: 14),
      ],
    ),
  ),
),
```

```dart
void _showWorkspacePicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => WorkspacePicker(
      onWorkspaceSelected: (path) {
        // Ouvrir le workspace sélectionné
        setState(() { /* update workspace */ });
      },
      onRemove: (path) {
        // Supprimer du récent
      },
    ),
  );
}
```

## Widget WorkspacePicker

```dart
class WorkspacePicker extends StatelessWidget {
  final List<String> recentFolders;
  final List<String> recentFiles;
  final void Function(String) onWorkspaceSelected;
  final void Function(String)? onRemove;

  const WorkspacePicker({
    required this.recentFolders,
    required this.recentFiles,
    required this.onWorkspaceSelected,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          // Handle
          Container(width: 36, height: 4, margin: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
          // Search
          Padding(padding: EdgeInsets.symmetric(horizontal: 16),
            child: TextField(decoration: InputDecoration(hintText: 'Search folders & files...'))),
          // Folders section
          _SectionHeader('Folders & Workspaces'),
          Expanded(child: ListView.builder(
            itemCount: recentFolders.length,
            itemBuilder: (_, i) => _WorkspaceTile(
              path: recentFolders[i],
              onTap: () => onWorkspaceSelected(recentFolders[i]),
              onRemove: onRemove != null ? () => onRemove!(recentFolders[i]) : null,
            ),
          )),
          Divider(),
          // Files section
          _SectionHeader('Files'),
          Expanded(child: ListView.builder(
            itemCount: recentFiles.length,
            itemBuilder: (_, i) => _WorkspaceTile(
              path: recentFiles[i],
              onTap: () => onWorkspaceSelected(recentFiles[i]),
              onRemove: onRemove != null ? () => onRemove!(recentFiles[i]) : null,
            ),
          )),
        ],
      ),
    );
  }
}
```

## Priorité
**P0** — Interaction principale de l'IDE.

## Effort
4h
