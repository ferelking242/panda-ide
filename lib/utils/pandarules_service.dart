import 'dart:io';

class PandaRulesService {
  static Future<String?> loadRules(String workspacePath) async {
    if (workspacePath.isEmpty) return null;
    final candidates = [
      '$workspacePath/.panda/rules.md',
      '$workspacePath/.pandarules',
      '$workspacePath/.cursorrules',
    ];

    for (final candidate in candidates) {
      try {
        final file = File(candidate);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            return content.trim();
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<void> saveRules(String workspacePath, String content) async {
    if (workspacePath.isEmpty) return;
    try {
      final dir = Directory('$workspacePath/.panda');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('$workspacePath/.panda/rules.md');
      await file.writeAsString(content);
    } catch (_) {}
  }
}
