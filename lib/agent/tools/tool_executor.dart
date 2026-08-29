import 'dart:async';

import '../events/agent_event.dart';
import '../events/agent_event_bus.dart';
import 'tool_registry.dart';

/// Executes tool calls with permission checking and event emission.
///
/// The agent runner calls [execute] for each tool call from the LLM.
/// The executor checks permissions, runs the tool, and emits events.
class ToolExecutor {
  final ToolRegistry _registry;
  final AgentEventBus _eventBus;
  final String Function()? _getCurrentMode;

  ToolExecutor({
    required ToolRegistry registry,
    required AgentEventBus eventBus,
    String Function()? getCurrentMode,
  })  : _registry = registry,
        _eventBus = eventBus,
        _getCurrentMode = getCurrentMode;

  /// Execute a tool call from the LLM.
  ///
  /// Returns the tool result as a string (for sending back to the LLM).
  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    final toolId = 'tool_${DateTime.now().microsecondsSinceEpoch}';

    // Check tool exists
    final tool = _registry.get(toolName);
    if (tool == null) {
      return 'Error: Unknown tool "$toolName". Available tools: ${_registry.all.map((t) => t.name).join(', ')}';
    }

    // Check permissions
    final mode = _getCurrentMode?.call() ?? 'agent';
    if (tool.isMutating && mode != 'agent') {
      _eventBus.emit(AgentToolBlocked(
        toolId: toolId,
        toolName: toolName,
        reason: 'Tool "$toolName" requires Agent mode. Current mode: $mode',
      ));
      return 'Blocage: L\'outil "$toolName" modifie l\'espace de travail et est indisponible en mode $mode.';
    }

    // Emit started event
    _eventBus.emit(AgentToolStarted(
      toolId: toolId,
      toolName: toolName,
      args: args,
    ));

    final stopwatch = Stopwatch()..start();

    try {
      final result = await tool.execute(args);
      stopwatch.stop();

      if (result.success) {
        _eventBus.emit(AgentToolFinished(
          toolId: toolId,
          result: result.data,
          durationMs: stopwatch.elapsedMilliseconds,
        ));
        return result.data ?? '';
      } else {
        _eventBus.emit(AgentToolFailed(
          toolId: toolId,
          error: result.error ?? 'Unknown error',
        ));
        return 'Error: ${result.error}';
      }
    } catch (e) {
      stopwatch.stop();
      _eventBus.emit(AgentToolFailed(
        toolId: toolId,
        error: e.toString(),
      ));
      return 'Error executing tool "$toolName": $e';
    }
  }
}
