library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../bloc/ui_bloc/ui_bloc.dart';
import '../bloc/repo_bloc/repo_bloc.dart';
import '../core/broken_icons.dart';
import '../utils/ai.dart';
import '../utils/constants.dart';
import '../utils/agentic_tool_catalog.dart';
import '../utils/copilot_chat.dart';
import '../utils/panda_log.dart';
import '../utils/subagent_orchestrator.dart';
import '../utils/api_key_rotation.dart';
import '../utils/agent_history_service.dart';
import 'agent_runner.dart';
import 'agent/agent_diff_viewer.dart';
import 'agent/agent_rooms_page.dart';
import 'agent/provider_models.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/ai_provider_logos.dart';
import '../utils/agent_export_service.dart';
import 'widgets.dart';

part 'agent/agent_settings_widgets.dart';

const _kAccent  = Color(0xff6366f1);
const _kDanger  = Color(0xffe05252);
const _kSuccess = Color(0xff4caf7d);

// Agent settings main page
// Extracted from agent_settings.dart

class AgentSettings extends StatefulWidget {
  final bool embedded;
  /// When true, reuse the provider settings implementation as a standalone
  /// page. This keeps the provider flow in one place without rendering the
  /// legacy Chat/Tools/Subagents shell inside Panda Agent.
  final bool providersOnly;
  /// When true, open directly on Tools → Settings → Providers.
  final bool openProvidersDirectly;

  const AgentSettings({
    super.key,
    this.embedded = false,
    this.providersOnly = false,
    this.openProvidersDirectly = false,
  });

  @override
  State<AgentSettings> createState() => _AgentSettingsState();
}

