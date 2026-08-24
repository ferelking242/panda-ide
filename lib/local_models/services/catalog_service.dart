/// CatalogService — charge et maintient le catalogue des modèles IA locaux.
///
/// Stratégie :
///   1. Charge le catalogue bundlé (assets/local_models_catalog.json) comme fallback.
///   2. Tente de mettre à jour depuis l'URL distante (GitHub raw).
///   3. Met en cache le catalogue distant dans SharedPreferences.
///   4. Expose le catalogue final (distant si dispo, bundlé sinon).
library;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_model_entry.dart';



class CatalogService {
  static const _kPrefsKey    = 'panda_model_catalog_v1';
  static const _kVersionKey  = 'panda_model_catalog_version_v1';
  static const _kRemoteUrl   =
      'https://raw.githubusercontent.com/ferelking242/panda-ide/main/assets/local_models_catalog.json';

  static ModelCatalog? _cached;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Retourne le catalogue (cache mémoire → cache prefs → bundlé).
  /// Lance une mise à jour en background si le cache a plus de 24h.
  static Future<ModelCatalog> load() async {
    if (_cached != null) return _cached!;

    final prefs   = await SharedPreferences.getInstance();
    final stored  = prefs.getString(_kPrefsKey);

    if (stored != null) {
      try {
        _cached = ModelCatalog.fromJson(
            Map<String, dynamic>.from(jsonDecode(stored) as Map));
        _updateInBackground(prefs);
        return _cached!;
      } catch (_) {/* cache corrompu */}
    }

    // Premier lancement : charge le bundlé
    _cached = await _loadBundled();
    _updateInBackground(prefs);
    return _cached!;
  }

  /// Force un rechargement depuis le réseau.
  static Future<ModelCatalog> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final fresh = await _fetchRemote();
    if (fresh != null) {
      _cached = fresh;
      await prefs.setString(_kPrefsKey, jsonEncode(_rawJson(fresh)));
      await prefs.setString(_kVersionKey, fresh.version);
    }
    return _cached ?? await _loadBundled();
  }

  /// Invalide le cache mémoire (utile après une mise à jour).
  static void invalidate() => _cached = null;

  // ── Privé ──────────────────────────────────────────────────────────────────

  static Future<ModelCatalog> _loadBundled() async {
    try {
      final raw = await rootBundle.loadString('assets/local_models_catalog.json');
      return ModelCatalog.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (e) {
      // Catalogue vide de secours absolu
      return ModelCatalog(
        version:   '0',
        fetchedAt: DateTime.now(),
        models:    [],
      );
    }
  }

  static void _updateInBackground(SharedPreferences prefs) {
    // Lance sans await intentionnellement
    _fetchRemote().then((fresh) async {
      if (fresh == null) return;
      final oldVersion = prefs.getString(_kVersionKey) ?? '0';
      if (fresh.version != oldVersion) {
        _cached = fresh;
        await prefs.setString(_kPrefsKey, jsonEncode(_rawJson(fresh)));
        await prefs.setString(_kVersionKey, fresh.version);
      }
    }).catchError((_) {/* pas de réseau — on garde le bundlé */});
  }

  static Future<ModelCatalog?> _fetchRemote() async {
    try {
      final resp = await http
          .get(Uri.parse(_kRemoteUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return ModelCatalog.fromJson(
            Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
      }
    } catch (_) {}
    return null;
  }

  /// Reconstruit le JSON brut depuis un ModelCatalog pour le cache prefs.
  static Map<String, dynamic> _rawJson(ModelCatalog c) => {
    'version': c.version,
    'models': c.models
        .map((m) => {
              'id':          m.id,
              'name':        m.name,
              'author':      m.author,
              'hf_repo':     m.hfRepo,
              'description': m.description,
              'categories':  m.categories,
              'tags':        m.tags,
              'released_at': m.releasedAt?.toIso8601String(),
              'capabilities': {
                'tool_calling':   m.capabilities.toolCalling,
                'vision':         m.capabilities.vision,
                'reasoning':      m.capabilities.reasoning,
                'context_length': m.capabilities.contextLength,
                'coding_score':   m.capabilities.codingScore,
                'min_ram_gb':     m.capabilities.minRamGb,
              },
              'quantizations': m.quantizations
                  .map((q) => {
                        'level':       q.level,
                        'size_gb':     q.sizeGb,
                        'hf_filename': q.hfFilename,
                        'sha256':      q.sha256,
                        'min_ram_gb':  q.minRamGb,
                      })
                  .toList(),
            })
        .toList(),
  };
}
