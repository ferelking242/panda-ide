/// Manages retry logic for agent operations.
///
/// Different error types get different retry strategies.
class RetryManager {
  final int maxRetries;
  final Duration baseDelay;

  RetryManager({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
  });

  /// Check if an error should be retried.
  bool shouldRetry(ErrorClassifierResult error, int attempt) {
    if (attempt >= maxRetries) return false;
    return error.isRetryable;
  }

  /// Get the delay before the next retry.
  Duration getDelay(int attempt) {
    // Exponential backoff: 1s, 2s, 4s
    return baseDelay * (1 << attempt);
  }

  /// Get retry info for display.
  RetryInfo getInfo(int attempt, ErrorClassifierResult error) {
    return RetryInfo(
      attempt: attempt,
      maxAttempts: maxRetries,
      delay: getDelay(attempt),
      reason: error.category,
      shouldRetry: shouldRetry(error, attempt),
    );
  }
}

class RetryInfo {
  final int attempt;
  final int maxAttempts;
  final Duration delay;
  final String reason;
  final bool shouldRetry;

  const RetryInfo({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.reason,
    required this.shouldRetry,
  });
}
