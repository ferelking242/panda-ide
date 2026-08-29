/// LocalModelsPage — Marketplace des modèles IA locaux.
///
/// Affiche des piles (stacks) horizontales de tuiles par catégorie.
/// Chaque tuile ouvre la page de détail du modèle.
library;
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ai_model_entry.dart';
import '../models/device_profile.dart';
import '../services/catalog_service.dart';
import '../services/device_profiler.dart';
import '../services/model_download_manager.dart';
import 'local_model_detail_page.dart';
import 'lru_manager_page.dart';
import 'advanced_inference_settings_page.dart';



// ── Définition des piles ──────────────────────────────────────────────────────

class _StackDef {
  final String label;
  final String emoji;
  final String category;   // "" = recommandés (filtre par score)
  final String description;

  const _StackDef({
    required this.label,
    required this.emoji,
    required this.category,
    required this.description,
  });
}

const _kStacks = [
  _StackDef(label: 'Recommandés',   emoji: '⭐', category: '__recommended__', description: 'Filtrés pour votre appareil'),
  _StackDef(label: 'Coding',        emoji: '💻', category: 'coding',          description: 'Complétion & génération de code'),
  _StackDef(label: 'Raisonnement',  emoji: '🧠', category: 'reasoning',       description: 'Logique, maths, chain-of-thought'),
  _StackDef(label: 'Général',       emoji: '🌍', category: 'general',         description: 'Chat, résumé, traduction'),
  _StackDef(label: 'Vision',        emoji: '👁️', category: 'vision',          description: 'Analyse d\'images & screenshots'),
  _StackDef(label: 'Tool Calling',  emoji: '🛠️', category: 'tool_calling',    description: 'Agents & appels de fonctions'),
  _StackDef(label: 'Légers <2 GB',  emoji: '📱', category: '__light__',       description: 'Pour appareils avec peu de RAM'),
  _StackDef(label: 'Nouveautés',    emoji: '🆕', category: '__new__',         description: 'Sorties dans les 30 derniers jours'),
];

// ══════════════════════════════════════════════════════════════════════════════
// LocalModelsPage
// ══════════════════════════════════════════════════════════════════════════════

