/// LocalModelDetailPage — page de détail complète d'un modèle.
///
/// Affiche specs, compatibilité, quantizations, et lance le téléchargement.
/// Phase 3 : bouton "Utiliser dans Panda AI" + config d'inférence auto.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ai_model_entry.dart';
import '../models/device_profile.dart';
import '../services/model_download_manager.dart';
import '../services/inference_config_service.dart';
import '../services/model_activation_service.dart';

class LocalModelDetailPage extends StatefulWidget {
  final AiModelEntry  model;
  final DeviceProfile? profile;

  const LocalModelDetailPage({
    super.key,
    required this.model,
    required this.profile,
  });

  @override
  State<LocalModelDetailPage> createState() => _LocalModelDetailPageState();
}

class _LocalModelDetailPageState extends State<LocalModelDetailPage> {
  late ModelQuant? _selectedQuant;
  String _storage = 'internal'; // "internal" | "sdcard"
  bool   _activating = false;
  String? _activationMessage;

  StreamSubscription<DownloadTask>? _dlSub;

  @override
  void initState() {
    super.initState();
    _selectedQuant = widget.model.recommendedQuant(
      widget.profile?.totalRamGb ?? 4,
    );
    _dlSub = ModelDownloadManager.instance.updates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    super.dispose();
  }

  // ── Données dérivées ──────────────────────────────────────────────────────

  int get _ramGb => widget.profile?.totalRamGb ?? 4;
  AiModelEntry get m => widget.model;

  String get _taskId => _selectedQuant != null
      ? '${m.id}_${_selectedQuant!.level}'
      : '';

  DownloadTask? get _activeTask =>
      _taskId.isNotEmpty ? ModelDownloadManager.instance.getTask(_taskId) : null;

  bool get _isInstalled => _selectedQuant != null &&
      ModelDownloadManager.instance.isInstalled(m.id, _selectedQuant!.level);

