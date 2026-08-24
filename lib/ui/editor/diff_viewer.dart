/// Inline diff viewer — shows Git diffs with added/removed highlighting.
import 'package:flutter/material.dart';

library;


/// A single line in a diff.
class DiffLine {
  final String type; // 'add', 'remove', 'context', 'header'
  final String content;
  final int? oldLine;
  final int? newLine;

  const DiffLine({
    required this.type,
    required this.content,
    this.oldLine,
    this.newLine,
  });
}

/// Parses unified diff output into DiffLine objects.
class DiffParser {
  static List<DiffLine> parse(String diffOutput) {
    final lines = <DiffLine>[];
    var oldLine = 0;
    var newLine = 0;

    for (final rawLine in diffOutput.split('\n')) {
      // Hunk header: @@ -oldStart,oldCount +newStart,newCount @@
      if (rawLine.startsWith('@@')) {
        final match = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(rawLine);
        if (match != null) {
          oldLine = int.parse(match.group(1)!);
          newLine = int.parse(match.group(2)!);
        }
        lines.add(DiffLine(type: 'header', content: rawLine));
        continue;
      }

      if (rawLine.startsWith('diff --git')) {
        lines.add(DiffLine(type: 'header', content: rawLine));
        continue;
      }

      if (rawLine.startsWith('---') || rawLine.startsWith('+++')) {
        lines.add(DiffLine(type: 'header', content: rawLine));
        continue;
      }

      if (rawLine.startsWith('+')) {
        lines.add(DiffLine(type: 'add', content: rawLine.substring(1), newLine: newLine));
        newLine++;
      } else if (rawLine.startsWith('-')) {
        lines.add(DiffLine(type: 'remove', content: rawLine.substring(1), oldLine: oldLine));
        oldLine++;
      } else if (rawLine.startsWith(' ')) {
        lines.add(DiffLine(type: 'context', content: rawLine.substring(1), oldLine: oldLine, newLine: newLine));
        oldLine++;
        newLine++;
      } else if (rawLine.isEmpty) {
        continue;
      } else {
        lines.add(DiffLine(type: 'context', content: rawLine, oldLine: oldLine, newLine: newLine));
        oldLine++;
        newLine++;
      }
    }

    return lines;
  }
}

/// Widget that displays a unified diff with syntax highlighting.
class DiffViewer extends StatelessWidget {
  final List<DiffLine> lines;
  final bool showLineNumbers;

  const DiffViewer({
    super.key,
    required this.lines,
    this.showLineNumbers = true,
  });

  /// Create from raw diff string.
  factory DiffViewer.fromString(String diffOutput, {bool showLineNumbers = true}) {
    return DiffViewer(
      lines: DiffParser.parse(diffOutput),
      showLineNumbers: showLineNumbers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lines.isEmpty) {
      return Center(
        child: Text('No changes', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      itemCount: lines.length,
      itemExtent: 22,
      itemBuilder: (_, i) {
        final line = lines[i];
        return _buildLine(line, cs, isDark);
      },
    );
  }

  Widget _buildLine(DiffLine line, ColorScheme cs, bool isDark) {
    Color bgColor;
    Color textColor;
    String prefix;

    switch (line.type) {
      case 'add':
        bgColor = const Color(0xFF1B5E20).withValues(alpha: 0.3);
        textColor = const Color(0xFF66BB6A);
        prefix = '+';
        break;
      case 'remove':
        bgColor = const Color(0xFFB71C1C).withValues(alpha: 0.3);
        textColor = const Color(0xFFEF5350);
        prefix = '-';
        break;
      case 'header':
        bgColor = cs.primary.withValues(alpha: 0.1);
        textColor = cs.primary;
        prefix = ' ';
        break;
      default:
        bgColor = Colors.transparent;
        textColor = cs.onSurface;
        prefix = ' ';
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (showLineNumbers) ...[
            // Old line number
            SizedBox(
              width: 40,
              child: Text(
                line.oldLine?.toString() ?? '',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace'),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 4),
            // New line number
            SizedBox(
              width: 40,
              child: Text(
                line.newLine?.toString() ?? '',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace'),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Prefix
          SizedBox(
            width: 14,
            child: Text(
              prefix,
              style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
            ),
          ),
          // Content
          Expanded(
            child: Text(
              line.content,
              style: TextStyle(fontSize: 12, color: textColor, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline diff decoration for the editor gutter.
class InlineDiffGutter extends StatelessWidget {
  final List<DiffLine> lines;
  final double lineHeight;

  const InlineDiffGutter({
    super.key,
    required this.lines,
    this.lineHeight = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: lines.map((line) {
        Color? color;
        switch (line.type) {
          case 'add':
            color = const Color(0xFF4CAF50);
            break;
          case 'remove':
            color = const Color(0xFFF44336);
            break;
          default:
            color = null;
        }

        return Container(
          width: 4,
          height: lineHeight,
          color: color,
        );
      }).toList(),
    );
  }
}
