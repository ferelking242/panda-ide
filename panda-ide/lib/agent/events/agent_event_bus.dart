import 'dart:async';

import 'agent_event.dart';

/// Centralized event bus for the Panda Agent runtime.
///
/// The agent engine emits events through [emit]. The UI listens through
/// [events] stream. This decouples the UI from the engine completely.
///
/// Usage:
/// ```dart
/// final bus = AgentEventBus();
///
/// // Engine side
/// bus.emit(AgentToolStarted(toolId: '1', toolName: 'readFile', args: {}));
///
/// // UI side
/// bus.events.listen((event) {
///   if (event is AgentToolStarted) { ... }
/// });
/// ```
class AgentEventBus {
  final _controller = StreamController<AgentEvent>.broadcast();
  final List<AgentEvent> _history = [];
  AgentEvent? _lastEvent;

  /// Stream of all agent events. UI should listen here.
  Stream<AgentEvent> get events => _controller.stream;

  /// Last emitted event (useful for quick state checks).
  AgentEvent? get lastEvent => _lastEvent;

  /// History of recent events (last 100).
  List<AgentEvent> get history => List.unmodifiable(_history);

  /// Emit an event to all listeners.
  void emit(AgentEvent event) {
    _lastEvent = event;
    _history.add(event);
    if (_history.length > 100) {
      _history.removeAt(0);
    }
    _controller.add(event);
  }

  /// Dispose the bus. Call when the agent session ends.
  void dispose() {
    _controller.close();
    _history.clear();
    _lastEvent = null;
  }
}
