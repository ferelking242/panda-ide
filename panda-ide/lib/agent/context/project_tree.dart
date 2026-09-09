import 'dart:io';

/// Scans the project directory and returns a compact tree representation.
class ProjectTree {
  /// Scan a directory and return a compact tree string.
  static Future<String> scan(String rootPath, {int maxDepth = 3}) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) return '';

    final buffer = StringBuffer();
    buffer.writeln('## Structure du Projet');
    buffer.writeln('```');

    await _scanDir(dir, buffer, '', 0, maxDepth);

    buffer.writeln('```');
    return buffer.toString();
  }

  static Future<void> _scanDir(
    Directory dir,
    StringBuffer buffer,
    String prefix,
    int depth,
    int maxDepth,
  ) async {
    if (depth >= maxDepth) return;

    try {
      final entries = dir.listSync(followLinks: false)
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.compareTo(b.path);
        });

      var count = 0;
      for (final entry in entries) {
        final name = entry.path.split(Platform.pathSeparator).last;

        // Skip hidden, build, node_modules, etc.
        if (_shouldSkip(name)) continue;

        if (entry is Directory) {
          buffer.writeln('$prefix📁 $name/');
          await _scanDir(entry, buffer, '$prefix  ', depth + 1, maxDepth);
        } else {
          buffer.writeln('$prefix📄 $name');
        }

        count++;
        if (count > 30) {
          buffer.writeln('$prefix… (autres fichiers)');
          break;
        }
      }
    } catch (_) {}
  }

  static bool _shouldSkip(String name) {
    if (name.startsWith('.')) return true;
    const skipped = {
      'build', 'node_modules', '__pycache__', 'target',
      '.dart_tool', '.pub-cache', '.git', 'android', 'ios',
      'web', 'windows', 'macos', 'linux',
    };
    return skipped.contains(name);
  }
}
