/// AdvancedInferenceSettingsPage — Paramètres llama.cpp manuels.
///
/// Permet à l'utilisateur expérimenté de surcharger les valeurs auto-calculées :
///   • n_threads      : nombre de threads CPU
///   • n_ctx          : taille de contexte (tokens)
///   • n_gpu_layers   : couches déchargées sur GPU
///   • n_batch        : taille de batch pour le prefill
///   • flash_attention : activer/désactiver
///   • mmap           : memory-mapped loading
///
/// Un bouton "Reset auto" recalcule les valeurs depuis InferenceConfigService.
library;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_model_entry.dart';
import '../models/device_profile.dart';
import '../services/inference_config_service.dart';



// ── Page principale ───────────────────────────────────────────────────────────

class AdvancedInferenceSettingsPage extends StatefulWidget {
  /// La fiche du modèle concerné (pour Reset auto).
  final AiModelEntry?  modelEntry;
  final ModelQuant?     quant;
  final DeviceProfile?  profile;

  /// L'ID aiConfig de ce modèle (pour sauvegarder dans SharedPrefs).
  final String         aiConfigId;

  const AdvancedInferenceSettingsPage({
    super.key,
    this.modelEntry,
    this.quant,
    this.profile,
    this.aiConfigId = '',
  });

  @override
  State<AdvancedInferenceSettingsPage> createState() =>
      _AdvancedInferenceSettingsPageState();
}

