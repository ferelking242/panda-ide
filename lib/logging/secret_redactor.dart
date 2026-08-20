/// Redacts sensitive information from log messages before persistence.
class SecretRedactor {
  /// Patterns that indicate sensitive data (order matters).
  static final _patterns = [
    RegExp(r'(?i)(api[_\-]?key|apikey)\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'(?i)(token|bearer)\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'(?i)(password|passwd|pwd)\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'(?i)(secret|secret[_\-]?key)\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'(?i)Authorization\s*[:=]\s*Bearer\s+\S+', caseSensitive: false),
    RegExp(r'(?i)Authorization\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'(?i)Cookie\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'ghp_[A-Za-z0-9]{30,}', caseSensitive: false),
    RegExp(r'gho_[A-Za-z0-9]{30,}', caseSensitive: false),
    RegExp(r'github_pat_[A-Za-z0-9_]{30,}', caseSensitive: false),
    RegExp(r'sk-[A-Za-z0-9]{20,}', caseSensitive: false),
    RegExp(r'(?i)access[_\-]?key[_\-]?secret\s*[:=]\s*\S+', caseSensitive: false),
    RegExp(r'(?i)AWS_SECRET_ACCESS_KEY\s*[:=]\s*\S+', caseSensitive: false),
  ];

  /// Redact sensitive data from a string.
  static String redact(String input) {
    var result = input;
    for (final pattern in _patterns) {
      result = result.replaceAllMapped(pattern, (match) {
        final full = match.group(0)!;
        // Keep the key name, mask the value
        final eqIdx = full.indexOf(RegExp(r'[:=]'));
        if (eqIdx >= 0) {
          final key = full.substring(0, eqIdx + 1);
          return '$key ********';
        }
        return '********';
      });
    }
    return result;
  }

  /// Check if a string contains sensitive data.
  static bool containsSensitive(String input) {
    return _patterns.any((p) => p.hasMatch(input));
  }
}
