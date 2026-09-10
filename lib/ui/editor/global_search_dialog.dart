import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/workspace/panda_workspace.dart';

class SearchMatchResult {
  final String filePath;
  final int lineNumber;
  final String lineText;

  SearchMatchResult({
    required this.filePath,
    required this.lineNumber,
    required this.lineText,
  });
}

class GlobalSearchDialog extends StatefulWidget {
  final Function(String filePath, int lineNumber)? onFileSelected;
  final String? workspacePath;

  const GlobalSearchDialog({
    super.key,
    this.onFileSelected,
    this.workspacePath,
  });

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController(text: 'build, .git, .dart_tool, node_modules');

  bool _matchCase = false;
  bool _useRegex = false;
  bool _showReplace = false;
  bool _isSearching = false;
  bool _isReplacing = false;
  String? _error;
  List<SearchMatchResult> _results = [];

  @override
  void dispose() {
    _queryController.dispose();
    _replaceController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  RegExp? _pattern() {
    final query = _queryController.text;
    if (query.isEmpty) return null;
    try {
      return RegExp(
        _useRegex ? query : RegExp.escape(query),
        caseSensitive: _matchCase,
      );
    } on FormatException catch (error) {
      _error = error.message;
      return null;
    }
  }

  Future<void> _performSearch() async {
    final query = _queryController.text;
    if (query.isEmpty) return;

    final pattern = _pattern();
    if (pattern == null) {
      setState(() {});
      return;
    }

    setState(() {
      _isSearching = true;
      _results = [];
      _error = null;
    });

    final workspacePath = widget.workspacePath;
    final workspace = PandaWorkspaceManager().currentWorkspace;
    final List<SearchMatchResult> matches = [];

    final includes = _includeController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final excludes = _excludeController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    if (workspacePath != null && workspacePath.isNotEmpty) {
      await _searchFolder(
        workspacePath,
        query,
        includes,
        excludes,
        matches,
        pattern,
      );
    } else if (workspace != null) {
      for (var folder in workspace.folders) {
        await _searchFolder(
          folder.uri.path,
          query,
          includes,
          excludes,
          matches,
          pattern,
        );
      }
    }

    setState(() {
      _results = matches;
      _isSearching = false;
    });
  }

  bool _matchesInclude(String filePath, List<String> includes) {
    if (includes.isEmpty) return true;
    final name = filePath.split(Platform.pathSeparator).last;
    return includes.any((pattern) {
      final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
      return RegExp('^$escaped\$', caseSensitive: false).hasMatch(name);
    });
  }

  Future<void> _searchFolder(
    String folderPath,
    String query,
    List<String> includes,
    List<String> excludes,
    List<SearchMatchResult> matches,
    RegExp pattern,
  ) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return;

      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final path = entity.path;
          if (excludes.any((ex) => path.contains(ex)) ||
              !_matchesInclude(path, includes)) {
            continue;
          }

          try {
            final content = await entity.readAsString();
            final lines = content.split('\n');
            for (int i = 0; i < lines.length; i++) {
              final line = lines[i];
              final matched = pattern.hasMatch(line);

              if (matched) {
                matches.add(SearchMatchResult(
                  filePath: path,
                  lineNumber: i + 1,
                  lineText: line.trim(),
                ));
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _replaceAll() async {
    if (_isReplacing || _queryController.text.isEmpty) return;
    await _performSearch();
    if (!mounted || _results.isEmpty) return;

    final filePaths = _results.map((result) => result.filePath).toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all matches?'),
        content: Text(
          'Replace ${_results.length} match(es) in ${filePaths.length} file(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final pattern = _pattern();
    if (pattern == null) {
      setState(() {});
      return;
    }
    setState(() {
      _isReplacing = true;
      _error = null;
    });

    var changedFiles = 0;
    try {
      for (final filePath in filePaths) {
        final file = File(filePath);
        final original = await file.readAsString();
        final replacement = original.replaceAll(pattern, _replaceController.text);
        if (replacement != original) {
          await file.writeAsString(replacement);
          changedFiles++;
        }
      }
      if (mounted) {
        setState(() => _isReplacing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated $changedFiles file(s).')),
        );
        await _performSearch();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isReplacing = false;
          _error = 'Replacement failed: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, size: 20),
                const SizedBox(width: 8),
                const Text('Search Across Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: 'Search term...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _performSearch,
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _performSearch(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilterChip(
                  label: const Text('Match Case'),
                  selected: _matchCase,
                  onSelected: (val) => setState(() => _matchCase = val),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Regex'),
                  selected: _useRegex,
                  onSelected: (val) => setState(() => _useRegex = val),
                ),
                 const SizedBox(width: 8),
                 FilterChip(
                   label: const Text('Replace'),
                   selected: _showReplace,
                   onSelected: (val) => setState(() => _showReplace = val),
                 ),
              ],
            ),
            const SizedBox(height: 8),
             if (_showReplace) ...[
               TextField(
                 controller: _replaceController,
                 decoration: const InputDecoration(
                   labelText: 'Replace with',
                   isDense: true,
                   border: OutlineInputBorder(),
                 ),
               ),
               const SizedBox(height: 8),
             ],
             Row(
               children: [
                 Expanded(
                   child: TextField(
                     controller: _includeController,
                     decoration: const InputDecoration(
                       labelText: 'Include (e.g. *.dart, *.js)',
                       isDense: true,
                       border: OutlineInputBorder(),
                     ),
                   ),
                 ),
                 if (_showReplace) ...[
                   const SizedBox(width: 8),
                   FilledButton.tonal(
                     onPressed: _isReplacing ? null : _replaceAll,
                     child: Text(_isReplacing ? 'Replacing…' : 'Replace all'),
                   ),
                 ],
               ],
             ),
             const SizedBox(height: 8),
            TextField(
              controller: _excludeController,
              decoration: const InputDecoration(
                labelText: 'Exclude pattern',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_isSearching) const LinearProgressIndicator(),
             if (_error != null)
               Padding(
                 padding: const EdgeInsets.only(top: 6),
                 child: Text(
                   _error!,
                   style: const TextStyle(color: Colors.red, fontSize: 12),
                 ),
               ),
            Text('${_results.length} results found', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final item = _results[index];
                  return ListTile(
                    dense: true,
                    title: Text('${item.filePath.split('/').last}:${item.lineNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(item.lineText, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      widget.onFileSelected?.call(item.filePath, item.lineNumber);
                      Navigator.of(context).pop();
                    },
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
