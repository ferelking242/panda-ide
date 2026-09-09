import 'dart:io';

/// Detects available executables in the Android/Termux environment.
class ExecutableDetector {
  static final Map<String, bool> _cache = {};

  /// Check if an executable is available.
  static Future<bool> isAvailable(String name) async {
    if (_cache.containsKey(name)) return _cache[name]!;

    try {
      final result = await Process.run(
        'which',
        [name],
        environment: {'PATH': _androidPath()},
      ).timeout(const Duration(seconds: 5));

      final available = result.exitCode == 0;
      _cache[name] = available;
      return available;
    } catch (_) {
      _cache[name] = false;
      return false;
    }
  }

  /// Detect all common development tools.
  static Future<Map<String, bool>> detectAll() async {
    const tools = [
      'git', 'rg', 'fd', 'grep', 'find',
      'python3', 'node', 'npm', 'bun',
      'rustc', 'cargo', 'go',
      'gcc', 'clang',
      'flutter', 'dart',
      'java', 'javac',
      'lua', 'ruby',
    ];

    final results = <String, bool>{};
    for (final tool in tools) {
      results[tool] = await isAvailable(tool);
    }
    return results;
  }

  static String _androidPath() {
    return '/data/data/com.termux/files/usr/bin:'
        '/data/data/com.termux/files/usr/bin/applets:'
        '/data/user/0/com.pandaide.app/files/flutter/bin:'
        '/data/user/0/com.pandaide.app/files/dart-sdk/bin:'
        '${Platform.environment['PATH'] ?? ''}';
  }

  static void clearCache() => _cache.clear();
}
