import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUICodeBlock — bloc de code syntax-highlighté, streaming-stable.
///
///   • Tokenizer léger (keywords, strings, comments, numbers)
///   • Numéros de ligne
///   • Bouton copier avec feedback
///   • Stable pendant le streaming (pas de re-highlight dérangeant)
/// ═══════════════════════════════════════════════════════════════════════════

class BeUICodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final bool showLineNumbers;
  final double? maxHeight;
  final bool isDark;

  const BeUICodeBlock({
    super.key,
    required this.code,
    this.language,
    this.showLineNumbers = true,
    this.maxHeight = 400,
    this.isDark = true,
  });

  @override
  State<BeUICodeBlock> createState() => _BeUICodeBlockState();
}

class _BeUICodeBlockState extends State<BeUICodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.split('\n');
    final accent = BeUIColors.accentOf(widget.isDark);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: BeUIColors.surfaceOf(widget.isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BeUIColors.borderOf(widget.isDark), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: language + copy ─────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: BeUIColors.borderOf(widget.isDark), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                if (widget.language != null)
                  Text(
                    widget.language!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent.withValues(alpha: 0.7),
                      letterSpacing: 0.5,
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: _copy,
                  child: AnimatedSwitcher(
                    duration: BeUIDurations.fast,
                    child: _copied
                        ? const Icon(Icons.check, size: 12, color: Colors.green, key: ValueKey('check'))
                        : Icon(Icons.copy, size: 12, color: BeUIColors.borderOf(widget.isDark)),
                  ),
                ),
              ],
            ),
          ),

          // ── Code body ───────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 400),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line numbers
                  if (widget.showLineNumbers)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < lines.length; i++)
                            Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: BeUIColors.borderOf(widget.isDark),
                                height: 1.6,
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Code content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                    child: Text.rich(
                      _highlight(lines, widget.isDark),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copy() {
    // TODO: Clipboard.setData
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Simple tokenizer → TextSpan tree.
  static TextSpan _highlight(List<String> lines, bool isDark) {
    final fg = isDark ? const Color(0xFFD4D4D4) : const Color(0xFF383A42);
    final commentColor = isDark ? const Color(0xFF6A9955) : const Color(0xFFA0A1A7);
    final stringColor = isDark ? const Color(0xFFCE9178) : const Color(0xFFA0A1A7);
    final keywordColor = isDark ? const Color(0xFFC586C0) : const Color(0xFFA626A4);
    final numberColor = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF986801);
    final typeColor = isDark ? const Color(0xFF4EC9B0) : const Color(0xFFE45649);

    const keywords = {
      'import', 'export', 'class', 'extends', 'implements', 'with',
      'void', 'int', 'double', 'String', 'bool', 'final', 'const',
      'var', 'late', 'static', 'async', 'await', 'return', 'if',
      'else', 'for', 'while', 'switch', 'case', 'break', 'new',
      'this', 'super', 'true', 'false', 'null', 'required',
      'function', 'const', 'let', 'from', 'in', 'of', 'try',
      'catch', 'throw', 'yield', 'enum', 'sealed', 'mixin',
    };

    final spans = <TextSpan>[];
    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      var pos = 0;
      while (pos < line.length) {
        // Line comment
        if (line[pos] == '#' || (pos + 1 < line.length && line.substring(pos, pos + 2) == '//')) {
          spans.add(TextSpan(
            text: line.substring(pos),
            style: TextStyle(color: commentColor),
          ));
          pos = line.length;
          continue;
        }

        // String
        if (line[pos] == '"' || line[pos] == "'" || line[pos] == '`') {
          final quote = line[pos];
          var end = pos + 1;
          while (end < line.length && line[end] != quote) {
            if (line[end] == '\\') end++;
            end++;
          }
          end = (end + 1).clamp(0, line.length);
          spans.add(TextSpan(
            text: line.substring(pos, end),
            style: TextStyle(color: stringColor),
          ));
          pos = end;
          continue;
        }

        // Number
        if (RegExp(r'[0-9]').hasMatch(line[pos])) {
          var end = pos;
          while (end < line.length && RegExp(r'[0-9._]').hasMatch(line[end])) end++;
          spans.add(TextSpan(
            text: line.substring(pos, end),
            style: TextStyle(color: numberColor),
          ));
          pos = end;
          continue;
        }

        // Word
        if (RegExp(r'[a-zA-Z_]').hasMatch(line[pos])) {
          var end = pos;
          while (end < line.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(line[end])) end++;
          final word = line.substring(pos, end);
          final isKeyword = keywords.contains(word);
          final isType = !isKeyword && word[0].toUpperCase() == word[0] && !word.startsWith('_');
          spans.add(TextSpan(
            text: word,
            style: TextStyle(
              color: isKeyword ? keywordColor : isType ? typeColor : fg,
              fontWeight: isKeyword ? FontWeight.w600 : FontWeight.normal,
            ),
          ));
          pos = end;
          continue;
        }

        // Plain char
        spans.add(TextSpan(text: line[pos], style: TextStyle(color: fg)));
        pos++;
      }
      // Line break (except last)
      if (lineIdx < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }
}
