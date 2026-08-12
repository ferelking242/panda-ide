import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/fs/panda_file_system_provider.dart';
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

  const GlobalSearchDialog({Key? key, this.onFileSelected}) : super(key: key);

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController(text: 'build, .git, .dart_tool, node_modules');

  bool _matchCase = false;
  bool _useRegex = false;
  bool _isSearching = false;
  List<SearchMatchResult> _results = [];

  Future<void> _performSearch() async {
    final query = _queryController.text;
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _results = [];
    });

    final workspace = PandaWorkspaceManager().currentWorkspace;
    final List<SearchMatchResult> matches = [];

    final excludes = _excludeController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    RegExp? regex;
    if (_useRegex) {
      try {
        regex = RegExp(query, caseSensitive: _matchCase);
      } catch (_) {}
    }

    if (workspace != null) {
      for (var folder in workspace.folders) {
        await _searchFolder(folder.uri.path, query, excludes, matches, regex);
      }
    }

    setState(() {
      _results = matches;
      _isSearching = false;
    });
  }

  Future<void> _searchFolder(String folderPath, String query, List<String> excludes, List<SearchMatchResult> matches, RegExp? regex) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return;

      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final path = entity.path;
          if (excludes.any((ex) => path.contains(ex))) continue;

          try {
            final content = await entity.readAsString();
            final lines = content.split('\n');
            for (int i = 0; i < lines.length; i++) {
              final line = lines[i];
              bool matched = false;
              if (regex != null) {
                matched = regex.hasMatch(line);
              } else if (_matchCase) {
                matched = line.contains(query);
              } else {
                matched = line.toLowerCase().contains(query.toLowerCase());
              }

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
