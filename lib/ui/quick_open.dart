/// Quick Open (Ctrl+P) — fuzzy file search across the workspace.
///
/// VS Code-style: type to filter, arrow keys to navigate, Enter to open.
/// Shows recent files, matches by filename and path.
library;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/constants.dart';





class QuickOpenResult {
  final String filePath;
  final String relativePath;
  final double score;

  const QuickOpenResult({
    required this.filePath,
    required this.relativePath,
    required this.score,
  });
}

class QuickOpen extends StatefulWidget {
  final String? initialQuery;
  final String workspaceRoot;
  final void Function(String filePath) onOpen;

  const QuickOpen({
    super.key,
    this.initialQuery,
    required this.workspaceRoot,
    required this.onOpen,
  });

  static Future<void> show(
    BuildContext context, {
    required String workspaceRoot,
    required void Function(String filePath) onOpen,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickOpenSheet(
        workspaceRoot: workspaceRoot,
        onOpen: onOpen,
      ),
    );
  }

  @override
  State<QuickOpen> createState() => _QuickOpenState();
}

class _QuickOpenState extends State<QuickOpen> {
  @override
  Widget build(BuildContext context) {
    return _QuickOpenSheet(
      workspaceRoot: widget.workspaceRoot,
      onOpen: widget.onOpen,
    );
  }
}

class _QuickOpenSheet extends StatefulWidget {
  final String workspaceRoot;
  final void Function(String filePath) onOpen;

  const _QuickOpenSheet({required this.workspaceRoot, required this.onOpen});

  @override
  State<_QuickOpenSheet> createState() => _QuickOpenSheetState();
}

