import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../utils/ai.dart';
import '../../utils/agent_export_service.dart';
import '../../utils/agent_history_service.dart';
import '../../utils/panda_log.dart';
import '../agent_runner.dart';
import 'agent_models.dart';
import 'flow_ui/models/flow_attachment.dart';

class QueuedAgentPrompt {
  QueuedAgentPrompt(
    this.text,
    this.attachments, {
    String? id,
    DateTime? createdAt,
    this.status = 'queued',
    this.pendingAfterRestart = false,
  })  : id = id ?? 'queued-${DateTime.now().microsecondsSinceEpoch}',
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String text;
  final List<FlowAttachment> attachments;
  final DateTime createdAt;
  String status;
  bool pendingAfterRestart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'pendingAfterRestart': pendingAfterRestart,
        'attachments': attachments
            .map((attachment) => {
                  'id': attachment.id,
                  'label': attachment.label,
                  'kind': attachment.kind,
                  'mimeType': attachment.mimeType,
                })
            .toList(),
      };

  factory QueuedAgentPrompt.fromJson(Map<String, dynamic> json) {
    final attachments = (json['attachments'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => FlowAttachment(
                id: (item['id'] ?? '').toString(),
                label: item['label']?.toString(),
                kind: item['kind']?.toString(),
                mimeType: item['mimeType']?.toString(),
              ),
            )
            .where((attachment) => attachment.id.isNotEmpty)
            .toList() ??
        <FlowAttachment>[];
    return QueuedAgentPrompt(
      json['text']?.toString() ?? '',
      attachments,
      id: json['id']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      status: json['status']?.toString() ?? 'queued',
      pendingAfterRestart: json['pendingAfterRestart'] == true,
    );
  }
}

/// Owns Panda Agent state and transport.
///
/// The home shell should only provide the current workspace and host context.
/// Conversation state must not be coupled to the editor's State object: the
/// panel can then be opened as a page, a side panel, or a floating surface
/// without creating a second runner or a second history.
class PandaAgentController extends ChangeNotifier {
  PandaAgentController({this.onRepositoryCloned}) {
    inputController.addListener(notifyListeners);
    unawaited(_loadPreferences());
    unawaited(_loadHistory());
  }

  /// Called after a successful `git clone` performed by the agent.
  /// The callback receives the absolute path of the cloned repository so the
  /// host shell can make it the active workspace.
  final ValueChanged<String>? onRepositoryCloned;

  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final AgentRunner runner = AgentRunner();
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
  final SpeechToText speech = SpeechToText();
  final List<FlowAttachment> pendingAttachments = <FlowAttachment>[];
  final List<QueuedAgentPrompt> queuedPrompts = <QueuedAgentPrompt>[];
  final List<AgentSession> history = <AgentSession>[];

  StreamSubscription<AgentChunk>? _subscription;
  Completer<bool>? _approval;
  int _requestSerial = 0;
  bool _turnFinalized = false;
  String _streamBuffer = '';
  String _visibleStreamBuffer = '';
  String _currentTool = '';

  AgentPhase phase = AgentPhase.idle;
  bool isGenerating = false;
  bool isListening = false;
  bool queuePaused = false;
  bool historyLoading = true;
  String chatMode = 'ask';
  String approvalMode = 'default';
  String conversationTitle = 'Nouvelle conversation';
  String? lastError;
  int usedTokens = 0;
  int maxTokens = 120000;
  int _promptTokens = 0;
  BuildContext? _lastContext;
  String _lastWorkspacePath = '';
  bool _disposed = false;
  String _sessionId = 'agent-${DateTime.now().microsecondsSinceEpoch}';
  bool _voiceStopRequested = false;
  bool _voiceRestarting = false;
  String _voiceBaseText = '';

  bool get hasPendingApproval => _approval != null;
  String get currentTool => _currentTool;
  String get sessionId => _sessionId;
  bool get hasPendingRestartQueue =>
      queuedPrompts.any((item) => item.pendingAfterRestart);

  Future<void> _loadHistory() async {
    final sessions = await AgentHistoryService.loadSessions();
    if (_disposed) return;
    history
      ..clear()
      ..addAll(sessions);
    if (sessions.isNotEmpty && messages.isEmpty) {
      _restoreSession(sessions.first);
    }
    historyLoading = false;
    notifyListeners();
  }

  void _restoreSession(AgentSession session) {
    _sessionId = session.id;
    conversationTitle = session.title;
    chatMode = session.agentMode;
    messages
      ..clear()
      ..addAll(
        session.messages.map((message) => Map<String, dynamic>.from(message)),
      );
    queuedPrompts
      ..clear()
      ..addAll(session.queuedPrompts.map(QueuedAgentPrompt.fromJson));
    for (final item in queuedPrompts) {
      item.pendingAfterRestart = true;
      item.status = 'queued';
    }
    queuePaused = session.queuePaused || queuedPrompts.isNotEmpty;
    lastError = null;
  }

  void selectHistorySession(AgentSession session) {
    if (isGenerating) return;
    _restoreSession(session);
    notifyListeners();
  }

  void startNewConversation() {
    if (isGenerating) stop();
    _sessionId = 'agent-${DateTime.now().microsecondsSinceEpoch}';
    conversationTitle = 'Nouvelle conversation';
    messages.clear();
    queuedPrompts.clear();
    queuePaused = false;
    lastError = null;
    notifyListeners();
  }

