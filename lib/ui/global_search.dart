/// Global Search — search across all files in the workspace (Ctrl+Shift+F).
///
/// Features:
///   - Fuzzy text search across all files
///   - Regex support
///   - File type filter
///   - Results grouped by file
///   - Jump to result in editor
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

library;



/// A single search result.
class SearchResult {
  final String filePath;
  final int lineNumber;
  final String lineContent;
  final int matchStart;
  final int matchEnd;

  const SearchResult({
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
    required this.matchStart,
    required this.matchEnd,
  });
}

/// Shows the global search dialog.
class GlobalSearch extends StatefulWidget {
  final String workspaceRoot;
  final void Function(String filePath, int line) onJumpTo;

  const GlobalSearch({
    super.key,
    required this.workspaceRoot,
    required this.onJumpTo,
  });

  static Future<void> show(
    BuildContext context, {
    required String workspaceRoot,
    required void Function(String filePath, int line) onJumpTo,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GlobalSearch(workspaceRoot: workspaceRoot, onJumpTo: onJumpTo),
    );
  }

  @override
  State<GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends State<GlobalSearch> {
  final _searchCtrl = TextEditingController();
  final _filterCtrl = TextEditingController();
  final _focus = FocusNode();
  Map<String, List<SearchResult>> _results = {};
  bool _loading = false;
  bool _useRegex = false;
  bool _caseSensitive = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _filterCtrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search());
  }

  Future<void> _search() async {
    final query = _searchCtrl.text;
    if (query.isEmpty) {
      setState(() => _results = {});
      return;
    }

    setState(() => _loading = true);

    final results = <String, List<SearchResult>>{};
    final filter = _filterCtrl.text.trim().toLowerCase();
    final root = Directory(widget.workspaceRoot);

    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (entity.path.contains('/node_modules/') || entity.path.contains('/build/')) continue;
        if (entity.path.contains('/.git/')) continue;

        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;

        // File filter
        if (filter.isNotEmpty && !name.toLowerCase().contains(filter)) continue;

        // Skip binary files
        final ext = p.extension(name).toLowerCase();
        if (['.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.eot', '.zip', '.tar', '.gz', '.exe', '.so', '.dylib'].contains(ext)) continue;

        try {
          final content = await entity.readAsString().timeout(const Duration(seconds: 2));
          final fileResults = <SearchResult>[];

          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            final matches = _findMatches(line, query);
            for (final match in matches) {
              fileResults.add(SearchResult(
                filePath: entity.path,
                lineNumber: i,
                lineContent: line,
                matchStart: match.$1,
                matchEnd: match.$2,
              ));
            }
          }

          if (fileResults.isNotEmpty) {
            results[entity.path] = fileResults;
          }
        } catch (_) {}
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  List<(int, int)> _findMatches(String line, String query) {
    final matches = <(int, int)>[];
    final text = _caseSensitive ? line : line.toLowerCase();
    final q = _caseSensitive ? query : query.toLowerCase();

    if (_useRegex) {
      try {
        final regex = RegExp(q);
        for (final m in regex.allMatches(text)) {
          matches.add((m.start, m.end));
        }
      } catch (_) {}
    } else {
      var start = 0;
      while (true) {
        final idx = text.indexOf(q, start);
        if (idx < 0) break;
        matches.add((idx, idx + q.length));
        start = idx + 1;
      }
    }

    return matches;
  }

  int get _totalMatches {
    var count = 0;
    for (final list in _results.values) {
      count += list.length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),

            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: TextField(
                controller: _searchCtrl, focusNode: _focus,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  hintText: 'Search in files...',
                  prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Regex toggle
                      IconButton(
                        icon: Icon(Icons.code, size: 16, color: _useRegex ? cs.primary : cs.onSurfaceVariant),
                        tooltip: 'Regex',
                        onPressed: () => setState(() => _useRegex = !_useRegex),
                      ),
                      // Case sensitive toggle
                      IconButton(
                        icon: Icon(Icons.text_fields, size: 16, color: _caseSensitive ? cs.primary : cs.onSurfaceVariant),
                        tooltip: 'Case Sensitive',
                        onPressed: () => setState(() => _caseSensitive = !_caseSensitive),
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  filled: true, fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // File filter
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _filterCtrl,
                style: TextStyle(color: cs.onSurface, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Filter by filename (e.g. *.dart)',
                  prefixIcon: Icon(Icons.filter_list, size: 16, color: cs.onSurfaceVariant),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  filled: true, fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                onChanged: (_) => _search(),
              ),
            ),

            // Results summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  if (_loading)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Text('$_totalMatches matches in ${_results.length} files',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),

            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

            // Results
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text(
                      _searchCtrl.text.isEmpty ? 'Type to search across all files' : 'No matches found',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, fileIdx) {
                        final filePath = _results.keys.elementAt(fileIdx);
                        final matches = _results[filePath]!;
                        final fileName = p.basename(filePath);
                        final relPath = p.relative(filePath, from: widget.workspaceRoot);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // File header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                              child: Row(
                                children: [
                                  Icon(Icons.insert_drive_file, size: 14, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(fileName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
                                  ),
                                  Text('${matches.length}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            // Matches
                            ...matches.take(5).map((m) => InkWell(
                              onTap: () { Navigator.pop(context); widget.onJumpTo(m.filePath, m.lineNumber); },
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(28, 4, 12, 4),
                                child: Row(
                                  children: [
                                    Text('${m.lineNumber + 1}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontFamily: 'monospace')),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m.lineContent.trim(),
                                        style: TextStyle(fontSize: 11, color: cs.onSurface, fontFamily: 'monospace'),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                            if (matches.length > 5)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(28, 2, 12, 6),
                                child: Text('... and ${matches.length - 5} more', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
