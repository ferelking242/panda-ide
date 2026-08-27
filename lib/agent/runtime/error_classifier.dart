/// Classifies errors to determine the appropriate response.
class ErrorClassifier {
  /// Classify an error and return the appropriate strategy.
  static ErrorClassifierResult classify(dynamic error) {
    final message = error.toString().toLowerCase();

    if (message.contains('timeout') || message.contains('timed out')) {
      return ErrorClassifierResult(
        category: 'network',
        isRetryable: true,
        suggestion: 'Retry after delay',
      );
    }

    if (message.contains('connection') || message.contains('socket')) {
      return ErrorClassifierResult(
        category: 'network',
        isRetryable: true,
        suggestion: 'Check network connection',
      );
    }

    if (message.contains('rate limit') || message.contains('429')) {
      return ErrorClassifierResult(
        category: 'rate_limit',
        isRetryable: true,
        suggestion: 'Wait before retrying',
      );
    }

    if (message.contains('context') && message.contains('overflow')) {
      return ErrorClassifierResult(
        category: 'context_overflow',
        isRetryable: false,
        suggestion: 'Compact context and retry',
      );
    }

    if (message.contains('permission') || message.contains('denied')) {
      return ErrorClassifierResult(
        category: 'permission',
        isRetryable: false,
        suggestion: 'Request user permission',
      );
    }

    if (message.contains('compilation') || message.contains('analyze')) {
      return ErrorClassifierResult(
        category: 'code_error',
        isRetryable: false,
        suggestion: 'Agent should fix the error',
      );
    }

    if (message.contains('invalid') && message.contains('tool')) {
      return ErrorClassifierResult(
        category: 'tool_error',
        isRetryable: false,
        suggestion: 'Model made invalid tool call',
      );
    }

    if (message.contains('cancelled') || message.contains('abort')) {
      return ErrorClassifierResult(
        category: 'cancelled',
        isRetryable: false,
        suggestion: 'Operation was cancelled',
      );
    }

    return ErrorClassifierResult(
      category: 'unknown',
      isRetryable: true,
      suggestion: 'Generic retry',
    );
  }
}

class ErrorClassifierResult {
  final String category;
  final bool isRetryable;
  final String suggestion;

  const ErrorClassifierResult({
    required this.category,
    required this.isRetryable,
    required this.suggestion,
  });
}