class _QuickOpenSheetState extends State<_QuickOpenSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _scrollCtrl = ScrollController();
  List<QuickOpenResult> _results = [];
  int _selectedIndex = 0;
  bool _loading = true;
  List<String> _allFiles = [];

  // Recent files cache
  static final List<String> _recentFiles = [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _scanWorkspace();
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onQuery);
    _ctrl.dispose();
    _focus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanWorkspace() async {
    final root = Directory(widget.workspaceRoot);
    if (!await root.exists()) {
      setState(() { _loading = false; });
      return;
    }

    final files = <String>[];
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final name = p.basename(entity.path);
          // Skip hidden, node_modules, build dirs
          if (name.startsWith('.') || name == 'node_modules' || name == 'build') continue;
          if (entity.path.contains('/node_modules/') || entity.path.contains('/build/')) continue;
          files.add(entity.path);
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _allFiles = files;
      _loading = false;
      _onQuery();
    });
  }

  void _onQuery() {
    final query = _ctrl.text.trim();
    setState(() {
      _results = _fuzzySearch(query, _allFiles, widget.workspaceRoot);
      _selectedIndex = 0;
    });
    // Scroll to top
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
  }

  List<QuickOpenResult> _fuzzySearch(String query, List<String> files, String root) {
    if (query.isEmpty) {
      // Show recent files first, then alphabetical
      final recent = _recentFiles
          .where((f) => files.contains(f))
          .take(5)
          .map((f) => QuickOpenResult(
                filePath: f,
                relativePath: p.relative(f, from: root),
                score: 100,
              ))
          .toList();
      final rest = files
          .take(50)
          .where((f) => !_recentFiles.contains(f))
          .map((f) => QuickOpenResult(
                filePath: f,
                relativePath: p.relative(f, from: root),
                score: 50,
              ))
          .toList();
      return [...recent, ...rest];
    }

    final q = query.toLowerCase();
    final scored = <QuickOpenResult>[];

    for (final file in files) {
      final rel = p.relative(file, from: root);
      final name = p.basename(file).toLowerCase();
      final path = rel.toLowerCase();

      double score = 0;

      // Exact filename match
      if (name == q) {
        score = 100;
      }
      // Starts with query
      else if (name.startsWith(q)) {
        score = 90;
      }
      // Contains query in filename
      else if (name.contains(q)) {
        score = 70;
      }
      // Contains query in path
      else if (path.contains(q)) {
        score = 50;
      }
      // Fuzzy match
      else if (_fuzzyMatch(q, name)) {
        score = 30;
      }

      // Bonus for recent files
      if (_recentFiles.contains(file)) {
        score += 20;
      }

      // Bonus for shorter paths (more relevant)
      score += (100 - rel.length.clamp(0, 100)) * 0.1;

      if (score > 0) {
        scored.add(QuickOpenResult(filePath: file, relativePath: rel, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(30).toList();
  }

  bool _fuzzyMatch(String query, String text) {
    var qi = 0;
    for (var ti = 0; ti < text.length && qi < query.length; ti++) {
      if (text[ti] == query[qi]) qi++;
    }
    return qi == query.length;
  }

  void _openSelected() {
    if (_results.isEmpty) return;
    final result = _results[_selectedIndex];
    // Add to recent
    _recentFiles.remove(result.filePath);
    _recentFiles.insert(0, result.filePath);
    if (_recentFiles.length > 20) _recentFiles.removeLast();

    Navigator.of(context).pop();
    widget.onOpen(result.filePath);
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _results.length - 1);
    });
    // Ensure visible
    final targetOffset = _selectedIndex * 48.0;
    if (targetOffset < _scrollCtrl.offset) {
      _scrollCtrl.animateTo(targetOffset, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    } else if (targetOffset > _scrollCtrl.offset + 300) {
      _scrollCtrl.animateTo(targetOffset - 300, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)],
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
            ),

            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _moveSelection(1);
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _moveSelection(-1);
                    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                      _openSelected();
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  style: TextStyle(color: cs.onSurface, fontSize: 15),
                  cursorColor: cs.primary,
                  decoration: InputDecoration(
                    hintText: 'Search files by name...',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 18),
                            onPressed: () => _ctrl.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),

            // Results count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    _loading ? 'Scanning...' : '${_results.length} files',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    '↑↓ navigate • Enter open • Esc close',
                    style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 10),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

            // Results list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _ctrl.text.isEmpty ? 'Start typing to search...' : 'No files match',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          itemCount: _results.length,
                          itemExtent: 48,
                          itemBuilder: (_, i) {
                            final result = _results[i];
                            final isSelected = i == _selectedIndex;
                            final isRecent = _recentFiles.contains(result.filePath);
                            final ext = p.extension(result.filePath).toLowerCase();

                            return Material(
                              color: isSelected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() => _selectedIndex = i);
                                  _openSelected();
                                },
                                onHover: (_) => setState(() => _selectedIndex = i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      // File icon
                                      Icon(_fileIcon(ext), size: 18, color: _fileColor(ext)),
                                      const SizedBox(width: 10),
                                      // Filename (bold) + path (dim)
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.basename(result.filePath),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: cs.onSurface,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              result.relativePath,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Recent badge
                                      if (isRecent)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: cs.primary.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('recent', style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.w600)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case '.dart': return Icons.code;
      case '.py': return Icons.code;
      case '.js': case '.ts': return Icons.javascript;
      case '.json': return Icons.data_object;
      case '.yaml': case '.yml': return Icons.settings;
      case '.md': return Icons.description;
      case '.xml': return Icons.web;
      case '.gradle': return Icons.build;
      case '.kt': case '.java': return Icons.android;
      case '.swift': return Icons.apple;
      case '.css': case '.scss': return Icons.palette;
      case '.html': return Icons.language;
      default: return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String ext) {
    switch (ext) {
      case '.dart': return const Color(0xFF00B4D8);
      case '.py': return const Color(0xFFFFD43B);
      case '.js': case '.ts': return const Color(0xFFF7DF1E);
      case '.json': return const Color(0xFF8BC34A);
      case '.yaml': case '.yml': return const Color(0xFFCB171E);
      case '.md': return const Color(0xFF42A5F5);
      case '.kt': case '.java': return const Color(0xFF3DDC84);
      default: return const Color(0xFF78909C);
    }
  }
}
