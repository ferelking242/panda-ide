library;

/// Helper function to parse `<think>...</think>` tags from agent responses.
/// Handles both completed `<think>...</think>` tags and unclosed `<think>...` during streaming.
Map<String, String> parseThinkingAndText(String fullContent) {
  if (fullContent.isEmpty) return {'think': '', 'text': ''};

  final StringBuffer thinkBuf = StringBuffer();
  final StringBuffer textBuf = StringBuffer();

  int idx = 0;
  while (idx < fullContent.length) {
    final openIdx = fullContent.indexOf('<think>', idx);
    if (openIdx == -1) {
      textBuf.write(fullContent.substring(idx));
      break;
    } else {
      textBuf.write(fullContent.substring(idx, openIdx));
      final closeIdx = fullContent.indexOf('</think>', openIdx + 7);
      if (closeIdx == -1) {
        // Unclosed <think> tag (currently streaming inside thinking block)
        thinkBuf.write(fullContent.substring(openIdx + 7));
        break;
      } else {
        thinkBuf.write(fullContent.substring(openIdx + 7, closeIdx));
        if (thinkBuf.isNotEmpty) thinkBuf.write('\n');
        idx = closeIdx + 8;
      }
    }
  }

  return {
    'think': thinkBuf.toString().trim(),
    'text': textBuf.toString().trim(),
  };
}