class _AgentSettingsState extends State<AgentSettings>
    with TickerProviderStateMixin {

  // ── Main tab controller ─────────────────────────────────────────────────
  late TabController _tab; // Chat | Tools | Subagents

  // ── Chat tab state ──────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _chatMessages = [];
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  String? _attachedImageBase64;
  final _chatInputCtrl  = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool       _chatGenerating   = false;
  AgentPhase _chatPhase        = AgentPhase.idle;
  String     _chatActivityLabel = '';
  DateTime?  _chatGenerationStartedAt;
  String     _chatStreamBuf    = '';
  String     _chatThinkingBuf  = '';
  int        _chatSerial       = 0;
  bool       _showScrollLatest = false;
  final List<String> _chatContextChips = [];
  final      _chatRunner       = AgentRunner();
  String     _chatMode         = 'plan'; // 'ask' | 'agent' | 'plan' — plan par défaut

  // ── Turn / rotation de clés ──────────────────────────────────────────────
  int  _turnAttempt      = 0;
  int? _activeAgentIdx;
  String? _turnProvider;
  String? _turnKeyId;
  String? _turnCfgKey;
  List<Map<String, dynamic>>? _turnMessages;
  String? _turnSystemOverride;
  Map<String, dynamic>? _turnBaseCfg;
  final Set<String> _triedKeys = {};

  // ── Dictée vocale ───────────────────────────────────────────────────────
  stt.SpeechToText? _speech;
  bool _speechAvailable = false;
  bool _listening       = false;

  // ── Orchestrateur sous-agents / rooms ────────────────────────────────────
  SubagentOrchestrator? _orch;

  // ── Tools tab state ─────────────────────────────────────────────────────
  bool _showToolsSettings = false; // false = tool list, true = settings sub-view

  // Provider/model state (used in Tools > Settings)
  String _selectedProviderId = 'openai';
  final _apiKeyCtrl         = TextEditingController();
  final _keyProfileNameCtrl = TextEditingController();
  final _customUrlCtrl      = TextEditingController();
  bool _obscureKey          = true;
  bool _testingKey          = false;
  bool? _testKeyResult;
  String _testKeyMessage    = '';
  List<Map<String, dynamic>> _availableModels = const [];

  // Memory settings
  final _memoryNotesCtrl   = TextEditingController();
  final _systemPromptCtrl  = TextEditingController();
  bool _memoryEnabled      = true;

  // ── Cost tracking ────────────────────────────────────────────────────────
  double _sessionCostUsd   = 0.0;   // cumulative cost for the session
  int    _sessionTokensIn  = 0;     // estimated input tokens sent
  int    _sessionTokensOut = 0;     // estimated output tokens received

  // ── Settings sub-tab (inside Tools > Settings) ──────────────────────────
  late TabController _settingsSubTab; // Providers | Mémoire | Apparence

  @override
  void initState() {
    super.initState();
    _tab            = TabController(length: 3, vsync: this); // Chat | Tools | Subagents
    _settingsSubTab = TabController(length: 4, vsync: this);
    _chatInputCtrl.addListener(() => setState(() {}));
    _chatScrollCtrl.addListener(_onChatScroll);
    _loadMemorySettings();
    KeyRotationBrain.instance;
    SubagentOrchestrator.instance.load().then((_) {
      if (!mounted) return;
      setState(() => _orch = SubagentOrchestrator.instance);
    });
    if (widget.openProvidersDirectly) {
      _tab.index             = 1; // Tools
      _showToolsSettings     = true;
      _settingsSubTab.index  = 0; // Providers
    }
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final s = stt.SpeechToText();
      _speechAvailable = await s.initialize(onError: (_) => setState(() => _listening = false));
      if (mounted) setState(() => _speech = s);
    } catch (_) {
      _speechAvailable = false;
    }
  }

  void _toggleListening() async {
    final s = _speech;
    if (s == null || !_speechAvailable) {
      _showSnack(context, 'Dictée vocale indisponible sur cet appareil.', isError: true);
      return;
    }
    if (_listening) {
      await s.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await s.listen(
      localeId: 'fr_FR',
      onResult: (r) {
        if (!r.finalResult) return;
        final current = _chatInputCtrl.text;
        final cursor = _chatInputCtrl.selection.baseOffset.clamp(0, current.length);
        final insert = current.isEmpty ? r.recognizedWords : '${current.substring(0, cursor)}${r.recognizedWords}${current.substring(cursor)}';
        _chatInputCtrl.value = TextEditingValue(
          text: insert,
          selection: TextSelection.collapsed(offset: cursor + r.recognizedWords.length),
        );
      },
      listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  void _onChatScroll() {
    if (!_chatScrollCtrl.hasClients) return;
    final distance = _chatScrollCtrl.position.maxScrollExtent -
        _chatScrollCtrl.position.pixels;
    final shouldShow = distance > 140 && _chatGenerating;
    if (shouldShow != _showScrollLatest && mounted) {
      setState(() => _showScrollLatest = shouldShow);
    }
  }

  Future<void> _loadMemorySettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _memoryEnabled         = prefs.getBool('agent_memory_enabled') ?? true;
      _memoryNotesCtrl.text  = prefs.getString('agent_memory_notes') ?? '';
      _systemPromptCtrl.text = prefs.getString('agent_system_prompt') ?? '';
    });
    // Restore previous conversation
    if (_chatMessages.isEmpty) await _loadChatHistory();
  }

  Future<void> _saveMemorySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_memory_enabled', _memoryEnabled);
    await prefs.setString('agent_memory_notes', _memoryNotesCtrl.text);
    await prefs.setString('agent_system_prompt', _systemPromptCtrl.text);
  }

  // ── Chat history ─────────────────────────────────────────────────────────

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _chatMessages.length > 200
          ? _chatMessages.sublist(_chatMessages.length - 200)
          : _chatMessages;
      await prefs.setString('agent_chat_history', jsonEncode(toSave));

      final titleMsg = _chatMessages.firstWhere(
            (m) => m['role'] == 'user',
            orElse: () => {'text': 'Nouvelle discussion'},
          )['text']?.toString() ?? 'Nouvelle discussion';

      final session = AgentSession(
        id: _currentSessionId,
        title: titleMsg.length > 50 ? '${titleMsg.substring(0, 50)}...' : titleMsg,
        updatedAt: DateTime.now(),
        messages: List<Map<String, dynamic>>.from(_chatMessages),
        agentMode: _chatMode,
      );
      await AgentHistoryService.saveSession(session);
    } catch (_) {}
  }

  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('agent_chat_history');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _chatMessages.addAll(list.cast<Map<String, dynamic>>());
      });
    } catch (_) {}
  }

  // ── .pandarules — lecture depuis le projet courant ───────────────────────

  Future<String> _loadPandaRules(SharedPreferences prefs) async {
    try {
      // Get the most recent project root from SharedPreferences
      final rawRecent = prefs.getString('recent');
      if (rawRecent == null || rawRecent.isEmpty) return '';
      final recent = jsonDecode(rawRecent);
      String? rootDir;
      if (recent is List && recent.isNotEmpty) {
        final first = recent.first;
        if (first is Map) {
          rootDir = first['rootDir']?.toString() ?? first['path']?.toString();
        }
      }
      if (rootDir == null || rootDir.isEmpty) return '';
      final file = File('$rootDir/.pandarules');
      if (!await file.exists()) return '';
      final content = await file.readAsString();
      return content.trim();
    } catch (_) {
      return '';
    }
  }

  // ── Cost tracking helpers ─────────────────────────────────────────────────

  /// Returns (inputCostPerMToken, outputCostPerMToken) in USD.
  (double, double) _costRateFor(String model) {
    final m = model.toLowerCase();
    // Gemini
    if (m.contains('gemini-2.5-pro'))      return (1.25, 10.00);
    if (m.contains('gemini-2.5-flash-lite')) return (0.075, 0.30);
    if (m.contains('gemini-2.5-flash'))    return (0.15, 0.60);
    if (m.contains('gemini-1.5-pro'))      return (1.25, 5.00);
    if (m.contains('gemini-1.5-flash'))    return (0.075, 0.30);
    if (m.contains('gemini-1.0-pro'))      return (0.50, 1.50);
    // OpenAI
    if (m.contains('gpt-4o-mini'))         return (0.15, 0.60);
    if (m.contains('gpt-4o'))              return (2.50, 10.00);
    if (m.contains('gpt-4-turbo'))         return (10.00, 30.00);
    if (m.contains('gpt-4'))               return (30.00, 60.00);
    if (m.contains('gpt-3.5'))             return (0.50, 1.50);
    if (m.contains('o3-mini'))             return (1.10, 4.40);
    if (m.contains('o3'))                  return (10.00, 40.00);
    if (m.contains('o1-mini'))             return (1.10, 4.40);
    if (m.contains('o1'))                  return (15.00, 60.00);
    // Claude
    if (m.contains('claude-3-5-sonnet'))   return (3.00, 15.00);
    if (m.contains('claude-3-5-haiku'))    return (0.80, 4.00);
    if (m.contains('claude-3-opus'))       return (15.00, 75.00);
    if (m.contains('claude-3-haiku'))      return (0.25, 1.25);
    if (m.contains('claude'))              return (3.00, 15.00);
    // DeepSeek
    if (m.contains('deepseek-r1'))         return (0.55, 2.19);
    if (m.contains('deepseek'))            return (0.27, 1.10);
    // Grok
    if (m.contains('grok-3-mini'))         return (0.30, 0.50);
    if (m.contains('grok'))                return (3.00, 15.00);
    // Mistral
    if (m.contains('mistral-large'))       return (2.00, 6.00);
    if (m.contains('mistral-small'))       return (0.20, 0.60);
    if (m.contains('mixtral'))             return (0.65, 0.65);
    // Llama / Groq
    if (m.contains('llama-3'))             return (0.20, 0.20);
    return (1.00, 1.00); // safe default
  }

  void _trackCost({required String modelName, required int inputTokens, required int outputTokens}) {
    final (inRate, outRate) = _costRateFor(modelName);
    final cost = (inputTokens / 1000000) * inRate + (outputTokens / 1000000) * outRate;
    if (mounted) {
      setState(() {
        _sessionTokensIn  += inputTokens;
        _sessionTokensOut += outputTokens;
        _sessionCostUsd   += cost;
      });
    }
  }

  String _fmtCost(double usd) {
    if (usd < 0.001) return '<\$0.001';
    if (usd < 0.01)  return '\$${usd.toStringAsFixed(4)}';
    if (usd < 1.0)   return '\$${usd.toStringAsFixed(3)}';
    return '\$${usd.toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    _tab.dispose();
    _settingsSubTab.dispose();
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    _apiKeyCtrl.dispose();
    _keyProfileNameCtrl.dispose();
    _customUrlCtrl.dispose();
    _memoryNotesCtrl.dispose();
    _systemPromptCtrl.dispose();
    try { _speech?.stop(); } catch (_) {}
    _chatRunner.cancel();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT — send logic
  // ══════════════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════════════
  // TOKEN COUNTER helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Approximate token count using the 4-chars-per-token heuristic.
  int _estimateTokens() {
    int chars = 0;
    for (final m in _chatMessages) {
      chars += (m['text'] as String? ?? '').length;
      chars += (m['thinking'] as String? ?? '').length;
      final calls = m['toolCalls'] as List? ?? [];
      for (final c in calls) {
        chars += (c['result'] as String? ?? '').length;
      }
    }
    chars += _chatInputCtrl.text.length;
    return (chars / 4).ceil();
  }

  /// Context window size (tokens) for the active model.
  int _contextWindowFor(String model) {
    final m = model.toLowerCase();
    // Gemini
    if (m.contains('gemini-2.5-pro'))   return 2000000;
    if (m.contains('gemini-2.5'))       return 1000000;
    if (m.contains('gemini-1.5-pro'))   return 2000000;
    if (m.contains('gemini-1.5'))       return 1000000;
    if (m.contains('gemini-exp'))       return 1000000;
    if (m.contains('gemini'))           return 128000;
    // OpenAI
    if (m.contains('gpt-4o'))           return 128000;
    if (m.contains('gpt-4-turbo'))      return 128000;
    if (m.contains('gpt-4-32k'))        return 32000;
    if (m.contains('gpt-4'))            return 8000;
    if (m.contains('gpt-3.5'))          return 16000;
    if (m.contains('o1-pro'))           return 200000;
    if (m.contains('o1'))               return 200000;
    if (m.contains('o3'))               return 200000;
    // Claude
    if (m.contains('claude'))           return 200000;
    // DeepSeek
    if (m.contains('deepseek-r1'))      return 128000;
    if (m.contains('deepseek'))         return 64000;
    // Llama
    if (m.contains('llama-3'))          return 128000;
    if (m.contains('llama-2'))          return 4000;
    // Mistral / Mixtral
    if (m.contains('mixtral'))          return 32000;
    if (m.contains('mistral-large'))    return 128000;
    if (m.contains('mistral'))          return 32000;
    // Grok
    if (m.contains('grok-3'))           return 131072;
    if (m.contains('grok'))             return 131072;
    // Qwen
    if (m.contains('qwen'))             return 128000;
    // Groq hosted
    if (m.contains('gemma'))            return 8000;
    return 32000; // safe default
  }

  String _fmtK(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}k';
    return '$n';
  }

  void _chatScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _chatSend() async {
    final text = _chatInputCtrl.text.trim();
    if (text.isEmpty || _chatGenerating) return;
    final requestId = ++_chatSerial;

    final aiState = context.read<AIBloc>().state;
    final selectedId = aiState.modelSelected['chat']?.toString();
    final selectedConfig = selectedId == null ? null : aiState.config[selectedId];
    final isAgentProfile = selectedId != null && selectedId.startsWith('agent_');

    if (!isAgentProfile || selectedConfig == null) {
      setState(() {
        _chatMessages.add({'role': 'user', 'text': text});
        _chatMessages.add({
          'role': 'agent',
          'text': 'Aucun provider configuré. Allez dans Tools → Settings → Providers pour ajouter un provider.',
          'thinking': '',
          'phase': 'error',
        });
        _chatInputCtrl.clear();
      });
      _chatScrollToBottom();
      return;
    }

    setState(() {
      _chatGenerating = true;
      _chatPhase      = AgentPhase.thinking;
      _chatActivityLabel = 'Réflexion sur votre demande…';
      _chatGenerationStartedAt = DateTime.now();
    });

    try {
      Models? model;
      try {
        final cfg = Map<String, dynamic>.from(selectedConfig as Map);
        // ── Cerveau de rotation : la meilleure clé du provider est injectée.
        _turnAttempt = 0; // reset rotation attempts
        _triedKeys.clear();
        _turnCfgKey  = selectedId;
        _turnBaseCfg = cfg;
        _turnProvider = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString().toLowerCase();
        await _applyKeyRotation(cfg);
        _turnKeyId = KeyRotationBrain.instance.profileIdForKey(
            _turnProvider!, Models.resolveApiKey(cfg));
        model = await _resolveModel(cfg);
      } catch (e) {
        setState(() {
          _chatGenerating = false;
          _chatPhase      = AgentPhase.error;
          _chatActivityLabel = '';
          _chatGenerationStartedAt = null;
          _chatMessages.add({'role': 'user', 'text': text});
          _chatMessages.add({'role': 'agent', 'text': 'Erreur résolution modèle : $e', 'thinking': '', 'phase': 'error'});
          _chatInputCtrl.clear();
        });
        _chatScrollToBottom();
        return;
      }

      if (model == null) {
        setState(() {
          _chatGenerating = false;
          _chatPhase      = AgentPhase.error;
          _chatActivityLabel = '';
          _chatGenerationStartedAt = null;
          _chatMessages.add({'role': 'user', 'text': text});
          _chatMessages.add({'role': 'agent', 'text': 'Modèle non disponible. Vérifiez votre configuration dans Tools → Settings.', 'thinking': '', 'phase': 'error'});
          _chatInputCtrl.clear();
        });
        _chatScrollToBottom();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final memoryEnabled = prefs.getBool('agent_memory_enabled') ?? true;
      final memoryNotes   = memoryEnabled ? (prefs.getString('agent_memory_notes') ?? '').trim() : '';
      final customPrompt  = (prefs.getString('agent_system_prompt') ?? '').trim();

      // ── .pandarules injection ─────────────────────────────────────────────
      final pandaRules = await _loadPandaRules(prefs);

      final parts = <String>[
        if (customPrompt.isNotEmpty) customPrompt,
        if (pandaRules.isNotEmpty) '# Project rules (.pandarules)\n$pandaRules',
        if (memoryNotes.isNotEmpty) 'Persistent context:\n$memoryNotes',
      ];

      final history = <Map<String, dynamic>>[];
      for (final m in _chatMessages) {
        final role    = m['role']?.toString();
        final content = m['text']?.toString() ?? '';
        if ((role == 'user' || role == 'agent') && content.isNotEmpty) {
          history.add({'role': role == 'user' ? 'user' : 'assistant', 'content': content});
        }
      }
      final messages = [...history, {'role': 'user', 'content': text}];

      setState(() {
        _chatMessages.add({'role': 'user', 'text': text});
        _chatMessages.add({
          'role': 'agent',
          'text': '',
          'thinking': '',
          'phase': 'streaming',
          'toolCalls': <Map<String, dynamic>>[],
          'timeline': <Map<String, dynamic>>[],
        });
        _chatInputCtrl.clear();
        _chatStreamBuf   = '';
        _chatThinkingBuf = '';
        _chatPhase       = AgentPhase.streaming;
      });

      final agentIdx = _chatMessages.length - 1;
      _activeAgentIdx     = agentIdx;
      _turnMessages       = messages;
      _turnSystemOverride = parts.isEmpty ? null : parts.join('\n\n');

      _subscribeAgentTurn(requestId: requestId, agentIdx: agentIdx, model: model);
    } catch (e) {
      PandaLog.e('AgentSettings', 'Chat send error', error: e);
      if (mounted) {
        setState(() {
          _chatGenerating = false;
          _chatPhase      = AgentPhase.error;
          _chatActivityLabel = '';
          _chatGenerationStartedAt = null;
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ROTATION DE CLÉS + SOUSCRIPTION DU TOUR AGENT (timeline chronologique)
  // ══════════════════════════════════════════════════════════════════════════

  /// Injecte dans [cfg] la meilleure clé disponible du cerveau de rotation
  /// (least-recently-used, en évitant les clés en cooldown / quota épuisé).
  Future<void> _applyKeyRotation(Map<String, dynamic> cfg) async {
    final brain    = KeyRotationBrain.instance;
    final provider = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString().toLowerCase();
    if (!brain.hasProfiles(provider)) return;
    final picked = await brain.pickKey(provider);
    if (picked == null || picked.isEmpty) return;
    cfg['apiKey']  = picked;
    cfg['key']     = picked;
    cfg['api_key'] = picked;
  }

  bool _isTurnMessage(int idx) =>
      idx >= 0 && idx < _chatMessages.length && _chatMessages[idx]['role'] == 'agent';

  /// Abonne le runner pour le tour courant. Les chunks sont rangés dans la
  /// timeline du message dans le vrai ordre chronologique :
  /// réflexion → texte d'annonce → outils → réflexion → … → réponse finale.
  void _subscribeAgentTurn({required int requestId, required int agentIdx, required Models model}) {
    _chatRunner.run(
      model: model,
      messages: _turnMessages ?? const [],
      context: context,
      workspacePath: '',
      agentMode: _chatMode,
      systemPromptOverride: _turnSystemOverride,
    ).listen(
      (chunk) {
        if (!mounted || requestId != _chatSerial || !_isTurnMessage(agentIdx)) return;
        _handleAgentChunk(chunk, agentIdx);
      },
      onError: (e) {
        PandaLog.e('AgentSettings', 'Stream error', error: e);
        if (!mounted || requestId != _chatSerial || !_isTurnMessage(agentIdx)) return;
        setState(() {
          _chatGenerating = false;
          _chatPhase      = AgentPhase.error;
          _chatActivityLabel = '';
          _chatGenerationStartedAt = null;
          _chatMessages[agentIdx]['text']  = 'Erreur : $e';
          _chatMessages[agentIdx]['phase'] = 'error';
        });
      },
      onDone: () => _onAgentTurnDone(requestId, agentIdx),
    );
  }

  String _activityLabelForTool(String toolName) {
    if (toolName == 'runShellCommand') return 'Exécution dans le terminal…';
    if (toolName.startsWith('search') || toolName.startsWith('grep') ||
        toolName.startsWith('glob')) {
      return 'Recherche dans le projet…';
    }
    if (toolName.startsWith('read') || toolName.startsWith('list')) {
      return 'Lecture du projet…';
    }
    if (toolName.startsWith('write') || toolName.startsWith('edit') ||
        toolName.startsWith('replace') || toolName.startsWith('insert')) {
      return 'Modification des fichiers…';
    }
    if (toolName.startsWith('openLinks')) return 'Recherche sur internet…';
    if (toolName.startsWith('git')) return 'Opération Git…';
    return 'Exécution d’une action…';
  }

  void _handleAgentChunk(AgentChunk chunk, int agentIdx) {
    var retryStatusCode = 0;
    setState(() {
      final msg = _chatMessages[agentIdx];
      final tl = (msg['timeline'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];

      /// Retrouve ou crée le bloc chronologique correspondant.
      Map<String, dynamic> upsertBlock(String type, int? id, String append) {
        Map<String, dynamic>? block;
        if (id != null) {
          for (final b in tl) {
            if (b['type'] == type && b['id'] == id) {
              block = b;
              break;
            }
          }
        } else if (tl.isNotEmpty && tl.last['type'] == type && tl.last['id'] == null) {
          block = tl.last;
        }
        block ??= {'type': type, if (id != null) 'id': id, 'text': ''};
        if (!tl.contains(block)) tl.add(block);
        block['text'] = (block['text'] as String? ?? '') + append;
        return block;
      }

      void syncLegacyToolCalls() {
        msg['toolCalls'] = tl
            .where((b) => b['type'] == 'tool')
            .map((b) => {
                  'name': b['name'],
                  'args': b['args'],
                  'result': b['result'],
                  'status': b['status'],
                })
            .toList();
      }

      switch (chunk.phase) {
        case AgentPhase.thinking:
          _chatPhase = AgentPhase.thinking;
          _chatActivityLabel = 'Réflexion…';
          _chatThinkingBuf += chunk.text;
          msg['thinking'] = _chatThinkingBuf;
          if (chunk.text.isNotEmpty) upsertBlock('thinking', chunk.blockId, chunk.text);
        case AgentPhase.streaming:
          _chatPhase = AgentPhase.streaming;
          _chatActivityLabel = 'Génération de la réponse…';
          _chatStreamBuf += chunk.text;
          msg['text'] = _chatStreamBuf;
          // Un texte qui suit des outils ouvre forcément un NOUVEAU bloc :
          // upsertBlock s'en charge car le dernier bloc est alors un 'tool'.
          if (chunk.text.isNotEmpty) upsertBlock('text', chunk.blockId, chunk.text);
        case AgentPhase.toolRunning:
          _chatPhase = AgentPhase.toolRunning;
          _chatActivityLabel = chunk.toolName == null || chunk.toolName!.isEmpty
              ? 'Exécution d’une action…'
              : _activityLabelForTool(chunk.toolName!);
          tl.add({
            'type': 'tool',
            'name': chunk.toolName ?? '',
            'args': chunk.toolArgs ?? {},
            'result': null,
            'status': 'running',
          });
          syncLegacyToolCalls();
        case AgentPhase.toolDone:
          for (var i = tl.length - 1; i >= 0; i--) {
            final b = tl[i];
            if (b['type'] == 'tool' &&
                b['name'] == (chunk.toolName ?? '') &&
                b['status'] == 'running') {
              b['result'] = chunk.toolResult ?? '';
              b['status'] = 'done';
              break;
            }
          }
          syncLegacyToolCalls();
        case AgentPhase.done:
          _chatPhase      = AgentPhase.done;
          _chatGenerating = false;
          _chatActivityLabel = '';
          _chatGenerationStartedAt = null;
          msg['phase'] = 'done';
          KeyRotationBrain.instance.reportSuccess(_turnProvider ?? '', _turnKeyId);
        case AgentPhase.error:
          final codeMatch = RegExp(r'\((\d{3})\)').firstMatch(chunk.text);
          final code = codeMatch != null ? int.tryParse(codeMatch.group(1)!) : null;
          const retryable = {401, 402, 403, 429, 500, 502, 503};
          if (code != null && retryable.contains(code) && _turnAttempt < 3) {
            // Pas d'erreur affichée tout de suite : on retente avec une autre clé.
            msg['phase']    = 'streaming';
            retryStatusCode = code;
          } else {
            _chatPhase      = AgentPhase.error;
            _chatGenerating = false;
            _chatActivityLabel = '';
            _chatGenerationStartedAt = null;
            msg['text']  = _chatStreamBuf.isNotEmpty ? _chatStreamBuf : 'Erreur : ${chunk.text}';
            msg['phase'] = 'error';
          }
        case AgentPhase.idle:
          break;
      }
    });
    if (retryStatusCode > 0) {
      unawaited(_retryWithNextKey(retryStatusCode));
    }
    _chatScrollToBottom();
  }

  /// Erreur récupérable (429 / 402 / 401 / 403 / 5xx) → le cerveau de
  /// rotation met la clé fautive en cooldown puis on relance avec la suivante.
  Future<void> _retryWithNextKey(int statusCode) async {
    if (!mounted) return;
    final provider = _turnProvider ?? '';
    final brain    = KeyRotationBrain.instance;
    await brain.reportFailure(provider, _turnKeyId, statusCode);
    if (_turnKeyId != null) _triedKeys.add(_turnKeyId!);

    final agentIdx = _activeAgentIdx ?? -1;
    void failOut(String message) {
      if (!mounted) return;
      setState(() {
        _chatGenerating = false;
        _chatPhase      = AgentPhase.error;
        _chatActivityLabel = '';
        _chatGenerationStartedAt = null;
        if (_isTurnMessage(agentIdx)) {
          _chatMessages[agentIdx]['text']  = message;
          _chatMessages[agentIdx]['phase'] = 'error';
        }
      });
    }

    final cfg = Map<String, dynamic>.from(_turnBaseCfg ?? {});
    await _applyKeyRotation(cfg);
    final nextKey = Models.resolveApiKey(cfg);
    final nextId  = brain.profileIdForKey(provider, nextKey);

    if (_triedKeys.contains(nextId ?? '')) {
      failOut('Toutes les clés connues ont été refusées (HTTP $statusCode). '
          'Ajoutez une nouvelle clé ou attendez la réinitialisation du quota '
          'dans Tools → Settings → Providers.');
      return;
    }

    final model = _modelFromAiConfig(cfg);
    if (model == null) {
      failOut('Impossible de reconstruire le modèle avec la clé suivante.');
      return;
    }
    _turnKeyId    = nextId;
    _turnAttempt += 1;
    _chatStreamBuf   = '';
    _chatThinkingBuf = '';
    setState(() {
      if (_isTurnMessage(agentIdx)) {
        _chatMessages[agentIdx]['text']     = '';
        _chatMessages[agentIdx]['thinking'] = '';
        _chatMessages[agentIdx]['phase']    = 'streaming';
      }
      _chatPhase = AgentPhase.thinking;
      _chatActivityLabel = 'Réflexion…';
    });
    PandaLog.i('AgentSettings', 'Rotation: retry attempt $_turnAttempt with another key');
    _subscribeAgentTurn(requestId: _chatSerial, agentIdx: agentIdx, model: model);
  }

  void _onAgentTurnDone(int requestId, int agentIdx) {
    if (!mounted || requestId != _chatSerial || !_chatGenerating) return;
    setState(() {
      _chatGenerating = false;
      if (_chatPhase != AgentPhase.error) {
        _chatPhase = AgentPhase.done;
        if (_isTurnMessage(agentIdx)) _chatMessages[agentIdx]['phase'] = 'done';
      }
    });
    // ── Cost + history ──────────────────────────────────────────────
    _saveChatHistory();
    // Estimate tokens for this turn and track cost
    final aiState2 = context.read<AIBloc>().state;
    final selId2   = aiState2.modelSelected['chat']?.toString();
    final cfg2     = selId2 == null ? null : aiState2.config[selId2];
    if (cfg2 != null) {
      final modelName2 = (cfg2['modelName'] ?? cfg2['model'] ?? '').toString();
      final userMsg  = _chatMessages
          .where((m) => m['role'] == 'user')
          .map((m) => (m['text'] as String? ?? '').length)
          .fold(0, (a, b) => a + b);
      final agentMsg = (_chatStreamBuf.length + _chatThinkingBuf.length);
      _trackCost(
        modelName: modelName2,
        inputTokens:  (userMsg / 4).ceil(),
        outputTokens: (agentMsg / 4).ceil(),
      );
    }
  }

  Models? _modelFromAiConfig(Map<String, dynamic> cfg) {
    final providerRaw = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString();
    final provider    = providerRaw.toLowerCase();
    final apiKey      = Models.resolveApiKey(cfg);
    final modelName   = (cfg['modelName'] ?? cfg['model'] ?? '').toString();

    switch (provider) {
      case 'gemini':     return Gemini(apiKey: apiKey, model: modelName);
      case 'claude':     return Claude(apiKey: apiKey, model: modelName);
      case 'openai':     return OpenAI(apiKey: apiKey, model: modelName);
      case 'grok':       return Grok(apiKey: apiKey, model: modelName);
      case 'deepseek':   return DeepSeek(apiKey: apiKey, model: modelName);
      case 'mistral':    return Mistral(apiKey: apiKey, model: modelName);
      case 'togetherai': return TogetherAi(apiKey: apiKey, model: modelName);
      case 'perplexity': return Perplexity(apiKey: apiKey, model: modelName);
      case 'openrouter': return OpenRouter(apiKey: apiKey, model: modelName);
      case 'groq':       return Groq(apiKey: apiKey, model: modelName);
      case 'fireworks':  return FireWorks(apiKey: apiKey, model: modelName);
      case 'cohere':     return Cohere(apiKey: apiKey, model: modelName);
      case 'cerebras':   return Cerebras(apiKey: apiKey, model: modelName);
      case 'novita':     return Novita(apiKey: apiKey, model: modelName);
      case 'hyperbolic': return Hyperbolic(apiKey: apiKey, model: modelName);
      case 'sambanova':  return SambaNova(apiKey: apiKey, model: modelName);
      case 'qwen':       return Qwen(apiKey: apiKey, model: modelName);
      case 'ollama':
        final ollamaPort = (cfg['port'] as num?)?.toInt() ?? 11434;
        return Ollama(model: modelName, port: ollamaPort);
      case 'lmstudio':
        final lmsPort = (cfg['port'] as num?)?.toInt() ?? 1234;
        return LmStudio(model: modelName, port: lmsPort);
      case 'pandagateway':
        final port = (cfg['port'] as num?)?.toInt() ?? 8000;
        return PandaGateway(apiKey: apiKey, model: modelName, port: port);
      case 'localllama':
        final mp = (cfg['modelPath'] ?? '').toString().trim();
        if (mp.isEmpty) return null;
        return LocalLlama(
          modelPath: mp,
          displayName: modelName.isNotEmpty ? modelName : mp.split('/').last,
          threads: (cfg['threads'] as num?)?.toInt() ?? 4,
          contextSize: (cfg['contextSize'] as num?)?.toInt() ?? 4096,
          gpuLayers: (cfg['gpuLayers'] as num?)?.toInt() ?? 0,
        );
      case 'custom':
        final url = (cfg['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final parsedHeaders = <String, String>{};
        final hdrs = cfg['headers'];
        if (hdrs is Map) {
          hdrs.forEach((k, v) {
            if (k != null && v != null) parsedHeaders[k.toString()] = v.toString();
          });
        }
        if (apiKey.isNotEmpty && !parsedHeaders.containsKey('Authorization')) {
          parsedHeaders['Authorization'] = 'Bearer $apiKey';
        }
        return CustomModel(
          url: url,
          httpMethod: (cfg['httpMethod'] ?? 'POST').toString(),
          toolCallingMethod: ToolCallingMethod.openAiCompatible,
          customHeaders: parsedHeaders,
          requestBuilder: (code, instruction) => {
            if (modelName.isNotEmpty) 'model': modelName,
            'messages': [
              {'role': 'system', 'content': instruction},
              {'role': 'user', 'content': code},
            ],
          },
          customParser: (response) {
            try {
              final data = response is Map ? response : {};
              final choices = data['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final msg = choices.first['message'] ?? choices.first['delta'];
                if (msg is Map) return (msg['content'] ?? '').toString();
              }
              return (data['text'] ?? data['content'] ?? response ?? '').toString();
            } catch (_) {
              return response?.toString() ?? '';
            }
          },
        );
      default:
        return null;
    }
  }

  Future<Models?> _resolveModel(Map<String, dynamic> cfg) async {
    final provider = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString().toLowerCase();
    if (provider != 'copilot') {
      return _modelFromAiConfig(cfg);
    }
    final auth = await CopilotChat.loadAuthContext();
    if (auth == null) return null;
    final client = CopilotChat(authToken: auth.authToken, initialApiEndpoint: auth.apiEndpoint);
    final payload  = await client.getCopilotModels();
    final models   = (payload['data'] as List?)
        ?.whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => m['id'] != null)
        .toList() ?? [];
    final modelName = models.isNotEmpty ? models.first['id'].toString() : '';
    if (modelName.isEmpty) return null;
    return Copilot(authToken: auth.authToken, apiEndpoint: auth.apiEndpoint, model: modelName);
  }

  void _chatStop() {
    _chatSerial++;
    _chatRunner.cancel();
    if (!mounted) return;
    setState(() {
      _chatGenerating = false;
      _chatPhase      = AgentPhase.idle;
      _chatActivityLabel = '';
      _chatGenerationStartedAt = null;
      if (_chatMessages.isNotEmpty &&
          _chatMessages.last['role'] == 'agent' &&
          (_chatMessages.last['phase'] == 'streaming' ||
              _chatMessages.last['phase'] == 'thinking')) {
        _chatMessages.last['text'] =
            _chatStreamBuf.isEmpty ? 'Génération arrêtée.' : _chatStreamBuf;
        _chatMessages.last['phase'] = 'cancelled';
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROVIDER SETTINGS — validate & save
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _testApiKey() async {
    final provider = providerDefs.firstWhere((p) => p.id == _selectedProviderId, orElse: () => providerDefs.first);
    final apiKey   = _apiKeyCtrl.text.trim();

    if (_selectedProviderId == 'copilot') {
      final githubSignedIn  = context.read<GithubAuthCubit>().state.isSignedIn;
      final copilotSignedIn = context.read<CopilotBloc>().state.isSignedIn;
      if (!githubSignedIn && !copilotSignedIn) {
        setState(() { _testKeyResult = false; _testKeyMessage = 'Connectez GitHub ou Copilot avant de valider ce provider.'; });
        return;
      }
    }
    if (provider.hasApiKey && apiKey.isEmpty) {
      setState(() { _testKeyResult = false; _testKeyMessage = 'Entrez la clé API avant de valider.'; });
      return;
    }
    if (_selectedProviderId == 'custom' && _customUrlCtrl.text.trim().isEmpty) {
      setState(() { _testKeyResult = false; _testKeyMessage = 'Entrez l\'URL de l\'endpoint avant de valider.'; });
      return;
    }

    setState(() { _testingKey = true; _testKeyResult = null; _testKeyMessage = 'Connexion au provider…'; _availableModels = const []; });

    try {
      final models = await _fetchLiveModels(provider: _selectedProviderId, apiKey: apiKey, customUrl: _customUrlCtrl.text.trim())
          .timeout(const Duration(seconds: 45));
      if (models.isEmpty) throw StateError('Aucun modèle retourné.');
      if (apiKey.isNotEmpty && _selectedProviderId != 'copilot') {
        // Le cerveau de rotation connaît désormais cette clé (profil nommé).
        await KeyRotationBrain.instance.addProfile(_selectedProviderId, _keyProfileNameCtrl.text, apiKey);
        _keyProfileNameCtrl.clear();
      }
      await _saveProviderConfig(context, provider: provider, apiKey: apiKey, models: models);
      setState(() {
        _testingKey      = false;
        _testKeyResult   = true;
        _availableModels = models;
        _testKeyMessage  = '✓ ${models.length} modèles récupérés. Provider activé.';
      });
      _showSnack(context, '${provider.name} activé ✓');
    } catch (e) {
      setState(() { _testingKey = false; _testKeyResult = false; _testKeyMessage = '✕ Impossible de valider : $e'; });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLiveModels({
    required String provider,
    required String apiKey,
    required String customUrl,
  }) async {
    if (provider == 'copilot') {
      final auth = await CopilotChat.loadAuthContext();
      if (auth == null) throw StateError('Connectez votre compte GitHub/Copilot.');
      final payload = await CopilotChat(authToken: auth.authToken, initialApiEndpoint: auth.apiEndpoint).getCopilotModels();
      return _normalizeModelCatalog(payload);
    }

    final urls = <String, String>{
      'openai':      'https://api.openai.com/v1/models',
      'claude':      'https://api.anthropic.com/v1/models',
      'gemini':      'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      'deepseek':    'https://api.deepseek.com/models',
      'grok':        'https://api.x.ai/v1/models',
      'openrouter':  'https://openrouter.ai/api/v1/models',
      'mistral':     'https://api.mistral.ai/v1/models',
      'togetherai':  'https://api.together.xyz/v1/models',
      'perplexity':  'https://api.perplexity.ai/models',
      'groq':        'https://api.groq.com/openai/v1/models',
      'fireworks':   'https://api.fireworks.ai/inference/v1/models',
      'cohere':      'https://api.cohere.com/v2/models',
      'cerebras':    'https://api.cerebras.ai/v1/models',
      'novita':      'https://api.novita.ai/v3/openai/models',
      'hyperbolic':  'https://api.hyperbolic.xyz/v1/models',
      'pandagateway': 'http://127.0.0.1:8000/v1/models',
    };

    if (provider == 'custom') {
      final base = customUrl.replaceFirst(RegExp(r'/chat/completions$'), '');
      final modelsUrl = '$base/models';
      final resp = await http.get(Uri.parse(modelsUrl), headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'});
      return _normalizeModelCatalog(jsonDecode(resp.body) as Map<String, dynamic>);
    }

    final url = urls[provider];
    if (url == null) throw UnsupportedError('Provider inconnu : $provider');

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider == 'claude') {
      headers['x-api-key']         = apiKey;
      headers['anthropic-version']  = '2023-06-01';
    } else if (provider != 'gemini' && provider != 'pandagateway') {
      headers['Authorization'] = 'Bearer $apiKey';
    } else if (provider == 'pandagateway') {
      headers['x-user-token'] = apiKey;
    }

    final resp = await http.get(Uri.parse(url), headers: headers);
    if (resp.statusCode != 200) {
      final detail = resp.body.substring(0, resp.body.length.clamp(0, 200));
      if (provider == 'gemini' && resp.statusCode == 401) {
        throw StateError('Clé Gemini refusée (401). Vérifiez la clé Google AI Studio, son projet et ses restrictions.');
      }
      throw StateError('HTTP ${resp.statusCode}: $detail');
    }
    return _normalizeModelCatalog(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  List<Map<String, dynamic>> _normalizeModelCatalog(Map<String, dynamic> raw, {bool showAll = false}) {
    final data   = raw['data'] ?? raw['models'] ?? raw;
    final models = <Map<String, dynamic>>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final rawId = (m['id'] ?? m['name'] ?? '').toString();
          final id = rawId.startsWith('models/')
              ? rawId.substring('models/'.length)
              : rawId;
          models.add({
            'id': id,
            'displayName': m['displayName'] ?? m['display_name'] ?? id,
            'supported_generation_methods': m['supported_generation_methods'] ??
                m['supportedGenerationMethods'],
            'supported_endpoints': m['supported_endpoints'] ??
                m['supportedEndpoints'],
          });
        }
      }
    }
    var allCapable = models.where((m) => m['id'].toString().isNotEmpty && _looksChatCapable(m)).toList();

    // ── Gemini : ne garder que les VRAIS modèles de chat utilisables ──────
    // L'API renvoie aussi embeddings, imagen, veo, tts, audio… → filtrés ici.
    if (_selectedProviderId == 'gemini') {
      final excluded = RegExp(r'(embedding|aqa|imagen|veo|tts|native-audio|audio|image|vision-exp|live|deprecated)');
      allCapable = allCapable
          .where((m) {
            final id = m['id'].toString().toLowerCase();
            return (id.startsWith('gemini') || id.startsWith('gemma')) && !excluded.hasMatch(id);
          })
          .toList()
        ..sort((a, b) => _geminiModelRank(b['id'].toString())
            .compareTo(_geminiModelRank(a['id'].toString())));
    }

    if (showAll) return allCapable;

    final cleanOnly = allCapable.where((m) => _isCleanCurrentModel(_selectedProviderId, m['id'].toString())).toList();
    return cleanOnly.isNotEmpty ? cleanOnly : allCapable;
  }

  /// Score de tri pour afficher les meilleurs modèles Gemini en premier
  /// (2.5 Pro > 2.5 Flash > 2.5 Flash-Lite > 2.0 > 1.5 …).
  static int _geminiModelRank(String id) {
    final l = id.toLowerCase();
    int score = 0;
    if (l.contains('2.5')) {
      score += 500;
    } else if (l.contains('2.0')) {
      score += 400;
    } else if (l.contains('1.5')) {
      score += 300;
    } else if (l.contains('3.')) {
      score += 550; // gemma-3…
    } else {
      score += 100;
    }
    if (l.contains('pro')) score += 50;
    if (l.contains('flash') && !l.contains('lite')) score += 30;
    if (l.contains('lite')) score += 10;
    return score;
  }

  static bool _isCleanCurrentModel(String provider, String modelId) {
    final p = provider.toLowerCase();
    final id = modelId.toLowerCase();

    if (p == 'gemini') {
      // Show all Gemini models returned by the API
      return true;
    }
    if (p == 'deepseek') {
      return id == 'deepseek-chat' || id == 'deepseek-reasoner';
    }
    if (p == 'openai') {
      return id == 'gpt-4o' || id == 'gpt-4o-mini' || id == 'o1' || id == 'o3-mini';
    }
    if (p == 'claude') {
      return id.contains('claude-3-5') || id.contains('claude-3-opus');
    }
    if (p == 'groq') {
      return id.contains('llama-3.3') || id.contains('llama-3.1') || id.contains('deepseek-r1') || id.contains('mixtral');
    }
    if (p == 'mistral') {
      return id.contains('mistral-large') || id.contains('mistral-small') || id.contains('codestral');
    }
    if (p == 'grok') {
      return id.contains('grok-2') || id.contains('grok-beta');
    }
    return !RegExp(r'(embedding|embed|moderation|whisper|transcri|tts|speech|audio|image|bison|aqa|preview-05)').hasMatch(id);
  }

  Future<void> _saveProviderConfig(BuildContext context, {
    required ProviderDef provider,
    required String apiKey,
    required List<Map<String, dynamic>> models,
  }) async {
    final usable    = models.firstWhere((m) => _looksChatCapable(m), orElse: () => models.first);
    final modelName = usable['id'].toString();
    if (_selectedProviderId == 'custom' && _customUrlCtrl.text.trim().isEmpty) return;

    final aiBloc  = context.read<AIBloc>();
    final newCfg  = Map<String, dynamic>.from(aiBloc.state.config);
    final modelId = 'agent_${_selectedProviderId}';

    final existingMap = newCfg[modelId] is Map ? Map<String, dynamic>.from(newCfg[modelId] as Map) : <String, dynamic>{};
    final List<Map<String, dynamic>> apiKeys = (existingMap['apiKeys'] as List?)
        ?.whereType<Map>()
        .map((k) => Map<String, dynamic>.from(k))
        .toList() ?? [];

    String activeKeyId = existingMap['activeKeyId']?.toString() ?? '';

    if (apiKey.isNotEmpty) {
      final existingIndex = apiKeys.indexWhere((k) => (k['key'] ?? k['apiKey']) == apiKey);
      if (existingIndex >= 0) {
        activeKeyId = apiKeys[existingIndex]['id']?.toString() ?? 'k_$existingIndex';
      } else {
        final newId = 'k_${DateTime.now().millisecondsSinceEpoch}';
        apiKeys.add({
          'id': newId,
          'label': 'Clé ${apiKeys.length + 1}',
          'key': apiKey,
        });
        activeKeyId = newId;
      }
    }

    newCfg[modelId] = {
      'provider':   _selectedProviderId,
      'apiProvider': _selectedProviderId,
      if (_selectedProviderId != 'copilot') 'apiKey': apiKey,
      if (_selectedProviderId != 'copilot') 'key': apiKey,
      if (_selectedProviderId != 'copilot') 'apiKeys': apiKeys,
      if (_selectedProviderId != 'copilot') 'activeKeyId': activeKeyId,
      'modelName':  modelName,
      'model':      modelName,
      'availableModels': models,
      if (_selectedProviderId == 'custom') 'url': _customUrlCtrl.text.trim(),
    };
    aiBloc.add(AIConfigEvent(newCfg));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiConfig', jsonEncode(newCfg));

    final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    selected['chat'] = modelId;
    aiBloc.add(ModelSelectEvent(selected));
    await prefs.setString('modelSelected', jsonEncode(selected));
  }

  bool _looksChatCapable(Map<String, dynamic> model) {
    final id      = model['id'].toString().toLowerCase();
    final methods = model['supported_generation_methods'] ??
        model['supportedGenerationMethods'];
    if (methods is List && methods.isNotEmpty) {
      return methods.any((m) {
        final method = m.toString().toLowerCase();
        return method == 'generatecontent' || method.contains('generatecontent');
      });
    }
    final endpoints = model['supported_endpoints'] ??
        model['supportedEndpoints'];
    if (endpoints is List && endpoints.isNotEmpty) {
      return endpoints.any((e) {
        final v = e.toString().toLowerCase();
        return v.contains('chat/completions') || v.contains('/responses');
      });
    }
    return !RegExp(r'(embedding|embed|moderation|whisper|transcri|tts|speech|audio|image)').hasMatch(id);
  }

  Future<void> _saveAiConfig(BuildContext context, Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiConfig', jsonEncode(config));
  }

  void _removeModel(BuildContext context, String modelId) {
    final aiBloc = context.read<AIBloc>();
    final newCfg = Map<String, dynamic>.from(aiBloc.state.config)..remove(modelId);
    aiBloc.add(AIConfigEvent(newCfg));
    _saveAiConfig(context, newCfg);
    final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    if (selected['chat'] == modelId) {
      selected.remove('chat');
      aiBloc.add(ModelSelectEvent(selected));
    }
    _showSnack(context, 'Provider supprimé.');
  }

  void _showSnack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: isError ? _kDanger : _kSuccess,
      duration: const Duration(seconds: 2),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5);
    final card   = isDark ? const Color(0xff252526) : Colors.white;
    final fg     = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted  = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final border = isDark ? const Color(0xff3a3a3a) : const Color(0xffe0e0e0);
    final hdrBg  = isDark ? const Color(0xff252526) : const Color(0xffececec);

    if (widget.providersOnly) {
      return Container(
        color: bg,
        child: _buildProvidersContent(
          context, isDark, bg, card, fg, muted, border,
        ),
      );
    }

    final body = Column(
      children: [
        // ── Tab bar header ─────────────────────────────────────────────
        Container(
          color: hdrBg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.embedded)
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Broken.arrow_left_2, color: fg),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Broken.cpu_setting, color: _kAccent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text('Panda Agent', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
                  ]),
                ),
              TabBar(
                controller: _tab,
                labelColor: _kAccent,
                unselectedLabelColor: muted,
                indicatorColor: _kAccent,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: 'Chat'),
                  Tab(text: 'Tools'),
                  Tab(text: 'Subagents'),
                ],
              ),
            ],
          ),
        ),

        // ── Tab body ──────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildChatTab(context, isDark, bg, card, fg, muted, border),
              _buildToolsTab(context, isDark, bg, card, fg, muted, border),
              _buildSubagentsTab(context, isDark, bg, card, fg, muted, border),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Container(color: bg, child: body);
    }
    return Scaffold(backgroundColor: bg, body: body);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — Chat
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildChatTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    final chatBg      = isDark ? _kChatBg : const Color(0xfff6f8fa);
    final inputBg     = isDark ? const Color(0xff151520) : Colors.white;
    final inputBorder = isDark ? const Color(0xff2a2a3a) : const Color(0xffd0d7de);

    return Column(
      children: [
        _buildChatHeader(isDark, fg, muted, border),
        // ── Chat area ─────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              Container(
                color: chatBg,
                child: _chatMessages.isEmpty
                    ? _buildChatEmpty(isDark, fg, muted)
                    : _buildChatMessages(isDark, fg, muted),
              ),
              if (_showScrollLatest)
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: InkWell(
                      onTap: () {
                        _chatScrollCtrl.animateTo(
                          _chatScrollCtrl.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                        setState(() => _showScrollLatest = false);
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _kAccent,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Broken.arrow_down_2, size: 13, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Derniers messages',
                                style: TextStyle(fontSize: 11, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Input area ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: inputBg,
            border: Border(top: BorderSide(color: inputBorder)),
          ),
          child: Column(
            children: [
              if (_chatGenerating)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
                  child: Row(
                    children: [
                      _DotsIndicator(color: _kAccent, size: 3.5),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _chatActivityLabel.isEmpty
                              ? 'Génération…'
                              : _chatActivityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      _ChatSmallIconButton(
                        icon: Broken.stop_circle,
                        color: _kDanger,
                        tooltip: 'Arrêter la génération',
                        onTap: _chatStop,
                      ),
                    ],
                  ),
                ),
              if (_chatContextChips.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _chatContextChips.map((chip) => Padding(
                        padding: const EdgeInsets.only(right: 6, bottom: 6),
                        child: InputChip(
                          label: Text(chip, style: TextStyle(fontSize: 10, color: fg)),
                          onDeleted: () => setState(() => _chatContextChips.remove(chip)),
                          deleteIcon: Icon(Broken.close_circle, size: 13, color: muted),
                          backgroundColor: _kChipBg,
                          side: BorderSide(color: inputBorder),
                          visualDensity: VisualDensity.compact,
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              // Text input
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff11111b) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: inputBorder),
                ),
                child: TextField(
                  controller: _chatInputCtrl,
                  maxLines: 8,
                  minLines: 1,
                  style: TextStyle(fontSize: 13, color: fg, height: 1.45),
                  decoration: InputDecoration(
                    hintText: _chatMode == 'agent'
                        ? 'Décris ta tâche…'
                        : _chatMode == 'ask'
                            ? 'Pose une question…'
                            : 'Que veux-tu planifier ?',
                    hintStyle: TextStyle(fontSize: 12, color: muted),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      child: Icon(Broken.slash, size: 15, color: muted),
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Ajouter un contexte',
                            icon: Icon(Broken.attach_square, size: 16, color: muted),
                            onPressed: () => setState(() => _chatContextChips.add('@file: sélection')),
                          ),
                          IconButton(
                            tooltip: _listening ? 'Arrêter la dictée' : 'Dictée vocale',
                            icon: _listening
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.6, color: _kDanger),
                                  )
                                : Icon(Broken.microphone,
                                    size: 16, color: _listening ? _kDanger : muted),
                            onPressed: _toggleListening,
                          ),
                        ],
                      ),
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _chatSend(),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _modeChip('ask', 'Ask', isDark, muted, fg),
                  const SizedBox(width: 4),
                  _modeChip('agent', 'Agent', isDark, muted, fg),
                  const SizedBox(width: 4),
                  _modeChip('plan', 'Plan', isDark, muted, fg),
                  const Spacer(),
                  if (!_chatGenerating)
                    _ChatSmallIconButton(
                      icon: Broken.send_1,
                      color: _chatInputCtrl.text.trim().isNotEmpty ? _kAccent : muted,
                      tooltip: 'Envoyer',
                      onTap: _chatInputCtrl.text.trim().isNotEmpty ? _chatSend : null,
                    ),
                  if (_chatMessages.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _ChatSmallIconButton(
                      icon: Broken.add_square,
                      color: muted,
                      tooltip: 'Nouvelle conversation',
                      onTap: () => setState(() {
                        _chatMessages.clear();
                        _sessionCostUsd = 0.0;
                        _sessionTokensIn = 0;
                        _sessionTokensOut = 0;
                      }),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatHeader(bool isDark, Color fg, Color muted, Color border) {
    return BlocBuilder<AIBloc, AIState>(
      builder: (_, aiState) {
        final selectedId = aiState.modelSelected['chat']?.toString();
        final cfg = selectedId == null ? null : aiState.config[selectedId];
        final modelName = cfg == null
            ? 'Aucun modèle sélectionné'
            : (cfg['modelName'] ?? cfg['model'] ?? 'Modèle actif').toString();
        final tokens = _estimateTokens();
        final maxCtx = _contextWindowFor(modelName);
        final ratio = maxCtx > 0
            ? (tokens / maxCtx).clamp(0.0, 1.0).toDouble()
            : 0.0;
        final tokenColor = ratio < 0.5
            ? _kSuccess
            : ratio < 0.8
                ? const Color(0xfff5a623)
                : _kDanger;

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff151520) : Colors.white,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Broken.cpu_setting, size: 15, color: _kAccent),
              ),
              // ── Titre centré dans l'espace restant ─────────────────────
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Panda Agent',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: muted)),
                  ],
                ),
              ),
              Tooltip(
                message: '${_fmtK(tokens)} / ${_fmtK(maxCtx)} tokens',
                child: Container(
                  width: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: tokenColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokenColor.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_fmtK(tokens)} / ${_fmtK(maxCtx)}',
                          style: TextStyle(fontSize: 9, color: tokenColor, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 3,
                          backgroundColor: tokenColor.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(tokenColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (_sessionCostUsd > 0)
                Text('~${_fmtCost(_sessionCostUsd)}',
                    style: TextStyle(fontSize: 9.5, color: muted)),
              IconButton(
                tooltip: 'Options du chat',
                visualDensity: VisualDensity.compact,
                icon: Icon(Broken.more, size: 17, color: muted),
                onPressed: () => _showChatMenu(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChatMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Broken.add_square),
              title: const Text('Nouvelle conversation'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _chatMessages.clear());
              },
            ),
            ListTile(
              leading: const Icon(Broken.document),
              title: const Text('Exporter en .md (+ presse-papiers)'),
              onTap: () {
                Navigator.pop(context);
                _exportConversationMd();
              },
            ),
            ListTile(
              leading: const Icon(Broken.copy),
              title: const Text('Copier la conversation'),
              onTap: () {
                Navigator.pop(context);
                final content = _chatMessages
                    .map((m) => '${m['role']}: ${m['text'] ?? ''}')
                    .join('\n\n');
                Clipboard.setData(ClipboardData(text: content));
                _showSnack(context, 'Conversation copiée.');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Exporte la conversation en Markdown : copie dans le presse-papiers ET
  /// sauvegarde un fichier .md (Download si possible, sinon documents).
  Future<void> _exportConversationMd() async {
    if (_chatMessages.isEmpty) {
      _showSnack(context, 'Rien à exporter.', isError: true);
      return;
    }
    String modelName = '';
    try {
      final aiState = context.read<AIBloc>().state;
      final selId   = aiState.modelSelected['chat']?.toString();
      final cfg     = selId == null ? null : aiState.config[selId];
      modelName = cfg == null ? '' : (cfg['modelName'] ?? cfg['model'] ?? '').toString();
    } catch (_) {}

    final md = AgentExportService.exportToMarkdown(_chatMessages, modelName: modelName);
    await Clipboard.setData(ClipboardData(text: md));

    String? savedPath;
    try {
      String two(int v) => v.toString().padLeft(2, '0');
      final now = DateTime.now();
      final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      const downloadDir = '/storage/emulated/0/Download';
      final Directory dir = Directory(downloadDir).existsSync()
          ? Directory(downloadDir)
          : await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/panda-agent-$stamp.md');
      await file.writeAsString(md);
      savedPath = file.path;
    } catch (_) {}

    _showSnack(context, savedPath != null
        ? 'Copié + exporté : $savedPath'
        : 'Conversation copiée dans le presse-papiers.');
  }

  /// Construit les blocs du message agent dans l'ordre chronologique réel :
  /// réflexion → texte d'annonce → outils → réflexion → … → réponse finale.
  /// Repli sur l'ancien rendu pour les messages sans timeline.
  List<Widget> _buildAgentTimeline(
    Map<String, dynamic> msg, {
    required bool isDark,
    required Color fg,
    required Color muted,
    required bool isStreaming,
    required bool isError,
    required String text,
    required String think,
  }) {
    final tl = (msg['timeline'] as List?)
            ?.whereType<Map>()
            .map((b) => b.cast<String, dynamic>())
            .toList() ??
        <Map<String, dynamic>>[];

    final widgets = <Widget>[];

    Widget responseText(String content, {bool live = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: live
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isError ? _kDanger : fg,
                        height: 1.55,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  _ChatBlinkingCursor(color: fg),
                ],
              )
            : _ChatMarkdownResponse(
                markdown: content,
                isDark: isDark,
                fg: isError ? _kDanger : fg,
              ),
      );
    }

    // ── Fallback legacy (anciens messages sauvegardés) ───────────────────
    if (tl.isEmpty) {
      if (think.isNotEmpty) {
        widgets.add(_ChatThinkingBlock(
          thinking: think,
          isDark: isDark,
          fg: fg,
          muted: muted,
          isStreaming: isStreaming && text.isEmpty,
        ));
      }
      final calls = (msg['toolCalls'] as List?)
              ?.whereType<Map>()
              .map((call) => call.cast<String, dynamic>())
              .toList() ??
          <Map<String, dynamic>>[];
      if (calls.isNotEmpty) {
        widgets.add(_ChatActionGroup(calls: calls, isDark: isDark, fg: fg, muted: muted));
      }
      if (text.isNotEmpty || (isStreaming && think.isEmpty)) {
        widgets.add(responseText(text, live: isStreaming));
      }
      return widgets;
    }

    // ── Rendu chronologique ──────────────────────────────────────────────
    var i = 0;
    while (i < tl.length) {
      final b = tl[i];

      // Regroupe les outils ADJACENTS en un seul bloc dépliable.
      if (b['type'] == 'tool') {
        final group = <Map<String, dynamic>>[];
        while (i < tl.length && tl[i]['type'] == 'tool') {
          group.add(tl[i]);
          i++;
        }
        widgets.add(_ChatActionGroup(calls: group, isDark: isDark, fg: fg, muted: muted));
        continue;
      }

      final bText = b['text'] as String? ?? '';
      final isLast = i == tl.length - 1;
      if (b['type'] == 'thinking' && bText.trim().isNotEmpty) {
        widgets.add(_ChatThinkingBlock(
          thinking: bText,
          isDark: isDark,
          fg: fg,
          muted: muted,
          isStreaming: isStreaming && isLast,
        ));
      } else if (b['type'] == 'text' && bText.isNotEmpty) {
        widgets.add(responseText(bText, live: isStreaming && isLast));
      }
      i++;
    }
    return widgets;
  }

  Widget _modeChip(String mode, String label, bool isDark, Color muted, Color fg) {
    final active = _chatMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _chatMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? _kAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _kAccent.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: active ? _kAccent : muted, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
        ),
      ),
    );
  }

  Widget _buildChatEmpty(bool isDark, Color fg, Color muted) {
    const suggestions = ['Explique ce code', 'Crée un fichier Flutter', 'Optimise cette fonction', 'Écris des tests'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Broken.message_programming, color: _kAccent, size: 28),
              ),
              const SizedBox(height: 12),
              Text('Panda Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 6),
              Text('Comment puis-je vous aider ?', style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('SUGGESTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: suggestions.map((s) => GestureDetector(
            onTap: () { _chatInputCtrl.text = s; _chatSend(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe8e8e8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd)),
              ),
              child: Text(s, style: TextStyle(fontSize: 12, color: fg)),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildChatMessages(bool isDark, Color fg, Color muted) {
    return ListView.builder(
      controller: _chatScrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _chatMessages.length,
      itemBuilder: (_, i) {
        final msg        = _chatMessages[i];
        final isMe       = msg['role'] == 'user';
        final phase      = msg['phase'] as String? ?? 'done';
        final text       = msg['text'] as String? ?? '';
        final think      = msg['thinking'] as String? ?? '';
        final isStreaming = phase == 'streaming';
        final isError    = phase == 'error';

        if (isMe) {
          return Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 2, left: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kAccent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(fontSize: 13.5, color: Colors.white, height: 1.45),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 2, bottom: 6),
                  child: _ChatActionBtn(
                    icon: Broken.copy,
                    label: 'Copier',
                    muted: muted,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Copié !', style: TextStyle(fontSize: 12)),
                        duration: Duration(seconds: 1),
                      ));
                    },
                  ),
                ),
              ],
            ),
          );
        }

        // ── Agent message — no bubble, plain text, full width ──────────────
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Streaming dots — only when nothing visible yet
              if (isStreaming && think.isEmpty && text.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _DotsIndicator(color: muted),
                    const SizedBox(width: 6),
                    Text('Génération…',
                        style: TextStyle(fontSize: 11, color: muted, fontStyle: FontStyle.italic)),
                  ]),
                ),

              // ── Timeline chronologique : réflexion → texte → outils → … ──
              // Les étapes s'affichent dans le VRAI ordre d'arrivée au lieu
              // d'empiler toute la réflexion en haut et les outils au milieu.
              ..._buildAgentTimeline(msg,
                  isDark: isDark, fg: fg, muted: muted,
                  isStreaming: isStreaming, isError: isError,
                  text: text, think: think),

              // Action row (copy + retry)
              if (!isStreaming && (text.isNotEmpty || isError))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (text.isNotEmpty)
                      _ChatActionBtn(
                        icon: Broken.copy,
                        label: 'Copier',
                        muted: muted,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content:
                                Text('Copié !', style: TextStyle(fontSize: 12)),
                            duration: Duration(seconds: 1),
                          ));
                        },
                      ),
                    if (i > 0 && _chatMessages[i - 1]['role'] == 'user')
                      _ChatActionBtn(
                        icon: Broken.refresh,
                        label: 'Réessayer',
                        muted: muted,
                        onTap: () {
                          if (_chatGenerating) return;
                          final userText =
                              _chatMessages[i - 1]['text'] as String? ?? '';
                          if (userText.isEmpty) return;
                          setState(() {
                            if (i < _chatMessages.length)
                              _chatMessages.removeAt(i);
                            if ((i - 1) < _chatMessages.length)
                              _chatMessages.removeAt(i - 1);
                            _chatInputCtrl.text = userText;
                          });
                          _chatSend();
                        },
                      ),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — Tools (Replit-style list + Settings sub-view)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildToolsTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _showToolsSettings
          ? _buildToolsSettings(context, isDark, bg, card, fg, muted, border)
          : _buildToolsList(context, isDark, bg, card, fg, muted, border),
    );
  }

  /// Replit-style tool list.
  Widget _buildToolsList(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {

    // Tools displayed in the list
    final toolItems = [
      _ToolItem(icon: Broken.setting_2, color: const Color(0xff888888), name: 'Settings', desc: 'Providers IA, mémoire, apparence', onTap: () => setState(() => _showToolsSettings = true)),
    ];

    // Tool specs from catalog
    final specItems = agenticToolSpecs.map((spec) => _ToolSpecItem(spec: spec)).toList();

    return BlocBuilder<AIChatUIBloc, AIChatUIState>(
      builder: (ctx, uiState) {
        final selections = uiState.agenticToolSelections;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // Settings row at top
            for (final item in toolItems)
              _buildToolRow(
                icon: item.icon,
                color: item.color,
                name: item.name,
                desc: item.desc,
                isDark: isDark,
                fg: fg,
                muted: muted,
                border: border,
                trailing: Icon(Broken.arrow_right_2, size: 14, color: muted),
                onTap: item.onTap,
              ),

            // Divider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Text('OUTILS DE L\'AGENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: muted)),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: border, height: 1)),
              ]),
            ),

            // Tool toggles
            ...specItems.map((item) {
              final enabled = selections[item.spec.name] ?? true;
              return _buildToolRow(
                icon: item.spec.requiresWriteAccess ? Broken.edit_2 : Broken.flash_circle,
                color: item.spec.requiresWriteAccess ? const Color(0xffe05252).withValues(alpha: 0.8) : _kAccent,
                name: item.spec.label,
                desc: item.spec.description,
                isDark: isDark,
                fg: fg,
                muted: muted,
                border: border,
                trailing: Switch(
                  value: enabled,
                  activeColor: _kAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    final updated = Map<String, bool>.from(selections)..[item.spec.name] = v;
                    ctx.read<AIChatUIBloc>().add(AIChatUIEvent(
                      chatMode: uiState.chatMode,
                      promptText: uiState.promptText,
                      scrollOffset: uiState.scrollOffset,
                      isGenerating: uiState.isGenerating,
                      agenticToolSelections: updated,
                      selectedModelId: uiState.selectedModelId,
                    ));
                  },
                ),
                onTap: null,
              );
            }),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildToolRow({
    required IconData icon,
    required Color color,
    required String name,
    required String desc,
    required bool isDark,
    required Color fg,
    required Color muted,
    required Color border,
    required Widget trailing,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border, width: 0.5)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          trailing,
        ]),
      ),
    );
  }

  /// Settings sub-view (Providers + Mémoire + Apparence).
  Widget _buildToolsSettings(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    final hdrBg = isDark ? const Color(0xff252526) : const Color(0xffececec);

    return Column(
      children: [
        // Back header
        Container(
          color: hdrBg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Back button row
              Row(children: [
                IconButton(
                  icon: Icon(Broken.arrow_left_2, color: fg, size: 18),
                  onPressed: () => setState(() => _showToolsSettings = false),
                  tooltip: 'Retour',
                ),
                Text('Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
              ]),
              // Sub-tab bar
              TabBar(
                controller: _settingsSubTab,
                labelColor: _kAccent,
                unselectedLabelColor: muted,
                indicatorColor: _kAccent,
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Providers'),
                  Tab(text: 'Mémoire'),
                  Tab(text: 'Apparence'),
                  Tab(text: 'Agent Settings'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _settingsSubTab,
            children: [
              _buildProvidersContent(context, isDark, bg, card, fg, muted, border),
              _buildMemoryContent(context, isDark, bg, card, fg, muted, border),
              _buildAppearanceContent(context, isDark, bg, card, fg, muted, border),
              _buildAgentSettingsContent(context, isDark, bg, card, fg, muted, border),
            ],
          ),
        ),
      ],
    );
  }

  // ── Providers content ────────────────────────────────────────────────────
  Widget _buildProvidersContent(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return BlocBuilder<AIBloc, AIState>(
      builder: (ctx, aiState) {
        final configured =
            aiState.config.entries.where((e) => e.key.startsWith('agent_')).toList();
        String currentDefaultModel = '';
        try {
          final cc = aiState.config['agent_$_selectedProviderId'];
          if (cc is Map) {
            currentDefaultModel = (cc['modelName'] ?? cc['model'] ?? '').toString();
          }
        } catch (_) {}

        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // ── Providers connectés ────────────────────────────────────────
            if (configured.isNotEmpty) ...[
              _sectionLabel('PROVIDERS CONNECTÉS', muted),
              const SizedBox(height: 8),
              ...configured.map((entry) {
                final id = entry.key;
                final cfg = entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : <String, dynamic>{};
                final name = cfg['modelName']?.toString() ?? id;
                final provider = cfg['provider']?.toString() ?? '';
                final pDef = providerDefs.firstWhere(
                    (p) => p.id == provider,
                    orElse: () => providerDefs.last);
                return _ProviderRowCompact(
                  name: pDef.name,
                  model: name,
                  providerId: provider,
                  isActive: aiState.modelSelected['chat']?.toString() == id,
                  isDark: isDark,
                  card: card,
                  fg: fg,
                  muted: muted,
                  border: border,
                  onRemove: () => _removeModel(ctx, id),
                );
              }),
              const SizedBox(height: 18),
            ],

            _sectionLabel('CONNECTER UN PROVIDER', muted),
            const SizedBox(height: 8),

            // ── Sélecteur compact avec vrais logos ─────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in providerDefs)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedProviderId = p.id;
                      _testKeyResult = null;
                      _testKeyMessage = '';
                      _availableModels = const [];
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _selectedProviderId == p.id
                            ? _kAccent.withValues(alpha: 0.14)
                            : card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _selectedProviderId == p.id
                                ? _kAccent.withValues(alpha: 0.6)
                                : border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ProviderLogoBadge(providerId: p.id, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          p.name
                              .replaceAll(' (Claude)', '')
                              .replaceAll('Google ', ''),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _selectedProviderId == p.id
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: _selectedProviderId == p.id ? _kAccent : fg,
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            Builder(builder: (_) {
              final pDef = providerDefs.firstWhere(
                  (p) => p.id == _selectedProviderId,
                  orElse: () => providerDefs.first);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Provider sélectionné + bouton vers la page de la clé ──
                  Row(children: [
                    ProviderLogoBadge(providerId: pDef.id, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(pDef.description,
                          style: TextStyle(fontSize: 11, color: muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (pDef.docsUrl.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => launchUrl(Uri.parse(pDef.docsUrl),
                            mode: LaunchMode.externalApplication),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _kAccent.withValues(alpha: 0.35)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Broken.link,
                                size: 12, color: _kAccent),
                            const SizedBox(width: 4),
                            Text('Obtenir la clé',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _kAccent)),
                          ]),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),

                  if (_selectedProviderId == 'custom') ...[
                    _SettingsField(
                      controller: _customUrlCtrl,
                      label: 'URL endpoint',
                      hint: 'http://localhost:11434/v1/chat/completions',
                      isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (pDef.hasApiKey) ...[
                    // ── Nom du profil de clé (cerveau de rotation) ──────────
                    _SettingsField(
                      controller: _keyProfileNameCtrl,
                      label: 'Nom du profil de clé',
                      hint: 'Ex : Perso, Pro, Gratuit…',
                      isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: _SettingsField(
                          controller: _apiKeyCtrl,
                          label: 'Clé API',
                          hint: pDef.apiKeyHint,
                          obscure: _obscureKey,
                          isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                          suffix: IconButton(
                            icon: Icon(_obscureKey ? Broken.eye_slash : Broken.eye,
                                size: 16, color: muted),
                            onPressed: () => setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                  ],
                  if (_selectedProviderId == 'copilot') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kAccent.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        'Nécessite GitHub Copilot. Connectez votre compte GitHub dans la sidebar Git.',
                        style: TextStyle(fontSize: 12, color: fg),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _testingKey ? null : _testApiKey,
                      child: _testingKey
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Valider et activer',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (_testKeyMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_testKeyResult == true ? _kSuccess : _kDanger)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: (_testKeyResult == true ? _kSuccess : _kDanger)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(_testKeyMessage,
                          style: TextStyle(
                              fontSize: 12,
                              color: _testKeyResult == true
                                  ? _kSuccess
                                  : _kDanger)),
                    ),
                  ],

                  // ── Grille de modèles (1-2 colonnes, vrais logos) ────────
                  if (_availableModels.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                        'Modèles disponibles (${_availableModels.length}) — touchez pour définir le défaut',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            MediaQuery.of(context).size.width > 600 ? 3 : 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: _availableModels.length,
                      itemBuilder: (_, gi) {
                        final m = _availableModels[gi];
                        final mid = m['id'].toString();
                        final displayName =
                            (m['displayName'] ?? mid).toString();
                        return _ModelGridTile(
                          modelId: mid,
                          displayName: displayName,
                          providerId: _selectedProviderId,
                          isDefault: mid == currentDefaultModel,
                          isDark: isDark,
                          card: card,
                          fg: fg,
                          muted: muted,
                          border: border,
                          onTap: () =>
                              _setDefaultModel(ctx, _selectedProviderId, mid),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              );
            }),

            // ── Cerveau de rotation des clés ────────────────────────────────
            _RotationMonitor(
              isDark: isDark, card: card, fg: fg, muted: muted, border: border,
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  /// Définit le modèle par défaut d'un provider et persiste le choix.
  Future<void> _setDefaultModel(
      BuildContext ctx, String providerId, String modelId) async {
    final aiBloc = ctx.read<AIBloc>();
    final newCfg = Map<String, dynamic>.from(aiBloc.state.config);
    final key = 'agent_$providerId';
    final cfg = Map<String, dynamic>.from((newCfg[key] as Map?) ?? {});
    cfg['modelName'] = modelId;
    cfg['model'] = modelId;
    newCfg[key] = cfg;
    aiBloc.add(AIConfigEvent(newCfg));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiConfig', jsonEncode(newCfg));
    _showSnack(ctx, 'Modèle par défaut : $modelId');
  }

  // ── Memory content ───────────────────────────────────────────────────────
  Widget _buildMemoryContent(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel('MÉMOIRE AGENT', muted),
        const SizedBox(height: 10),
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Broken.cpu_setting, size: 18, color: _kAccent),
                const SizedBox(width: 8),
                Text('Mémoire persistante', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                const Spacer(),
                Switch(
                  value: _memoryEnabled,
                  activeColor: _kAccent,
                  onChanged: (v) { setState(() => _memoryEnabled = v); _saveMemorySettings(); },
                ),
              ]),
              const SizedBox(height: 4),
              Text('L\'agent mémorise les faits importants entre les conversations.', style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('NOTES PERMANENTES', muted),
        const SizedBox(height: 8),
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Informations permanentes injectées dans chaque conversation.', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 10),
              TextField(
                controller: _memoryNotesCtrl,
                maxLines: 6,
                style: TextStyle(fontSize: 13, color: fg, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Ex : "Utilise toujours Dart null-safety…"',
                  hintStyle: TextStyle(fontSize: 12, color: muted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                  contentPadding: const EdgeInsets.all(12),
                  isDense: true,
                ),
                onChanged: (_) => _saveMemorySettings(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('PROMPT SYSTÈME PERSONNALISÉ', muted),
        const SizedBox(height: 8),
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remplace le prompt système par défaut de Panda Agent.', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 10),
              TextField(
                controller: _systemPromptCtrl,
                maxLines: 5,
                style: TextStyle(fontSize: 12, color: fg, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Laissez vide pour utiliser le prompt par défaut…',
                  hintStyle: TextStyle(fontSize: 12, color: muted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                  contentPadding: const EdgeInsets.all(12),
                  isDense: true,
                ),
                onChanged: (_) => _saveMemorySettings(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Appearance content ────────────────────────────────────────────────────
  Widget _buildAppearanceContent(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Messages utilisateur', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 12),
              Text('Couleur des bulles', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in [
                    const Color(0xff4f8ef7), const Color(0xff5856d6),
                    const Color(0xff34c759), const Color(0xffff2d55),
                    const Color(0xffff9500), const Color(0xff636366),
                  ])
                    _ColorSwatch(color: c, selected: false, onTap: () {}),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Messages agent', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 12),
              Text('Affichage du markdown', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Rendu Markdown', style: TextStyle(fontSize: 12, color: fg)),
                value: true,
                activeColor: _kAccent,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mise en page', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 12),
              Text('Taille de police', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Slider(min: 10, max: 18, value: 13, divisions: 8, activeColor: _kAccent, label: '13', onChanged: (_) {}),
              const SizedBox(height: 8),
              Text('Rayon des bulles', style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Slider(min: 0, max: 20, value: 8, divisions: 4, activeColor: _kAccent, label: '8', onChanged: (_) {}),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, Color muted) => Text(
    label,
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: muted),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — Subagents (max 4) + Salle de conférence + Rooms multi-agents
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> _currentWorkspacePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawRecent = prefs.getString('recent');
      if (rawRecent == null || rawRecent.isEmpty) return '';
      final recent = jsonDecode(rawRecent);
      if (recent is List && recent.isNotEmpty && recent.first is Map) {
        final first = recent.first;
        return first['rootDir']?.toString() ?? first['path']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  String _defaultAgentCfgKey() {
    try {
      final st = context.read<AIBloc>().state;
      final sel = st.modelSelected['chat']?.toString();
      if (sel != null && sel.startsWith('agent_')) return sel;
      for (final k in st.config.keys) {
        if (k.startsWith('agent_')) return k;
      }
    } catch (_) {}
    return '';
  }

  Widget _buildSubagentsTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    final orch = SubagentOrchestrator.instance;
    return BlocBuilder<AIBloc, AIState>(
      builder: (ctx, aiState) {
        orch.aiConfig = Map<String, dynamic>.from(aiState.config);
        final cfgOptions = aiState.config.entries
            .where((e) => e.key.startsWith('agent_'))
            .map((e) {
          final c = e.value is Map
              ? Map<String, dynamic>.from(e.value as Map)
              : <String, dynamic>{};
          return (
            key: e.key,
            label: (c['modelName'] ?? e.key).toString(),
          );
        }).toList();

        return AnimatedBuilder(
          animation: orch,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── Configuration des sous-agents (max 4) ────────────────────
              Row(children: [
                Text('SOUS-AGENTS (${orch.subAgents.length}/${SubagentOrchestrator.maxSubAgents})',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: muted)),
                const Spacer(),
                InkWell(
                  onTap: orch.subAgents.length >=
                          SubagentOrchestrator.maxSubAgents
                      ? null
                      : () => orch.addSubAgent(
                          name: 'Sub-agent',
                          modelCfgKey: _defaultAgentCfgKey()),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: orch.subAgents.length >=
                              SubagentOrchestrator.maxSubAgents
                          ? border.withValues(alpha: 0.3)
                          : _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: orch.subAgents.length >=
                                  SubagentOrchestrator.maxSubAgents
                              ? border
                              : _kAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Broken.add_square,
                          size: 11,
                          color: orch.subAgents.length >=
                                  SubagentOrchestrator.maxSubAgents
                              ? muted
                              : _kAccent),
                      const SizedBox(width: 4),
                      Text('Ajouter',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: orch.subAgents.length >=
                                      SubagentOrchestrator.maxSubAgents
                                  ? muted
                                  : _kAccent)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (orch.subAgents.isEmpty)
                Text(
                  'Aucun sous-agent. Ajoutez jusqu\'à ${SubagentOrchestrator.maxSubAgents} : '
                  'chacun a son modèle, son profil de clé (rotation auto) et reçoit '
                  'des tâches de l\'agent principal dans la salle de conférence.',
                  style: TextStyle(fontSize: 11, color: muted,
                      fontStyle: FontStyle.italic),
                )
              else
                for (final s in orch.subAgents)
                  _SubAgentCard(
                    config: s,
                    cfgOptions: cfgOptions,
                    isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                  ),
              const SizedBox(height: 16),

              // ── Tâches données par l'agent principal ─────────────────────
              Text('TÂCHES DES SOUS-AGENTS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: muted)),
              const SizedBox(height: 8),
              if (orch.tasks.isEmpty)
                Text('Aucune tâche. Créez-en une et lancez-la.',
                    style: TextStyle(fontSize: 11, color: muted,
                        fontStyle: FontStyle.italic))
              else
                for (final t in orch.tasks) _taskRow(t, isDark, card, fg, muted, border),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccent,
                  side: BorderSide(color: _kAccent.withValues(alpha: 0.4)),
                ),
                onPressed: orch.subAgents.isEmpty ? null : () => _newTaskDialog(context),
                icon: const Icon(Broken.add_square, size: 13),
                label: const Text('Nouvelle tâche',
                    style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 16),

              // ── Salle de conférence ──────────────────────────────────────
              Text('SALLE DE CONFÉRENCE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: muted)),
              const SizedBox(height: 8),
              ConferenceRoomView(),
              const SizedBox(height: 16),

              // ── Rooms multi-agents ───────────────────────────────────────
              Text('ROOMS MULTI-AGENTS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: muted)),
              const SizedBox(height: 8),
              MultiAgentRoomsView(
                isDark: isDark, card: card, fg: fg, muted: muted, border: border,
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _taskRow(OrchestratorTask t, bool isDark, Color card, Color fg,
      Color muted, Color border) {
    SubAgentConfig? sub;
    for (final s in SubagentOrchestrator.instance.subAgents) {
      if (s.id == t.subAgentId) {
        sub = s;
        break;
      }
    }
    Color statusColor;
    String statusLabel;
    switch (t.status) {
      case 'running':
        statusColor = const Color(0xfff5a623);
        statusLabel = 'en cours';
        break;
      case 'done':
        statusColor = _kSuccess;
        statusLabel = 'terminé';
        break;
      case 'failed':
        statusColor = _kDanger;
        statusLabel = 'échec';
        break;
      default:
        statusColor = muted;
        statusLabel = 'prête';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(t.title,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
          ),
        ]),
        if (t.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(t.description,
                style: TextStyle(fontSize: 10.5, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('→ ${sub.name}',
                style: TextStyle(fontSize: 10, color: _kAccent)),
          ),
        if (t.log.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Text(
                  t.log.toString(),
                  style: TextStyle(
                      fontSize: 9.5,
                      height: 1.4,
                      fontFamily: 'monospace',
                      color: muted),
                ),
              ),
            ),
          ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (t.status != 'running')
            TextButton.icon(
              onPressed: () => _runTask(t),
              icon: const Icon(Broken.play, size: 12),
              label: const Text('Lancer', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                  foregroundColor: _kAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
          TextButton.icon(
            onPressed: () {
              SubagentOrchestrator.instance.tasks.remove(t);
              SubagentOrchestrator.instance.notifyListeners();
            },
            icon: const Icon(Broken.trash, size: 12),
            label: const Text('Retirer', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
                foregroundColor: muted,
                padding: const EdgeInsets.symmetric(horizontal: 6)),
          ),
        ]),
      ]),
    );
  }

  Future<void> _runTask(OrchestratorTask t) async {
    final ws = await _currentWorkspacePath();
    unawaited(SubagentOrchestrator.instance.runTask(t, workspacePath: ws));
  }

  void _newTaskDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    final orch = SubagentOrchestrator.instance;
    var selectedSub = orch.subAgents.first.id;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Nouvelle tâche',
              style: TextStyle(fontSize: 15, color: Colors.white)),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Titre',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[700]!)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kAccent)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Consignes détaillées pour le sous-agent…',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[700]!)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kAccent)),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedSub,
                dropdownColor: Colors.grey[900],
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Assigné à',
                  labelStyle:
                      TextStyle(fontSize: 11, color: Colors.grey[500]),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[700]!)),
                ),
                items: [
                  for (final s in orch.subAgents)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setDialog(() => selectedSub = v ?? selectedSub),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('Annuler', style: TextStyle(color: Colors.grey))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                final task = orch.createTask(
                    titleCtrl.text, descCtrl.text, selectedSub);
                Navigator.pop(ctx);
                _runTask(task);
              },
              child: const Text('Créer et lancer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