  Future<void> deleteHistorySession(String id) async {
    await AgentHistoryService.deleteSession(id);
    history.removeWhere((session) => session.id == id);
    if (_sessionId == id) startNewConversation();
    notifyListeners();
  }

  Future<void> archiveHistorySession(AgentSession session) async {
    final updated = session.copyWith(
      archived: !session.archived,
      updatedAt: DateTime.now(),
    );
    await AgentHistoryService.saveSession(updated);
    final index = history.indexWhere((item) => item.id == session.id);
    if (index >= 0) history[index] = updated;
    notifyListeners();
  }

  Future<void> renameHistorySession(AgentSession session, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    final updated = session.copyWith(title: clean, updatedAt: DateTime.now());
    await AgentHistoryService.saveSession(updated);
    final index = history.indexWhere((item) => item.id == session.id);
    if (index >= 0) history[index] = updated;
    if (_sessionId == session.id) conversationTitle = clean;
    notifyListeners();
  }

  void renameConversation(String title) {
    final clean = title.trim();
    if (clean.isEmpty) return;
    conversationTitle = clean;
    unawaited(_persistSession());
    notifyListeners();
  }

  String exportMarkdown() =>
      AgentExportService.exportToMarkdown(messages, modelName: '');

  String exportJson() => AgentExportService.exportToJson(messages);

  Future<void> _persistSession() async {
    if (_disposed || (messages.isEmpty && queuedPrompts.isEmpty)) return;
    final session = AgentSession(
      id: _sessionId,
      title: conversationTitle,
      updatedAt: DateTime.now(),
      messages:
          messages.map((message) => Map<String, dynamic>.from(message)).toList(),
      agentMode: chatMode,
      queuedPrompts: queuedPrompts.map((item) => item.toJson()).toList(),
      queuePaused: queuePaused,
    );
    await AgentHistoryService.saveSession(session);
    if (_disposed) return;
    final currentIndex = history.indexWhere((item) => item.id == session.id);
    if (currentIndex >= 0) {
      history[currentIndex] = session;
    } else {
      history.insert(0, session);
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      final savedMode = prefs.getString('panda_agent_chat_mode');
      final savedApproval = prefs.getString('panda_agent_approval_mode');
      if (savedMode != null && {'ask', 'agent', 'plan'}.contains(savedMode)) {
        chatMode = savedMode;
      }
      if (savedApproval != null &&
          {'default', 'every', 'autopilot'}.contains(savedApproval)) {
        approvalMode = savedApproval;
      }
      notifyListeners();
    } catch (_) {
      // Preferences are optional; the safe defaults remain active.
    }
  }