class _AdvancedInferenceSettingsPageState
    extends State<AdvancedInferenceSettingsPage> {

  late InferenceConfig _auto;   // valeurs calculées automatiquement
  bool _useManual = false;      // si false → utilise les valeurs auto

  // Contrôleurs pour les champs texte
  late TextEditingController _threadsCtrl;
  late TextEditingController _ctxCtrl;
  late TextEditingController _gpuLayersCtrl;
  late TextEditingController _batchCtrl;

  bool _flashAttention = false;
  bool _mmap           = true;
  bool _saving         = false;

  @override
  void initState() {
    super.initState();
    _auto = InferenceConfigService.compute(
      model:   widget.modelEntry!,
      quant:   widget.quant!,
      profile: widget.profile!,
    );
    _resetToAuto();
    _loadExisting();
  }

  void _resetToAuto() {
    _threadsCtrl    = TextEditingController(text: _auto.threads.toString());
    _ctxCtrl        = TextEditingController(text: _auto.contextSize.toString());
    _gpuLayersCtrl  = TextEditingController(text: _auto.gpuLayers.toString());
    _batchCtrl      = TextEditingController(text: _auto.batchSize.toString());
    _flashAttention = _auto.flashAttention;
    _mmap           = true;
  }

  Future<void> _loadExisting() async {
    final prefs        = await SharedPreferences.getInstance();
    final aiConfigStr  = prefs.getString('aiConfig') ?? '{}';
    final aiConfig     = Map<String, dynamic>.from(jsonDecode(aiConfigStr) as Map);
    final entry        = aiConfig[widget.aiConfigId];
    if (entry is Map) {
      setState(() {
        _useManual       = entry['manualOverride'] as bool? ?? false;
        _threadsCtrl.text   = (entry['threads'] as int?    ?? _auto.threads).toString();
        _ctxCtrl.text       = (entry['contextSize'] as int? ?? _auto.contextSize).toString();
        _gpuLayersCtrl.text = (entry['gpuLayers'] as int?  ?? _auto.gpuLayers).toString();
        _batchCtrl.text     = (entry['batchSize'] as int?  ?? _auto.batchSize).toString();
        _flashAttention     = entry['flashAttention'] as bool? ?? _auto.flashAttention;
        _mmap               = entry['mmap'] as bool? ?? true;
      });
    }
  }

  @override
  void dispose() {
    _threadsCtrl.dispose();
    _ctxCtrl.dispose();
    _gpuLayersCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  // ── Sauvegarde ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs       = await SharedPreferences.getInstance();
      final aiConfigStr = prefs.getString('aiConfig') ?? '{}';
      final aiConfig    = Map<String, dynamic>.from(jsonDecode(aiConfigStr) as Map);
      final entry       = Map<String, dynamic>.from(
          (aiConfig[widget.aiConfigId] as Map<String, dynamic>?) ?? {});

      if (_useManual) {
        entry['manualOverride'] = true;
        entry['threads']        = int.tryParse(_threadsCtrl.text) ?? _auto.threads;
        entry['contextSize']    = int.tryParse(_ctxCtrl.text)     ?? _auto.contextSize;
        entry['gpuLayers']      = int.tryParse(_gpuLayersCtrl.text) ?? _auto.gpuLayers;
        entry['batchSize']      = int.tryParse(_batchCtrl.text)   ?? _auto.batchSize;
        entry['flashAttention'] = _flashAttention;
        entry['mmap']           = _mmap;
      } else {
        // Supprime les overrides → retour aux valeurs auto
        entry.remove('manualOverride');
        entry['threads']        = _auto.threads;
        entry['contextSize']    = _auto.contextSize;
        entry['gpuLayers']      = _auto.gpuLayers;
        entry['batchSize']      = _auto.batchSize;
        entry['flashAttention'] = _auto.flashAttention;
        entry['mmap']           = true;
      }

      aiConfig[widget.aiConfigId] = entry;
      await prefs.setString('aiConfig', jsonEncode(aiConfig));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres sauvegardés'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5),
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xff252526) : Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Paramètres avancés',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text('Sauvegarder', style: TextStyle(color: cs.primary)),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Modèle ciblé
          _buildModelCard(cs, dark),
          const SizedBox(height: 16),

          // Toggle mode manuel
          _buildManualModeToggle(cs, dark),
          const SizedBox(height: 16),

          // Valeurs auto calculées (toujours visibles pour référence)
          _buildAutoSummary(cs, dark),
          const SizedBox(height: 16),

          // Paramètres manuels (grisés si _useManual == false)
          _buildParamSection(cs, dark),
          const SizedBox(height: 16),

          // Booleans
          _buildBoolSection(cs, dark),
          const SizedBox(height: 16),

          // Explications
          _buildExplanations(cs, dark),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildModelCard(ColorScheme cs, bool dark) => Container(
    padding: const EdgeInsets.all(14),
    decoration: _cardDecoration(cs, dark),
    child: Row(
      children: [
        Icon(Icons.smart_toy_outlined, size: 22, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.modelEntry!.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.quant!.level}  ·  ${widget.quant!.sizeLabel}',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildManualModeToggle(ColorScheme cs, bool dark) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: _cardDecoration(cs, dark),
    child: Row(
      children: [
        Icon(
          _useManual ? Icons.tune : Icons.auto_awesome,
          size: 20,
          color: _useManual ? cs.primary : cs.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _useManual ? 'Mode manuel activé' : 'Mode automatique',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _useManual
                    ? 'Vos paramètres remplacent les valeurs auto-calculées.'
                    : 'Les paramètres sont calculés selon votre appareil.',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Switch(
          value: _useManual,
          onChanged: (v) => setState(() {
            _useManual = v;
            if (!v) _resetToAuto();
          }),
        ),
      ],
    ),
  );

  Widget _buildAutoSummary(ColorScheme cs, bool dark) {
    final summary = InferenceConfigService.summary(_auto, widget.profile!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Valeurs auto-calculées (référence)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...summary.map((line) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '• $line',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildParamSection(ColorScheme cs, bool dark) => Container(
    padding: const EdgeInsets.all(14),
    decoration: _cardDecoration(cs, dark),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paramètres numériques',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildIntField(
          label:    'n_threads',
          hint:     '1 – 16',
          ctrl:     _threadsCtrl,
          enabled:  _useManual,
          cs:       cs,
          help:     'Threads CPU alloués à llama.cpp',
        ),
        const SizedBox(height: 10),
        _buildIntField(
          label:   'n_ctx',
          hint:    '512 – 131072',
          ctrl:    _ctxCtrl,
          enabled: _useManual,
          cs:      cs,
          help:    'Taille de contexte (tokens)',
        ),
        const SizedBox(height: 10),
        _buildIntField(
          label:   'n_gpu_layers',
          hint:    '0 = auto, -1 = tout',
          ctrl:    _gpuLayersCtrl,
          enabled: _useManual,
          cs:      cs,
          help:    '0 = auto-détection GPU, -1 = toutes les couches sur GPU',
        ),
        const SizedBox(height: 10),
        _buildIntField(
          label:   'n_batch',
          hint:    '128 – 2048',
          ctrl:    _batchCtrl,
          enabled: _useManual,
          cs:      cs,
          help:    'Tokens traités en parallèle (prefill)',
        ),
      ],
    ),
  );

  Widget _buildBoolSection(ColorScheme cs, bool dark) => Container(
    padding: const EdgeInsets.all(14),
    decoration: _cardDecoration(cs, dark),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Options',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        _buildBoolRow(
          label:    'Flash Attention',
          subtext:  'Réduit la mémoire KV pour les longs contextes',
          value:    _flashAttention,
          enabled:  _useManual,
          onChanged: (v) => setState(() => _flashAttention = v),
          cs: cs,
        ),
        const Divider(height: 1, thickness: 0.5),
        _buildBoolRow(
          label:    'mmap (memory-mapped)',
          subtext:  'Chargement GGUF via mmap — recommandé',
          value:    _mmap,
          enabled:  _useManual,
          onChanged: (v) => setState(() => _mmap = v),
          cs: cs,
        ),
      ],
    ),
  );

  Widget _buildExplanations(ColorScheme cs, bool dark) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Conseils',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        ..._tips.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '• $t',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        )),
      ],
    ),
  );

  // ── Sous-widgets ──────────────────────────────────────────────────────────

  Widget _buildIntField({
    required String               label,
    required String               hint,
    required TextEditingController ctrl,
    required bool                 enabled,
    required ColorScheme          cs,
    required String               help,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: enabled ? cs.onSurface : cs.onSurfaceVariant,
              fontFamily: 'firaCode',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              help,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 38,
        child: TextField(
          controller:  ctrl,
          enabled:     enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 13,
            color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            fontFamily: 'firaCode',
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            filled:     true,
            fillColor:  enabled
                ? cs.surfaceContainerHighest
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            border:     OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:   BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
          ),
        ),
      ),
    ],
  );

  Widget _buildBoolRow({
    required String   label,
    required String   subtext,
    required bool     value,
    required bool     enabled,
    required void Function(bool) onChanged,
    required ColorScheme cs,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              Text(
                subtext,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Switch(
          value:     value,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    ),
  );

  BoxDecoration _cardDecoration(ColorScheme cs, bool dark) => BoxDecoration(
    color:        dark ? const Color(0xff252526) : Colors.white,
    borderRadius: BorderRadius.circular(10),
    border:       Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
  );

  static const _tips = [
    'n_threads : laisser 1-2 cœurs libres pour l\'UI Android évite les freezes.',
    'n_ctx > 8192 augmente la RAM nécessaire. Commencez par 4096.',
    'n_gpu_layers = 0 → LlamaController auto-détecte Vulkan. Mettez -1 pour forcer tout le GPU.',
    'Flash Attention est utile surtout avec n_ctx > 4096.',
    'mmap permet de charger le modèle sans copie mémoire — laissez activé.',
  ];
}
