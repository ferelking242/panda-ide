/// LruCacheService — Cache LRU + nettoyage automatique des modèles GGUF.
///
/// Fonctionnalités :
///   • Mise à jour de `lastUsedAt` à chaque activation d'un modèle.
///   • Seuil de nettoyage configurable (max storage GB + jours non-utilisés).
///   • Candidates LRU triées pour libérer de l'espace intelligemment.
///   • Nettoyage auto déclenché au démarrage et à chaque téléchargement terminé.
library;

import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_model_entry.dart';
import 'model_download_manager.dart';

// ── Constantes ────────────────────────────────────────────────────────────────

const _kLruSettingsKey = 'panda_lru_settings_v1';

// ── Paramètres LRU configurables ──────────────────────────────────────────────

class LruSettings {
  /// Nombre maximum de jours sans utilisation avant qu'un modèle soit éligible au nettoyage.
  final int maxDaysUnused;

  /// Seuil de stockage (GB) en dessous duquel le nettoyage auto se déclenche.
  final double cleanupThresholdGb;

  /// Activer le nettoyage automatique.
  final bool autoCleanupEnabled;

  const LruSettings({
    this.maxDaysUnused       = 30,
    this.cleanupThresholdGb  = 2.0,
    this.autoCleanupEnabled  = true,
  });

  LruSettings copyWith({
    int?    maxDaysUnused,
    double? cleanupThresholdGb,
    bool?   autoCleanupEnabled,
  }) => LruSettings(
    maxDaysUnused:      maxDaysUnused      ?? this.maxDaysUnused,
    cleanupThresholdGb: cleanupThresholdGb ?? this.cleanupThresholdGb,
    autoCleanupEnabled: autoCleanupEnabled ?? this.autoCleanupEnabled,
  );

  Map<String, dynamic> toJson() => {
    'max_days_unused':      maxDaysUnused,
    'cleanup_threshold_gb': cleanupThresholdGb,
    'auto_cleanup_enabled': autoCleanupEnabled,
  };

  factory LruSettings.fromJson(Map<String, dynamic> j) => LruSettings(
    maxDaysUnused:      j['max_days_unused']      as int?    ?? 30,
    cleanupThresholdGb: (j['cleanup_threshold_gb'] as num?)?.toDouble() ?? 2.0,
    autoCleanupEnabled: j['auto_cleanup_enabled']  as bool?  ?? true,
  );
}

// ── Candidat LRU ──────────────────────────────────────────────────────────────

class LruCandidate {
  final InstalledModel model;
  final int             daysUnused;
  final bool            isEligible; // daysUnused >= maxDaysUnused

  const LruCandidate({
    required this.model,
    required this.daysUnused,
    required this.isEligible,
  });

  String get label => '${model.modelId} ${model.quantLevel}';
  String get sizeLabel {
    if (model.sizeGb >= 1) return '${model.sizeGb.toStringAsFixed(1)} GB';
    return '${(model.sizeGb * 1024).round()} MB';
  }

  String get lastUsedLabel {
    if (daysUnused == 0) return 'utilisé aujourd\'hui';
    if (daysUnused == 1) return 'utilisé hier';
    return 'utilisé il y a $daysUnused jours';
  }
}

// ── Résultat du nettoyage ──────────────────────────────────────────────────────

class CleanupResult {
  final int    deletedCount;
  final double freedGb;
  final List<String> deletedIds;

  const CleanupResult({
    required this.deletedCount,
    required this.freedGb,
    required this.deletedIds,
  });

  bool get anyDeleted => deletedCount > 0;

  @override
  String toString() =>
      'CleanupResult(deleted=$deletedCount, freed=${freedGb.toStringAsFixed(1)} GB)';
}

// ── Service ───────────────────────────────────────────────────────────────────

class LruCacheService {
  LruCacheService._();
  static final LruCacheService instance = LruCacheService._();

  LruSettings _settings = const LruSettings();

