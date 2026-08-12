import 'dart:io';

class IndexedSymbol {
  final String name;
  final String type; // class, function, variable
  final String filePath;
  final int lineNumber;
  final String lineContent;

  IndexedSymbol({
    required this.name,
    required this.type,
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
  });
}

class SemanticWorkspaceIndexer {
  static final SemanticWorkspaceIndexer _instance = SemanticWorkspaceIndexer._internal();
  factory SemanticWorkspaceIndexer() => _instance;
  SemanticWorkspaceIndexer._internal();

  final List<IndexedSymbol> _symbolsIndex = [];
  bool _isIndexing = false;

  bool get isIndexing => _isIndexing;

  Future<void> indexWorkspace(String rootPath) async {
    _isIndexing = true;
    _symbolsIndex.clear();

    try {
      final dir = Directory(rootPath);
      if (!await dir.exists()) return;

      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && (entity.path.endsWith('.dart') || entity.path.endsWith('.js') || entity.path.endsWith('.ts') || entity.path.endsWith('.kt'))) {
          await _indexFile(entity.path);
        }
      }
    } catch (_) {
    } finally {
      _isIndexing = false;
    }
  }

  Future<void> _indexFile(String filePath) async {
    try {
      final file = File(filePath);
      final lines = await file.readAsLines();

      final classRegex = RegExp(r'class\s+([A-Za-z0-9_]+)');
      final funcRegex = RegExp(r'(void|Future|String|int|bool|dynamic|[A-Z][A-Za-z0-9_]*)\s+([a-z][A-Za-z0-9_]*)\s*\(');

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        final classMatch = classRegex.firstMatch(line);
        if (classMatch != null) {
          _symbolsIndex.add(IndexedSymbol(
            name: classMatch.group(1)!,
            type: 'class',
            filePath: filePath,
            lineNumber: i + 1,
            lineContent: line.trim(),
          ));
        }

        final funcMatch = funcRegex.firstMatch(line);
        if (funcMatch != null) {
          _symbolsIndex.add(IndexedSymbol(
            name: funcMatch.group(2)!,
            type: 'function',
            filePath: filePath,
            lineNumber: i + 1,
            lineContent: line.trim(),
          ));
        }
      }
    } catch (_) {}
  }

  List<IndexedSymbol> searchSymbols(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return _symbolsIndex.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  String retrieveRelevantContext(String prompt) {
    final words = prompt.split(' ').where((w) => w.length > 3).toList();
    final Set<String> matchedSnippets = {};

    for (var word in words) {
      final matches = searchSymbols(word);
      for (var match in matches.take(3)) {
        matchedSnippets.add('[${match.type}] ${match.name} at ${match.filePath}:${match.lineNumber}\n  ${match.lineContent}');
      }
    }

    if (matchedSnippets.isEmpty) return '';
    return '--- Relevant Workspace Context ---\n' + matchedSnippets.join('\n');
  }
}
