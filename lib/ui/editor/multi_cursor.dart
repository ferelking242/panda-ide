/// Multi-cursor support for the editor.
///
/// Features:
///   - Ctrl+D: Select next occurrence
///   - Ctrl+Shift+L: Select all occurrences
///   - Alt+Click: Add cursor at position
///   - Ctrl+Alt+Up/Down: Add cursor above/below
///   - Multiple cursors for simultaneous editing
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents a single cursor position in the editor.
class CursorPosition {
  final int line;
  final int column;

  const CursorPosition({required this.line, required this.column});

  CursorPosition copyWith({int? line, int? column}) {
    return CursorPosition(line: line ?? this.line, column: column ?? this.column);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CursorPosition && line == other.line && column == other.column;

  @override
  int get hashCode => line.hashCode ^ column.hashCode;

  @override
  String toString() => '($line:$column)';
}

/// Represents a selection range between two cursor positions.
class SelectionRange {
  final CursorPosition start;
  final CursorPosition end;

  const SelectionRange({required this.start, required this.end});

  bool get isCollapsed => start == end;

  SelectionRange normalized() {
    if (start.line < end.line || (start.line == end.line && start.column <= end.column)) {
      return this;
    }
    return SelectionRange(start: end, end: start);
  }
}

/// Manages multiple cursors and selections for the editor.
class MultiCursorManager extends ChangeNotifier {
  final List<CursorPosition> _cursors = [const CursorPosition(line: 0, column: 0)];
  SelectionRange? _lastFoundRange;
  String _lastSearchText = '';

  List<CursorPosition> get cursors => List.unmodifiable(_cursors);
  int get cursorCount => _cursors.length;
  bool get hasMultipleCursors => _cursors.length > 1;

  CursorPosition get primaryCursor => _cursors.first;

  /// Add a cursor at the given position (Alt+Click).
  void addCursor(CursorPosition position) {
    if (!_cursors.contains(position)) {
      _cursors.add(position);
      _cursors.sort((a, b) {
        if (a.line != b.line) return a.line.compareTo(b.line);
        return a.column.compareTo(b.column);
      });
      notifyListeners();
    }
  }

  /// Remove a cursor at the given position.
  void removeCursor(CursorPosition position) {
    if (_cursors.length > 1) {
      _cursors.remove(position);
      notifyListeners();
    }
  }

  /// Move primary cursor to a new position.
  void movePrimaryTo(CursorPosition position) {
    _cursors[0] = position;
    notifyListeners();
  }

  /// Select next occurrence of the given text (Ctrl+D).
  /// Returns true if a match was found.
  bool selectNextOccurrence(String text, String documentContent, {CursorPosition? after}) {
    if (text.isEmpty) return false;

    final searchFrom = after ?? _cursors.last;
    final lines = documentContent.split('\n');

    // Search from current position
    for (var line = searchFrom.line; line < lines.length; line++) {
      final startCol = (line == searchFrom.line) ? searchFrom.column + 1 : 0;
      final lineText = lines[line];
      final idx = lineText.indexOf(text, startCol);

      if (idx >= 0) {
        final newCursor = CursorPosition(line: line, column: idx);
        final endCursor = CursorPosition(line: line, column: idx + text.length);

        if (!_cursors.contains(newCursor)) {
          _cursors.add(newCursor);
          _lastFoundRange = SelectionRange(start: newCursor, end: endCursor);
          _lastSearchText = text;
          notifyListeners();
          return true;
        }
      }
    }

    // Wrap around to beginning
    for (var line = 0; line <= searchFrom.line; line++) {
      final endCol = (line == searchFrom.line) ? searchFrom.column : lines[line].length;
      final lineText = lines[line];
      final idx = lineText.indexOf(text, 0);

      if (idx >= 0 && idx < endCol) {
        final newCursor = CursorPosition(line: line, column: idx);
        if (!_cursors.contains(newCursor)) {
          _cursors.add(newCursor);
          _lastFoundRange = SelectionRange(
            start: newCursor,
            end: CursorPosition(line: line, column: idx + text.length),
          );
          _lastSearchText = text;
          notifyListeners();
          return true;
        }
      }
    }

    return false;
  }