  Future<void> _persistModes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('panda_agent_chat_mode', chatMode);
    await prefs.setString('panda_agent_approval_mode', approvalMode);
  }

  String providerLabel(String provider) {
    if (provider.trim().isEmpty) return 'Custom';
    return provider
        .trim()
        .split(RegExp(r'[_-]+'))
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String get activityLabel {
    return switch (phase) {
      AgentPhase.thinking => 'Analyse en cours…',
      AgentPhase.toolRunning => _currentTool.isEmpty
          ? 'Exécution en cours…'
          : 'Exécution de $_currentTool',
      AgentPhase.streaming => 'Flux actif…',
      AgentPhase.error => 'La génération a échoué',
      _ => 'Traitement en cours…',
    };
  }

  void addAttachments(Iterable<FlowAttachment> attachments) {
    for (final attachment in attachments) {
      if (attachment.id.isEmpty ||
          pendingAttachments.any((item) => item.id == attachment.id)) {
        continue;
      }
      pendingAttachments.add(attachment);
    }
    notifyListeners();
  }

  void removeAttachment(String id) {
    pendingAttachments.removeWhere((attachment) => attachment.id == id);
    notifyListeners();
  }

  Future<void> toggleListening() async {
    if (isListening) {
      _voiceStopRequested = true;
      await speech.stop();
      isListening = false;
      notifyListeners();
      return;
    }

    final available = await speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          if (_voiceStopRequested) {
            isListening = false;
            notifyListeners();
          } else {
            unawaited(_restartSpeechSegment());
          }
        }
      },
      onError: (error) {
        if (error.permanent) {
          isListening = false;
          lastError = 'La saisie vocale n’est pas disponible sur cet appareil.';
          notifyListeners();
        } else {
          unawaited(_restartSpeechSegment());
        }
      },
    );
    if (!available) return;

    _voiceStopRequested = false;
    _voiceBaseText = inputController.text.trim();
    isListening = true;
    notifyListeners();
    await _startSpeechSegment();
  }

  Future<void> _startSpeechSegment() async {
    if (!isListening || _voiceStopRequested) return;
    await speech.listen(
      partialResults: true,
      cancelOnError: false,
      onResult: (result) {
        final heard = result.recognizedWords.trim();
        if (heard.isEmpty) return;
        final combined = <String>[
          if (_voiceBaseText.isNotEmpty) _voiceBaseText,
          heard,
        ].join(' ');
        inputController.value = inputController.value.copyWith(
          text: combined,
          selection: TextSelection.collapsed(
            offset: combined.length,
          ),
          composing: TextRange.empty,
        );
        if (result.finalResult) _voiceBaseText = combined;
        notifyListeners();
      },
    );
  }

  Future<void> _restartSpeechSegment() async {
    if (!isListening || _voiceStopRequested || _voiceRestarting) return;
    _voiceRestarting = true;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (isListening && !_voiceStopRequested) {
      await _startSpeechSegment();
    }
    _voiceRestarting = false;
  }

  MapEntry<String, dynamic>? selectedProfile(AIState state) {
    final selectedId = state.modelSelected['chat']?.toString();
    final selected = selectedId == null ? null : state.config[selectedId];
    if (selected is Map && _hasProvider(selected)) {
      return MapEntry(selectedId!, Map<String, dynamic>.from(selected));
    }

    // Older configurations did not use the agent_ prefix. A provider config
    // is valid for Agent when it is the selected chat profile.
    for (final entry in state.config.entries) {
      if (entry.value is Map && _hasProvider(entry.value)) {
        return MapEntry(entry.key, Map<String, dynamic>.from(entry.value));
      }
    }
    return null;
  }

  String providerName(Map<String, dynamic>? config) =>
      (config?['provider'] ?? config?['apiProvider'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

  String modelName(Map<String, dynamic>? config) =>
      (config?['modelName'] ?? config?['model'] ?? '').toString().trim();

  bool providerNeedsKey(String provider) {
    return provider.isNotEmpty &&
        !{'ollama', 'lmstudio', 'localllama', 'custom'}
            .contains(provider);
  }

  Future<void> send({
    required BuildContext context,
    required AIState aiState,
    required String workspacePath,
    String? text,
    List<FlowAttachment>? attachmentsOverride,
  }) async {
    final prompt = (text ?? inputController.text).trim();
    final attachments = List<FlowAttachment>.of(
      attachmentsOverride ?? pendingAttachments,
    );
    if (prompt.isEmpty && attachments.isEmpty) return;
    if (isGenerating) {
      if (queuedPrompts.length >= 5) {
        lastError = 'La file d’attente est pleine (5 messages maximum).';
      } else {
        queuedPrompts.add(QueuedAgentPrompt(prompt, attachments));
        inputController.clear();
        pendingAttachments.clear();
        lastError = null;
        unawaited(_persistSession());
      }
      notifyListeners();
      return;
    }

    final requestId = ++_requestSerial;
    _lastContext = context;
    _lastWorkspacePath = workspacePath;
    isGenerating = true;
    phase = AgentPhase.thinking;
    lastError = null;
    if (messages.isEmpty && conversationTitle == 'Nouvelle conversation') {
      conversationTitle = _smartTitle(
        prompt.isEmpty ? (attachments.first.label ?? 'Pièce jointe') : prompt,
      );
    }
    messages
      ..add(<String, dynamic>{
        'role': 'user',
        'text': prompt,
        'attachments': attachments
            .map(
              (attachment) => <String, dynamic>{
                'path': attachment.id,
                'name': attachment.label ?? attachment.id,
                'mimeType': attachment.mimeType,
              },
            )
            .toList(),
        'phase': 'done',
      })
      ..add(<String, dynamic>{
        'role': 'agent',
        'text': '',
        'thinking': '',
        'showThinkingLine': true,
        'activityLabel': 'Préparation de la demande…',
        'activityState': 'working',
        'phase': 'streaming',
        'toolCalls': <Map<String, dynamic>>[],
        'blocks': <Map<String, dynamic>>[],
      });
    inputController.clear();
    pendingAttachments.clear();
    _streamBuffer = '';
    _visibleStreamBuffer = '';
    _currentTool = '';
    _turnFinalized = false;
    unawaited(_persistSession());
    // Create the assistant turn before resolving the model so the startup
    // orb is visible immediately, including while credentials are loading.
    notifyListeners();

    try {
      final selected = selectedProfile(aiState);
      final config = selected?.value is Map
          ? Map<String, dynamic>.from(selected!.value as Map)
          : null;
      final model = await _resolveModel(config);
      if (model == null) {
        throw StateError(_modelError(config));
      }

      final prefs = await SharedPreferences.getInstance();
      final memory = prefs.getBool('agent_memory_enabled') == false
          ? ''
          : (prefs.getString('agent_memory_notes') ?? '').trim();
      final customPrompt = (prefs.getString('agent_system_prompt') ?? '').trim();
      final projectMemory = _readProjectMemory(workspacePath);
      final systemParts = <String>[
        if (customPrompt.isNotEmpty) customPrompt,
        if (memory.isNotEmpty) 'Persistent project/user context:\n$memory',
        if (projectMemory.isNotEmpty) '## MÉMOIRE PROJET\n$projectMemory',
      ];

      final history = _historyForModel();
      final attachmentSummary = attachments
          .map((attachment) => attachment.label ?? attachment.id)
          .where((name) => name.trim().isNotEmpty)
          .join(', ');
      final modelPrompt = [
        if (prompt.isNotEmpty) prompt,
        if (attachmentSummary.isNotEmpty)
          '[Pièces jointes: $attachmentSummary]',
      ].join('\n');
      history.add(<String, dynamic>{'role': 'user', 'content': modelPrompt});
      usedTokens = _estimateTokens(
        history.map((entry) => entry['content']?.toString() ?? '').join('\n'),
      );
      maxTokens = _contextLimit(config);
      _promptTokens = usedTokens;
      notifyListeners();
      // Keep the persistent activity row in "Starting/Thinking" until the
      // first model chunk arrives. The message itself is streaming, but the
      // visible phase should not skip the opening analysis state.
      notifyListeners();

      await _subscription?.cancel();
      _subscription = runner
          .run(
            model: model,
            messages: history,
            context: context,
            workspacePath: workspacePath,
            agentMode: chatMode,
            approvalMode: approvalMode,
            onConfirmRequired: _requestApproval,
            systemPromptOverride:
                systemParts.isEmpty ? null : systemParts.join('\n\n'),
          )
          .listen(
            (chunk) => _handleChunk(chunk, requestId),
            onError: (Object error, StackTrace stack) {
              PandaLog.e('PandaAgent', 'Stream error', error: '$error\n$stack');
              _finish(
                requestId,
                error: error.toString(),
                failed: true,
              );
            },
            onDone: () => _finish(requestId),
          );
    } catch (error, stack) {
      PandaLog.e('PandaAgent', 'Failed before stream started',
          error: '$error\n$stack');
      _finish(requestId, error: error.toString(), failed: true);
    }
  }

  void stop() {
    if (!isGenerating) return;
    _requestSerial++;
    runner.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final approval = _approval;
    _approval = null;
    approval?.complete(false);
    isGenerating = false;
    // Stop is an explicit park operation: queued prompts stay pending and
    // never start until the user resumes them.
    queuePaused = true;
    phase = AgentPhase.idle;
    _currentTool = '';
    if (messages.isNotEmpty && messages.last['role'] == 'agent') {
      final visibleText = _stripThinking(_streamBuffer).text;
      messages.last['text'] =
          visibleText.isEmpty ? 'Génération arrêtée.' : visibleText;
      messages.last['phase'] = 'error';
    }
    notifyListeners();
    unawaited(_persistSession());
  }

  void resolveApproval(bool allowed) {
    final completer = _approval;
    _approval = null;
    if (messages.isNotEmpty && messages.last['role'] == 'agent') {
      final blocks = _blocks();
      final blockIndex = blocks.lastIndexWhere(
          (block) => block['type'] == 'toolCall' && block['status'] == 'pending_approval');
      if (blockIndex >= 0) {
        blocks[blockIndex]['status'] = allowed ? 'running' : 'cancelled';
        if (!allowed) blocks[blockIndex]['result'] = 'Annulé par l’utilisateur';
      }
      messages.last['blocks'] = blocks;
      notifyListeners();
    }
    completer?.complete(allowed);
  }

  void setMode(String mode) {
    if (!{'ask', 'agent', 'plan'}.contains(mode) || chatMode == mode) return;
    chatMode = mode;
    unawaited(_persistModes());
    notifyListeners();
  }

  void setApprovalMode(String mode) {
    if (!{'default', 'every', 'autopilot'}.contains(mode)) return;
    approvalMode = mode;
    unawaited(_persistModes());
    notifyListeners();
  }

  Future<void> selectModel(BuildContext context, String modelId) async {
    final bloc = context.read<AIBloc>();
    final separator = modelId.indexOf('::');
    final profileId = separator > 0 ? modelId.substring(0, separator) : modelId;
    final selectedModel = separator > 0
        ? modelId.substring(separator + 2).trim()
        : null;
    final config = Map<String, dynamic>.from(bloc.state.config);
    if (selectedModel != null && selectedModel.isNotEmpty && config[profileId] is Map) {
      final profile = Map<String, dynamic>.from(config[profileId] as Map)
        ..['modelName'] = selectedModel
        ..['model'] = selectedModel;
      config[profileId] = profile;
      bloc.add(AIConfigEvent(config));
    }
    final selected = Map<String, dynamic>.from(bloc.state.modelSelected)
      ..['chat'] = profileId;
    bloc.add(ModelSelectEvent(selected));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modelSelected', jsonEncode(selected));
    notifyListeners();
  }

  void removeQueued(int index) {
    if (index < 0 || index >= queuedPrompts.length) return;
    queuedPrompts.removeAt(index);
    unawaited(_persistSession());
    notifyListeners();
  }

  void editQueued(int index, String text) {
    if (index < 0 || index >= queuedPrompts.length || text.trim().isEmpty) return;
    queuedPrompts[index].text = text.trim();
    unawaited(_persistSession());
    notifyListeners();
  }

  void moveQueued(int index, int direction) {
    final nextIndex = index + direction;
    if (index < 0 ||
        index >= queuedPrompts.length ||
        nextIndex < 0 ||
        nextIndex >= queuedPrompts.length) {
      return;
    }
    final item = queuedPrompts.removeAt(index);
    queuedPrompts.insert(nextIndex, item);
    unawaited(_persistSession());
    notifyListeners();
  }

  void clearQueue() {
    if (queuedPrompts.isEmpty) return;
    queuedPrompts.clear();
    queuePaused = false;
    unawaited(_persistSession());
    notifyListeners();
  }

  void pauseQueue() {
    if (queuePaused) return;
    queuePaused = true;
    unawaited(_persistSession());
    notifyListeners();
  }

  /// Promotes an item without interrupting the active run. This is the safe
  /// interpretation of "Send now" when the runner cannot steer mid-tool-call.
  void sendQueuedNow(int index) {
    if (index < 0 || index >= queuedPrompts.length) return;
    final item = queuedPrompts.removeAt(index);
    queuedPrompts.insert(0, item);
    unawaited(_persistSession());
    notifyListeners();
  }

  void resumeQueue({
    required BuildContext context,
    required AIState aiState,
    required String workspacePath,
  }) {
    if (isGenerating || queuedPrompts.isEmpty) return;
    queuePaused = false;
    _startNextQueued(
      context: context,
      aiState: aiState,
      workspacePath: workspacePath,
    );
    notifyListeners();
  }

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
  }

  void retry(int messageIndex) {
    if (isGenerating || messageIndex <= 0 || messageIndex >= messages.length) return;
    final userIndex = messageIndex - 1;
    if (messages[userIndex]['role'] != 'user') return;
    inputController.text = messages[userIndex]['text']?.toString() ?? '';
    messages.removeRange(userIndex, messages.length);
    notifyListeners();
  }

  List<Map<String, dynamic>> _historyForModel() {
    final result = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message['role']?.toString();
      if (role == 'user') {
        final text = message['text']?.toString() ?? '';
        if (text.isNotEmpty) result.add({'role': 'user', 'content': text});
        continue;
      }
      if (role != 'agent') continue;
      final parts = <String>[];
      final blocks = (message['blocks'] as List?)
              ?.whereType<Map>()
              .map((block) => Map<String, dynamic>.from(block)) ??
          const <Map<String, dynamic>>[];
      for (final block in blocks) {
        switch (block['type']) {
          case 'toolCall':
            parts.add('[tool ${block['name'] ?? 'unknown'}]\n'
                '${block['result'] ?? 'running'}');
          case 'text':
            final blockText = block['text']?.toString() ?? '';
            if (blockText.isNotEmpty) parts.add(blockText);
        }
      }
      final text = message['text']?.toString() ?? '';
      if (parts.isEmpty && text.isNotEmpty) parts.add(text);
      if (parts.isNotEmpty) {
        result.add({'role': 'assistant', 'content': parts.join('\n\n')});
      }
    }
    return result;
  }

  Future<Models?> _resolveModel(Map<String, dynamic>? config) async {
    if (config == null) return null;
    final provider = providerName(config);
    final key = Models.resolveApiKey(config);
    if (providerNeedsKey(provider) && key.isEmpty) return null;
    return _modelFromConfig({...config, 'apiKey': key, 'key': key});
  }

  Models? _modelFromConfig(Map<String, dynamic> config) {
    final provider = providerName(config);
    final key = Models.resolveApiKey(config);
    final model = modelName(config);
    switch (provider) {
      case 'gemini': return Gemini(apiKey: key, model: model);
      case 'claude': return Claude(apiKey: key, model: model);
      case 'openai': return OpenAI(apiKey: key, model: model);
      case 'grok': return Grok(apiKey: key, model: model);
      case 'deepseek': return DeepSeek(apiKey: key, model: model);
      case 'mistral': return Mistral(apiKey: key, model: model);
      case 'togetherai': return TogetherAi(apiKey: key, model: model);
      case 'perplexity': return Perplexity(apiKey: key, model: model);
      case 'openrouter': return OpenRouter(apiKey: key, model: model);
      case 'groq': return Groq(apiKey: key, model: model);
      case 'fireworks': return FireWorks(apiKey: key, model: model);
      case 'cohere': return Cohere(apiKey: key, model: model);
      case 'cerebras': return Cerebras(apiKey: key, model: model);
      case 'novita': return Novita(apiKey: key, model: model);
      case 'hyperbolic': return Hyperbolic(apiKey: key, model: model);
      case 'sambanova': return SambaNova(apiKey: key, model: model);
      case 'qwen': return Qwen(apiKey: key, model: model);
      case 'ollama':
        return Ollama(model: model, port: (config['port'] as num?)?.toInt() ?? 11434);
      case 'lmstudio':
        return LmStudio(model: model, port: (config['port'] as num?)?.toInt() ?? 1234);
      case 'localllama':
        final modelPath = (config['modelPath'] ?? '').toString().trim();
        if (modelPath.isEmpty) return null;
        return LocalLlama(
          modelPath: modelPath,
          displayName: model.isEmpty ? modelPath.split('/').last : model,
          threads: (config['threads'] as num?)?.toInt() ?? 4,
          contextSize: (config['contextSize'] as num?)?.toInt() ?? 4096,
          gpuLayers: (config['gpuLayers'] as num?)?.toInt() ?? 0,
          temperature: (config['temperature'] as num?)?.toDouble() ?? 0.7,
          topP: (config['topP'] as num?)?.toDouble() ?? 0.9,
          topK: (config['topK'] as num?)?.toInt() ?? 40,
          repeatPenalty: (config['repeatPenalty'] as num?)?.toDouble() ?? 1.1,
          frequencyPenalty: (config['frequencyPenalty'] as num?)?.toDouble() ?? 0,
          presencePenalty: (config['presencePenalty'] as num?)?.toDouble() ?? 0,
          repeatLastN: (config['repeatLastN'] as num?)?.toInt() ?? 64,
          seed: (config['seed'] as num?)?.toInt() ?? 42,
          maxTokens: (config['maxTokens'] as num?)?.toInt() ?? 512,
          mirostat: (config['mirostat'] as num?)?.toInt() ?? 0,
          mirostatTau: (config['mirostatTau'] as num?)?.toDouble() ?? 5,
          mirostatEta: (config['mirostatEta'] as num?)?.toDouble() ?? 0.1,
        );
      case 'custom':
        final url = (config['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final headers = <String, String>{};
        final rawHeaders = config['headers'];
        if (rawHeaders is Map) {
          rawHeaders.forEach((key, value) {
            if (key != null && value != null) {
              headers[key.toString()] = value.toString();
            }
          });
        }
        if (key.isNotEmpty && !headers.containsKey('Authorization')) {
          headers['Authorization'] = 'Bearer $key';
        }
        return CustomModel(
          url: url,
          httpMethod: (config['httpMethod'] ?? 'POST').toString(),
          toolCallingMethod: ToolCallingMethod.openAiCompatible,
          customHeaders: headers,
          requestBuilder: (code, instruction) => {
            if (model.isNotEmpty) 'model': model,
            'messages': [
              {'role': 'system', 'content': instruction},
              {'role': 'user', 'content': code},
            ],
          },
          customParser: (response) {
            if (response is! Map) return response?.toString() ?? '';
            final choices = response['choices'];
            if (choices is List && choices.isNotEmpty && choices.first is Map) {
              final message = choices.first['message'] ?? choices.first['delta'];
              if (message is Map) return (message['content'] ?? '').toString();
            }
            return (response['text'] ?? response['content'] ?? '').toString();
          },
        );
      default:
        return null;
    }
  }

  void _handleChunk(AgentChunk chunk, int requestId) {
    if (requestId != _requestSerial || messages.isEmpty || _turnFinalized) return;
    final message = messages.last;
    if (message['role'] != 'agent') return;
    final blocks = _blocks();
    switch (chunk.phase) {
      case AgentPhase.thinking:
        phase = AgentPhase.thinking;
        message['activityLabel'] = _thinkingActivityLabel(chunk.text);
        message['activityState'] = 'working';
        final thinking = chunk.text.trim();
        if (thinking.isNotEmpty) {
          _closeThinkingBlocks(blocks);
          message['thinking'] =
              '${message['thinking'] ?? ''}${chunk.text}';
          _appendBlock(
            blocks,
            'thinking',
            {
              'thinking': chunk.text,
              'label': _thinkingActivityLabel(chunk.text),
              'active': true,
            },
          );
        }
      case AgentPhase.toolRunning:
        phase = AgentPhase.toolRunning;
        _closeThinkingBlocks(blocks);
        _currentTool = chunk.toolName ?? 'outil';
        message['activityLabel'] = _activityLabelForTool(
          _currentTool,
          chunk.toolArgs ?? const <String, dynamic>{},
        );
        message['activityState'] = _orbStateForTool(_currentTool);
        final id = '${chunk.blockId ?? DateTime.now().microsecondsSinceEpoch}:$_currentTool';
        blocks.add({
          'type': 'toolCall',
          'id': id,
          'name': _currentTool,
          'args': chunk.toolArgs ?? const <String, dynamic>{},
          'result': null,
          'status': 'running',
        });
      case AgentPhase.toolDone:
        _closeThinkingBlocks(blocks);
        message['activityLabel'] = 'Analyse du résultat…';
        message['activityState'] = 'solving';
        final index = blocks.lastIndexWhere((block) =>
            block['type'] == 'toolCall' &&
            block['name'] == (chunk.toolName ?? _currentTool) &&
            block['status'] == 'running');
        if (index >= 0) {
          blocks[index]['result'] = chunk.toolResult ?? '';
          blocks[index]['status'] = 'done';
          _notifyRepositoryCloned(
            toolName: chunk.toolName ?? _currentTool,
            args: Map<String, dynamic>.from(
              (blocks[index]['args'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{},
            ),
            result: chunk.toolResult ?? '',
          );
        }
        _currentTool = '';
      case AgentPhase.streaming:
        phase = AgentPhase.streaming;
        _closeThinkingBlocks(blocks);
        message['activityLabel'] = 'Rédaction de la réponse…';
        message['activityState'] = 'composing';
        _streamBuffer += chunk.text;
        usedTokens = math.min(
          maxTokens,
          _promptTokens + _estimateTokens(_streamBuffer),
        ).toInt();
        final clean = _stripThinking(_streamBuffer);
        message['text'] = clean.text;
        message['thinking'] = '';
        final visibleDelta = clean.text.startsWith(_visibleStreamBuffer)
            ? clean.text.substring(_visibleStreamBuffer.length)
            : clean.text;
        _visibleStreamBuffer = clean.text;
        if (visibleDelta.isNotEmpty) {
          _appendBlock(blocks, 'text', {'text': visibleDelta});
        }
      case AgentPhase.done:
        _finish(requestId);
      case AgentPhase.error:
        _finish(requestId, error: chunk.text, failed: true);
      case AgentPhase.idle:
        break;
    }
    message['blocks'] = blocks;
    notifyListeners();
    _scrollToLatest();
  }

  Future<bool> _requestApproval({
    required String toolName,
    required String command,
    required String details,
  }) async {
    if (_approval != null) return _approval!.future;
    final completer = Completer<bool>();
    _approval = completer;
    if (messages.isNotEmpty && messages.last['role'] == 'agent') {
      final blocks = _blocks();
      final index = blocks.lastIndexWhere(
          (block) => block['type'] == 'toolCall' && block['name'] == toolName);
      if (index >= 0) {
        blocks[index]['status'] = 'pending_approval';
        blocks[index]['command'] = command;
        messages.last['blocks'] = blocks;
        notifyListeners();
      }
    }
    return completer.future;
  }

  void _finish(int requestId, {String? error, bool failed = false}) {
    if (requestId != _requestSerial || _turnFinalized) return;
    _turnFinalized = true;
    isGenerating = false;
    phase = failed ? AgentPhase.error : AgentPhase.done;
    if (messages.isNotEmpty && messages.last['role'] == 'agent') {
      if (failed) {
        final visibleText = _stripThinking(_streamBuffer).text;
        messages.last['text'] = visibleText.isEmpty
            ? 'Erreur : ${error ?? 'la génération a échoué'}'
            : visibleText;
        messages.last['phase'] = 'error';
        lastError = error;
      } else {
        messages.last['phase'] = 'done';
        messages.last['activityLabel'] = 'Action terminée';
      }
      messages.last['thinking'] = '';
      messages.last['blocks'] = _blocks();
    }
    _currentTool = '';
    notifyListeners();
    unawaited(_persistSession());
    if (!queuePaused) {
      final nextContext = _lastContext;
      final nextAiState = nextContext != null && nextContext.mounted
          ? nextContext.read<AIBloc>().state
          : null;
      _startNextQueued(
        context: nextContext,
        aiState: nextAiState,
        workspacePath: _lastWorkspacePath,
      );
    }
  }

  void _startNextQueued({
    required BuildContext? context,
    required AIState? aiState,
    required String workspacePath,
  }) {
    if (isGenerating ||
        queuePaused ||
        queuedPrompts.isEmpty ||
        context == null ||
        !context.mounted ||
        aiState == null) {
      return;
    }
    final next = queuedPrompts.removeAt(0);
    next.status = 'running';
    next.pendingAfterRestart = false;
    unawaited(_persistSession());
    unawaited(
      Future<void>.delayed(
        Duration.zero,
        () => send(
          context: context,
          aiState: aiState,
          workspacePath: workspacePath,
          text: next.text,
          attachmentsOverride: next.attachments,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _blocks() {
    if (messages.isEmpty || messages.last['role'] != 'agent') {
      return <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.from(
      (messages.last['blocks'] as List?)
              ?.whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value)) ??
          const <Map<String, dynamic>>[],
    );
  }

  void _appendBlock(
    List<Map<String, dynamic>> blocks,
    String type,
    Map<String, dynamic> data,
  ) {
    if (type == 'thinking' && blocks.isNotEmpty && blocks.last['type'] == type) {
      blocks.last['thinking'] =
          '${blocks.last['thinking'] ?? ''}${data['thinking'] ?? ''}';
      if (data['active'] == true) blocks.last['active'] = true;
      final label = data['label']?.toString().trim() ?? '';
      if (label.isNotEmpty) blocks.last['label'] = label;
      return;
    }
    if (type == 'text' && blocks.isNotEmpty && blocks.last['type'] == type) {
      blocks.last['text'] = '${blocks.last['text'] ?? ''}${data['text'] ?? ''}';
      return;
    }
    blocks.add({'type': type, ...data});
  }

  void _closeThinkingBlocks(List<Map<String, dynamic>> blocks) {
    for (final block in blocks) {
      if (block['type'] == 'thinking') block['active'] = false;
    }
  }

  String _thinkingActivityLabel(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('explor') ||
        lower.contains('méthode') ||
        lower.contains('approach') ||
        lower.contains('option')) {
      return 'Exploration des différentes méthodes…';
    }
    if (lower.contains('plan') ||
        lower.contains('étape') ||
        lower.contains('step')) {
      return 'Construction du plan…';
    }
    if (lower.contains('vérif') ||
        lower.contains('test') ||
        lower.contains('check')) {
      return 'Vérification de la solution…';
    }
    if (lower.contains('fichier') ||
        lower.contains('dépôt') ||
        lower.contains('repo') ||
        lower.contains('projet')) {
      return 'Analyse du projet…';
    }
    return 'Réflexion sur la demande…';
  }

  void _notifyRepositoryCloned({
    required String toolName,
    required Map<String, dynamic> args,
    required String result,
  }) {
    final lowerTool = toolName.toLowerCase();
    if (!lowerTool.contains('shell') &&
        !lowerTool.contains('command') &&
        !lowerTool.contains('bash')) {
      return;
    }

    final command = (args['command'] ?? args['cmd'] ?? '').toString().trim();
    if (!command.toLowerCase().contains('git clone')) return;

    final exitCode = RegExp(r'''exitCode['"]?\s*[:=]\s*['"]?(\d+)''')
        .firstMatch(result)
        ?.group(1);
    if (exitCode != null && exitCode != '0') return;

    final outputPath = RegExp(r'''Cloning into ['"]([^'"]+)['"]''',
            caseSensitive: false)
        .firstMatch(result)
        ?.group(1);
    final cloneTarget = outputPath ?? _cloneTargetFromCommand(command);
    if (cloneTarget == null || cloneTarget.trim().isEmpty) return;
    if (_lastWorkspacePath.trim().isEmpty) return;

    final absolutePath = path.isAbsolute(cloneTarget)
        ? path.normalize(cloneTarget)
        : path.normalize(path.join(_lastWorkspacePath, cloneTarget));
    if (absolutePath == _lastWorkspacePath ||
        !Directory(absolutePath).existsSync()) {
      return;
    }
    onRepositoryCloned?.call(absolutePath);
  }

  String? _cloneTargetFromCommand(String command) {
    final tokens = command
        .replaceAll('&&', ' && ')
        .replaceAll(';', ' ; ')
        .split(RegExp(r'\s+'))
        .map(_unquoteShellToken)
        .where((token) => token.isNotEmpty)
        .toList();
    final cloneIndex = tokens.indexWhere(
      (token) => token.toLowerCase() == 'clone',
    );
    if (cloneIndex < 0) return null;

    final positional = <String>[];
    const optionsWithValues = {
      '--branch',
      '-b',
      '--depth',
      '--origin',
      '-o',
      '--template',
      '--config',
      '--separate-git-dir',
      '--reference',
      '--dissociate',
      '--upload-pack',
    };
    var skipNext = false;
    for (var i = cloneIndex + 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '&&' || token == ';' || token == '|') break;
      if (skipNext) {
        skipNext = false;
        continue;
      }
      if (token == '--') continue;
      if (token.startsWith('-')) {
        if (optionsWithValues.contains(token)) skipNext = true;
        continue;
      }
      positional.add(token);
      if (positional.length == 2) break;
    }
    if (positional.isEmpty) return null;
    if (positional.length > 1) return positional[1];

    final source = positional.first.split('?').first.split('#').first;
    final sourceUri = Uri.tryParse(source);
    final sourcePath = sourceUri != null && sourceUri.path.isNotEmpty
        ? sourceUri.path
        : source.replaceFirst(RegExp(r'^.+:'), '');
    final name = path.basename(sourcePath);
    if (name.isEmpty || name == '.') return null;
    return name.endsWith('.git') ? name.substring(0, name.length - 4) : name;
  }

  String _unquoteShellToken(String token) {
    if (token.length >= 2 &&
        ((token.startsWith("'") && token.endsWith("'")) ||
            (token.startsWith('"') && token.endsWith('"')))) {
      return token.substring(1, token.length - 1);
    }
    return token;
  }

  String _activityLabelForTool(String toolName, Map<String, dynamic> args) {
    final humanLabel = toolHumanLabel(toolName, args);
    if (humanLabel != 'Action en cours…') return humanLabel;

    final name = toolName.toLowerCase();
    final command = (args['command'] ?? args['cmd'] ?? '').toString();
    if (command.contains('git clone')) return 'Clonage du dépôt…';
    if (command.contains('npm install') ||
        command.contains('bun install') ||
        command.contains('pip install') ||
        command.contains('flutter pub get')) {
      return 'Installation des dépendances…';
    }
    if (command.contains('git')) return 'Opération Git en cours…';
    if (name.contains('search') ||
        name.contains('grep') ||
        name.contains('glob') ||
        name.contains('find')) {
      return 'Exploration du projet…';
    }
    if (name.contains('read') || name.contains('list')) {
      return 'Lecture du projet…';
    }
    if (name.contains('write') ||
        name.contains('edit') ||
        name.contains('create') ||
        name.contains('patch')) {
      return 'Modification du projet…';
    }
    if (name.contains('shell') ||
        name.contains('command') ||
        name.contains('exec') ||
        name.contains('run')) {
      return 'Exécution de la commande…';
    }
    return 'Action en cours…';
  }

  String _orbStateForTool(String toolName) {
    final name = toolName.toLowerCase();
    if (name.contains('search') ||
        name.contains('grep') ||
        name.contains('glob') ||
        name.contains('find') ||
        name.contains('read') ||
        name.contains('list')) {
      return 'searching';
    }
    if (name.contains('write') ||
        name.contains('edit') ||
        name.contains('create') ||
        name.contains('patch')) {
      return 'shaping';
    }
    if (name.contains('shell') ||
        name.contains('command') ||
        name.contains('exec') ||
        name.contains('run') ||
        name.contains('git')) {
      return 'solving';
    }
    return 'working';
  }

  ({String text, String thinking}) _stripThinking(String value) {
    var thinking = '';
    for (final match in RegExp(
      r'<(think|thought)>([\s\S]*?)(?:</\1>|$)',
      caseSensitive: false,
    ).allMatches(value)) {
      thinking += '${match.group(2)?.trim() ?? ''}\n';
    }
    final text = value
        .replaceAll(
          RegExp(r'<(think|thought)>[\s\S]*?(?:</\1>|$)',
              caseSensitive: false),
          '',
        )
        .trim();
    return (text: text, thinking: thinking.trim());
  }

  String _readProjectMemory(String workspacePath) {
    if (workspacePath.isEmpty) return '';
    try {
      final file = File('$workspacePath/.panda/memory.md');
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  String _modelError(Map<String, dynamic>? config) {
    if (config == null) {
      return 'Aucun provider configuré pour Panda Agent. Ouvrez Tools → Providers.';
    }
    final provider = providerName(config);
    if (providerNeedsKey(provider) && Models.resolveApiKey(config).isEmpty) {
      return 'Aucune clé configurée pour $provider. Ouvrez Tools → Providers.';
    }
    return 'Impossible de charger le modèle ${modelName(config)}.';
  }

  int _estimateTokens(String value) =>
      math.max(0, (value.length / 4).ceil()).toInt();

  int _contextLimit(Map<String, dynamic>? config) {
    final configured = config?['contextSize'] ?? config?['maxContextTokens'];
    final value = configured is num ? configured.toInt() : 120000;
    return value.clamp(1024, 1000000).toInt();
  }

  bool _hasProvider(dynamic config) =>
      config is Map &&
      (config['provider'] ?? config['apiProvider'])?.toString().trim().isNotEmpty ==
          true;

  String _smartTitle(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 42) return clean;
    return '${clean.substring(0, 39)}…';
  }

  void _scrollToLatest() {
    if (!scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    runner.cancel();
    unawaited(_subscription?.cancel());
    unawaited(speech.stop());
    _approval?.complete(false);
    inputController.removeListener(notifyListeners);
    inputController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}