# 06 — Terminal Multi-Tab (Phase 2 — Critique)

## Objectif
VS Code a des onglets dans le terminal (Terminal 1, Terminal 2, etc.)
Panda n'a qu'un seul terminal. Il faut support multi-terminal avec onglets.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/terminal/terminal.dart` | **MODIFIER** — Gérer plusieurs instances |
| `lib/ui/home.dart` | **MODIFIER** — Bottom panel avec onglets terminal |
| `lib/ui/editor/bottom_panel.dart` | **MODIFIER** — Tab bar dans le panel |

## Comportement VS Code (source : terminal.all.ts)

```
1. Ctrl+` = créer/toggle premier terminal
2. Le panel montre « Terminal 1 » avec un × pour fermer
3. Bouton + pour créer un nouveau terminal
4. Clic sur « Terminal 1 » → dropdown « Rename... | Split Terminal | Kill Terminal »
5. Ctrl+Shift+` = créer un nouveau terminal
6. Chaque terminal a son propre PTY/process
7. Split = diviser le terminal en deux
```

## Terminal Tabs UI

```
┌──────────────────────────────────────┐
│ Terminal 1  ×  │ Terminal 2  ×  │ + │  ← tab bar
├──────────────────────────────────────┤
│ $ _                                  │
│ ls                                    │
│ file1.txt  file2.dart               │
│ $ _                                  │
└──────────────────────────────────────┘
```

## Code : TerminalTab model

```dart
class TerminalTab {
  final String id;
  final String name;
  final Process? process;
  final StreamController<String> output;
  bool isActive;

  TerminalTab({
    required this.id,
    required this.name,
    this.process,
    required this.output,
    this.isActive = false,
  });
}
```

## Code : Bottom panel avec tabs

```dart
Widget _buildTerminalPanel() {
  return Column(children: [
    // Tab bar
    Container(
      height: 32,
      child: Row(children: [
        for (var tab in _terminalTabs)
          _terminalTabWidget(tab),
        // New terminal button
        IconButton(
          icon: Icon(Icons.add, size: 16),
          onPressed: _createNewTerminal,
        ),
      ]),
    ),
    // Active terminal
    Expanded(
      child: _activeTerminal != null
          ? TerminalWidget(terminal: _activeTerminal!)
          : Center(child: Text('No terminal open')),
    ),
  ]);
}

Widget _terminalTabWidget(TerminalTab tab) {
  return GestureDetector(
    onTap: () => _switchTerminal(tab),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(
          color: tab.isActive ? Colors.blue : Colors.transparent,
          width: 2,
        )),
      ),
      child: Row(children: [
        Text(tab.name, style: TextStyle(fontSize: 12)),
        SizedBox(width: 4),
        GestureDetector(
          onTap: () => _closeTerminal(tab),
          child: Icon(Icons.close, size: 14),
        ),
      ]),
    ),
  );
}
```

## Priorité
**P2 — Critique** — Fonctionnalité de base d'un IDE.

## Effort
12h