  int get _compatScore => m.compatibilityScore(_ramGb);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg   = dark ? const Color(0xff1e1e1e) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xff252526) : const Color(0xfff5f5f5),
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          m.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHero(cs, dark),
          const SizedBox(height: 16),
          _buildSpecsCard(cs, dark),
          const SizedBox(height: 14),
          _buildCompatibility(cs),
          const SizedBox(height: 14),
          _buildDescription(cs, dark),
          const SizedBox(height: 14),
          _buildTags(cs),
          const SizedBox(height: 14),
          _buildQuantSelector(cs, dark),
          const SizedBox(height: 14),
          if (widget.profile?.sdCardFreeGb != null &&
              widget.profile!.sdCardFreeGb > 0)
            _buildStorageSelector(cs, dark),
          if (widget.profile?.sdCardFreeGb != null &&
              widget.profile!.sdCardFreeGb > 0)
            const SizedBox(height: 14),
          _buildStorageInfo(cs, dark),
          const SizedBox(height: 16),
          _buildActionButton(cs),
          const SizedBox(height: 8),
          _buildHFLink(cs),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(ColorScheme cs, bool dark) {
    final authorColor = _authorColor(m.author, cs);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: authorColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: authorColor.withValues(alpha: 0.3)),
          ),
          child: Icon(Icons.smart_toy_outlined, size: 28, color: authorColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'par ${m.author}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  ...List.generate(
                    5,
                    (i) => Text(
                      i < m.capabilities.codingScore ? '⭐' : '☆',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  if (m.capabilities.toolCalling)
                    _Chip(label: '🛠️ Tool Calling', cs: cs),
                  if (m.capabilities.vision)
                    _Chip(label: '👁️ Vision', cs: cs),
                  if (m.capabilities.reasoning)
                    _Chip(label: '🧠 Reasoning', cs: cs),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Specs card ────────────────────────────────────────────────────────────

  Widget _buildSpecsCard(ColorScheme cs, bool dark) {
    return _Card(
      cs: cs,
      dark: dark,
      child: Column(
        children: [
          _SpecRow(icon: Icons.storage,           label: 'Taille',           value: _selectedQuant?.sizeLabel ?? '—', cs: cs),
          _SpecRow(icon: Icons.compress,           label: 'Format',           value: 'GGUF ${_selectedQuant?.level ?? "—"}', cs: cs),
          _SpecRow(icon: Icons.chat_bubble_outline, label: 'Contexte',        value: m.capabilities.contextLabel, cs: cs),
          _SpecRow(icon: Icons.build_circle_outlined, label: 'Tool Calling',  value: m.capabilities.toolCalling ? '✅ Oui' : '❌ Non', cs: cs),
          _SpecRow(icon: Icons.image_outlined,    label: 'Vision',           value: m.capabilities.vision ? '✅ Oui' : '❌ Non', cs: cs),
          _SpecRow(icon: Icons.psychology_outlined, label: 'Raisonnement',   value: m.capabilities.reasoning ? '✅ Oui' : '❌ Non', cs: cs),
          _SpecRow(icon: Icons.memory,            label: 'RAM minimale',     value: '${m.capabilities.minRamGb} GB', cs: cs),
          _SpecRow(icon: Icons.hub_outlined,      label: 'Source',           value: 'bartowski / HuggingFace', cs: cs, last: true),
        ],
      ),
    );
  }

  // ── Compatibilité ─────────────────────────────────────────────────────────

  Widget _buildCompatibility(ColorScheme cs) {
    final score = _compatScore;
    final color = score >= 70 ? Colors.green
                : score >= 40 ? Colors.orange
                : cs.error;
    final label = score >= 70 ? '✅ Compatible'
                : score >= 40 ? '⚠️ Limité'
                : '❌ Insuffisant';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Compatibilité avec votre appareil',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            const Spacer(),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 6,
            backgroundColor: cs.outlineVariant.withValues(alpha: 0.25),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  // ── Description ───────────────────────────────────────────────────────────

  Widget _buildDescription(ColorScheme cs, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Description',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 6),
        Text(
          m.description,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.5),
        ),
      ],
    );
  }

  // ── Tags ──────────────────────────────────────────────────────────────────

  Widget _buildTags(ColorScheme cs) {
    if (m.tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: m.tags.map((t) => _Chip(label: t, cs: cs)).toList(),
    );
  }

  // ── Sélecteur de quantization ─────────────────────────────────────────────

  Widget _buildQuantSelector(ColorScheme cs, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quantizations disponibles',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 8),
        ...m.quantizations.map((q) {
          final selected  = _selectedQuant?.level == q.level;
          final compatible = q.minRamGb <= _ramGb;
          final installed = ModelDownloadManager.instance.isInstalled(m.id, q.level);

          return GestureDetector(
            onTap: compatible ? () => setState(() => _selectedQuant = q) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.12)
                    : dark ? const Color(0xff2d2d2d) : const Color(0xfff8f8f8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Radio<String>(
                    value: q.level,
                    groupValue: _selectedQuant?.level,
                    onChanged: compatible ? (v) => setState(() => _selectedQuant = q) : null,
                    activeColor: cs.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(q.level,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: compatible ? cs.onSurface : cs.onSurfaceVariant,
                                )),
                            const SizedBox(width: 6),
                            Text(q.sizeLabel,
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            const Spacer(),
                            if (installed)
                              _Chip(label: '✓ Installé', cs: cs, small: true),
                            if (!compatible)
                              _Chip(label: '${q.minRamGb}G min', cs: cs, small: true, error: true),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _quantDescription(q.level),
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _quantDescription(String level) {
    switch (level) {
      case 'Q2_K':   return 'Ultra léger — qualité réduite, très rapide';
      case 'Q3_K_M': return 'Léger — bonne vitesse, qualité acceptable';
      case 'Q4_K_S': return 'Léger — bon compromis vitesse/qualité';
      case 'Q4_K_M': return '⭐ Recommandé — excellent compromis';
      case 'Q5_K_M': return 'Haute qualité — proche du FP16';
      case 'Q6_K':   return 'Très haute qualité — lent sur CPU seul';
      case 'Q8_0':   return 'Quasi FP16 — RAM élevée requise';
      default:       return '';
    }
  }

  // ── Sélecteur de stockage ─────────────────────────────────────────────────

  Widget _buildStorageSelector(ColorScheme cs, bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Destination',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 8),
        Row(
          children: [
            _StorageOption(
              label: 'Stockage interne',
              sub: '${widget.profile?.internalFreeGb ?? "?"} GB libres',
              icon: Icons.phone_android,
              selected: _storage == 'internal',
              onTap: () => setState(() => _storage = 'internal'),
              cs: cs, dark: dark,
            ),
            const SizedBox(width: 8),
            _StorageOption(
              label: 'Carte SD',
              sub: '${widget.profile?.sdCardFreeGb ?? "?"} GB libres',
              icon: Icons.sd_card,
              selected: _storage == 'sdcard',
              onTap: () => setState(() => _storage = 'sdcard'),
              cs: cs, dark: dark,
            ),
          ],
        ),
      ],
    );
  }

  // ── Info stockage ─────────────────────────────────────────────────────────

  Widget _buildStorageInfo(ColorScheme cs, bool dark) {
    final freeGb = _storage == 'sdcard'
        ? (widget.profile?.sdCardFreeGb ?? 0)
        : (widget.profile?.internalFreeGb ?? 0);
    final sizeGb = _selectedQuant?.sizeGb ?? 0.0;
    final enough = freeGb >= sizeGb;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (enough ? Colors.green : cs.error).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (enough ? Colors.green : cs.error).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            enough ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            size: 16,
            color: enough ? Colors.green : cs.error,
          ),
          const SizedBox(width: 8),
          Text(
            enough
                ? 'Espace libre : $freeGb GB  ·  Requis : ${sizeGb.toStringAsFixed(1)} GB'
                : 'Espace insuffisant ($freeGb GB libres, ${sizeGb.toStringAsFixed(1)} GB requis)',
            style: TextStyle(
              fontSize: 11,
              color: enough ? Colors.green : cs.error,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bouton d'action ───────────────────────────────────────────────────────

  Widget _buildActionButton(ColorScheme cs) {
    final task = _activeTask;

    if (task != null &&
        (task.status == DownloadStatus.downloading ||
         task.status == DownloadStatus.verifying)) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 8,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                task.status == DownloadStatus.verifying
                    ? 'Vérif…'
                    : '${(task.progress * 100).round()}%',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                task.status == DownloadStatus.verifying
                    ? 'Vérification SHA256…'
                    : '${task.speedMbps.toStringAsFixed(1)} MB/s  ·  '
                      '${_remainingTime(task)} restantes',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ModelDownloadManager.instance.cancelDownload(_taskId);
                  setState(() {});
                },
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: const Text('Annuler', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      );
    }

    if (task != null && task.status == DownloadStatus.failed) {
      return Column(
        children: [
          Text(
            'Erreur : ${task.errorMessage ?? "Inconnue"}',
            style: TextStyle(fontSize: 11, color: cs.error),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          _MainButton(
            label: '↻ Réessayer',
            icon: Icons.refresh,
            onTap: () => ModelDownloadManager.instance.retryDownload(_taskId),
            cs: cs,
          ),
        ],
      );
    }

    if (_isInstalled) {
      return Column(
        children: [
          // Bouton principal : Utiliser dans Panda AI
          if (_activationMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _activationMessage!,
                      style: TextStyle(fontSize: 11, color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),

          if (widget.profile != null)
            _buildInferenceConfigPreview(cs),
          const SizedBox(height: 10),

          _MainButton(
            label: _activating
                ? 'Activation…'
                : '🧠  Utiliser dans Panda AI',
            icon: Icons.smart_toy_outlined,
            onTap: _activating ? null : () => _activateModel(cs),
            cs: cs,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MainButton(
                  label: '✓ Installé',
                  icon: Icons.check_circle_outline,
                  onTap: null,
                  cs: cs,
                  secondary: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MainButton(
                  label: 'Supprimer',
                  icon: Icons.delete_outline,
                  onTap: () async {
                    await ModelDownloadManager.instance
                        .deleteModel(m.id, _selectedQuant!.level);
                    setState(() {});
                  },
                  cs: cs,
                  danger: true,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final freeGb   = _storage == 'sdcard'
        ? (widget.profile?.sdCardFreeGb ?? 0)
        : (widget.profile?.internalFreeGb ?? 0);
    final sizeGb   = _selectedQuant?.sizeGb ?? 0.0;
    final enough   = freeGb >= sizeGb;
    final compat   = _compatScore > 0;
    final score    = _compatScore;

    // Colour coding
    //  ≥ 60 → vert (modèle bien adapté)
    //  1–59 → jaune (faisable mais limité)
    //  0    → rouge (RAM insuffisante) — triple-tap pour forcer
    if (!compat) {
      // RAM insuffisante — triple-tap pour installer quand même
      return _TripleTapDownloadButton(
        label: _selectedQuant != null
            ? '⬇️  Télécharger ${_selectedQuant!.level} (${_selectedQuant!.sizeLabel})'
            : 'Sélectionnez une quantization',
        warningLabel: '⚠️  RAM insuffisante — ${widget.profile?.totalRamGb ?? 0} GB détectés, '
            '${_selectedQuant?.minRamGb ?? 0} GB requis. Appuyez 3× pour forcer.',
        enabled: _selectedQuant != null,
        onConfirmed: _selectedQuant != null ? _startDownload : null,
        cs: cs,
      );
    }

    // Enough RAM — color based on score
    final btnColor = score >= 60 ? Colors.green[600]! : Colors.orange[700]!;
    final tooltip  = score >= 60
        ? '✅ Compatible — devrait tourner sans problème'
        : '⚠️ Faisable mais limité — performances réduites possibles';

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: (enough && _selectedQuant != null) ? _startDownload : null,
          icon: const Icon(Icons.download, size: 16),
          label: Text(
            _selectedQuant != null
                ? '⬇️  Télécharger ${_selectedQuant!.level} (${_selectedQuant!.sizeLabel})'
                : 'Sélectionnez une quantization',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: (enough && _selectedQuant != null) ? btnColor : cs.surfaceVariant,
            foregroundColor: (enough && _selectedQuant != null) ? Colors.white : cs.onSurfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildHFLink(ColorScheme cs) {
    return GestureDetector(
      onTap: () {
        // Ouvre la page HuggingFace (si webview dispo)
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.open_in_new, size: 12, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            'Voir sur Hugging Face',
            style: TextStyle(fontSize: 11, color: cs.primary),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _startDownload() {
    if (_selectedQuant == null) return;
    ModelDownloadManager.instance.startDownload(
      model:   m,
      quant:   _selectedQuant!,
      storage: _storage,
    );
    setState(() {});
  }

  // ── Activation dans Panda AI ───────────────────────────────────────────────

  Future<void> _activateModel(ColorScheme cs) async {
    if (_selectedQuant == null || widget.profile == null) return;
    setState(() { _activating = true; _activationMessage = null; });
    try {
      final result = await ModelActivationService.activate(
        modelEntry:   m,
        quantLevel:   _selectedQuant!.level,
        profile:      widget.profile!,
        setAsDefault: false,
      );
      if (!mounted) return;
      setState(() {
        _activating = false;
        _activationMessage = result.alreadyExisted
            ? 'Paramètres mis à jour dans Panda AI'
            : result.setAsDefault
                ? '${m.name} activé et sélectionné comme modèle de chat ✓'
                : '${m.name} ajouté à Panda AI ✓';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activating = false;
        _activationMessage = 'Erreur : $e';
      });
    }
  }

  // ── Aperçu config d'inférence ─────────────────────────────────────────────

  Widget _buildInferenceConfigPreview(ColorScheme cs) {
    if (_selectedQuant == null || widget.profile == null) {
      return const SizedBox.shrink();
    }
    final config = InferenceConfigService.compute(
      model:   m,
      quant:   _selectedQuant!,
      profile: widget.profile!,
    );
    final lines = InferenceConfigService.summary(config, widget.profile!);
    final dark  = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff2a2a2a) : const Color(0xfff2f6ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 13, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Config d\'inférence auto-calculée',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...lines.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Text('·  ', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                  Expanded(
                    child: Text(l,
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _remainingTime(DownloadTask task) {
    if (task.speedMbps <= 0) return '—';
    final remaining = (task.totalBytes - task.bytesDownloaded) / (1024 * 1024);
    final secs = (remaining / task.speedMbps).round();
    if (secs < 60)  return '$secs s';
    if (secs < 3600) return '${secs ~/ 60} min';
    return '${secs ~/ 3600} h';
  }

  Color _authorColor(String author, ColorScheme cs) {
    final a = author.toLowerCase();
    if (a.contains('qwen') || a.contains('alibaba')) return Colors.blue;
    if (a.contains('microsoft')) return Colors.indigo;
    if (a.contains('google'))    return Colors.green;
    if (a.contains('meta'))      return Colors.deepPurple;
    if (a.contains('mistral'))   return Colors.orange;
    if (a.contains('deepseek'))  return Colors.cyan;
    return cs.primary;
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final ColorScheme cs;
  final bool dark;
  final Widget child;
  const _Card({required this.cs, required this.dark, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: dark ? const Color(0xff2d2d2d) : const Color(0xfff8f8f8),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
    ),
    child: child,
  );
}

class _SpecRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final ColorScheme cs;
  final bool     last;
  const _SpecRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(value,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ],
          ),
        ),
        if (!last)
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.25),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  final bool small;
  final bool error;
  const _Chip({
    required this.label,
    required this.cs,
    this.small = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: small ? 5 : 7, vertical: small ? 1 : 3),
    decoration: BoxDecoration(
      color: (error ? cs.error : cs.primary).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(
          color: (error ? cs.error : cs.primary).withValues(alpha: 0.25)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: small ? 9 : 10,
        color: error ? cs.error : cs.primary,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _StorageOption extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool dark;

  const _StorageOption({
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.1)
              : dark ? const Color(0xff2d2d2d) : const Color(0xfff8f8f8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: cs.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── _TripleTapDownloadButton — bouton rouge pour RAM insuffisante ──────────────

class _TripleTapDownloadButton extends StatefulWidget {
  final String    label;
  final String    warningLabel;
  final bool      enabled;
  final VoidCallback? onConfirmed;
  final ColorScheme   cs;

  const _TripleTapDownloadButton({
    required this.label,
    required this.warningLabel,
    required this.enabled,
    required this.onConfirmed,
    required this.cs,
  });

  @override
  State<_TripleTapDownloadButton> createState() => _TripleTapDownloadButtonState();
}

class _TripleTapDownloadButtonState extends State<_TripleTapDownloadButton> {
  int _tapCount = 0;

  void _onTap() {
    if (!widget.enabled) return;
    setState(() => _tapCount++);
    if (_tapCount >= 3) {
      setState(() => _tapCount = 0);
      widget.onConfirmed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = 3 - _tapCount;
    final btnLabel  = _tapCount == 0
        ? widget.label
        : 'Encore $remaining appui${remaining > 1 ? "s" : ""} pour confirmer…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.cs.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.cs.error.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: widget.cs.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.warningLabel,
                  style: TextStyle(fontSize: 11, color: widget.cs.error, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: widget.enabled ? _onTap : null,
            icon: const Icon(Icons.download, size: 16),
            label: Text(btnLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.enabled ? widget.cs.error : widget.cs.surfaceVariant,
              foregroundColor: widget.enabled ? Colors.white : widget.cs.onSurfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MainButton extends StatelessWidget {
  final String   label;
  final IconData icon;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final bool secondary;
  final bool danger;

  const _MainButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.cs,
    this.secondary = false,
    this.danger    = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? cs.error : secondary ? cs.outline : cs.primary;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: onTap != null ? color : cs.surfaceVariant,
          foregroundColor: onTap != null
              ? (danger || secondary ? Colors.white : cs.onPrimary)
              : cs.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    );
  }
}
