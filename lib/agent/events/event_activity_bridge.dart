import '../../ui/agent/agent_models.dart';
import 'agent_event.dart';
import 'agent_event_bus.dart';

/// Bridges the new AgentEventBus with the existing AgentActivityController.
///
/// When events come through the bus, they update the activity controller
/// so the existing Activity Feed UI works without modification.
class EventActivityBridge {
  final AgentEventBus _eventBus;
  final AgentActivityController _activityCtrl;

  EventActivityBridge({
    required AgentEventBus eventBus,
    required AgentActivityController activityController,
  })  : _eventBus = eventBus,
        _activityCtrl = activityController;

  /// Start listening to events and updating the activity controller.
  void start() {
    _eventBus.events.listen(_onEvent);
  }

  void _onEvent(AgentEvent event) {
    switch (event) {
      case AgentStarted():
        _activityCtrl.startRun();

      case AgentThinkingStarted():
        _activityCtrl.updateNarrative('Réflexion…');

      case AgentThinkingFinished():
        _activityCtrl.updateNarrative('Réflexion terminée');

      case AgentStreamingStarted():
        _activityCtrl.updateNarrative('Génération…');

      case AgentStreamingChunk():
        // Don't update narrative on every chunk to avoid flicker

      case AgentToolStarted(:final toolId, :final toolName, :final args):
        _activityCtrl.startTool(
          toolId: toolId,
          toolName: toolName,
          args: args,
        );

      case AgentToolFinished(:final toolId, :final result):
        _activityCtrl.completeTool(
          toolId: toolId,
          result: result,
        );

      case AgentToolFailed(:final toolId, :final error):
        _activityCtrl.failTool(
          toolId: toolId,
          error: error,
        );

      case AgentToolBlocked(:final toolId, :final reason):
        _activityCtrl.failTool(
          toolId: toolId,
          error: 'Blocked: $reason',
        );

      case AgentVerificationStarted():
        _activityCtrl.updateNarrative('Vérification…');

      case AgentVerificationPassed():
        _activityCtrl.updateNarrative('Vérification OK');

      case AgentVerificationFailed(:final errors):
        _activityCtrl.updateNarrative('${errors.length} erreur(s)');

      case AgentSubagentStarted(:final agentType):
        _activityCtrl.updateNarrative('Sub-agent $agentType…');

      case AgentSubagentFinished():
        _activityCtrl.updateNarrative('Sub-agent terminé');

      case AgentContextCompacted(:final tokensAfter):
        _activityCtrl.updateNarrative(
            'Contexte compresse ($tokensAfter tokens)');

      case AgentRetryStarted(:final attempt, :final maxAttempts, :final reason):
        _activityCtrl.updateNarrative(
            'Retry $attempt/$maxAttempts: $reason');

      case AgentFinished():
        _activityCtrl.finishRun();

      case AgentError(:final error):
        _activityCtrl.finishRun(error: error);

      case AgentCancelled():
        _activityCtrl.finishRun(error: 'Annulé');

      default:
        // Other events don't need activity feed updates
        break;
    }
  }

  void dispose() {
    // Stream subscription is managed by the caller
  }
}
