import 'dart:async';

import '../events/agent_event.dart';
import '../events/agent_event_bus.dart';
import '../agents/agent_definition.dart';
import '../agents/agent_registry.dart';

/// Manages spawning, tracking, and result collection of subagents.
///
/// The MainAgent can spawn subagents for specific tasks.
/// Each subagent runs independently and returns a result.
class SubagentManager {
  final AgentRegistry _registry;
  final AgentEventBus _eventBus;
  final int maxConcurrent;

  final Map<String, SubagentTask> _activeTasks = {};

  SubagentManager({
    required AgentRegistry registry,
    required AgentEventBus eventBus,
    this.maxConcurrent = 2,
  })  : _registry = registry,
        _eventBus = eventBus;

  /// Spawn a subagent for a specific task.
  ///
  /// Returns a [SubagentTask] that can be awaited for the result.
  Future<SubagentTaskResult> spawn({
    required String agentId,
    required String prompt,
    List<String> filePaths = const [],
    Map<String, dynamic>? extraContext,
  }) async {
    // Check concurrency limit
    if (_activeTasks.length >= maxConcurrent) {
      return SubagentTaskResult(
        success: false,
        error: 'Max concurrent subagents ($maxConcurrent) reached.',
      );
    }

    // Get agent definition
    final agent = _registry.get(agentId);
    if (agent == null) {
      return SubagentTaskResult(
        success: false,
        error: 'Unknown agent: $agentId',
      );
    }

    final taskId = 'sub_${DateTime.now().microsecondsSinceEpoch}';
    final task = SubagentTask(
      id: taskId,
      agentId: agentId,
      agent: agent,
      prompt: prompt,
      filePaths: filePaths,
      status: SubagentStatus.running,
      createdAt: DateTime.now(),
    );

    _activeTasks[taskId] = task;

    _eventBus.emit(AgentSubagentStarted(
      subagentId: taskId,
      agentType: agentId,
      prompt: prompt,
    ));

    return SubagentTaskResult(
      success: true,
      taskId: taskId,
      agent: agent,
    );
  }

  /// Mark a subagent task as completed.
  void complete(String taskId, String result) {
    final task = _activeTasks[taskId];
    if (task == null) return;

    task.status = SubagentStatus.completed;
    task.result = result;

    _eventBus.emit(AgentSubagentFinished(
      subagentId: taskId,
      result: result,
    ));

    _activeTasks.remove(taskId);
  }

  /// Mark a subagent task as failed.
  void fail(String taskId, String error) {
    final task = _activeTasks[taskId];
    if (task == null) return;

    task.status = SubagentStatus.failed;
    task.result = error;

    _eventBus.emit(AgentSubagentFailed(
      subagentId: taskId,
      error: error,
    ));

    _activeTasks.remove(taskId);
  }

  /// Get active tasks count.
  int get activeCount => _activeTasks.length;

  /// Check if we can spawn more subagents.
  bool get canSpawn => _activeTasks.length < maxConcurrent;
}

enum SubagentStatus { running, completed, failed }

class SubagentTask {
  final String id;
  final String agentId;
  final AgentDefinition agent;
  final String prompt;
  final List<String> filePaths;
  SubagentStatus status;
  String result;
  final DateTime createdAt;

  SubagentTask({
    required this.id,
    required this.agentId,
    required this.agent,
    required this.prompt,
    required this.filePaths,
    required this.status,
    this.result = '',
    required this.createdAt,
  });
}

class SubagentTaskResult {
  final bool success;
  final String? taskId;
  final AgentDefinition? agent;
  final String? error;

  const SubagentTaskResult({
    required this.success,
    this.taskId,
    this.agent,
    this.error,
  });
}
