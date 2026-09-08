import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../utils/ai.dart';
import '../../utils/copilot_chat.dart';
import '../../utils/panda_log.dart';
import '../agent_runner.dart';
import 'flow_ui/models/flow_attachment.dart';

class QueuedAgentPrompt {
  QueuedAgentPrompt(this.text, this.attachments);

  String text;
  final List<FlowAttachment> attachments;
}

/// Owns Panda Agent state and transport.
///
/// The home shell should only provide the current workspace and host context.
/// Conversation state must not be coupled to the editor's State object: the
/// panel can then be opened as a page, a side panel, or a floating surface
/// without creating a second runner or a second history.
class PandaAgentController extends ChangeNotifier {
  PandaAgentController() {
    inputController.addListener(notifyListeners);
  }

  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final AgentRunner runner = AgentRunner();
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
  final SpeechToText speech = SpeechToText();
  final List<FlowAttachment> pendingAttachments = <FlowAttachment>[];
  final List<QueuedAgentPrompt> queuedPrompts = <QueuedAgentPrompt>[];

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
  String chatMode = 'ask';
  String approvalMode = 'default';
  String conversationTitle = 'Nouvelle conversation';
  String? lastError;
  int usedTokens = 0;
  int maxTokens = 120000;
  BuildContext? _lastContext;
  String _lastWorkspacePath = '';

  bool get hasPendingApproval => _approval != null;
  String get currentTool => _currentTool;

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
      await speech.stop();
      isListening = false;
      notifyListeners();
      return;
    }

    final available = await speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          isListening = false;
          notifyListeners();
        }
      },
      onError: (_) {
        isListening = false;
        notifyListeners();
      },
    );
    if (!available) return;

    isListening = true;
    notifyListeners();
    await speech.listen(
      onResult: (result) {
        inputController.value = inputController.value.copyWith(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(
            offset: result.recognizedWords.length,
          ),
          composing: TextRange.empty,
        );
        notifyListeners();
      },
    );
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
        !{'copilot', 'ollama', 'lmstudio', 'localllama', 'custom', 'pandagateway'}
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
      notifyListeners();
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
    phase = AgentPhase.idle;
    _currentTool = '';
    if (messages.isNotEmpty && messages.last['role'] == 'agent') {
      final visibleText = _stripThinking(_streamBuffer).text;
      messages.last['text'] =
          visibleText.isEmpty ? 'Génération arrêtée.' : visibleText;
      messages.last['phase'] = 'error';
    }
    notifyListeners();
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
    notifyListeners();
  }

  void setApprovalMode(String mode) {
    if (!{'default', 'every', 'autopilot'}.contains(mode)) return;
    approvalMode = mode;
    notifyListeners();
  }

  Future<void> selectModel(BuildContext context, String modelId) async {
    final bloc = context.read<AIBloc>();
    final selected = Map<String, dynamic>.from(bloc.state.modelSelected)
      ..['chat'] = modelId;
    bloc.add(ModelSelectEvent(selected));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modelSelected', jsonEncode(selected));
    notifyListeners();
  }

  void removeQueued(int index) {
    if (index < 0 || index >= queuedPrompts.length) return;
    queuedPrompts.removeAt(index);
    notifyListeners();
  }

  void editQueued(int index, String text) {
    if (index < 0 || index >= queuedPrompts.length || text.trim().isEmpty) return;
    queuedPrompts[index].text = text.trim();
    notifyListeners();
  }

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
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
    if (provider == 'copilot') {
      final auth = await CopilotChat.loadAuthContext();
      if (auth == null) return null;
      final client = CopilotChat(
        authToken: auth.authToken,
        initialApiEndpoint: auth.apiEndpoint,
      );
      var selectedModel = modelName(config);
      if (selectedModel.isEmpty || selectedModel == 'auto') {
        final payload = await client.getCopilotModels();
        final catalog = (payload['data'] as List?)
                ?.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) => item['id'] != null)
                .where((item) => item['model_picker_enabled'] != false)
                .toList() ??
            const <Map<String, dynamic>>[];
        selectedModel = catalog.isEmpty ? '' : catalog.first['id'].toString();
      }
      if (selectedModel.isEmpty) return null;
      return Copilot(
        authToken: auth.authToken,
        apiEndpoint: auth.apiEndpoint,
        model: selectedModel,
      );
    }
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
      case 'pandagateway':
        return PandaGateway(apiKey: key, model: model, port: (config['port'] as num?)?.toInt() ?? 8000);
      case 'localllama':
        final modelPath = (config['modelPath'] ?? '').toString().trim();
        if (modelPath.isEmpty) return null;
        return LocalLlama(
          modelPath: modelPath,
          displayName: model.isEmpty ? modelPath.split('/').last : model,
          threads: (config['threads'] as num?)?.toInt() ?? 4,
          contextSize: (config['contextSize'] as num?)?.toInt() ?? 4096,
          gpuLayers: (config['gpuLayers'] as num?)?.toInt() ?? 0,
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
        final thinking = chunk.text.trim();
        if (thinking.isNotEmpty) {
          message['thinking'] =
              '${message['thinking'] ?? ''}${chunk.text}';
          _appendBlock(blocks, 'thinking', {'thinking': chunk.text});
        }
      case AgentPhase.toolRunning:
        phase = AgentPhase.toolRunning;
        _currentTool = chunk.toolName ?? 'outil';
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
        final index = blocks.lastIndexWhere((block) =>
            block['type'] == 'toolCall' &&
            block['name'] == (chunk.toolName ?? _currentTool) &&
            block['status'] == 'running');
        if (index >= 0) {
          blocks[index]['result'] = chunk.toolResult ?? '';
          blocks[index]['status'] = 'done';
        }
        _currentTool = '';
      case AgentPhase.streaming:
        phase = AgentPhase.streaming;
        _streamBuffer += chunk.text;
        usedTokens = math.max(
          usedTokens,
          _estimateTokens(_streamBuffer),
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
      }
      messages.last['thinking'] = '';
      messages.last['blocks'] = _blocks();
    }
    _currentTool = '';
    notifyListeners();
    if (queuedPrompts.isNotEmpty) {
      final next = queuedPrompts.removeAt(0);
      final nextContext = _lastContext;
      final nextWorkspace = _lastWorkspacePath;
      if (nextContext != null && nextContext.mounted) {
        unawaited(Future<void>.delayed(
          Duration.zero,
          () => send(
            context: nextContext,
            aiState: nextContext.read<AIBloc>().state,
            workspacePath: nextWorkspace,
            text: next.text,
            attachmentsOverride: next.attachments,
          ),
        ));
      }
    }
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
      return;
    }
    if (type == 'text' && blocks.isNotEmpty && blocks.last['type'] == type) {
      blocks.last['text'] = '${blocks.last['text'] ?? ''}${data['text'] ?? ''}';
      return;
    }
    blocks.add({'type': type, ...data});
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