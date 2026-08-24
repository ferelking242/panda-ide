/// Code folding — fold/unfold code scopes.
///
/// Supports: classes, functions, if/else, for, while, switch, try/catch,
/// comments, regions, and indentation-based folding.
library;
import 'package:flutter/material.dart';



/// Represents a foldable region in the code.
class FoldRegion {
  final int startLine;
  final int endLine;
  final String type; // 'class', 'function', 'if', 'comment', 'region', 'indent'
  final String label;
  bool isCollapsed;

  FoldRegion({
    required this.startLine,
    required this.endLine,
    required this.type,
    this.label = '',
    this.isCollapsed = false,
  });

  int get lineCount => endLine - startLine + 1;
}

/// Detects foldable regions in Dart/JS/Python/Kotlin code.
class FoldingDetector {
  /// Detect all foldable regions in the given code.
  static List<FoldRegion> detect(String code, {String? language}) {
    final lines = code.split('\n');
    final regions = <FoldRegion>[];
    final stack = <_FoldScope>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      // Skip empty lines
      if (trimmed.isEmpty) continue;

      // Single-line comments block
      if (trimmed.startsWith('//') && i + 1 < lines.length) {
        var end = i;
        while (end + 1 < lines.length && lines[end + 1].trim().startsWith('//')) {
          end++;
        }
        if (end > i) {
          regions.add(FoldRegion(
            startLine: i,
            endLine: end,
            type: 'comment',
            label: trimmed.length > 30 ? trimmed.substring(0, 30) : trimmed,
          ));
        }
      }

      // Block comments /* ... */
      if (trimmed.startsWith('/*') && !trimmed.endsWith('*/')) {
        var end = i;
        while (end + 1 < lines.length && !lines[end].trim().endsWith('*/')) {
          end++;
        }
        regions.add(FoldRegion(startLine: i, endLine: end, type: 'comment', label: 'Block comment'));
      }

      // Region markers
      if (trimmed.startsWith('// region') || trimmed.toLowerCase().startsWith('# region')) {
        stack.add(_FoldScope(type: 'region', startLine: i, label: trimmed.substring(8).trim()));
      }
      if ((trimmed.startsWith('// end region') || trimmed.toLowerCase().startsWith('# end region')) && stack.isNotEmpty) {
        final scope = stack.lastWhere((s) => s.type == 'region', orElse: () => _FoldScope(type: '', startLine: i));
        if (scope.type == 'region') {
          stack.remove(scope);
          regions.add(FoldRegion(
            startLine: scope.startLine,
            endLine: i,
            type: 'region',
            label: scope.label,
          ));
        }
      }

      // Count opening braces
      for (final ch in line.split('')) {
        if (ch == '{' || ch == '(' || ch == '[') {
          stack.add(_FoldScope(type: _detectScopeType(trimmed), startLine: i));
        }
      }

      // Count closing braces
      for (final ch in line.split('').reversed) {
        if (ch == '}' || ch == ')' || ch == ']') {
          if (stack.isNotEmpty) {
            final scope = stack.removeLast();
            final endLine = i;
            // Only fold if region is > 1 line
            if (endLine > scope.startLine) {
              regions.add(FoldRegion(
                startLine: scope.startLine,
                endLine: endLine,
                type: scope.type,
                label: lines[scope.startLine].trim(),
              ));
            }
          }
        }
      }
    }

    return regions;
  }

  static String _detectScopeType(String line) {
    if (RegExp(r'^(class|abstract\s+class|enum|mixin)\s').hasMatch(line)) return 'class';
    if (RegExp(r'^(void|int|String|bool|double|Future|Stream|List|Map|Set|dynamic|var|final|const|static|async|override)\s').hasMatch(line)) return 'function';
    if (RegExp(r'^(if|else|for|while|switch|try|catch|finally)\b').hasMatch(line)) return 'control';
    return 'block';
  }
}

/// Manages fold state for the editor.
class FoldingManager extends ChangeNotifier {
  List<FoldRegion> _regions = [];
  final Set<int> _collapsedLines = {};

  List<FoldRegion> get regions => List.unmodifiable(_regions);
  Set<int> get collapsedLines => Set.unmodifiable(_collapsedLines);

  /// Update regions when document changes.
  void updateRegions(String code, {String? language}) {
    _regions = FoldingDetector.detect(code, language: language);
    // Remove collapsed state for lines that no longer exist
    _collapsedLines.removeWhere((line) => !_regions.any((r) => r.startLine == line));
    notifyListeners();
  }

  /// Toggle fold at the given line.
  void toggleFold(int line) {
    final region = _regions.where((r) => r.startLine == line).firstOrNull;
    if (region == null) return;

    if (_collapsedLines.contains(line)) {
      _collapsedLines.remove(line);
      region.isCollapsed = false;
    } else {
      _collapsedLines.add(line);
      region.isCollapsed = true;
    }
    notifyListeners();
  }

  /// Check if a line is hidden (inside a collapsed region).
  bool isLineHidden(int line) {
    for (final region in _regions) {
      if (region.isCollapsed && line > region.startLine && line <= region.endLine) {
        return true;
      }
    }
    return false;
  }

  /// Get visible line count (total - hidden).
  int visibleLineCount(int totalLines) {
    var hidden = 0;
    for (final region in _regions) {
      if (region.isCollapsed) {
        hidden += region.endLine - region.startLine;
      }
    }
    return totalLines - hidden;
  }

  /// Map a visible line index to the actual line index.
  int visibleToActual(int visibleLine, int totalLines) {
    var actual = 0;
    var visible = 0;

    for (var i = 0; i < totalLines; i++) {
      if (visible == visibleLine) return i;

      bool hidden = false;
      for (final region in _regions) {
        if (region.isCollapsed && i > region.startLine && i <= region.endLine) {
          hidden = true;
          break;
        }
      }

      if (!hidden) {
        visible++;
      }
      actual = i + 1;
    }

    return actual.clamp(0, totalLines - 1);
  }

  /// Fold all regions.
  void foldAll() {
    for (final region in _regions) {
      _collapsedLines.add(region.startLine);
      region.isCollapsed = true;
    }
    notifyListeners();
  }

  /// Unfold all regions.
  void unfoldAll() {
    _collapsedLines.clear();
    for (final region in _regions) {
      region.isCollapsed = false;
    }
    notifyListeners();
  }
}

class _FoldScope {
  final String type;
  final int startLine;
  final String label;

  _FoldScope({required this.type, required this.startLine, this.label = ''});
}

/// Fold indicator widget for the editor gutter.
class FoldIndicator extends StatelessWidget {
  final FoldRegion? region;
  final bool isHidden;
  final VoidCallback? onTap;

  const FoldIndicator({
    super.key,
    this.region,
    this.isHidden = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (region == null) return const SizedBox(width: 20);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: Icon(
          region!.isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
