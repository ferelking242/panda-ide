import 'package:flutter/material.dart';

class MobileTouchToolbar extends StatelessWidget {
  final TextEditingController controller;
  final List<String> symbols;

  const MobileTouchToolbar({
    Key? key,
    required this.controller,
    this.symbols = const ['{', '}', '[', ']', '(', ')', ';', '=', '=>', '\$', '"', "'", '<', '>', ':', '+', '-', '/', '*', '_', '|', '&', '!', '?'],
  }) : super(key: key);

  void _insertSymbol(String symbol) {
    final selection = controller.selection;
    final text = controller.text;

    if (selection.isValid && selection.baseOffset >= 0) {
      final newText = text.substring(0, selection.baseOffset) + symbol + text.substring(selection.extentOffset);
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: selection.baseOffset + symbol.length);
    } else {
      controller.text += symbol;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: symbols.length,
        itemBuilder: (context, index) {
          final sym = symbols[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: () => _insertSymbol(sym),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Center(
                    child: Text(
                      sym,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
