/// Editor decorations — indent guides, bracket colorization, word wrap.
library;
import 'package:flutter/material.dart';



// ═══════════════════════════════════════════════════════════════
// Indent Guides
// ═══════════════════════════════════════════════════════════════

/// Renders vertical indent guide lines in the editor gutter.
class IndentGuidesPainter extends CustomPainter {
  final String code;
  final double lineHeight;
  final double charWidth;
  final int tabSize;
  final double scrollOffset;
  final double visibleHeight;
  final Color guideColor;
  final Color activeGuideColor;

  IndentGuidesPainter({
    required this.code,
    required this.lineHeight,
    this.charWidth = 8.0,
    this.tabSize = 2,
    this.scrollOffset = 0,
    this.visibleHeight = 600,
    this.guideColor = const Color(0xFF333333),
    this.activeGuideColor = const Color(0xFF666666),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lines = code.split('\n');
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final startLine = (scrollOffset / lineHeight).floor();
    final endLine = ((scrollOffset + visibleHeight) / lineHeight).ceil().clamp(0, lines.length - 1);

    for (var lineIdx = startLine; lineIdx <= endLine; lineIdx++) {
      final line = lines[lineIdx];
      final indent = _getIndentLevel(line);

      if (indent > 0) {
        for (var level = 1; level <= indent; level++) {
          final x = level * tabSize * charWidth;
          final y = (lineIdx * lineHeight) - scrollOffset;

          paint.color = guideColor;
          canvas.drawLine(
            Offset(x, y),
            Offset(x, y + lineHeight),
            paint,
          );
        }
      }
    }
  }

  int _getIndentLevel(String line) {
    if (line.isEmpty) return 0;
    var spaces = 0;
    for (final ch in line.split('')) {
      if (ch == ' ') {
        spaces++;
      } else if (ch == '\t') {
        spaces += tabSize;
      } else {
        break;
      }
    }
    return (spaces / tabSize).floor();
  }

  @override
  bool shouldRepaint(covariant IndentGuidesPainter oldDelegate) =>
      code != oldDelegate.code || scrollOffset != oldDelegate.scrollOffset;
}

// ═══════════════════════════════════════════════════════════════
// Bracket Pair Colorization
// ═══════════════════════════════════════════════════════════════

/// Colors for bracket pairs at different nesting levels.
const _bracketColors = [
  Color(0xFF00B4D8), // Level 0: cyan
  Color(0xFFE91E63), // Level 1: pink
  Color(0xFFFFC107), // Level 2: amber
  Color(0xFF4CAF50), // Level 3: green
  Color(0xFF9C27B0), // Level 4: purple
];

/// Computes bracket colorization for a line of code.
class BracketColorizer {
  /// Returns a map of character index -> color for brackets in the line.
  static Map<int, Color> colorizeLine(
    String line,
    int nestingLevel,
  ) {
    final result = <int, Color>{};
    var level = nestingLevel;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '(' || ch == '[' || ch == '{') {
        result[i] = _bracketColors[level % _bracketColors.length];
        level++;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        level = (level - 1).clamp(0, _bracketColors.length - 1);
        result[i] = _bracketColors[level % _bracketColors.length];
      }
    }

    return result;
  }

  /// Get the nesting level at the start of a line given the full code.
  static int getNestingLevelAtLine(String code, int lineIndex) {
    final lines = code.split('\n');
    var level = 0;

    for (var i = 0; i < lineIndex && i < lines.length; i++) {
      for (final ch in lines[i].split('')) {
        if (ch == '(' || ch == '[' || ch == '{') level++;
        if (ch == ')' || ch == ']' || ch == '}') level = (level - 1).clamp(0, 100);
      }
    }

    return level;
  }
}

// ═══════════════════════════════════════════════════════════════
// Editor Settings (Word Wrap, etc.)
// ═══════════════════════════════════════════════════════════════

/// Editor display settings.
class EditorSettings {
  final bool wordWrap;
  final bool showIndentGuides;
  final bool bracketColorization;
  final bool showMinimap;
  final bool showBreadcrumbs;
  final bool stickyScroll;
  final int tabSize;
  final double fontSize;
  final String fontFamily;
  final bool renderWhitespace;
  final bool highlightActiveLine;
  final bool smoothScrolling;

  const EditorSettings({
    this.wordWrap = true,
    this.showIndentGuides = true,
    this.bracketColorization = true,
    this.showMinimap = false,
    this.showBreadcrumbs = true,
    this.stickyScroll = false,
    this.tabSize = 2,
    this.fontSize = 14,
    this.fontFamily = 'JetBrains Mono',
    this.renderWhitespace = false,
    this.highlightActiveLine = true,
    this.smoothScrolling = true,
  });

  EditorSettings copyWith({
    bool? wordWrap,
    bool? showIndentGuides,
    bool? bracketColorization,
    bool? showMinimap,
    bool? showBreadcrumbs,
    bool? stickyScroll,
    int? tabSize,
    double? fontSize,
    String? fontFamily,
    bool? renderWhitespace,
    bool? highlightActiveLine,
    bool? smoothScrolling,
  }) {
    return EditorSettings(
      wordWrap: wordWrap ?? this.wordWrap,
      showIndentGuides: showIndentGuides ?? this.showIndentGuides,
      bracketColorization: bracketColorization ?? this.bracketColorization,
      showMinimap: showMinimap ?? this.showMinimap,
      showBreadcrumbs: showBreadcrumbs ?? this.showBreadcrumbs,
      stickyScroll: stickyScroll ?? this.stickyScroll,
      tabSize: tabSize ?? this.tabSize,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      renderWhitespace: renderWhitespace ?? this.renderWhitespace,
      highlightActiveLine: highlightActiveLine ?? this.highlightActiveLine,
      smoothScrolling: smoothScrolling ?? this.smoothScrolling,
    );
  }
}

/// Settings change notifier.
class EditorSettingsNotifier extends ChangeNotifier {
  EditorSettings _settings = const EditorSettings();

  EditorSettings get settings => _settings;

  void update(EditorSettings Function(EditorSettings) updater) {
    _settings = updater(_settings);
    notifyListeners();
  }

  void toggleWordWrap() => update((s) => s.copyWith(wordWrap: !s.wordWrap));
  void toggleIndentGuides() => update((s) => s.copyWith(showIndentGuides: !s.showIndentGuides));
  void toggleBracketColorization() => update((s) => s.copyWith(bracketColorization: !s.bracketColorization));
  void toggleMinimap() => update((s) => s.copyWith(showMinimap: !s.showMinimap));
  void toggleBreadcrumbs() => update((s) => s.copyWith(showBreadcrumbs: !s.showBreadcrumbs));
  void toggleStickyScroll() => update((s) => s.copyWith(stickyScroll: !s.stickyScroll));
  void setFontSize(double size) => update((s) => s.copyWith(fontSize: size));
  void setTabSize(int size) => update((s) => s.copyWith(tabSize: size));
}
