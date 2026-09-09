import 'package:flutter/material.dart';

/// Represents a single inlay hint (type annotation, parameter name, etc.).
class InlayHint {
  final int line;
  final int character;
  final String label;
  final InlayHintKind kind;
  final String? tooltip;

  const InlayHint({
    required this.line,
    required this.character,
    required this.label,
    this.kind = InlayHintKind.type,
    this.tooltip,
  });
}

enum InlayHintKind {
  type,
  parameter,
  enum_,
  label,
}

/// Renders inlay hints inline in the editor gutter or next to identifiers.
class InlayHintsOverlay extends StatelessWidget {
  final List<InlayHint> hints;
  final int line;
  final double fontSize;
  final Color? textColor;

  const InlayHintsOverlay({
    super.key,
    required this.hints,
    required this.line,
    this.fontSize = 12,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final lineHints = hints.where((h) => h.line == line).toList();
    if (lineHints.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      children: lineHints.map((hint) => _buildHint(hint, context)).toList(),
    );
  }

  Widget _buildHint(InlayHint hint, BuildContext context) {
    final color = _kindColor(hint.kind, context);
    return Tooltip(
      message: hint.tooltip ?? hint.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(
          hint.label,
          style: TextStyle(
            fontSize: fontSize - 1,
            fontStyle: FontStyle.italic,
            color: color,
          ),
        ),
      ),
    );
  }

  Color _kindColor(InlayHintKind kind, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (kind) {
      case InlayHintKind.type:
        return cs.primary;
      case InlayHintKind.parameter:
        return Colors.teal;
      case InlayHintKind.enum_:
        return Colors.orange;
      case InlayHintKind.label:
        return cs.onSurfaceVariant;
    }
  }
}

/// Parses LSP inlayHint results into InlayHint objects.
class InlayHintParser {
  static List<InlayHint> parse(List<dynamic> lspHints) {
    final hints = <InlayHint>[];
    for (final h in lspHints) {
      if (h is! Map) continue;
      final pos = h['position'];
      if (pos == null) continue;
      final label = _extractLabel(h['label']);
      if (label.isEmpty) continue;
      hints.add(InlayHint(
        line: pos['line'] ?? 0,
        character: pos['character'] ?? 0,
        label: label,
        kind: _parseKind(h['kind']),
        tooltip: h['tooltip'],
      ));
    }
    return hints;
  }

  static String _extractLabel(dynamic label) {
    if (label is String) return label;
    if (label is List) {
      return label.map((l) {
        if (l is Map) return l['value'] ?? '';
        return l.toString();
      }).join('');
    }
    return label?.toString() ?? '';
  }

  static InlayHintKind _parseKind(dynamic kind) {
    switch (kind) {
      case 1: return InlayHintKind.type;
      case 2: return InlayHintKind.parameter;
      case 3: return InlayHintKind.enum_;
      case 4: return InlayHintKind.label;
      default: return InlayHintKind.type;
    }
  }
}