  // ── Persistance des settings ───────────────────────────────────────────────

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kLruSettingsKey);
    if (raw != null) {
      try {
        _settings = LruSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
  }

  Future<void> saveSettings(LruSettings settings) async {
    _settings = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLruSettingsKey, jsonEncode(settings.toJson()));
  }

  LruSettings get settings => _settings;

  // ── Touch (mise à jour lastUsedAt) ────────────────────────────────────────

  /// Appeler à chaque fois qu'un modèle est activé / utilisé.
  Future<void> touch(String modelId, String quantLevel) async {
    final list = ModelDownloadManager.instance.getInstalled(modelId);
    for (final m in list) {
      if (m.quantLevel == quantLevel) {
        m.lastUsedAt = DateTime.now();
      }
    }
    // Persiste l'index mis à jour
    await ModelDownloadManager.instance.persistInstalledIndex();
  }

  // ── Candidats LRU ─────────────────────────────────────────────────────────

  /// Retourne tous les modèles installés triés du moins récemment utilisé au plus récent.
  List<LruCandidate> getCandidates() {
    final now    = DateTime.now();
    final models = ModelDownloadManager.instance.allInstalled;

    final candidates = models.map((m) {
      final days = now.difference(m.lastUsedAt).inDays;
      return LruCandidate(
        model:      m,
        daysUnused: days,
        isEligible: days >= _settings.maxDaysUnused,
      );
    }).toList()
      ..sort((a, b) => b.daysUnused.compareTo(a.daysUnused)); // plus vieux en premier

    return candidates;
  }

  /// Retourne uniquement les candidats éligibles (daysUnused >= maxDaysUnused).
  List<LruCandidate> getEligibleCandidates() =>
      getCandidates().where((c) => c.isEligible).toList();

  // ── Stockage libre ────────────────────────────────────────────────────────

  Future<double> _freeStorageGb(String path) async {
    try {
      final result = await Process.run('df', ['-k', path]);
      // Ligne 2 : Filesystem  Size  Used  Avail  Use%  Mounted
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length >= 2) {
        final parts = lines[1].trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final availKb = int.tryParse(parts[3]) ?? 0;
          return availKb / (1024 * 1024); // → GB
        }
      }
    } catch (_) {}
    return 10.0; // fallback conservateur
  }

  Future<double> get internalFreeGb =>
      _freeStorageGb('/data/data/com.panda.ide');

  // ── Nettoyage automatique ─────────────────────────────────────────────────

  /// Déclenché au démarrage et après chaque téléchargement.
  /// Ne supprime que les modèles éligibles LRU si l'espace libre < seuil.
  Future<CleanupResult?> runAutoCleanup() async {
    if (!_settings.autoCleanupEnabled) return null;
    await loadSettings();

    final freeGb = await internalFreeGb;
    if (freeGb >= _settings.cleanupThresholdGb) return null; // assez d'espace

    final candidates = getEligibleCandidates();
    if (candidates.isEmpty) return null;

    return _deleteUntilFree(candidates, freeGb);
  }

  /// Nettoyage manuel : supprime les modèles fournis.
  Future<CleanupResult> cleanupSelected(List<LruCandidate> selected) async {
    double freed    = 0;
    int    deleted  = 0;
    final  ids      = <String>[];

    for (final c in selected) {
      try {
        await ModelDownloadManager.instance
            .deleteModel(c.model.modelId, c.model.quantLevel);
        freed   += c.model.sizeGb;
        deleted++;
        ids.add('${c.model.modelId}/${c.model.quantLevel}');
      } catch (_) {}
    }

    return CleanupResult(
      deletedCount: deleted,
      freedGb:      freed,
      deletedIds:   ids,
    );
  }

  // ── Interne ───────────────────────────────────────────────────────────────

  Future<CleanupResult> _deleteUntilFree(
      List<LruCandidate> candidates, double currentFreeGb) async {
    double freed    = 0;
    int    deleted  = 0;
    final  ids      = <String>[];
    double freeGb   = currentFreeGb;

    for (final c in candidates) {
      if (freeGb + freed >= _settings.cleanupThresholdGb) break;
      try {
        await ModelDownloadManager.instance
            .deleteModel(c.model.modelId, c.model.quantLevel);
        freed   += c.model.sizeGb;
        deleted++;
        ids.add('${c.model.modelId}/${c.model.quantLevel}');
      } catch (_) {}
    }

    return CleanupResult(
      deletedCount: deleted,
      freedGb:      freed,
      deletedIds:   ids,
    );
  }

  // ── Résumé du stockage utilisé par les modèles ───────────────────────────

  double get totalInstalledGb => ModelDownloadManager.instance.allInstalled
      .fold(0.0, (sum, m) => sum + m.sizeGb);

  int get totalInstalledCount =>
      ModelDownloadManager.instance.allInstalled.length;
}
