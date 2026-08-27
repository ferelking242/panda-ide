/// Agent Event types for the Panda Agent event bus.
///
/// All state changes in the agent runtime emit events through [AgentEventBus].
/// The UI listens to these events to update without coupling to the engine.

// ── Base ───────────────────────────────────────────────────────────────────

sealed class AgentEvent {
  AgentEvent();
  final DateTime timestamp = DateTime.now();
}

// ── Agent Lifecycle ────────────────────────────────────────────────────────

class AgentStarted extends AgentEvent {
  final String taskId;
  final String mode; // 'agent', 'ask', 'plan'
  AgentStarted({required this.taskId, required this.mode});
}

class AgentFinished extends AgentEvent {
  final String taskId;
  final String result;
  AgentFinished({required this.taskId, required this.result});
}

class AgentError extends AgentEvent {
  final String taskId;
  final String error;
  final String? stackTrace;
  AgentError({required this.taskId, required this.error, this.stackTrace});
}

class AgentCancelled extends AgentEvent {
  final String taskId;
  AgentCancelled({required this.taskId});
}

// ── Thinking ───────────────────────────────────────────────────────────────

class AgentThinkingStarted extends AgentEvent {
  AgentThinkingStarted();
}

class AgentThinkingChunk extends AgentEvent {
  final String text;
  AgentThinkingChunk({required this.text});
}

class AgentThinkingFinished extends AgentEvent {
  final String fullThinking;
  AgentThinkingFinished({required this.fullThinking});
}

// ── Streaming ──────────────────────────────────────────────────────────────

class AgentStreamingStarted extends AgentEvent {
  AgentStreamingStarted();
}

class AgentStreamingChunk extends AgentEvent {
  final String text;
  AgentStreamingChunk({required this.text});
}

class AgentStreamingFinished extends AgentEvent {
  final String fullText;
  AgentStreamingFinished({required this.fullText});
}

// ── Tool Calls ─────────────────────────────────────────────────────────────

class AgentToolStarted extends AgentEvent {
  final String toolId;
  final String toolName;
  final Map<String, dynamic> args;
  AgentToolStarted({
    required this.toolId,
    required this.toolName,
    required this.args,
  });
}

class AgentToolProgress extends AgentEvent {
  final String toolId;
  final String message;
  AgentToolProgress({required this.toolId, required this.message});
}

class AgentToolFinished extends AgentEvent {
  final String toolId;
  final String toolName;
  final String? result;
  final int durationMs;
  AgentToolFinished({
    required this.toolId,
    this.toolName = '',
    this.result,
    this.durationMs = 0,
  });
}

class AgentToolFailed extends AgentEvent {
  final String toolId;
  final String error;
  AgentToolFailed({required this.toolId, required this.error});
}

class AgentToolBlocked extends AgentEvent {
  final String toolId;
  final String toolName;
  final String reason;
  AgentToolBlocked({
    required this.toolId,
    required this.toolName,
    required this.reason,
  });
}

// ── Approval ───────────────────────────────────────────────────────────────

class AgentApprovalRequired extends AgentEvent {
  final String toolId;
  final String toolName;
  final Map<String, dynamic> args;
  AgentApprovalRequired({
    required this.toolId,
    required this.toolName,
    required this.args,
  });
}

class AgentApprovalGranted extends AgentEvent {
  final String toolId;
  AgentApprovalGranted({required this.toolId});
}

class AgentApprovalDenied extends AgentEvent {
  final String toolId;
  AgentApprovalDenied({required this.toolId});
}

// ── Subagents ──────────────────────────────────────────────────────────────

class AgentSubagentStarted extends AgentEvent {
  final String subagentId;
  final String agentType;
  final String prompt;
  AgentSubagentStarted({
    required this.subagentId,
    required this.agentType,
    required this.prompt,
  });
}

class AgentSubagentFinished extends AgentEvent {
  final String subagentId;
  final String result;
  AgentSubagentFinished({
    required this.subagentId,
    required this.result,
  });
}

class AgentSubagentFailed extends AgentEvent {
  final String subagentId;
  final String error;
  AgentSubagentFailed({required this.subagentId, required this.error});
}

// ── Verification ───────────────────────────────────────────────────────────

class AgentVerificationStarted extends AgentEvent {
  final List<String> files;
  AgentVerificationStarted({required this.files});
}

class AgentVerificationProgress extends AgentEvent {
  final String checker;
  final String message;
  AgentVerificationProgress({required this.checker, required this.message});
}

class AgentVerificationPassed extends AgentEvent {
  AgentVerificationPassed();
}

class AgentVerificationFailed extends AgentEvent {
  final List<String> errors;
  AgentVerificationFailed({required this.errors});
}

// ── Context ────────────────────────────────────────────────────────────────

class AgentContextBuilding extends AgentEvent {
  AgentContextBuilding();
}

class AgentContextCompacted extends AgentEvent {
  final int tokensBefore;
  final int tokensAfter;
  AgentContextCompacted({
    required this.tokensBefore,
    required this.tokensAfter,
  });
}

// ── Session ────────────────────────────────────────────────────────────────

class AgentSessionSaved extends AgentEvent {
  final String sessionId;
  AgentSessionSaved({required this.sessionId});
}

class AgentSessionResumed extends AgentEvent {
  final String sessionId;
  AgentSessionResumed({required this.sessionId});
}

// ── Retry ──────────────────────────────────────────────────────────────────

class AgentRetryStarted extends AgentEvent {
  final int attempt;
  final int maxAttempts;
  final String reason;
  AgentRetryStarted({
    required this.attempt,
    required this.maxAttempts,
    required this.reason,
  });
}

// ── Files ──────────────────────────────────────────────────────────────────

class AgentFileChanged extends AgentEvent {
  final String path;
  final String changeType; // 'created', 'modified', 'deleted'
  AgentFileChanged({required this.path, required this.changeType});
}

// ── Plan ───────────────────────────────────────────────────────────────────

class AgentPlanCreated extends AgentEvent {
  final List<String> steps;
  AgentPlanCreated({required this.steps});
}

class AgentPlanStepCompleted extends AgentEvent {
  final int stepIndex;
  final String stepDescription;
  AgentPlanStepCompleted({
    required this.stepIndex,
    required this.stepDescription,
  });
}