class LocalModelsPage extends StatefulWidget {
  final bool embedded;
  const LocalModelsPage({super.key, this.embedded = false});

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage> {
  ModelCatalog?   _catalog;
  DeviceProfile?  _profile;
  bool            _loading  = true;
  String?         _error;

  StreamSubscription<DownloadTask>? _dlSub;

  @override
  void initState() {
    super.initState();
    _load();
    _dlSub = ModelDownloadManager.instance.updates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        CatalogService.load(),
        DeviceProfiler.load(),
        ModelDownloadManager.instance.init(),
      ]);
      _catalog = results[0] as ModelCatalog;
      _profile = results[1] as DeviceProfile;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return _buildLoading(cs);
    }
    if (_error != null) {
      return _buildError(cs);
    }

    return Column(
      children: [
        _buildHeader(cs, dark),
        if (_profile != null) _buildDeviceBanner(cs, dark),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _kStacks.length,
              itemBuilder: (_, i) => _buildStack(_kStacks[i], cs, dark),
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme cs, bool dark) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5),
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'Local Models',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.speed, size: 17, color: cs.onSurfaceVariant),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LruManagerPage(),
            )),
            tooltip: 'Cache LRU',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.tune, size: 17, color: cs.onSurfaceVariant),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdvancedInferenceSettingsPage(),
            )),
            tooltip: 'Paramètres avancés d\'inférence',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 17, color: cs.onSurfaceVariant),
            onPressed: _load,
            tooltip: 'Actualiser le catalogue',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ── Bannière device ───────────────────────────────────────────────────────

  Widget _buildDeviceBanner(ColorScheme cs, bool dark) {
    final p = _profile!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.cpuArch}  ·  ${p.totalRamGb} GB RAM  ·  ${p.performanceLabel}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  'Modèles jusqu\'à ${p.recommendedMaxModelSizeGb} GB · ${p.recommendedQuant}'
                  '${p.gpuOffloadAvailable ? " · GPU offload ✅" : ""}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Score bar
          Column(
            children: [
              Text(
                '${p.performanceScore}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.primary),
              ),
              Text('/100', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stack section ─────────────────────────────────────────────────────────

  Widget _buildStack(_StackDef def, ColorScheme cs, bool dark) {
    final models = _getModels(def);
    if (models.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Row(
            children: [
              Text(def.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(
                def.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                def.description,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: models.length,
            itemBuilder: (_, i) => _ModelTile(
              model:   models[i],
              profile: _profile,
              onTap: () => _openDetail(models[i]),
            ),
          ),
        ),
      ],
    );
  }

  List<AiModelEntry> _getModels(_StackDef def) {
    final cat = _catalog!;
    final ram = _profile?.totalRamGb ?? 4;

    switch (def.category) {
      case '__recommended__':
        return cat.recommended(ram).take(8).toList();
      case '__light__':
        return cat.models.where((m) {
          final q = m.recommendedQuant(ram);
          return q != null && q.sizeGb < 2.0;
        }).toList();
      case '__new__':
        return cat.newModels;
      default:
        return cat.forCategory(def.category);
    }
  }

  void _openDetail(AiModelEntry model) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LocalModelDetailPage(
        model:   model,
        profile: _profile,
      ),
    ));
  }

  // ── Loading / Error ───────────────────────────────────────────────────────

  Widget _buildLoading(ColorScheme cs) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 12),
        Text('Chargement du catalogue…', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ],
    ),
  );

  Widget _buildError(ColorScheme cs) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: cs.error, size: 40),
        const SizedBox(height: 10),
        Text('Erreur de chargement', style: TextStyle(color: cs.error, fontSize: 13)),
        const SizedBox(height: 4),
        Text(_error ?? '', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        const SizedBox(height: 14),
        ElevatedButton(onPressed: _load, child: const Text('Réessayer')),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// _ModelTile — tuile individuelle dans une pile
// ══════════════════════════════════════════════════════════════════════════════

class _ModelTile extends StatelessWidget {
  final AiModelEntry  model;
  final DeviceProfile? profile;
  final VoidCallback  onTap;

  const _ModelTile({
    required this.model,
    required this.profile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final dark      = Theme.of(context).brightness == Brightness.dark;
    final ram       = profile?.totalRamGb ?? 4;
    final quant     = model.recommendedQuant(ram);
    final compat    = model.compatibilityScore(ram);
    final installed = quant != null &&
        ModelDownloadManager.instance.isInstalled(model.id, quant.level);
    final taskId    = quant != null ? '${model.id}_${quant.level}' : null;
    final task      = taskId != null
        ? ModelDownloadManager.instance.getTask(taskId)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dark ? const Color(0xff252526) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: installed
                ? cs.primary.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icône + badge
            Row(
              children: [
                _ModelIcon(authorColor: _authorColor(model.author, cs)),
                const Spacer(),
                if (installed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('✓', style: TextStyle(fontSize: 10, color: cs.primary)),
                  ),
                if (model.isNew && !installed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('NEW', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Nom
            Text(
              model.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),

            // Auteur
            Text(
              model.author,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            // Taille + RAM
            if (quant != null)
              Row(
                children: [
                  Icon(Icons.storage, size: 10, color: cs.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(quant.sizeLabel, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Icon(Icons.memory, size: 10, color: cs.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text('${model.capabilities.minRamGb}G',
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ],
              ),
            const SizedBox(height: 6),

            // Badges capacités
            _CapBadges(model: model, cs: cs),
            const SizedBox(height: 8),

            // Progression ou bouton
            if (task != null &&
                (task.status == DownloadStatus.downloading ||
                 task.status == DownloadStatus.verifying))
              _ProgressBar(task: task, cs: cs)
            else
              _DownloadBtn(
                installed: installed,
                compat: compat,
                cs: cs,
                onTap: onTap,
              ),
          ],
        ),
      ),
    );
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

// ── Icône modèle ──────────────────────────────────────────────────────────────

class _ModelIcon extends StatelessWidget {
  final Color authorColor;
  const _ModelIcon({required this.authorColor});

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: authorColor.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: authorColor.withValues(alpha: 0.3)),
    ),
    child: Icon(Icons.smart_toy_outlined, size: 17, color: authorColor),
  );
}

// ── Badges capacités ──────────────────────────────────────────────────────────

class _CapBadges extends StatelessWidget {
  final AiModelEntry model;
  final ColorScheme  cs;
  const _CapBadges({required this.model, required this.cs});

  @override
  Widget build(BuildContext context) {
    final badges = <String>[];
    if (model.capabilities.toolCalling) badges.add('🛠️');
    if (model.capabilities.vision)      badges.add('👁️');
    if (model.capabilities.reasoning)   badges.add('🧠');
    if (model.capabilities.codingScore >= 4) badges.add('💻');

    if (badges.isEmpty) return const SizedBox.shrink();

    return Row(
      children: badges
          .map((b) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Text(b, style: const TextStyle(fontSize: 11)),
              ))
          .toList(),
    );
  }
}

// ── Barre de progression ──────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final DownloadTask task;
  final ColorScheme  cs;
  const _ProgressBar({required this.task, required this.cs});

  @override
  Widget build(BuildContext context) {
    final pct = (task.progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: task.progress,
            minHeight: 3,
            backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          task.status == DownloadStatus.verifying
              ? 'Vérification…'
              : '$pct%  ${task.speedMbps.toStringAsFixed(1)} MB/s',
          style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ── Bouton téléchargement ─────────────────────────────────────────────────────

class _DownloadBtn extends StatelessWidget {
  final bool        installed;
  final int         compat;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _DownloadBtn({
    required this.installed,
    required this.compat,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (installed) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 12, color: cs.primary),
          const SizedBox(width: 4),
          Text('Installé', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600)),
        ],
      );
    }

    final incompatible = compat == 0;
    return SizedBox(
      width: double.infinity,
      height: 26,
      child: ElevatedButton(
        onPressed: incompatible ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: incompatible ? cs.surfaceContainerHighest : cs.primary,
          foregroundColor: incompatible ? cs.onSurfaceVariant : cs.onPrimary,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        child: Text(
          incompatible ? 'RAM insuffisante' : 'Télécharger',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
