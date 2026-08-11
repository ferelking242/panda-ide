/// AgentSettings — Agent panel avec Chat, Tools et Subagents.
///
/// Structure inspirée de Replit :
///   • Chat        — interface de chat standalone avec AgentRunner
///   • Tools       — liste outils style Replit + Settings (providers, mémoire, apparence)
///   • Subagents   — tableau de tâches Ready / Active / Draft
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

import '../bloc/ui_bloc/ui_bloc.dart';
import '../bloc/repo_bloc/repo_bloc.dart';
import '../core/broken_icons.dart';
import '../utils/ai.dart';
import '../utils/constants.dart';
import '../utils/agentic_tool_catalog.dart';
import '../utils/copilot_chat.dart';
import '../utils/panda_log.dart';
import 'agent_runner.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:markdown_widget/config/configs.dart';

// ─────────────────────────────────────────────────────────────────────────────
const _kAccent  = Color(0xff5090c8);
const _kDanger  = Color(0xffe05252);
const _kSuccess = Color(0xff4caf7d);
const _kChatBg  = Color(0xff0f0f1a);
const _kGroupBg = Color(0xff1a1a2a);
const _kChipBg  = Color(0xff252535);

// ── Provider definitions ────────────────────────────────────────────────────
class _ProviderDef {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String docsUrl;
  final bool hasApiKey;
  final String apiKeyHint;

  const _ProviderDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.docsUrl,
    this.hasApiKey = true,
    this.apiKeyHint = 'sk-...',
  });
}

