# 07 — Code Lens (Phase 2 — Haute)

## Objectif
Code Lens affiche des actions inline au-dessus des fonctions/classes
(ex: "Run test", "Show Coverage", "2 references").
VS Code a 17 fichiers pour cette feature.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/ui/editor/code_folding.dart` | **MODIFIER** — Ajouter le rendering CodeLens |
| `lib/extensions/language_feature_router.dart` | **MODIFIER** — Route les CodeLens providers |
| `lib/ui/editor_page.dart` | **MODIFIER** — Afficher les CodeLens au-dessus des lignes |

## Comportement VS Code (source : codelens/)

```
1. Extensions enregistrent des CodeLens providers
2. Le provider retourne des CodeLens items pour chaque document
3. Chaque item a: range (position), command (action), isResolved
4. Les items s'affichent en gris au-dessus des lignes concernées
5. Clic sur un item exécute la command
6. Auto-refresh quand le document change
```

## Exemples de CodeLens

```
  2 references    refactor    test    ← CodeLens (gris, au-dessus)
function myFunction() {
  // ...
}

  1 implementation             ← CodeLens
class MyClass {
  // ...
}
```

## Code : CodeLens widget

```dart
class CodeLensItem {
  final String label;
  final VoidCallback onTap;
  final int lineNumber;

  CodeLensItem({
    required this.label,
    required this.onTap,
    required this.lineNumber,
  });
}

class CodeLensWidget extends StatelessWidget {
  final List<CodeLensItem> items;

  const CodeLensWidget({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 60), // aligner avec le code
      child: Wrap(
        spacing: 12,
        children: items.map((item) => GestureDetector(
          onTap: item.onTap,
          child: Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
              decoration: TextDecoration.underline,
            ),
          ),
        )).toList(),
      ),
    );
  }
}
```

## Intégration dans l'éditeur

```dart
// Dans le rendering de chaque ligne :
Widget _buildLine(int lineNumber, String text) {
  final codeLensItems = _getCodeLensForLine(lineNumber);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (codeLensItems.isNotEmpty)
        CodeLensWidget(items: codeLensItems),
      _buildCodeLine(lineNumber, text),
    ],
  );
}
```

## Priorité
**P1** — Feature importante pour l'expérience développeur.

## Effort
8h
