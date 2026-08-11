import "dart:io";
import "package:path/path.dart" as path;

class CodeChunk {
  final String filePath;
  final int startLine;
  final int endLine;
  final String content;

  CodeChunk({
    required this.filePath,
    required this.startLine,
    required this.endLine,
    required this.content,
  });
}

class CodebaseIndexer {
  static final List<CodeChunk> _chunks = [];

  static Future<void> indexWorkspace(String workspacePath) async {
    _chunks.clear();
    if (workspacePath.isEmpty) return;
    try {
      final dir = Directory(workspacePath);
      if (!await dir.exists()) return;

      final files = dir.listSync(recursive: true).whereType<File>().where((f) {
        final p = f.path;
        return !p.contains("/.git/") &&
            !p.contains("/build/") &&
            !p.contains("/node_modules/") &&
            !p.contains("/.dart_tool/") &&
            (p.endsWith(".dart") || p.endsWith(".ts") || p.endsWith(".json") || p.endsWith(".md"));
      }).take(100);

      for (final file in files) {
        try {
          final content = await file.readAsString();
          final lines = content.split("\n");
          final relPath = path.relative(file.path, from: workspacePath);

          for (var i = 0; i < lines.length; i += 30) {
            final end = (i + 30 < lines.length) ? i + 30 : lines.length;
            final chunkLines = lines.sublist(i, end);
            _chunks.add(CodeChunk(
              filePath: relPath,
              startLine: i + 1,
              endLine: end,
              content: chunkLines.join("\n"),
            ));
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static List<CodeChunk> semanticSearch(String query, {int limit = 5}) {
    if (query.isEmpty || _chunks.isEmpty) return [];
    final terms = query.toLowerCase().split(RegExp(r"\s+"));

    final scored = _chunks.map((chunk) {
      int score = 0;
      final lowerContent = chunk.content.toLowerCase();
      for (final term in terms) {
        if (term.length > 2 && lowerContent.contains(term)) {
          score += 1;
        }
      }
      return MapEntry(chunk, score);
    }).where((e) => e.value > 0).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }
}
