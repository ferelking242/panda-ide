/// Tracks token budget for context construction.
///
/// The context is built from multiple sources, each with a token budget.
/// The total must not exceed [maxTokens].
class ContextBudget {
  final int maxTokens;
  final Map<String, int> _allocated = {};
  int _used = 0;

  ContextBudget({required this.maxTokens});

  /// Maximum tokens available.
  int get available => maxTokens - _used;

  /// Whether we have budget left.
  bool get hasBudget => available > 0;

  /// Percentage used.
  double get usagePercent => _used / maxTokens;

  /// Allocate tokens for a source. Returns actual tokens allocated
  /// (may be less than requested if budget is tight).
  int allocate(String source, int requested) {
    final actual = requested.clamp(0, available);
    _allocated[source] = actual;
    _used += actual;
    return actual;
  }

  /// Get tokens allocated to a source.
  int allocated(String source) => _allocated[source] ?? 0;

  /// Reset all allocations.
  void reset() {
    _allocated.clear();
    _used = 0;
  }

  /// Get summary of allocations.
  Map<String, int> get summary => Map.unmodifiable(_allocated);
}

/// Budget configuration based on device capabilities.
class ContextBudgetConfig {
  final int maxTokens;
  final int userRequestBudget;
  final int projectTreeBudget;
  final int codeMapBudget;
  final int relevantFilesBudget;
  final int activeFileBudget;
  final int gitDiffBudget;
  final int memoryBudget;
  final int knowledgeBudget;
  final int toolOutputBudget;
  final int conversationHistoryBudget;
  final int lspDiagnosticsBudget;

  const ContextBudgetConfig({
    required this.maxTokens,
    this.userRequestBudget = 2000,
    this.projectTreeBudget = 3000,
    this.codeMapBudget = 4000,
    this.relevantFilesBudget = 15000,
    this.activeFileBudget = 10000,
    this.gitDiffBudget = 5000,
    this.memoryBudget = 2000,
    this.knowledgeBudget = 2000,
    this.toolOutputBudget = 4000,
    this.conversationHistoryBudget = 20000,
    this.lspDiagnosticsBudget = 1000,
  });

  /// Default config for a high-end device (8GB+ RAM).
  factory ContextBudgetConfig.highEnd() => const ContextBudgetConfig(
        maxTokens: 120000,
      );

  /// Default config for a mid-range device (4-6GB RAM).
  factory ContextBudgetConfig.midRange() => const ContextBudgetConfig(
        maxTokens: 80000,
        relevantFilesBudget: 10000,
        activeFileBudget: 8000,
        conversationHistoryBudget: 15000,
      );

  /// Default config for a low-end device (<4GB RAM).
  factory ContextBudgetConfig.lowEnd() => const ContextBudgetConfig(
        maxTokens: 40000,
        projectTreeBudget: 1500,
        codeMapBudget: 0,
        relevantFilesBudget: 5000,
        activeFileBudget: 5000,
        gitDiffBudget: 2000,
        conversationHistoryBudget: 8000,
      );
}