const _providers = <_ProviderDef>[
  _ProviderDef(
    id: 'openai',
    name: 'OpenAI',
    description: 'GPT-4o, o1, o3 — le plus utilisé',
    icon: Broken.global,
    color: Color(0xff10a37f),
    docsUrl: 'https://platform.openai.com/api-keys',
    apiKeyHint: 'sk-...',
  ),
  _ProviderDef(
    id: 'claude',
    name: 'Anthropic (Claude)',
    description: 'Claude 3.5 Sonnet, Haiku, Opus',
    icon: Broken.cpu,
    color: Color(0xffb87333),
    docsUrl: 'https://console.anthropic.com/settings/keys',
    apiKeyHint: 'sk-ant-...',
  ),
  _ProviderDef(
    id: 'gemini',
    name: 'Google Gemini',
    description: 'Gemini 2.0 Flash, 1.5 Pro',
    icon: Broken.global_search,
    color: Color(0xff4285f4),
    docsUrl: 'https://aistudio.google.com/app/apikey',
    apiKeyHint: 'AIza...',
  ),
  _ProviderDef(
    id: 'deepseek',
    name: 'DeepSeek',
    description: 'DeepSeek-V3, R1 — très bon rapport qualité/coût',
    icon: Broken.search_normal,
    color: Color(0xff4b6ef5),
    docsUrl: 'https://platform.deepseek.com/api_keys',
    apiKeyHint: 'sk-...',
  ),
  _ProviderDef(
    id: 'grok',
    name: 'Grok (xAI)',
    description: 'Grok-2, Grok Beta',
    icon: Broken.code_circle,
    color: Color(0xff1da1f2),
    docsUrl: 'https://console.x.ai/',
    apiKeyHint: 'xai-...',
  ),
  _ProviderDef(
    id: 'openrouter',
    name: 'OpenRouter',
    description: 'Accès unifié à 200+ modèles',
    icon: Broken.routing_2,
    color: Color(0xff8b5cf6),
    docsUrl: 'https://openrouter.ai/keys',
    apiKeyHint: 'sk-or-...',
  ),
  _ProviderDef(
    id: 'mistral',
    name: 'Mistral AI',
    description: 'Mistral Large, Codestral',
    icon: Broken.wind,
    color: Color(0xffff7000),
    docsUrl: 'https://console.mistral.ai/api-keys',
    apiKeyHint: '...',
  ),
  _ProviderDef(
    id: 'togetherai',
    name: 'Together AI',
    description: 'Llama, Mixtral et autres open-source',
    icon: Broken.people,
    color: Color(0xff00c9b1),
    docsUrl: 'https://api.together.xyz/settings/api-keys',
    apiKeyHint: '...',
  ),
  _ProviderDef(
    id: 'perplexity',
    name: 'Perplexity',
    description: 'Sonar — recherche web intégrée',
    icon: Broken.search_zoom_in,
    color: Color(0xff20b2aa),
    docsUrl: 'https://www.perplexity.ai/settings/api',
    apiKeyHint: 'pplx-...',
  ),
  _ProviderDef(
    id: 'pandagateway',
    name: 'Panda Gateway',
    description: 'Accès unifié sans clé API (abonnement Panda)',
    icon: Broken.cpu_setting,
    color: Color(0xff5090c8),
    docsUrl: '',
    hasApiKey: false,
    apiKeyHint: 'optionnel',
  ),
  _ProviderDef(
    id: 'copilot',
    name: 'GitHub Copilot',
    description: 'GPT-4o via votre abonnement GitHub Copilot',
    icon: Broken.message_programming,
    color: Color(0xff8b5cf6),
    docsUrl: 'https://github.com/settings/copilot',
    hasApiKey: false,
    apiKeyHint: 'optionnel',
  ),
  _ProviderDef(
    id: 'groq',
    name: 'Groq',
    description: 'Llama 3, Mixtral — ultra-rapide (inference cloud)',
    icon: Broken.flash_circle,
    color: Color(0xfff97316),
    docsUrl: 'https://console.groq.com/keys',
    apiKeyHint: 'gsk_...',
  ),
  _ProviderDef(
    id: 'fireworks',
    name: 'Fireworks AI',
    description: 'Llama, Mistral, DeepSeek — inference rapide',
    icon: Broken.flash_1,
    color: Color(0xffef4444),
    docsUrl: 'https://fireworks.ai/account/api-keys',
    apiKeyHint: 'fw_...',
  ),
  _ProviderDef(
    id: 'cohere',
    name: 'Cohere',
    description: 'Command R+, Command A — spécialisé RAG',
    icon: Broken.diagram,
    color: Color(0xff39d353),
    docsUrl: 'https://dashboard.cohere.com/api-keys',
    apiKeyHint: '...',
  ),
  _ProviderDef(
    id: 'cerebras',
    name: 'Cerebras',
    description: 'Llama sur wafer silicon — le plus rapide du marché',
    icon: Broken.cpu,
    color: Color(0xffa855f7),
    docsUrl: 'https://cloud.cerebras.ai/',
    apiKeyHint: 'csk-...',
  ),
  _ProviderDef(
    id: 'novita',
    name: 'Novita AI',
    description: 'Llama, Mistral, DeepSeek — 200+ modèles',
    icon: Broken.global,
    color: Color(0xff06b6d4),
    docsUrl: 'https://novita.ai/settings#key-management',
    apiKeyHint: '...',
  ),
  _ProviderDef(
    id: 'hyperbolic',
    name: 'Hyperbolic',
    description: 'Llama, DeepSeek — inference GPU économique',
    icon: Broken.flash_circle,
    color: Color(0xffe11d48),
    docsUrl: 'https://app.hyperbolic.xyz/settings',
    apiKeyHint: 'eyJ...',
  ),
  _ProviderDef(
    id: 'custom',
    name: 'Custom / Local',
    description: 'Endpoint OpenAI-compatible (Ollama, LM Studio…)',
    icon: Broken.code_1,
    color: Color(0xff888888),
    docsUrl: '',
    apiKeyHint: 'optionnel',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
class AgentSettings extends StatefulWidget {
  final bool embedded;
  /// When true, reuse the provider settings implementation as a standalone
  /// page. This keeps the provider flow in one place without rendering the
  /// legacy Chat/Tools/Subagents shell inside Panda Agent.
  final bool providersOnly;

  const AgentSettings({
    super.key,
    this.embedded = false,
    this.providersOnly = false,
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
  final _chatInputCtrl  = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool       _chatGenerating   = false;
  AgentPhase _chatPhase        = AgentPhase.idle;
  String     _chatStreamBuf    = '';
  String     _chatThinkingBuf  = '';
  int        _chatSerial       = 0;
  bool       _showScrollLatest = false;
  final List<String> _chatContextChips = [];
  final      _chatRunner       = AgentRunner();
  String     _chatMode         = 'agent'; // 'ask' | 'agent' | 'plan'

  // ── Tools tab state ─────────────────────────────────────────────────────
  bool _showToolsSettings = false; // false = tool list, true = settings sub-view

  // Provider/model state (used in Tools > Settings)
  String _selectedProviderId = 'openai';
  final _apiKeyCtrl         = TextEditingController();
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

  // ── Subagents tab state ─────────────────────────────────────────────────
  final List<Map<String, dynamic>> _readyTasks  = [];
  final List<Map<String, dynamic>> _activeTasks = [];
  final List<Map<String, dynamic>> _draftTasks  = [];
  int _subagentSerial = 0;
  bool _showNewTaskBanner = true;

  // ── Settings sub-tab (inside Tools > Settings) ──────────────────────────
  late TabController _settingsSubTab; // Providers | Mémoire | Apparence

  @override
  void initState() {
    super.initState();
    _tab            = TabController(length: 3, vsync: this);
    _settingsSubTab = TabController(length: 3, vsync: this);
    _chatInputCtrl.addListener(() => setState(() {}));
    _chatScrollCtrl.addListener(_onChatScroll);
    _loadMemorySettings();
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
      // Keep last 200 messages max to avoid excessive storage
      final toSave = _chatMessages.length > 200
          ? _chatMessages.sublist(_chatMessages.length - 200)
          : _chatMessages;
      await prefs.setString('agent_chat_history', jsonEncode(toSave));
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
    _customUrlCtrl.dispose();
    _memoryNotesCtrl.dispose();
    _systemPromptCtrl.dispose();
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
    });

    try {
      Models? model;
      try {
        final cfg = Map<String, dynamic>.from(selectedConfig as Map);
        model = await _resolveModel(cfg);
      } catch (e) {
        setState(() {
          _chatGenerating = false;
          _chatPhase      = AgentPhase.error;
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
        _chatMessages.add({'role': 'agent', 'text': '', 'thinking': '', 'phase': 'streaming', 'toolCalls': <Map<String, dynamic>>[]});
        _chatInputCtrl.clear();
        _chatStreamBuf   = '';
        _chatThinkingBuf = '';
        _chatPhase       = AgentPhase.streaming;
      });

      final agentIdx = _chatMessages.length - 1;

      _chatRunner.run(
        model: model,
        messages: messages,
        context: context,
        workspacePath: '',
        agentMode: _chatMode,
        systemPromptOverride: parts.isEmpty ? null : parts.join('\n\n'),
      ).listen(
        (chunk) {
          if (!mounted || requestId != _chatSerial) return;
          setState(() {
            switch (chunk.phase) {
              case AgentPhase.thinking:
                _chatPhase = AgentPhase.thinking;
                _chatThinkingBuf += chunk.text;
                _chatMessages[agentIdx]['thinking'] = _chatThinkingBuf;
              case AgentPhase.toolRunning:
                _chatPhase = AgentPhase.toolRunning;
                final calls = List<Map<String,dynamic>>.from(
                  (_chatMessages[agentIdx]['toolCalls'] as List?)?.cast<Map<String,dynamic>>() ?? []);
                calls.add({'name': chunk.toolName ?? '', 'args': chunk.toolArgs ?? {}, 'result': null, 'status': 'running'});
                _chatMessages[agentIdx]['toolCalls'] = calls;
              case AgentPhase.toolDone:
                final calls = List<Map<String,dynamic>>.from(
                  (_chatMessages[agentIdx]['toolCalls'] as List?)?.cast<Map<String,dynamic>>() ?? []);
                final idx = calls.lastIndexWhere((c) => c['name'] == chunk.toolName && c['status'] == 'running');
                if (idx >= 0) {
                  calls[idx] = {...calls[idx], 'result': chunk.toolResult ?? '', 'status': 'done'};
                }
                _chatMessages[agentIdx]['toolCalls'] = calls;
              case AgentPhase.streaming:
                _chatPhase = AgentPhase.streaming;
                _chatStreamBuf += chunk.text;
                _chatMessages[agentIdx]['text'] = _chatStreamBuf;
              case AgentPhase.done:
                _chatPhase      = AgentPhase.done;
                _chatGenerating = false;
                _chatMessages[agentIdx]['phase'] = 'done';
              case AgentPhase.error:
                _chatPhase      = AgentPhase.error;
                _chatGenerating = false;
                _chatMessages[agentIdx]['text']  = _chatStreamBuf.isNotEmpty ? _chatStreamBuf : 'Erreur : ${chunk.text}';
                _chatMessages[agentIdx]['phase'] = 'error';
              case AgentPhase.idle:
                break;
            }
          });
          _chatScrollToBottom();
        },
        onError: (e) {
          PandaLog.e('AgentSettings', 'Stream error', error: e);
          if (!mounted || requestId != _chatSerial) return;
          setState(() {
            _chatGenerating = false;
            _chatPhase      = AgentPhase.error;
            _chatMessages[agentIdx]['text']  = 'Erreur : $e';
            _chatMessages[agentIdx]['phase'] = 'error';
          });
        },
        onDone: () {
          if (!mounted || requestId != _chatSerial || !_chatGenerating) return;
          setState(() {
            _chatGenerating = false;
            if (_chatPhase != AgentPhase.error) {
              _chatPhase = AgentPhase.done;
              _chatMessages[agentIdx]['phase'] = 'done';
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
        },
      );
    } catch (e) {
      PandaLog.e('AgentSettings', 'Chat send error', error: e);
      if (mounted) {
        setState(() {
          _chatGenerating = false;
          _chatPhase      = AgentPhase.error;
        });
      }
    }
  }

  Models? _modelFromAiConfig(Map<String, dynamic> cfg) {
    final providerRaw = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString();
    final provider    = providerRaw.toLowerCase();
    final apiKey      = (cfg['apiKey'] ?? cfg['key'] ?? cfg['api_key'] ?? cfg['secretKey'] ?? '').toString();
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
      if (_chatMessages.isNotEmpty && _chatMessages.last['role'] == 'agent' && _chatMessages.last['phase'] == 'streaming') {
        _chatMessages.last['text']  = _chatStreamBuf.isEmpty ? 'Arrêté.' : _chatStreamBuf;
        _chatMessages.last['phase'] = 'error';
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROVIDER SETTINGS — validate & save
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _testApiKey() async {
    final provider = _providers.firstWhere((p) => p.id == _selectedProviderId, orElse: () => _providers.first);
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
          .timeout(const Duration(seconds: 20));
      if (models.isEmpty) throw StateError('Aucun modèle retourné.');
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
          final id = _selectedProviderId == 'gemini' && rawId.startsWith('models/')
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
    final allCapable = models.where((m) => m['id'].toString().isNotEmpty && _looksChatCapable(m)).toList();
    if (showAll) return allCapable;

    final cleanOnly = allCapable.where((m) => _isCleanCurrentModel(_selectedProviderId, m['id'].toString())).toList();
    return cleanOnly.isNotEmpty ? cleanOnly : allCapable;
  }

  static bool _isCleanCurrentModel(String provider, String modelId) {
    final p = provider.toLowerCase();
    final id = modelId.toLowerCase();

    if (p == 'gemini') {
      return id == 'gemini-2.0-flash' ||
             id == 'gemini-2.0-flash-lite' ||
             id == 'gemini-1.5-flash' ||
             id == 'gemini-1.5-pro' ||
             id == 'gemini-1.5-flash-8b';
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
    required _ProviderDef provider,
    required String apiKey,
    required List<Map<String, dynamic>> models,
  }) async {
    final usable    = models.firstWhere((m) => _looksChatCapable(m), orElse: () => models.first);
    final modelName = usable['id'].toString();
    if (_selectedProviderId == 'custom' && _customUrlCtrl.text.trim().isEmpty) return;

    final aiBloc  = context.read<AIBloc>();
    final newCfg  = Map<String, dynamic>.from(aiBloc.state.config);
    final modelId = 'agent_${_selectedProviderId}';
    newCfg[modelId] = {
      'provider':   _selectedProviderId,
      'apiProvider': _selectedProviderId,
      if (_selectedProviderId != 'copilot') 'apiKey': apiKey,
      if (_selectedProviderId != 'copilot') 'key': apiKey,
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
                            tooltip: 'Entrée vocale',
                            icon: Icon(Broken.microphone, size: 16, color: muted),
                            onPressed: () => _showSnack(context, 'Entrée vocale bientôt disponible.'),
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
                  if (_chatGenerating)
                    _ChatSmallIconButton(
                      icon: Broken.stop_circle,
                      color: _kDanger,
                      tooltip: 'Arrêter',
                      onTap: _chatStop,
                    )
                  else
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
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 9),
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
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Panda Agent',
                        style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              leading: const Icon(Broken.copy),
              title: const Text('Exporter le texte'),
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

              // Thinking block — collapsible with brain icon
              if (think.isNotEmpty)
                _ChatThinkingBlock(
                  thinking: think,
                  isDark: isDark,
                  fg: fg,
                  muted: muted,
                  isStreaming: isStreaming && text.isEmpty,
                ),

              // Tool calls — grouped into one collapsible action timeline.
              ...() {
                final calls = (msg['toolCalls'] as List?)
                        ?.whereType<Map>()
                        .map((call) => call.cast<String, dynamic>())
                        .toList() ??
                    <Map<String, dynamic>>[];
                if (calls.isEmpty) return <Widget>[];
                return <Widget>[
                  _ChatActionGroup(
                    calls: calls,
                    isDark: isDark,
                    fg: fg,
                    muted: muted,
                  ),
                ];
              }(),

              // Response text — NO bubble, plain
              if (text.isNotEmpty || (isStreaming && think.isEmpty))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: isStreaming
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                text,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: isError ? _kDanger : fg,
                                  height: 1.55,
                                ),
                              ),
                            ),
                            if (text.isNotEmpty) ...[
                              const SizedBox(width: 3),
                              _ChatBlinkingCursor(color: fg),
                            ],
                          ],
                        )
                      : _ChatMarkdownResponse(
                          markdown: text,
                          isDark: isDark,
                          fg: isError ? _kDanger : fg,
                        ),
                ),

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
        final configured = aiState.config.entries.where((e) => e.key.startsWith('agent_')).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (configured.isNotEmpty) ...[
              _sectionLabel('PROVIDERS CONNECTÉS', muted),
              const SizedBox(height: 8),
              ...configured.map((entry) {
                final id       = entry.key;
                final cfg      = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : <String, dynamic>{};
                final name     = cfg['modelName']?.toString() ?? id;
                final provider = cfg['provider']?.toString() ?? '';
                final pDef     = _providers.firstWhere((p) => p.id == provider, orElse: () => _providers.last);
                return _ModelCard(id: id, name: name, provider: provider, pDef: pDef, isDark: isDark, card: card, fg: fg, muted: muted, border: border, onRemove: () => _removeModel(ctx, id));
              }),
              const SizedBox(height: 20),
            ],

            _sectionLabel('CONNECTER UN PROVIDER', muted),
            const SizedBox(height: 10),

            _ProviderPicker(
              providers: _providers,
              selected: _selectedProviderId,
              isDark: isDark, card: card, fg: fg, muted: muted, border: border,
              onChanged: (id) => setState(() {
                _selectedProviderId = id;
                _testKeyResult  = null;
                _testKeyMessage = '';
                _availableModels = const [];
              }),
            ),
            const SizedBox(height: 12),

            Builder(builder: (_) {
              final pDef = _providers.firstWhere((p) => p.id == _selectedProviderId, orElse: () => _providers.first);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedProviderId == 'custom') ...[
                    _SettingsField(
                      controller: _customUrlCtrl,
                      label: 'URL endpoint',
                      hint: 'http://localhost:11434/v1/chat/completions',
                      isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (pDef.hasApiKey) ...[
                    Row(children: [
                      Expanded(
                        child: _SettingsField(
                          controller: _apiKeyCtrl,
                          label: 'Clé API',
                          hint: pDef.apiKeyHint,
                          obscure: _obscureKey,
                          isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                          suffix: IconButton(
                            icon: Icon(_obscureKey ? Broken.eye_slash : Broken.eye, size: 16, color: muted),
                            onPressed: () => setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Broken.link, size: 16),
                        tooltip: 'Docs',
                        onPressed: pDef.docsUrl.isNotEmpty ? () => launchUrl(Uri.parse(pDef.docsUrl)) : null,
                      ),
                    ]),
                    const SizedBox(height: 12),
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
                  // Validate button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _testingKey ? null : _testApiKey,
                      child: _testingKey
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Valider et activer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (_testKeyMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_testKeyResult == true ? _kSuccess : _kDanger).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (_testKeyResult == true ? _kSuccess : _kDanger).withValues(alpha: 0.3)),
                      ),
                      child: Text(_testKeyMessage, style: TextStyle(fontSize: 12, color: _testKeyResult == true ? _kSuccess : _kDanger)),
                    ),
                  ],
                  if (_availableModels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Catalogue (${_availableModels.length} modèles)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                    const SizedBox(height: 5),
                    Text(
                      _availableModels.take(12).map((m) => '${m['displayName']}  —  ${m['id']}').join('\n'),
                      maxLines: 12,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, height: 1.4, color: muted),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              );
            }),
            const SizedBox(height: 32),
          ],
        );
      },
    );
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
  // TAB 3 — Subagents (Ready / Active / Draft)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSubagentsTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // New task banner
        if (_showNewTaskBanner)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff252526) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Broken.cpu_setting, size: 16, color: _kAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'New',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showNewTaskBanner = false),
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(Broken.close_square, size: 16, color: muted),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final icon in [Broken.cpu_setting, Broken.code_1, Broken.flash_circle, Broken.global, Broken.diagram])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: [
                              const Color(0xff4285f4), const Color(0xff10a37f),
                              const Color(0xfff97316), const Color(0xff8b5cf6),
                              const Color(0xffe05252),
                            ][([Broken.cpu_setting, Broken.code_1, Broken.flash_circle, Broken.global, Broken.diagram].indexOf(icon))].withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(icon, size: 14, color: [
                            const Color(0xff4285f4), const Color(0xff10a37f),
                            const Color(0xfff97316), const Color(0xff8b5cf6),
                            const Color(0xffe05252),
                          ][([Broken.cpu_setting, Broken.code_1, Broken.flash_circle, Broken.global, Broken.diagram].indexOf(icon))]),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Les background tasks permettent d\'accomplir plus en parallèle.', style: TextStyle(fontSize: 13, color: fg)),
                const SizedBox(height: 4),
                Text('Créez votre première tâche !', style: TextStyle(fontSize: 13, color: fg)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _addDraftTask(fg),
                  child: Text('View documentation', style: TextStyle(fontSize: 13, color: _kAccent)),
                ),
              ],
            ),
          ),

        // Section: Ready
        _buildTaskSection('Ready', _readyTasks, isDark, fg, muted, border, card),
        const SizedBox(height: 12),

        // Section: Active
        _buildTaskSection('Active', _activeTasks, isDark, fg, muted, border, card),
        const SizedBox(height: 12),

        // Section: Draft
        _buildTaskSection('Draft', _draftTasks, isDark, fg, muted, border, card,
            addButton: true,
            onAdd: () => _addDraftTask(fg)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTaskSection(
    String title,
    List<Map<String, dynamic>> tasks,
    bool isDark,
    Color fg,
    Color muted,
    Color border,
    Color card, {
    bool addButton = false,
    VoidCallback? onAdd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff252526) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: tasks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('No ${title.toLowerCase()} tasks', style: TextStyle(fontSize: 13, color: muted)),
                      if (addButton)
                        GestureDetector(
                          onTap: onAdd,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _kAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Broken.add_square, size: 12, color: _kAccent),
                              const SizedBox(width: 4),
                              const Text('New task', style: TextStyle(fontSize: 12, color: _kAccent, fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: tasks.asMap().entries.map((entry) {
                    final idx  = entry.key;
                    final task = entry.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: idx < tasks.length - 1
                            ? Border(bottom: BorderSide(color: border, width: 0.5))
                            : null,
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task['title'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
                              if ((task['desc'] as String? ?? '').isNotEmpty)
                                Text(task['desc'] as String? ?? '', style: TextStyle(fontSize: 11, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() { tasks.removeAt(idx); });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Broken.close_square, size: 14, color: muted),
                          ),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  void _addDraftTask(Color fg) {
    _subagentSerial++;
    final id = 'task-$_subagentSerial';
    setState(() {
      _draftTasks.add({'id': id, 'title': 'Nouvelle tâche', 'desc': 'Description…', 'status': 'draft'});
      _showNewTaskBanner = false;
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper data classes
// ─────────────────────────────────────────────────────────────────────────────

class _ToolItem {
  final IconData icon;
  final Color color;
  final String name;
  final String desc;
  final VoidCallback onTap;
  const _ToolItem({required this.icon, required this.color, required this.name, required this.desc, required this.onTap});
}

class _ToolSpecItem {
  final AgenticToolSpec spec;
  const _ToolSpecItem({required this.spec});
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final Color card, border;
  final Widget child;
  final EdgeInsets padding;
  const _SettingsCard({
    required this.isDark, required this.card, required this.border,
    required this.child, this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: child,
  );
}

class _SettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final bool isDark;
  final Color card, fg, muted, border;
  final Widget? suffix;
  const _SettingsField({
    required this.controller, required this.label, required this.hint,
    this.obscure = false, required this.isDark, required this.card,
    required this.fg, required this.muted, required this.border, this.suffix,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: TextStyle(fontSize: 13, color: fg),
              decoration: InputDecoration(
                hintText: hint, hintStyle: TextStyle(fontSize: 12, color: muted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none, isDense: true,
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ]),
      ),
    ],
  );
}

class _ChatSmallIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _ChatSmallIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(icon, size: 16, color: onTap == null ? color.withValues(alpha: 0.35) : color),
      );
}

class _ChatActionGroup extends StatefulWidget {
  final List<Map<String, dynamic>> calls;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _ChatActionGroup({
    required this.calls,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<_ChatActionGroup> createState() => _ChatActionGroupState();
}

class _ChatActionGroupState extends State<_ChatActionGroup> {
  bool _expanded = false;

  IconData _groupIcon() {
    final names = widget.calls.map((call) => call['name']?.toString() ?? '').toList();
    if (names.any((name) => name == 'runShellCommand')) return Broken.code_1;
    if (names.any((name) => name.startsWith('write') || name.startsWith('edit'))) {
      return Broken.edit;
    }
    if (names.any((name) => name.startsWith('git'))) return Broken.hierarchy_2;
    if (names.any((name) => name.startsWith('search') || name.startsWith('grep'))) {
      return Broken.search_normal;
    }
    return Broken.setting_2;
  }

  String _title() {
    final first = widget.calls.first['name']?.toString() ?? '';
    if (first == 'runShellCommand') return 'Exécution du terminal';
    if (first.startsWith('read') || first.startsWith('list')) return 'Exploration du projet';
    if (first.startsWith('write') || first.startsWith('edit')) return 'Mise à jour des fichiers';
    if (first.startsWith('git')) return 'Opérations Git';
    return 'Actions de Panda Agent';
  }

  String _labelFor(String name) {
    if (name.isEmpty) return 'Action';
    final spaced = name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  IconData _iconFor(String name) {
    if (name == 'runShellCommand') return Broken.code_1;
    if (name.startsWith('write') || name.startsWith('edit') ||
        name.startsWith('replace') || name.startsWith('insert')) {
      return Broken.edit;
    }
    if (name.startsWith('read')) return Broken.document_1;
    if (name.startsWith('delete')) return Broken.trash;
    if (name.startsWith('list') || name.startsWith('glob')) return Broken.folder_2;
    if (name.startsWith('grep') || name.startsWith('search')) return Broken.search_normal;
    if (name.startsWith('git')) return Broken.hierarchy_2;
    if (name.startsWith('openLinks')) return Broken.global_search;
    if (name.startsWith('updateProject') || name.startsWith('memory')) return Broken.note_2;
    if (name.startsWith('getLsp') || name.startsWith('diagnostic')) return Broken.warning_2;
    return Broken.cpu_setting;
  }

  String? _argsSummary(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return null;
    final value = args.values.first;
    if (value is! String) return null;
    final clean = value.replaceAll('\n', ' ').trim();
    if (clean.isEmpty) return null;
    return clean.length > 54 ? '${clean.substring(0, 54)}…' : clean;
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? const Color(0xff2a2a3e) : const Color(0xffd0d7de);
    final running = widget.calls.any((call) => call['status'] == 'running');
    final groupColor = running ? const Color(0xfff5a623) : widget.muted;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: widget.isDark ? _kGroupBg : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: running ? groupColor.withValues(alpha: 0.45) : border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(_groupIcon(), size: 15, color: groupColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: widget.fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('${widget.calls.length} actions',
                      style: TextStyle(fontSize: 10, color: widget.muted)),
                  const SizedBox(width: 7),
                  if (running)
                    _DotsIndicator(color: groupColor, size: 3.5)
                  else
                    Icon(_expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                        size: 13, color: widget.muted),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _expanded
                ? Column(
                    children: [
                      Divider(height: 1, color: border),
                      ...widget.calls.map((call) {
                        final name = call['name']?.toString() ?? '';
                        final result = call['result']?.toString() ?? '';
                        final args = (call['args'] as Map?)?.cast<String, dynamic>();
                        final itemRunning = call['status'] == 'running';
                        final summary = _argsSummary(args);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(itemRunning ? Broken.more_circle : Broken.tick_circle,
                                  size: 13,
                                  color: itemRunning ? groupColor : _kSuccess),
                              const SizedBox(width: 7),
                              Icon(_iconFor(name), size: 13, color: widget.muted),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_labelFor(name),
                                        style: TextStyle(fontSize: 11, color: widget.fg)),
                                    if (summary != null)
                                      Text(summary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: widget.muted,
                                              fontStyle: FontStyle.italic)),
                                    if (result.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: widget.isDark
                                                ? const Color(0xff0d1117)
                                                : const Color(0xfff6f8fa),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: SelectableText(
                                            result.length > 700
                                                ? '${result.substring(0, 700)}\n…'
                                                : result,
                                            style: TextStyle(
                                                fontSize: 10,
                                                height: 1.45,
                                                color: widget.muted,
                                                fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  final List<_ProviderDef> providers;
  final String selected;
  final bool isDark;
  final Color card, fg, muted, border;
  final ValueChanged<String> onChanged;
  const _ProviderPicker({
    required this.providers, required this.selected, required this.isDark,
    required this.card, required this.fg, required this.muted, required this.border,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pDef = providers.firstWhere((p) => p.id == selected, orElse: () => providers.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Provider', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: card, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: card,
            style: TextStyle(fontSize: 13, color: fg),
            items: providers.map((p) => DropdownMenuItem(
              value: p.id,
              child: Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: p.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Icon(p.icon, size: 14, color: p.color),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(p.name, style: TextStyle(fontSize: 13, color: fg))),
              ]),
            )).toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ),
        const SizedBox(height: 4),
        Text(pDef.description, style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  final String id, name, provider;
  final _ProviderDef pDef;
  final bool isDark;
  final Color card, fg, muted, border;
  final VoidCallback onRemove;
  const _ModelCard({
    required this.id, required this.name, required this.provider,
    required this.pDef, required this.isDark, required this.card,
    required this.fg, required this.muted, required this.border,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: card, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: pDef.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(pDef.icon, size: 16, color: pDef.color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pDef.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          Text(name, style: TextStyle(fontSize: 11, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
      IconButton(
        icon: Icon(Broken.trash, size: 15, color: _kDanger.withValues(alpha: 0.7)),
        tooltip: 'Supprimer',
        onPressed: onRemove,
      ),
    ]),
  );
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2.5),
        boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)] : [],
      ),
      child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat sub-widgets (local to this file, avoid duplicating from home.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color muted;
  final VoidCallback onTap;
  const _ChatActionBtn({required this.icon, required this.label, required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: muted),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: muted)),
      ]),
    ),
  );
}

class _ChatPhaseChip extends StatelessWidget {
  final String label;
  final bool isDark;
  const _ChatPhaseChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _kAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11, color: _kAccent)),
  );
}

// ─── DotsIndicator — 3 points animés (thinking / loading) ───────────────────

class _DotsIndicator extends StatefulWidget {
  final Color color;
  final double size;
  const _DotsIndicator({required this.color, this.size = 4.0});
  @override
  State<_DotsIndicator> createState() => _DotsIndicatorState();
}

class _DotsIndicatorState extends State<_DotsIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 3 + 8,
      height: widget.size * 2,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              // chaque point bounce avec un décalage de phase
              final phase = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
              final bounce = Curves.easeInOut.transform(
                (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0),
              );
              return Transform.translate(
                offset: Offset(0, -bounce * widget.size * 0.9),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.4 + bounce * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Thinking block — collapsible avec icône cerveau ────────────────────────

class _ChatThinkingBlock extends StatefulWidget {
  final String thinking;
  final bool isDark;
  final bool isStreaming;   // true = le modèle pense encore
  final Color fg, muted;
  const _ChatThinkingBlock({
    required this.thinking,
    required this.isDark,
    required this.fg,
    required this.muted,
    this.isStreaming = false,
  });
  @override
  State<_ChatThinkingBlock> createState() => _ChatThinkingBlockState();
}

class _ChatThinkingBlockState extends State<_ChatThinkingBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  static const _kThinkPurple = Color(0xff9b7de8);
  static const _kThinkBorder = Color(0xff7c5cbf);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _pulseAnim = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.isStreaming) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ChatThinkingBlock old) {
    super.didUpdateWidget(old);
    if (widget.isStreaming && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isStreaming && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _kThinkBorder.withValues(alpha: widget.isDark ? 0.08 : 0.05);
    final border = _kThinkBorder.withValues(alpha: 0.3);
    final charCount = widget.thinking.length;
    final hint = charCount > 0
        ? '${(charCount / 1000).toStringAsFixed(1)}k'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  // Cerveau animé
                  FadeTransition(
                    opacity: widget.isStreaming ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
                    child: const Icon(Broken.cpu, size: 16, color: _kThinkPurple),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isStreaming ? 'Réflexion en cours…' : 'Réflexion interne',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kThinkPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _kThinkBorder.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(hint,
                          style: TextStyle(fontSize: 9.5, color: widget.muted)),
                    ),
                  ],
                  const Spacer(),
                  if (widget.isStreaming)
                    _DotsIndicator(color: _kThinkPurple.withValues(alpha: 0.7))
                  else
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 13,
                      color: _kThinkPurple,
                    ),
                ]),
              ),
            ),
          ),
          // ── Contenu déplié ──────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _expanded && widget.thinking.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, color: border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: SelectableText(
                          widget.thinking,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.muted,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── Tool call block — icône par type, résultat expandable ──────────────────

class _ChatToolCallBlock extends StatefulWidget {
  final String toolName, status;
  final String? result;
  final Map<String, dynamic>? args;
  final bool isDark;
  final Color fg, muted;
  const _ChatToolCallBlock({
    required this.toolName,
    required this.status,
    this.result,
    this.args,
    required this.isDark,
    required this.fg,
    required this.muted,
  });
  @override
  State<_ChatToolCallBlock> createState() => _ChatToolCallBlockState();
}

class _ChatToolCallBlockState extends State<_ChatToolCallBlock> {
  bool _expanded = false;

  // ── Icône selon le nom de l'outil ─────────────────────────────────────────
  IconData _iconFor(String name) {
    if (name == 'runShellCommand') return Broken.code_1;
    if (name.startsWith('write') || name.startsWith('edit') ||
        name.startsWith('replace') || name.startsWith('insert')) return Broken.edit;
    if (name.startsWith('read')) return Broken.document_1;
    if (name.startsWith('delete')) return Broken.trash;
    if (name.startsWith('list') || name.startsWith('glob')) return Broken.folder_2;
    if (name.startsWith('grep') || name.startsWith('search')) return Broken.search_normal;
    if (name.startsWith('git')) return Broken.hierarchy_2;
    if (name.startsWith('searchInWeb') || name.startsWith('openLinks')) return Broken.global_search;
    if (name.startsWith('updateProject') || name.startsWith('memory')) return Broken.note_2;
    if (name.startsWith('getLsp') || name.startsWith('diagnostic')) return Broken.warning_2;
    if (name.startsWith('rename') || name.startsWith('move')) return Broken.document_text;
    if (name.startsWith('getFile') || name.startsWith('info')) return Broken.info_circle;
    if (name.startsWith('activeEditor') || name.startsWith('currentlySelected')) return Broken.code_circle;
    return Broken.cpu_setting;
  }

  // ── Label lisible (camelCase → "Camel case") ──────────────────────────────
  String _labelFor(String name) {
    if (name.isEmpty) return name;
    final spaced = name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => ' ${m.group(1)!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  // ── Résumé court des args ─────────────────────────────────────────────────
  String? _argsSummary(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return null;
    final first = args.values.first;
    if (first is String) {
      final trimmed = first.replaceAll('\n', ' ').trim();
      return trimmed.length > 55 ? '${trimmed.substring(0, 55)}…' : trimmed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.status == 'running';
    const runColor = Color(0xfff97316);
    final border = widget.isDark ? const Color(0xff2a2a3a) : const Color(0xffe0e0e0);
    final cardBg = widget.isDark ? const Color(0xff1a1a2a) : const Color(0xfff4f4f8);
    final hasResult = (widget.result ?? '').isNotEmpty;
    final icon = _iconFor(widget.toolName);
    final label = _labelFor(widget.toolName);
    final argHint = _argsSummary(widget.args);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: isRunning ? runColor.withValues(alpha: 0.06) : cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning ? runColor.withValues(alpha: 0.4) : border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasResult ? () => setState(() => _expanded = !_expanded) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ─────────────────────────────────────────────
                Row(children: [
                  // Status badge
                  if (isRunning)
                    _DotsIndicator(color: runColor, size: 3.5)
                  else
                    Icon(Broken.tick_circle, size: 13, color: _kSuccess),
                  const SizedBox(width: 7),
                  // Tool icon
                  Icon(icon, size: 13,
                      color: isRunning
                          ? runColor.withValues(alpha: 0.85)
                          : widget.fg.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  // Label + arg hint
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        text: label,
                        style: TextStyle(
                          fontSize: 12,
                          color: isRunning ? runColor : widget.fg,
                          fontWeight: FontWeight.w500,
                        ),
                        children: argHint != null
                            ? [
                                TextSpan(
                                  text: '  $argHint',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: widget.muted,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                  if (hasResult)
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 12,
                      color: widget.muted,
                    ),
                ]),

                // ── Résultat déplié ────────────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 190),
                  curve: Curves.easeOut,
                  child: _expanded && hasResult
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(height: 1, color: border),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: widget.isDark
                                      ? const Color(0xff0d1117)
                                      : const Color(0xfff6f8fa),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SelectableText(
                                  () {
                                    final r = widget.result!;
                                    const limit = 900;
                                    if (r.length > limit) {
                                      return '${r.substring(0, limit)}\n… [${r.length - limit} chars tronqués]';
                                    }
                                    return r;
                                  }(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: widget.muted,
                                    fontFamily: 'monospace',
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMarkdownResponse extends StatelessWidget {
  final String markdown;
  final bool isDark;
  final Color fg;
  const _ChatMarkdownResponse({
    required this.markdown,
    required this.isDark,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final config = isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff11121a) : const Color(0xfff8f9fb),
        borderRadius: BorderRadius.circular(8),
      ),
      child: MarkdownWidget(
        data: markdown,
        config: config.copy(configs: [
          PConfig(
            textStyle: TextStyle(fontSize: 13.5, color: fg, height: 1.55),
          ),
        ]),
      ),
    );
  }
}

class _ChatBlinkingCursor extends StatefulWidget {
  final Color color;
  const _ChatBlinkingCursor({required this.color});
  @override
  State<_ChatBlinkingCursor> createState() => _ChatBlinkingCursorState();
}

class _ChatBlinkingCursorState extends State<_ChatBlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(width: 2, height: 14, color: widget.color),
  );
}
