/// AgentSettings — page dédiée aux paramètres de Panda Agent.
///
/// Différent des paramètres IDE (settings.dart).
/// Gère : providers IA, clés API, catalogues de modèles,
///         mémoire, outils actifs.
library;

import 'dart:convert';
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

// ─────────────────────────────────────────────────────────────────────────────
const _kAccent  = Color(0xff5090c8);
const _kDanger  = Color(0xffe05252);
const _kSuccess = Color(0xff4caf7d);

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
    name: 'Panda Open Gateway',
    description: 'Accès ChatGPT/Claude via Panda Browser Gateway local',
    icon: Broken.routing_2,
    color: Color(0xff5090c8),
    docsUrl: '',
    hasApiKey: false,
    apiKeyHint: 'Token Panda Open Gateway (optionnel)',
  ),
  _ProviderDef(
    id: 'copilot',
    name: 'GitHub Copilot',
    description: 'Modèles Copilot via votre session GitHub',
    icon: Broken.message_programming,
    color: Color(0xff8b5cf6),
    docsUrl: 'https://github.com/features/copilot',
    hasApiKey: false,
  ),
  _ProviderDef(
    id: 'custom',
    name: 'Custom / Local',
    description: 'Endpoint OpenAI-compatible (Ollama, LM Studio…)',
    icon: Broken.cpu_setting,
    color: Color(0xff888888),
    docsUrl: '',
    apiKeyHint: 'optionnel',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
class AgentSettings extends StatefulWidget {
  final bool embedded;
  const AgentSettings({super.key, this.embedded = false});

  @override
  State<AgentSettings> createState() => _AgentSettingsState();
}

class _AgentSettingsState extends State<AgentSettings>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  // Controllers for adding new provider
  String _selectedProviderId = 'openai';
  final _apiKeyCtrl         = TextEditingController();
  final _customUrlCtrl      = TextEditingController();
  bool _obscureKey          = true;
  bool _testingKey          = false;
  bool? _testKeyResult;
  String _testKeyMessage    = '';
  List<Map<String, dynamic>> _availableModels = const [];

  // Per-provider daily limit controllers (key = provider+model id)
  final Map<String, TextEditingController> _limitCtrls = {};

  // Memory settings
  final _memoryNotesCtrl = TextEditingController();
  bool _memoryEnabled    = true;

  // System prompt override
  final _systemPromptCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _loadMemorySettings();
  }

  Future<void> _loadMemorySettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _memoryEnabled     = prefs.getBool('agent_memory_enabled') ?? true;
      _memoryNotesCtrl.text = prefs.getString('agent_memory_notes') ?? '';
      _systemPromptCtrl.text = prefs.getString('agent_system_prompt') ?? '';
    });
  }

  Future<void> _saveMemorySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_memory_enabled', _memoryEnabled);
    await prefs.setString('agent_memory_notes', _memoryNotesCtrl.text);
    await prefs.setString('agent_system_prompt', _systemPromptCtrl.text);
  }

  @override
  void dispose() {
    _tab.dispose();
    _apiKeyCtrl.dispose();
    _customUrlCtrl.dispose();
    _memoryNotesCtrl.dispose();
    _systemPromptCtrl.dispose();
    for (final c in _limitCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ── Validate provider and fetch its live model catalog ─────────────────────
  Future<void> _testApiKey() async {
    final provider = _providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => _providers.first,
    );
    final apiKey = _apiKeyCtrl.text.trim();
    if (_selectedProviderId == 'copilot') {
      final githubSignedIn = context.read<GithubAuthCubit>().state.isSignedIn;
      final copilotSignedIn = context.read<CopilotBloc>().state.isSignedIn;
      if (!githubSignedIn && !copilotSignedIn) {
        setState(() {
          _testKeyResult = false;
          _testKeyMessage =
              'Connectez GitHub ou Copilot avant de valider ce provider.';
        });
        return;
      }
    }
    if (provider.hasApiKey && apiKey.isEmpty) {
      setState(() {
        _testKeyResult = false;
        _testKeyMessage = 'Entrez la clé API avant de valider.';
      });
      return;
    }
    if (_selectedProviderId == 'custom' && _customUrlCtrl.text.trim().isEmpty) {
      setState(() {
        _testKeyResult = false;
        _testKeyMessage = 'Entrez l’URL de l’endpoint avant de valider.';
      });
      return;
    }

    setState(() {
      _testingKey = true;
      _testKeyResult = null;
      _testKeyMessage = 'Connexion au provider et récupération du catalogue…';
      _availableModels = const [];
    });
    try {
      final models = await _fetchLiveModels(
        provider: _selectedProviderId,
        apiKey: apiKey,
        customUrl: _customUrlCtrl.text.trim(),
      ).timeout(const Duration(seconds: 20));
      if (models.isEmpty) {
        throw StateError('Le provider n’a retourné aucun modèle exploitable.');
      }
      await _saveProviderConfig(
        context,
        provider: provider,
        apiKey: apiKey,
        models: models,
      );
      setState(() {
        _testingKey = false;
        _testKeyResult = true;
        _availableModels = models;
        _testKeyMessage =
            '✓ Clé valide — ${models.length} vrais modèles récupérés. '
            'Le premier modèle compatible est utilisé automatiquement.';
      });
      _showSnack(context, '${provider.name} — provider activé ✓');
    } catch (e) {
      setState(() {
        _testingKey = false;
        _testKeyResult = false;
        _testKeyMessage = '✕ Impossible de valider ce provider : $e';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLiveModels({
    required String provider,
    required String apiKey,
    required String customUrl,
  }) async {
    if (provider == 'copilot') {
      final auth = await CopilotChat.loadAuthContext();
      if (auth == null) {
        throw StateError('Connectez votre compte GitHub/Copilot.');
      }
      final payload = await CopilotChat(
        authToken: auth.authToken,
        initialApiEndpoint: auth.apiEndpoint,
      ).getCopilotModels();
      return _normalizeModelCatalog(payload);
    }

    final urls = <String, String>{
      'openai': 'https://api.openai.com/v1/models',
      'claude': 'https://api.anthropic.com/v1/models',
      'gemini':
          'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      'deepseek': 'https://api.deepseek.com/models',
      'grok': 'https://api.x.ai/v1/models',
      'openrouter': 'https://openrouter.ai/api/v1/models',
      'mistral': 'https://api.mistral.ai/v1/models',
      'togetherai': 'https://api.together.xyz/v1/models',
      'perplexity': 'https://api.perplexity.ai/models',
      'pandagateway': 'http://127.0.0.1:8000/v1/models',
    };
    var url = urls[provider] ?? customUrl;
    if (provider == 'custom') {
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme) {
        throw StateError('URL custom invalide.');
      }
      final normalizedUrl = url.replaceFirst(RegExp(r'/+$'), '');
      if (normalizedUrl.endsWith('/chat/completions')) {
        url = '${normalizedUrl.substring(
          0,
          normalizedUrl.length - '/chat/completions'.length,
        )}/models';
      } else if (normalizedUrl.endsWith('/responses')) {
        url = '${normalizedUrl.substring(
          0,
          normalizedUrl.length - '/responses'.length,
        )}/models';
      } else if (!normalizedUrl.endsWith('/models')) {
        url = '$normalizedUrl/models';
      }
    }
    if (url.isEmpty) throw StateError('Aucun endpoint de catalogue configuré.');

    final headers = <String, String>{
      'Accept': 'application/json',
      if (provider == 'claude') ...{
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      } else if (provider != 'gemini') ...{
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
    };
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode >= 400) {
      throw StateError('HTTP ${response.statusCode}: ${response.body}');
    }
    return _normalizeModelCatalog(jsonDecode(response.body));
  }

  List<Map<String, dynamic>> _normalizeModelCatalog(dynamic payload) {
    final raw = payload is Map
        ? (payload['data'] is List
            ? payload['data']
            : payload['models'] is List
                ? payload['models']
                : const [])
        : payload is List
            ? payload
            : const [];
    final models = <Map<String, dynamic>>[];
    for (final item in raw) {
      final model = item is Map
          ? Map<String, dynamic>.from(item)
          : <String, dynamic>{'id': item.toString()};
      final id = (model['id'] ?? model['name'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      model['id'] = id.startsWith('models/') ? id.substring(7) : id;
      model['displayName'] = (model['displayName'] ??
              model['display_name'] ??
              model['name'] ??
              id)
          .toString();
      models.add(model);
    }
    return models;
  }

  Future<void> _saveProviderConfig(
    BuildContext context, {
    required _ProviderDef provider,
    required String apiKey,
    required List<Map<String, dynamic>> models,
  }) async {
    final usable = models.firstWhere(
      (model) => _looksChatCapable(model),
      orElse: () => models.first,
    );
    final modelName = usable['id'].toString();
    if (_selectedProviderId == 'custom' && _customUrlCtrl.text.trim().isEmpty) {
      return;
    }

    final aiBloc  = context.read<AIBloc>();
    final newCfg  = Map<String, dynamic>.from(aiBloc.state.config);
    final modelId = 'agent_${_selectedProviderId}';

    newCfg[modelId] = {
      'provider':   _selectedProviderId,
      'apiProvider': _selectedProviderId,
      if (_selectedProviderId != 'copilot') 'apiKey': apiKey,
      'modelName':  modelName,
      'model':      modelName,
      'availableModels': models,
      if (_selectedProviderId == 'custom') 'url': _customUrlCtrl.text.trim(),
    };

    aiBloc.add(AIConfigEvent(newCfg));
    await _saveAiConfig(context, newCfg);

    final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    selected['chat'] = modelId;
    aiBloc.add(ModelSelectEvent(selected));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('modelSelected', jsonEncode(selected));
  }

  bool _looksChatCapable(Map<String, dynamic> model) {
    final id = model['id'].toString().toLowerCase();
    final methods = model['supported_generation_methods'];
    if (methods is List && methods.isNotEmpty) {
      return methods.any((method) =>
          method.toString().toLowerCase().contains('generatecontent'));
    }
    final endpoints = model['supported_endpoints'];
    if (endpoints is List && endpoints.isNotEmpty) {
      return endpoints.any((endpoint) {
        final value = endpoint.toString().toLowerCase();
        return value.contains('chat/completions') || value.contains('/responses');
      });
    }
    return !RegExp(
      r'(embedding|embed|moderation|whisper|transcri|tts|speech|audio|image)',
    ).hasMatch(id);
  }

  Future<void> _saveAiConfig(
      BuildContext context, Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiConfig', jsonEncode(config));
  }

  void _removeModel(BuildContext context, String modelId) {
    final aiBloc = context.read<AIBloc>();
    final newCfg = Map<String, dynamic>.from(aiBloc.state.config)
      ..remove(modelId);
    aiBloc.add(AIConfigEvent(newCfg));
    _saveAiConfig(context, newCfg);
    // If removed was selected, clear
    final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    if (selected['chat'] == modelId) {
      selected.remove('chat');
      aiBloc.add(ModelSelectEvent(selected));
    }
    _showSnack(context, 'Modèle supprimé.');
  }

  void _showSnack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: isError ? _kDanger : _kSuccess,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5);
    final card   = isDark ? const Color(0xff252526) : Colors.white;
    final fg     = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted  = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final border = isDark ? const Color(0xff3a3a3a) : const Color(0xffe0e0e0);

    final body = Column(
      children: [
        // ── Tab bar header (always shown) ────────────────────────────────
        Container(
          color: isDark ? const Color(0xff252526) : Colors.white,
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
                        color: _kAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Broken.cpu_setting, color: _kAccent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text('Panda Agent — Paramètres',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                  ]),
                ),
              TabBar(
                controller: _tab,
                labelColor: _kAccent,
                unselectedLabelColor: muted,
                indicatorColor: _kAccent,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: 'Providers IA'),
                  Tab(text: 'Mémoire'),
                  Tab(text: 'Outils'),
                  Tab(text: 'Apparence'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildProvidersTab(context, isDark, bg, card, fg, muted, border),
              _buildMemoryTab(context, isDark, bg, card, fg, muted, border),
              _buildToolsTab(context, isDark, bg, card, fg, muted, border),
              _buildAppearanceTab(context, isDark, bg, card, fg, muted, border),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Container(color: bg, child: body);
    }

    return Scaffold(
      backgroundColor: bg,
      body: body,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — Providers & modèles
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildProvidersTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return BlocBuilder<AIBloc, AIState>(
      builder: (ctx, aiState) {
        final configuredModels = aiState.config.entries
            .where((entry) => entry.key.startsWith('agent_'))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Models configured ──────────────────────────────────────
            if (configuredModels.isNotEmpty) ...[
              _sectionLabel('PROVIDERS CONNECTÉS', muted),
              const SizedBox(height: 8),
              ...configuredModels.map((entry) {
                final id  = entry.key;
                final cfg = entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : <String, dynamic>{};
                final name     = cfg['modelName']?.toString() ?? id;
                final provider = cfg['provider']?.toString() ?? '';
                final pDef     = _providers.firstWhere(
                    (p) => p.id == provider,
                    orElse: () => _providers.last);
                return _ModelCard(
                  id: id, name: name, provider: provider,
                  pDef: pDef,
                  isDark: isDark, card: card, fg: fg, muted: muted,
                  border: border,
                  onRemove: () => _removeModel(ctx, id),
                );
              }),
              const SizedBox(height: 20),
            ],

            // ── Add new model ──────────────────────────────────────────
            _sectionLabel('CONNECTER UN PROVIDER', muted),
            const SizedBox(height: 10),

            // Provider selector
            _ProviderPicker(
              providers: _providers,
              selected: _selectedProviderId,
              isDark: isDark, card: card, fg: fg, muted: muted, border: border,
              onChanged: (id) => setState(() {
                _selectedProviderId = id;
                _testKeyResult = null;
                _testKeyMessage = '';
                _availableModels = const [];
              }),
            ),
            const SizedBox(height: 12),

            // Endpoint and credential. Model selection is intentionally absent:
            // validation fetches the provider's live catalog and picks the
            // first chat-capable model automatically.
            Builder(builder: (_) {
              final pDef = _providers.firstWhere(
                  (p) => p.id == _selectedProviderId,
                  orElse: () => _providers.first);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedProviderId == 'custom') ...[
                    _SettingsField(
                      controller: _customUrlCtrl,
                      label: 'URL endpoint (ex: http://localhost:11434/v1/chat/completions)',
                      hint: 'http://localhost:11434/v1/chat/completions',
                      isDark: isDark, card: card, fg: fg, muted: muted,
                      border: border,
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
                          isDark: isDark, card: card, fg: fg, muted: muted,
                          border: border,
                          suffix: IconButton(
                            icon: Icon(
                              _obscureKey ? Broken.eye : Broken.eye_slash,
                              size: 16, color: muted),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  Row(children: [
                    OutlinedButton.icon(
                      onPressed: _testingKey ? null : _testApiKey,
                      icon: _testingKey
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _kAccent,
                              ),
                            )
                          : const Icon(Broken.flash_circle, size: 14),
                      label: Text(
                        _testingKey
                            ? 'Connexion…'
                            : 'Valider et récupérer les modèles',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kAccent,
                        side: BorderSide(color: border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (pDef.docsUrl.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(pDef.docsUrl)),
                        icon: Icon(Broken.export_3, size: 12, color: muted),
                        label: Text(
                          'Obtenir une clé',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ]),
                  if (_testKeyMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _testKeyMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: _testKeyResult == true
                              ? _kSuccess
                              : _kDanger,
                        ),
                      ),
                    ),
                  if (_availableModels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Catalogue réel (${_availableModels.length} modèles)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _availableModels
                          .take(12)
                          .map((model) =>
                              '${model['displayName']}  —  ${model['id']}')
                          .join('\n'),
                      maxLines: 12,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: muted,
                      ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — Mémoire
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildMemoryTab(BuildContext context, bool isDark, Color bg,
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
                Text('Mémoire persistante',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg)),
                const Spacer(),
                Switch(
                  value: _memoryEnabled,
                  activeColor: _kAccent,
                  onChanged: (v) {
                    setState(() => _memoryEnabled = v);
                    _saveMemorySettings();
                  },
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                'L\'agent mémorise les faits importants entre les conversations.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('NOTES MÉMORABLES (CONTEXTE PERMANENT)', muted),
        const SizedBox(height: 8),
        _SettingsCard(
          isDark: isDark, card: card, border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informations que l\'agent doit toujours connaître '
                '(votre stack, préférences, contraintes…)',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _memoryNotesCtrl,
                maxLines: 6,
                style: TextStyle(fontSize: 13, color: fg,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Ex : "Utilise toujours Dart null-safety. '
                      'Mon projet est une app Flutter mobile…"',
                  hintStyle: TextStyle(fontSize: 12, color: muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kAccent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
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
              Text(
                'Remplace le prompt système par défaut de Panda Agent.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _systemPromptCtrl,
                maxLines: 5,
                style: TextStyle(fontSize: 12, color: fg,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Laissez vide pour utiliser le prompt par défaut…',
                  hintStyle: TextStyle(fontSize: 12, color: muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kAccent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — Outils
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildToolsTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return BlocBuilder<AIChatUIBloc, AIChatUIState>(
      builder: (ctx, uiState) {
        final selections = uiState.agenticToolSelections;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionLabel('OUTILS DE L\'AGENT', muted),
            const SizedBox(height: 4),
            Text(
              'Choisissez quels outils Panda Agent peut utiliser.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 12),
            ...agenticToolSpecs.map((spec) {
              final enabled = selections[spec.name] ?? true;
              return _SettingsCard(
                isDark: isDark, card: card, border: border,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _kAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Broken.flash_circle,
                        size: 14, color: _kAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(spec.name,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: fg)),
                        Text(spec.description,
                            style: TextStyle(
                                fontSize: 11, color: muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    activeColor: _kAccent,
                    onChanged: (v) {
                      final updated = Map<String, bool>.from(selections);
                      updated[spec.name] = v;
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
                ]),
              );
            }),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, Color muted) => Text(
        label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: muted),
      );

  // ── TAB 4 — Apparence du chat ──────────────────────────────────────────────
  Widget _buildAppearanceTab(BuildContext context, bool isDark, Color bg,
      Color card, Color fg, Color muted, Color border) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsCard(
          isDark: isDark,
          card: card,
          border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Messages utilisateur',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 12),
              Text('Couleur des bulles',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final c in [
                  const Color(0xff4f8ef7),
                  const Color(0xff5856d6),
                  const Color(0xff34c759),
                  const Color(0xffff2d55),
                  const Color(0xffff9500),
                  const Color(0xff636366),
                ])
                  _ColorSwatch(
                    color: c,
                    selected: false,
                    onTap: () {},
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          isDark: isDark,
          card: card,
          border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Messages agent',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 12),
              Text('Affichage du markdown',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Rendu Markdown',
                    style: TextStyle(fontSize: 12, color: fg)),
                value: true,
                activeColor: _kAccent,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          isDark: isDark,
          card: card,
          border: border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mise en page',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 12),
              Text('Taille de police',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Slider(
                min: 10,
                max: 18,
                value: 13,
                divisions: 8,
                activeColor: _kAccent,
                label: '13',
                onChanged: (_) {},
              ),
              const SizedBox(height: 8),
              Text('Rayon des bulles',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Slider(
                min: 0,
                max: 20,
                value: 8,
                divisions: 4,
                activeColor: _kAccent,
                label: '8',
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final bool  isDark;
  final Color card, border;
  final Widget child;
  final EdgeInsets padding;
  const _SettingsCard({
    required this.isDark,
    required this.card,
    required this.border,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

class _SettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final bool isDark;
  final Color card, fg, muted, border;
  final Widget? suffix;

  const _SettingsField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: muted)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(fontSize: 13, color: fg),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 12, color: muted),
            suffixIcon: suffix,
            filled: true,
            fillColor: card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kAccent),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
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
    required this.providers,
    required this.selected,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sel = providers.firstWhere((p) => p.id == selected,
        orElse: () => providers.first);
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: sel.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(sel.icon, size: 14, color: sel.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sel.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: fg)),
                Text(sel.description,
                    style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ),
          Icon(Broken.arrow_down_2, size: 14, color: muted),
        ]),
      ),
    );
  }

  void _show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scroll) => ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: providers.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Choisir un provider',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: fg)),
              );
            }
            final p = providers[i - 1];
            final isSel = p.id == selected;
            return ListTile(
              dense: true,
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: p.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(p.icon, size: 16, color: p.color),
              ),
              title: Text(p.name,
                  style: TextStyle(
                      fontSize: 13,
                      color: fg,
                      fontWeight: isSel
                          ? FontWeight.w600
                          : FontWeight.normal)),
              subtitle: Text(p.description,
                  style: TextStyle(fontSize: 11, color: muted)),
              trailing: isSel
                  ? const Icon(Broken.tick_circle,
                      size: 16, color: _kAccent)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onChanged(p.id);
              },
            );
          },
        ),
      ),
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
    required this.id,
    required this.name,
    required this.provider,
    required this.pDef,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: pDef.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(pDef.icon, size: 14, color: pDef.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: fg)),
                ),
              ]),
              Text(pDef.name,
                  style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Broken.trash, size: 15, color: _kDanger.withOpacity(0.7)),
          tooltip: 'Supprimer',
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ColorSwatch — clickable color dot for theme colour picker
// ─────────────────────────────────────────────────────────────────────────────
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
              : [],
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}
