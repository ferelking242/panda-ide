import 'package:flutter/material.dart';

/// A single CodeLens item displayed above a code line.
class CodeLensItem {
  /// Start line (0-based).
  final int line;
  /// Display text (e.g. "3 references", "Refactor").
  final String commandTitle;
  /// Tooltip shown on hover.
  final String? tooltip;
  /// Callback when tapped.
  final VoidCallback? onTap;

  const CodeLensItem({
    required this.line,
    required this.commandTitle,
    this.tooltip,
    this.onTap,
  });
}

/// Widget that renders CodeLens items above the editor.
/// Wraps around the editor and overlays CodeLens items at the correct positions.
class CodeLensOverlay extends StatelessWidget {
  final List<CodeLensItem> items;
  final Widget child;
  final double lineHeight;
  final double gutterWidth;
  final ScrollController? scrollController;

  const CodeLensOverlay({
    super.key,
    required this.items,
    required this.child,
    this.lineHeight = 20.0,
    this.gutterWidth = 60.0,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return child;

    // Group items by line
    final byLine = <int, List<CodeLensItem>>{};
    for (final item in items) {
      byLine.putIfAbsent(item.line, () => []).add(item);
    }

    return Stack(
      children: [
        child,
        // Overlay CodeLens items
        for (final entry in byLine.entries)
          Positioned(
            top: entry.key * lineHeight + 2,
            left: gutterWidth + 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: entry.value.map((item) => GestureDetector(
                onTap: item.onTap,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Tooltip(
                    message: item.tooltip ?? item.commandTitle,
                    child: Text(
                      item.commandTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }
}
