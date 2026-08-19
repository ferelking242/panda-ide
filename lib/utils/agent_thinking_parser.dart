library;

/// Helper function to parse `<think>...</think>`, `<thought>...</thought>`, and `<reasoning>...</reasoning>` tags from agent responses.
/// Handles completed tags, nested blocks, and unclosed opening tags during real-time token streaming.
Map<String, String> parseThinkingAndText(String fullContent) {
  if (fullContent.isEmpty) return {'think': '', 'text': ''};

  final openTags = ['<think>', '<thought>', '<reasoning>', '[THINK]'];
  final closeTags = ['</think>', '</thought>', '</reasoning>', '[/THINK]'];

  final StringBuffer thinkBuf = StringBuffer();
  final StringBuffer textBuf = StringBuffer();

  int idx = 0;
  while (idx < fullContent.length) {
    // Find the earliest matching open tag
    int earliestOpenIdx = -1;
    int matchedTagIdx = -1;

    for (int t = 0; t < openTags.length; t++) {
      final pos = fullContent.indexOf(openTags[t], idx);
      if (pos != -1 && (earliestOpenIdx == -1 || pos < earliestOpenIdx)) {
        earliestOpenIdx = pos;
        matchedTagIdx = t;
      }
    }

    if (earliestOpenIdx == -1) {
      textBuf.write(fullContent.substring(idx));
      break;
    }

    textBuf.write(fullContent.substring(idx, earliestOpenIdx));
    final openTag = openTags[matchedTagIdx];
    final closeTag = closeTags[matchedTagIdx];

    final startContent = earliestOpenIdx + openTag.length;
    final closeIdx = fullContent.indexOf(closeTag, startContent);

    if (closeIdx == -1) {
      // Unclosed tag (currently streaming inside thinking block)
      thinkBuf.write(fullContent.substring(startContent));
      break;
    } else {
      thinkBuf.write(fullContent.substring(startContent, closeIdx));
      if (thinkBuf.isNotEmpty) thinkBuf.write('\n');
      idx = closeIdx + closeTag.length;
    }
  }

  return {
    'think': thinkBuf.toString().trim(),
    'text': textBuf.toString().trim(),
  };
}
