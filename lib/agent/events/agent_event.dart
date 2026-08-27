/// Agent Event types for the Panda Agent event bus.
///
/// All state changes in the agent runtime emit events through [AgentEventBus].
/// The UI listens to these events to update without coupling to the engine.
library;

// ── Base ───────────────────────────────────────────────────────────────────

sealed class AgentEvent {
  const AgentEvent();
  final DateTime timestamp = DateTime.now();
}

// ── Agent Lifecycle ────────────────────────────────────────────────────────

class AgentStarted extends AgentEvent {
  final String taskId;
  final String mode; // 'agent', 'ask', 'plan'
  const AgentStarted({required this.taskId, required this.mode});
}

class AgentFinished extends AgentEvent {
  final String taskId;
  final String result;
  const AgentFinished({required this.taskId, required this.result});
}

class AgentError extends AgentEvent {
  final String taskId;
  final String error;
  final String? stackTrace;
  const AgentError({required this.taskId, required this.error, this.stackTrace});
}

class AgentCancelled extends AgentEvent {
  final String taskId;
  const AgentCancelled({required this.taskId});
}

// ── Thinking ───────────────────────────────────────────────────────────────

class AgentThinkingStarted extends AgentEvent {
  const AgentThinkingStarted();
}

class AgentThinkingChunk extends AgentEvent {
  final String text;
  const AgentThinkingChunk({required this.text});
}

class AgentThinkingFinished extends AgentEvent {
  final String fullThinking;
  const AgentThinkingFinished({required this.fullThinking});
}

// ── Streaming ──────────────────────────────────────────────────────────────

class AgentStreamingStarted extends AgentEvent {
  const AgentStreamingStarted();
}

class AgentStreamingChunk extends AgentEvent {
  final String text;
  const AgentStreamingChunk({required this.text});
}

class AgentStreamingFinished extends AgentEvent {
  final String fullText;
  const AgentStreamingFinished({required this.fullText});
}

// ── Tool Calls ─────────────────────────────────────────────────────────────

class AgentToolStarted extends AgentEvent {
  final String toolId;
  final String toolName;
  final Map<String, dynamic> args;
  const AgentToolStarted({
    required this.toolId,
    required this.toolName,
    required this.args,
  });
}

class AgentToolProgress extends AgentEvent {
  final String toolId;
  final String message;
  const AgentToolProgress({required this.toolId, required this.message});
}

class AgentToolFinished extends AgentEvent {
  final String toolId;
  final String? result;
  final int durationMs;
  const AgentToolFinished({
    required this.toolId,
    this.result,
    required this.durationMs,
  });
}

class AgentToolFailed extends AgentEvent {
  final String toolId;
  final String error;
  const AgentToolFailed({required this.toolId, required this.error});
}

class AgentToolBlocked extends AgentEvent {
  final String toolId;
  final String toolName;
  final String reason;
  const AgentToolBlocked({
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
  const AgentApprovalRequired({
    required this.toolId,
    required this.toolName,
    required this.args,
  });
}

class AgentApprovalGranted extends AgentEvent {
  final String toolId;
  const AgentApprovalGranted({required this.toolId});
}

class AgentApprovalDenied extends AgentEvent {
  final String toolId;
  const AgentApprovalDenied({required this.toolId});
}

// ── Subagents ──────────────────────────────────────────────────────────────

class AgentSubagentStarted extends AgentEvent {
  final String subagentId;
  final String agentType;
  final String prompt;
  const AgentSubagentStarted({
    required this.subagentId,
    required this.agentType,
    required this.prompt,
  });
}

class AgentSubagentFinished extends AgentEvent {
  final String subagentId;
  final String result;
  const AgentSubagentFinished({
    required this.subagentId,
    required this.result,
  });
}

class AgentSubagentFailed extends AgentEvent {
  final String subagentId;
  final String error;
  const AgentSubagentFailed({required this.subagentId, required this.error});
}

// ── Verification ───────────────────────────────────────────────────────────

class AgentVerificationStarted extends AgentEvent {
  final List<String> files;
  const AgentVerificationStarted({required this.files});
}

class AgentVerificationProgress extends AgentEvent {
  final String checker;
  final String message;
  const AgentVerificationProgress({required this.checker, required this.message});
}

class AgentVerificationPassed extends AgentEvent {
  const AgentVerificationPassed();
}

class AgentVerificationFailed extends AgentEvent {
  final List<String> errors;
  const AgentVerificationFailed({required this.errors});
}

// ── Context ────────────────────────────────────────────────────────────────

class AgentContextBuilding extends AgentEvent {
  const AgentContextBuilding();
}

class AgentContextCompacted extends AgentEvent {
  final int tokensBefore;
  final int tokensAfter;
  const AgentContextCompacted({
    required this.tokensBefore,
    required this.tokensAfter,
  });
}

// ── Session ────────────────────────────────────────────────────────────────

class AgentSessionSaved extends AgentEvent {
  final String sessionId;
  const AgentSessionSaved({required this.sessionId});
}

class AgentSessionResumed extends AgentEvent {
  final String sessionId;
  const AgentSessionResumed({required this.sessionId});
}

// ── Retry ──────────────────────────────────────────────────────────────────

class AgentRetryStarted extends AgentEvent {
  final int attempt;
  final int maxAttempts;
  final String reason;
  const AgentRetryStarted({
    required this.attempt,
    required this.maxAttempts,
    required this.reason,
  });
}

// ── Files ──────────────────────────────────────────────────────────────────

class AgentFileChanged extends AgentEvent {
  final String path;
  final String changeType; // 'created', 'modified', 'deleted'
  const AgentFileChanged({required this.path, required this.changeType});
}

// ── Plan ───────────────────────────────────────────────────────────────────

class AgentPlanCreated extends AgentEvent {
  final List<String> steps;
  const AgentPlanCreated({required this.steps});
}

class AgentPlanStepCompleted extends AgentEvent {
  final int stepIndex;
  final String stepDescription;
  const AgentPlanStepCompleted({
    required this.stepIndex,
    required this.stepDescription,
  });
}
