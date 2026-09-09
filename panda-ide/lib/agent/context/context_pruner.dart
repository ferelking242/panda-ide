/// Prunes context to stay within budget.
///
/// This is a Dart component (NOT a subagent LLM).
/// It removes old tool outputs, truncates large results,
/// and preserves important decisions.
class ContextPruner {
  /// Prune a list of messages to fit within [maxTokens].
  static List<Map<String, dynamic>> prune(
    List<Map<String, dynamic>> messages, {
    required int maxTokens,
    int? keepLastN,
  }) {
    if (messages.isEmpty) return messages;

    final kept = <Map<String, dynamic>>[];
    int tokenEstimate = 0;
    final keepCount = keepLastN ?? 20;

    // Always keep the system message
    if (messages.first['role'] == 'system') {
      kept.add(messages.first);
      tokenEstimate += _estimateTokens(messages.first['content']?.toString() ?? '');
    }

    // Always keep the last N messages
    final recentStart = (messages.length - keepCount).clamp(0, messages.length);
    final recent = messages.sublist(recentStart);

    // Process messages from oldest to newest
    for (var i = (kept.isNotEmpty ? 1 : 0); i < recentStart; i++) {
      final msg = messages[i];
      final content = msg['content']?.toString() ?? '';

      // Truncate large tool outputs
      String prunedContent = content;
      if (content.length > 2000) {
        prunedContent = '${content.substring(0, 2000)}\n… [tronqué, ${content.length} chars]';
      }

      final tokens = _estimateTokens(prunedContent);
      if (tokenEstimate + tokens <= maxTokens) {
        kept.add({...msg, 'content': prunedContent});
        tokenEstimate += tokens;
      }
    }

    // Add recent messages
    for (final msg in recent) {
      kept.add(msg);
      tokenEstimate += _estimateTokens(msg['content']?.toString() ?? '');
    }

    return kept;
  }

  /// Truncate tool output to fit within a token budget.
  static String truncateToolOutput(String output, {int maxTokens = 2000}) {
    if (_estimateTokens(output) <= maxTokens) return output;
    final maxChars = maxTokens * 4; // rough estimate: 1 token ≈ 4 chars
    return '${output.substring(0, maxChars)}\n… [tronqué]';
  }

  /// Estimate token count (rough: 1 token ≈ 4 chars).
  static int _estimateTokens(String text) => (text.length / 4).ceil();
}
