import 'dart:io';
import 'package:path/path.dart' as p;

/// Finds files relevant to the current task based on keywords and heuristics.
class RelevantFiles {
  /// Find files relevant to the user's request.
  static Future<List<RelevantFile>> find(
    String rootPath,
    String userRequest, {
    int maxFiles = 10,
  }) async {
    final keywords = _extractKeywords(userRequest);
    final candidates = <RelevantFile>[];

    await for (final entity in Directory(rootPath).list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: rootPath);
      if (_shouldSkip(rel)) continue;

      final score = _scoreFile(rel, keywords);
      if (score > 0) {
        candidates.add(RelevantFile(path: rel, score: score));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(maxFiles).toList();
  }

  static Set<String> _extractKeywords(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();
    // Remove common stop words
    words.removeAll({'the', 'and', 'for', 'with', 'that', 'this', 'from',
      'une', 'des', 'les', 'pour', 'dans', 'avec', 'qui', 'que', 'est'});
    return words;
  }

  static int _scoreFile(String path, Set<String> keywords) {
    final lower = path.toLowerCase();
    int score = 0;

    for (final kw in keywords) {
      if (lower.contains(kw)) score += 10;
    }

    // Boost important files
    if (lower.endsWith('main.dart')) score += 5;
    if (lower.contains('pubspec.yaml')) score += 3;
    if (lower.contains('lib/')) score += 2;
    if (lower.contains('test/')) score += 1;

    return score;
  }

  static bool _shouldSkip(String path) {
    return path.contains('/build/') ||
        path.contains('/.dart_tool/') ||
        path.contains('/node_modules/') ||
        path.startsWith('.');
  }
}

class RelevantFile {
  final String path;
  final int score;
  const RelevantFile({required this.path, required this.score});
}
