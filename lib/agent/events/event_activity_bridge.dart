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
    required AgentActivityController activityCtrl,
  })  : _eventBus = eventBus,
        _activityCtrl = activityCtrl;

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

      case AgentToolStarted():
        _activityCtrl.startTool(
          toolId: event.toolId,
          toolName: event.toolName,
          args: event.args,
        );

      case AgentToolFinished():
        _activityCtrl.completeTool(
          toolId: event.toolId,
          result: event.result,
        );

      case AgentToolFailed():
        _activityCtrl.failTool(
          toolId: event.toolId,
          error: event.error,
        );

      case AgentToolBlocked():
        _activityCtrl.failTool(
          toolId: event.toolId,
          error: 'Blocked: ${event.reason}',
        );

      case AgentVerificationStarted():
        _activityCtrl.updateNarrative('Vérification…');

      case AgentVerificationPassed():
        _activityCtrl.updateNarrative('Vérification OK');

      case AgentVerificationFailed():
        _activityCtrl.updateNarrative('${event.errors.length} erreur(s)');

      case AgentSubagentStarted():
        _activityCtrl.updateNarrative('Sub-agent ${event.agentType}…');

      case AgentSubagentFinished():
        _activityCtrl.updateNarrative('Sub-agent terminé');

      case AgentContextCompacted():
        _activityCtrl.updateNarrative(
            'Contexte compresse (${event.tokensAfter} tokens)');

      case AgentRetryStarted():
        _activityCtrl.updateNarrative(
            'Retry ${event.attempt}/${event.maxAttempts}: ${event.reason}');

      case AgentFinished():
        _activityCtrl.finishRun();

      case AgentError():
        _activityCtrl.finishRun(error: event.error);

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
