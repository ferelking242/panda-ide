import 'dart:convert';

class AgentExportService {
  static String exportToMarkdown(
    List<Map<String, dynamic>> messages, {
    String modelName = '',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# 🐼 Panda Agent — Conversation Export');
    buffer.writeln('**Date:** ${DateTime.now().toLocal().toString().split('.').first}');
    if (modelName.isNotEmpty) {
      buffer.writeln('**Modèle:** $modelName');
    }
    buffer.writeln('\n---');

    for (final m in messages) {
      final role = m['role']?.toString().toUpperCase() ?? 'USER';
      final text = m['text']?.toString() ?? m['content']?.toString() ?? '';
      final thinking = m['thinking']?.toString() ?? '';
      final toolCalls = m['toolCalls'] as List?;

      buffer.writeln('\n### 👤 $role');

      if (thinking.isNotEmpty) {
        buffer.writeln('\n> **🧠 Réflexion:**\n> ${thinking.replaceAll('\n', '\n> ')}');
      }

      if (text.isNotEmpty) {
        buffer.writeln('\n$text');
      }

      if (toolCalls != null && toolCalls.isNotEmpty) {
        buffer.writeln('\n**🔧 Outils exécutés:**');
        for (final tc in toolCalls) {
          final name = tc['name'] ?? tc['toolName'] ?? 'tool';
          final result = tc['result'] ?? tc['content'] ?? '';
          buffer.writeln('- **`$name`**');
          if (result.toString().trim().isNotEmpty) {
            buffer.writeln('  ```\n  $result\n  ```');
          }
        }
      }
      buffer.writeln('\n---');
    }

    return buffer.toString();
  }

  static String exportToJson(List<Map<String, dynamic>> messages) {
    return const JsonEncoder.withIndent('  ').convert(messages);
  }
}