  /// Select ALL occurrences of the given text (Ctrl+Shift+L).
  int selectAllOccurrences(String text, String documentContent) {
    if (text.isEmpty) return 0;

    _cursors.clear();
    final lines = documentContent.split('\n');
    var count = 0;

    for (var line = 0; line < lines.length; line++) {
      var startCol = 0;
      while (true) {
        final idx = lines[line].indexOf(text, startCol);
        if (idx < 0) break;
        _cursors.add(CursorPosition(line: line, column: idx));
        startCol = idx + text.length;
        count++;
      }
    }

    if (count > 0) {
      _lastSearchText = text;
      notifyListeners();
    }

    return count;
  }

  /// Add cursor above/below current (Ctrl+Alt+Up/Down).
  void addCursorAbove(String documentContent) {
    final last = _cursors.last;
    if (last.line > 0) {
      final newLine = last.line - 1;
      final lines = documentContent.split('\n');
      final maxCol = newLine < lines.length ? lines[newLine].length : 0;
      final newCol = last.column.clamp(0, maxCol);
      addCursor(CursorPosition(line: newLine, column: newCol));
    }
  }

  void addCursorBelow(String documentContent) {
    final last = _cursors.last;
    final lines = documentContent.split('\n');
    if (last.line < lines.length - 1) {
      final newLine = last.line + 1;
      final maxCol = lines[newLine].length;
      final newCol = last.column.clamp(0, maxCol);
      addCursor(CursorPosition(line: newLine, column: newCol));
    }
  }

  /// Collapse all cursors to the primary cursor.
  void collapseCursors() {
    if (_cursors.length > 1) {
      final primary = _cursors.first;
      _cursors.clear();
      _cursors.add(primary);
      notifyListeners();
    }
  }

  /// Clear all cursors and reset to single cursor at (0,0).
  void reset() {
    _cursors.clear();
    _cursors.add(const CursorPosition(line: 0, column: 0));
    _lastFoundRange = null;
    _lastSearchText = '';
    notifyListeners();
  }
}

/// Keyboard handler for multi-cursor shortcuts.
///
/// Usage: Wrap your editor with this and call handleKey on key events.
class MultiCursorHandler {
  final MultiCursorManager manager;
  final String Function() getDocumentContent;
  final String Function() getSelectedText;
  final void Function(String text) replaceSelection;

  MultiCursorHandler({
    required this.manager,
    required this.getDocumentContent,
    required this.getSelectedText,
    required this.replaceSelection,
  });

  /// Handle a key event. Returns true if handled.
  bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl+D: Select next occurrence
    if (isCtrl && !isAlt && !isShift && event.logicalKey == LogicalKeyboardKey.keyD) {
      final selected = getSelectedText();
      if (selected.isNotEmpty) {
        manager.selectNextOccurrence(selected, getDocumentContent());
        return true;
      }
      return false;
    }

    // Ctrl+Shift+L: Select all occurrences
    if (isCtrl && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyL) {
      final selected = getSelectedText();
      if (selected.isNotEmpty) {
        manager.selectAllOccurrences(selected, getDocumentContent());
        return true;
      }
      return false;
    }

    // Ctrl+Alt+Up: Add cursor above
    if (isCtrl && isAlt && !isShift && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      manager.addCursorAbove(getDocumentContent());
      return true;
    }

    // Ctrl+Alt+Down: Add cursor below
    if (isCtrl && isAlt && !isShift && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      manager.addCursorBelow(getDocumentContent());
      return true;
    }

    // Escape: Collapse cursors
    if (!isCtrl && !isAlt && !isShift && event.logicalKey == LogicalKeyboardKey.escape) {
      if (manager.hasMultipleCursors) {
        manager.collapseCursors();
        return true;
      }
    }

    return false;
  }
}

/// Widget that displays multiple cursor indicators in the editor gutter.
class MultiCursorIndicators extends StatelessWidget {
  final MultiCursorManager manager;
  final double lineHeight;
  final double gutterWidth;

  const MultiCursorIndicators({
    super.key,
    required this.manager,
    required this.lineHeight,
    this.gutterWidth = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        if (!manager.hasMultipleCursors) return const SizedBox.shrink();

        return Column(
          children: [
            for (var i = 0; i < manager.cursors.length; i++)
              Container(
                width: gutterWidth,
                height: lineHeight,
                alignment: Alignment.center,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == 0 ? Colors.blue : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
