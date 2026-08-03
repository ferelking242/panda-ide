/// AgentSettings — page dédiée aux paramètres de Panda Agent.
///
/// Différent des paramètres IDE (settings.dart).
/// Gère : providers IA, clés API, limites journalières,
///         mémoire, sélection de modèle, outils actifs.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../bloc/ui_bloc/ui_bloc.dart';
import '../core/broken_icons.dart';
import '../utils/ai.dart';
import '../utils/constants.dart';
import '../utils/agentic_tool_catalog.dart';

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
  final List<String> models;
  final String docsUrl;
  final bool hasApiKey;
  final String apiKeyHint;

  const _ProviderDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.models,
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
    models: ['gpt-4o', 'gpt-4o-mini', 'o1', 'o1-mini', 'o3-mini', 'gpt-4-turbo'],
    docsUrl: 'https://platform.openai.com/api-keys',
    apiKeyHint: 'sk-...',
  ),
  _ProviderDef(
    id: 'claude',
    name: 'Anthropic (Claude)',
    description: 'Claude 3.5 Sonnet, Haiku, Opus',
    icon: Broken.cpu,
    color: Color(0xffb87333),
    models: ['claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229', 'claude-3-sonnet-20240229'],
    docsUrl: 'https://console.anthropic.com/settings/keys',
    apiKeyHint: 'sk-ant-...',
  ),
  _ProviderDef(
    id: 'gemini',
    name: 'Google Gemini',
    description: 'Gemini 2.0 Flash, 1.5 Pro',
    icon: Broken.global_search,
    color: Color(0xff4285f4),
    models: ['gemini-2.0-flash-exp', 'gemini-2.5-pro-preview', 'gemini-1.5-pro', 'gemini-1.5-flash'],
    docsUrl: 'https://aistudio.google.com/app/apikey',
    apiKeyHint: 'AIza...',
  ),
  _ProviderDef(
    id: 'deepseek',
    name: 'DeepSeek',
    description: 'DeepSeek-V3, R1 — très bon rapport qualité/coût',
    icon: Broken.search_normal,
    color: Color(0xff4b6ef5),
    models: ['deepseek-chat', 'deepseek-coder', 'deepseek-reasoner'],
    docsUrl: 'https://platform.deepseek.com/api_keys',
    apiKeyHint: 'sk-...',
  ),
  _ProviderDef(
    id: 'grok',
    name: 'Grok (xAI)',
    description: 'Grok-2, Grok Beta',
    icon: Broken.code_circle,
    color: Color(0xff1da1f2),
    models: ['grok-2', 'grok-2-mini', 'grok-beta'],
    docsUrl: 'https://console.x.ai/',
    apiKeyHint: 'xai-...',
  ),
  _ProviderDef(
    id: 'openrouter',
    name: 'OpenRouter',
    description: 'Accès unifié à 200+ modèles',
    icon: Broken.routing_2,
    color: Color(0xff8b5cf6),
    models: ['openai/gpt-4o', 'anthropic/claude-3.5-sonnet', 'google/gemini-2.0-flash-exp', 'deepseek/deepseek-r1'],
    docsUrl: 'https://openrouter.ai/keys',
    apiKeyHint: 'sk-or-...',
  ),
  _ProviderDef(
    id: 'mistral',
    name: 'Mistral AI',
    description: 'Mistral Large, Codestral',
    icon: Broken.wind,
    color: Color(0xffff7000),
    models: ['mistral-large-latest', 'codestral-latest', 'mistral-small-latest'],
    docsUrl: 'https://console.mistral.ai/api-keys',
    apiKeyHint: '...',
  ),
  _ProviderDef(
    id: 'togetherai',
    name: 'Together AI',
    description: 'Llama, Mixtral et autres open-source',
    icon: Broken.people,
    color: Color(0xff00c9b1),
    models: ['meta-llama/Llama-3.3-70B-Instruct-Turbo', 'mistralai/Mixtral-8x7B', 'Qwen/Qwen2.5-72B-Instruct-Turbo'],
    docsUrl: 'https://api.together.xyz/settings/api-keys',
    apiKeyHint: '...',
  ),
  _ProviderDef(
    id: 'perplexity',
    name: 'Perplexity',
    description: 'Sonar — recherche web intégrée',
    icon: Broken.search_zoom_in,
    color: Color(0xff20b2aa),
    models: ['llama-3.1-sonar-large-128k-online', 'llama-3.1-sonar-small-128k-online'],
    docsUrl: 'https://www.perplexity.ai/settings/api',
    apiKeyHint: 'pplx-...',
  ),
  _ProviderDef(
    id: 'pandagateway',
    name: 'Panda Open Gateway',
    description: 'Accès ChatGPT/Claude via Panda Browser Gateway local',
    icon: Broken.routing_2,
    color: Color(0xff5090c8),
    models: ['gpt-4o', 'gpt-4o-mini', 'claude-3-5-sonnet', 'claude-3-haiku'],
    docsUrl: '',
    apiKeyHint: 'Token Panda Open Gateway (optionnel)',
  ),
  _ProviderDef(
    id: 'custom',
    name: 'Custom / Local',
    description: 'Endpoint OpenAI-compatible (Ollama, LM Studio…)',
    icon: Broken.cpu_setting,
    color: Color(0xff888888),
    models: [],
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
  String _selectedModelId   = '';
  final _apiKeyCtrl         = TextEditingController();
  final _customUrlCtrl      = TextEditingController();
  final _customModelCtrl    = TextEditingController();
  bool _obscureKey          = true;
  bool _testingKey          = false;
  bool? _testKeyResult;
  String _testKeyMessage    = '';

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
    _selectedModelId = _providers.first.models.isNotEmpty
        ? _providers.first.models.first
        : '';
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
    _customModelCtrl.dispose();
    _memoryNotesCtrl.dispose();
    _systemPromptCtrl.dispose();
    for (final c in _limitCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ── Test API key ────────────────────────────────────────────────────────────
  Future<void> _testApiKey() async {
    if (_apiKeyCtrl.text.trim().isEmpty) return;
    setState(() { _testingKey = true; _testKeyResult = null; });
    try {
      final provDef = _providers.firstWhere((p) => p.id == _selectedProviderId,
          orElse: () => _providers.first);
      String url = '';
      Map<String, String> headers = {};
      String body = '';

      switch (_selectedProviderId) {
        case 'openai':
        case 'grok':
        case 'deepseek':
        case 'togetherai':
        case 'perplexity':
        case 'openrouter':
        case 'mistral':
          final urls = {
            'openai': 'https://api.openai.com/v1/models',
            'grok': 'https://api.x.ai/v1/models',
            'deepseek': 'https://api.deepseek.com/models',
            'togetherai': 'https://api.together.xyz/v1/models',
            'perplexity': 'https://api.perplexity.ai/models',
            'openrouter': 'https://openrouter.ai/api/v1/models',
            'mistral': 'https://api.mistral.ai/v1/models',
          };
          url = urls[_selectedProviderId] ?? '';
          headers = { 'Authorization': 'Bearer ${_apiKeyCtrl.text.trim()}' };
          break;
        case 'claude':
          url = 'https://api.anthropic.com/v1/models';
          headers = {
            'x-api-key': _apiKeyCtrl.text.trim(),
            'anthropic-version': '2023-06-01',
          };
          break;
        case 'gemini':
          url = 'https://generativelanguage.googleapis.com/v1beta/models?key=${_apiKeyCtrl.text.trim()}';
          break;
        default:
          url = _customUrlCtrl.text.trim();
          if (url.isNotEmpty) {
            headers = { 'Authorization': 'Bearer ${_apiKeyCtrl.text.trim()}' };
          }
      }

      if (url.isEmpty) {
        setState(() {
          _testingKey = false;
          _testKeyResult = null;
          _testKeyMessage = 'Entrez une URL pour tester.';
        });
        return;
      }

      final resp = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
      setState(() {
        _testingKey = false;
        _testKeyResult = resp.statusCode < 400;
        _testKeyMessage = resp.statusCode < 400
            ? '✅ Clé valide (HTTP ${resp.statusCode})'
            : '❌ Erreur HTTP ${resp.statusCode}';
      });
    } catch (e) {
      setState(() {
        _testingKey = false;
        _testKeyResult = false;
        _testKeyMessage = '❌ $e';
      });
    }
  }

  // ── Add model to AIBloc ─────────────────────────────────────────────────────
  void _addModel(BuildContext context) {
    final provDef = _providers.firstWhere((p) => p.id == _selectedProviderId,
        orElse: () => _providers.first);
    final apiKey  = _apiKeyCtrl.text.trim();
    final model   = _selectedProviderId == 'custom'
        ? _customModelCtrl.text.trim()
        : _selectedModelId;

    if (model.isEmpty) {
      _showSnack(context, 'Choisissez un modèle.', isError: true);
      return;
    }
    if (provDef.hasApiKey && apiKey.isEmpty && _selectedProviderId != 'custom') {
      _showSnack(context, 'Entrez la clé API.', isError: true);
      return;
    }
    if (_selectedProviderId == 'custom' && _customUrlCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Entrez l\'URL de l\'endpoint.', isError: true);
      return;
    }

    final aiBloc  = context.read<AIBloc>();
    final newCfg  = Map<String, dynamic>.from(aiBloc.state.config);
    final modelId = '${_selectedProviderId}_${model.replaceAll('/', '_')}';

    newCfg[modelId] = {
      'provider':   _selectedProviderId,
      'apiProvider': _selectedProviderId,
      'apiKey':     apiKey,
      'modelName':  model,
      'model':      model,
      if (_selectedProviderId == 'custom') 'url': _customUrlCtrl.text.trim(),
    };

    aiBloc.add(AIConfigEvent(newCfg));
    _saveAiConfig(context, newCfg);

    // Set as default chat model if none selected
    final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    if (selected['chat'] == null || (selected['chat'] as String).isEmpty) {
      selected['chat'] = modelId;
      aiBloc.add(ModelSelectEvent(selected));
    }

    _showSnack(context, '${provDef.name} — $model ajouté ✓');
    _apiKeyCtrl.clear();
    setState(() { _testKeyResult = null; });
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

  void _setDefaultModel(BuildContext context, String modelId) {
    final aiBloc   = context.read<AIBloc>();
    final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    selected['chat'] = modelId;
    aiBloc.add(ModelSelectEvent(selected));
    SharedPreferences.getInstance().then((p) =>
        p.setString('modelSelected', jsonEncode(selected)));
    _showSnack(context, 'Modèle par défaut mis à jour ✓');
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
        final configuredModels = aiState.config.entries.toList();
        final defaultChatModel = aiState.modelSelected['chat'] as String? ?? '';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Models configured ──────────────────────────────────────
            if (configuredModels.isNotEmpty) ...[
              _sectionLabel('MODÈLES CONFIGURÉS', muted),
              const SizedBox(height: 8),
              ...configuredModels.map((entry) {
                final id  = entry.key;
                final cfg = entry.value as Map<String, dynamic>? ?? {};
                final name     = cfg['modelName']?.toString() ?? id;
                final provider = cfg['provider']?.toString() ?? '';
                final pDef     = _providers.firstWhere(
                    (p) => p.id == provider,
                    orElse: () => _providers.last);
                final isDefault = id == defaultChatModel;
                return _ModelCard(
                  id: id, name: name, provider: provider,
                  pDef: pDef, isDefault: isDefault,
                  isDark: isDark, card: card, fg: fg, muted: muted,
                  border: border,
                  onSetDefault: () => _setDefaultModel(ctx, id),
                  onRemove: () => _removeModel(ctx, id),
                );
              }),
              const SizedBox(height: 20),
            ],

            // ── Add new model ──────────────────────────────────────────
            _sectionLabel('AJOUTER UN MODÈLE', muted),
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
                final pDef = _providers.firstWhere((p) => p.id == id,
                    orElse: () => _providers.first);
                _selectedModelId = pDef.models.isNotEmpty
                    ? pDef.models.first : '';
              }),
            ),
            const SizedBox(height: 12),

            // Model selector
            Builder(builder: (_) {
              final pDef = _providers.firstWhere(
                  (p) => p.id == _selectedProviderId,
                  orElse: () => _providers.first);
              if (_selectedProviderId == 'custom') {
                return _SettingsField(
                  controller: _customModelCtrl,
                  label: 'Nom du modèle',
                  hint: 'llama3, qwen2.5-coder, mistral…',
                  isDark: isDark, card: card, fg: fg, muted: muted,
                  border: border,
                );
              }
              return _ModelDropdown(
                models: pDef.models,
                selected: _selectedModelId,
                isDark: isDark, card: card, fg: fg, muted: muted, border: border,
                onChanged: (m) => setState(() => _selectedModelId = m),
              );
            }),
            const SizedBox(height: 12),

            // API key / URL
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
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: _testingKey ? null : _testApiKey,
                        icon: _testingKey
                            ? SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kAccent))
                            : const Icon(Broken.flash_circle, size: 14),
                        label: Text(_testingKey ? 'Test…' : 'Tester la clé'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kAccent,
                          side: BorderSide(color: border),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (pDef.docsUrl.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {},
                          icon: Icon(Broken.export_3, size: 12, color: muted),
                          label: Text('Obtenir une clé',
                              style: TextStyle(fontSize: 12, color: muted)),
                        ),
                      ],
                    ]),
                    if (_testKeyMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_testKeyMessage,
                            style: TextStyle(
                              fontSize: 12,
                              color: _testKeyResult == true
                                  ? _kSuccess
                                  : _kDanger,
                            )),
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            }),

            // Add button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _addModel(context),
                icon: const Icon(Broken.add_circle, size: 16),
                label: const Text('Ajouter ce modèle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
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

/// Model dropdown — utilise un BottomSheet au lieu de DropdownButton.
/// DropdownButton échoue silencieusement sur certains appareils Android
/// (overlay bloqué par le touch event system). Le BottomSheet fonctionne
/// nativement sur mobile comme sur desktop.
class _ModelDropdown extends StatelessWidget {
  final List<String> models;
  final String selected;
  final bool isDark;
  final Color card, fg, muted, border;
  final ValueChanged<String> onChanged;

  const _ModelDropdown({
    required this.models,
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
    if (models.isEmpty) return const SizedBox.shrink();
    final eff = models.contains(selected) ? selected : models.first;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _show(context, eff),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              eff,
              style: TextStyle(fontSize: 13, color: fg),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Broken.arrow_down_2, size: 14, color: muted),
        ]),
      ),
    );
  }

  void _show(BuildContext context, String eff) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Choisir un modèle',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
                itemCount: models.length,
                itemBuilder: (_, i) {
                  final m = models[i];
                  final isSel = m == eff;
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: Icon(
                      isSel ? Broken.tick_circle : Broken.cpu,
                      size: 16,
                      color: isSel ? _kAccent : muted,
                    ),
                    title: Text(
                      m,
                      style: TextStyle(
                        fontSize: 13,
                        color: fg,
                        fontWeight:
                            isSel ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: isSel,
                    selectedTileColor: _kAccent.withOpacity(0.08),
                    onTap: () {
                      Navigator.pop(ctx);
                      onChanged(m);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final String id, name, provider;
  final _ProviderDef pDef;
  final bool isDefault, isDark;
  final Color card, fg, muted, border;
  final VoidCallback onSetDefault, onRemove;

  const _ModelCard({
    required this.id,
    required this.name,
    required this.provider,
    required this.pDef,
    required this.isDefault,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
    required this.onSetDefault,
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
        border: Border.all(
          color: isDefault
              ? _kAccent.withOpacity(0.5)
              : border,
          width: isDefault ? 1.5 : 1,
        ),
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
                if (isDefault)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('défaut',
                        style: TextStyle(
                            fontSize: 10,
                            color: _kAccent,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
              Text(pDef.name,
                  style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
        if (!isDefault)
          IconButton(
            icon: Icon(Broken.tick_circle, size: 16, color: muted),
            tooltip: 'Définir par défaut',
            onPressed: onSetDefault,
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
