import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_event.dart';
import 'agent_event_bus.dart';
import '../../ui/agent_runner.dart' show AgentPhase;
import '../../ui/agent_runner.dart' show AgentPhase;

/// Agent phase — mirrors the phase from AgentRunner for V3 bridge use.

/// Provides reactive state for UI widgets by listening to AgentEventBus.
///
/// Widgets use this to get current agent state without tight coupling.
class AgentUiState extends ChangeNotifier {
  final AgentEventBus _eventBus;
  StreamSubscription<AgentEvent>? _sub;

  String _phase = 'idle';
  String _currentTool = '';
  String _thinking = '';
  String _streaming = '';
  bool _isGenerating = false;
  String? _error;
  final List<SubagentInfo> _activeSubagents = [];
  VerificationInfo? _verification;

  AgentUiState({required AgentEventBus eventBus}) : _eventBus = eventBus;

  // ── Getters ────────────────────────────────────────────────────────────

  String get phase => _phase;
  String get currentTool => _currentTool;
  String get thinking => _thinking;
  String get streaming => _streaming;
  bool get isGenerating => _isGenerating;
  String? get error => _error;
  List<SubagentInfo> get activeSubagents => List.unmodifiable(_activeSubagents);
  VerificationInfo? get verification => _verification;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  void start() {
    _sub = _eventBus.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Event handling ─────────────────────────────────────────────────────

  void _onEvent(AgentEvent event) {
    switch (event) {
      case AgentStarted():
        _phase = 'streaming';
        _isGenerating = true;
        _error = null;
        _thinking = '';
        _streaming = '';
        notifyListeners();

      case AgentThinkingStarted():
        _phase = 'thinking';
        notifyListeners();

      case AgentThinkingChunk():
        _thinking += event.text;
        notifyListeners();

      case AgentThinkingFinished():
        _thinking = event.fullThinking;
        notifyListeners();

      case AgentStreamingStarted():
        _phase = 'streaming';
        notifyListeners();

      case AgentStreamingChunk():
        _streaming += event.text;
        notifyListeners();

      case AgentToolStarted():
        _currentTool = event.toolName;
        _phase = 'toolRunning';
        notifyListeners();

      case AgentToolFinished():
        _currentTool = '';
        _phase = 'streaming';
        notifyListeners();

      case AgentToolFailed():
        _currentTool = '';
        _phase = 'streaming';
        notifyListeners();

      case AgentSubagentStarted():
        _activeSubagents.add(SubagentInfo(
          id: event.subagentId,
          type: event.agentType,
          status: 'running',
        ));
        notifyListeners();

      case AgentSubagentFinished():
        _updateSubagent(event.subagentId, 'completed');
        notifyListeners();

      case AgentSubagentFailed():
        _updateSubagent(event.subagentId, 'failed');
        notifyListeners();

      case AgentVerificationStarted():
        _verification = VerificationInfo(
          files: event.files,
          status: 'running',
        );
        notifyListeners();

      case AgentVerificationPassed():
        _verification = _verification?.copyWith(status: 'passed');
        notifyListeners();

      case AgentVerificationFailed():
        _verification = _verification?.copyWith(
          status: 'failed',
          errors: event.errors,
        );
        notifyListeners();

      case AgentFinished():
        _phase = 'done';
        _isGenerating = false;
        _currentTool = '';
        _activeSubagents.clear();
        _verification = null;
        notifyListeners();

      case AgentError():
        _phase = 'error';
        _isGenerating = false;
        _error = event.error;
        _currentTool = '';
        notifyListeners();

      case AgentCancelled():
        _phase = AgentPhase.idle;
        _isGenerating = false;
        _currentTool = '';
        _activeSubagents.clear();
        notifyListeners();

      default:
        break;
    }
  }

  void _updateSubagent(String id, String status) {
    final idx = _activeSubagents.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      _activeSubagents[idx] = _activeSubagents[idx].copyWith(status: status);
    }
  }
}
