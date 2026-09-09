/// Compacts conversation history when it grows too large.
///
/// Summarizes older messages while preserving recent context.
class HistoryCompactor {
  /// Compact history if it exceeds [maxTokens].
  ///
  /// Returns the original messages if no compaction needed,
  /// or a compacted list with a summary message replacing old messages.
  static Future<List<Map<String, dynamic>>> compact(
    List<Map<String, dynamic>> messages, {
    required int maxTokens,
    required Future<String> Function(String text) summarize,
  }) async {
    final totalTokens = _estimateTotalTokens(messages);
    if (totalTokens <= maxTokens) return messages;

    // Keep system message + last 10 messages
    final systemMsg = messages.where((m) => m['role'] == 'system').toList();
    final nonSystem = messages.where((m) => m['role'] != 'system').toList();

    if (nonSystem.length <= 10) return messages;

    final oldMessages = nonSystem.sublist(0, nonSystem.length - 10);
    final recentMessages = nonSystem.sublist(nonSystem.length - 10);

    // Summarize old messages
    final oldText = oldMessages
        .map((m) => '${m['role']}: ${m['content']?.toString() ?? ''}')
        .join('\n');

    final summary = await summarize(oldText);

    final compacted = <Map<String, dynamic>>[
      ...systemMsg,
      {
        'role': 'user',
        'content': '[Historique compacté]\n$summary',
      },
      ...recentMessages,
    ];

    return compacted;
  }

  static int _estimateTotalTokens(List<Map<String, dynamic>> messages) {
    int total = 0;
    for (final m in messages) {
      total += (m['content']?.toString().length ?? 0) ~/ 4;
    }
    return total;
  }
}
