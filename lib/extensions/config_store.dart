/// ConfigStore — vscode.workspace.getConfiguration() — Phase 3.
///
/// Stocke la config par extension (section = ID extension ou namespace VSCode).
/// Persisté via SharedPreferences sous la clé "ext_config_<section>".
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

library;



// ── ConfigStore ───────────────────────────────────────────────────────────

class ConfigStore {
  static final ConfigStore instance = ConfigStore._();
  ConfigStore._();

  /// Cache in-mémoire : section → { key: value }
  final Map<String, Map<String, dynamic>> _cache = {};

  static const _prefix = 'ext_config_';

  // ── Initialisation (appeler une fois au démarrage) ────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final keys  = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      final section = key.substring(_prefix.length);
      final raw     = prefs.getString(key);
      if (raw != null) {
        try {
          _cache[section] = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {}
      }
    }
  }

  // ── get ───────────────────────────────────────────────────────────────────

  dynamic get(String? section, String key, dynamic defaultValue) {
    final resolved = _resolveSection(section, key);
    return _cache[resolved.section]?[resolved.key] ?? defaultValue;
  }

  // ── update ────────────────────────────────────────────────────────────────

  Future<void> update(
      String? section, String key, dynamic value, int? target) async {
    final resolved = _resolveSection(section, key);
    _cache.putIfAbsent(resolved.section, () => {});
    if (value == null) {
      _cache[resolved.section]!.remove(resolved.key);
    } else {
      _cache[resolved.section]![resolved.key] = value;
    }
    await _persist(resolved.section);
  }

  // ── getSectionProxy ───────────────────────────────────────────────────────
  /// Retourne une Map JSON sérialisable représentant la config d'une section.
  /// Le runtime JS l'utilise pour reconstruire WorkspaceConfiguration.
  Map<String, dynamic> getSectionProxy(String? section) {
    final s     = section ?? '';
    final items = Map<String, dynamic>.from(_cache[s] ?? {});
    return {
      'section': s,
      'items': items,
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  _Resolved _resolveSection(String? section, String key) {
    // Si la key contient un point (ex: 'editor.fontSize'), le premier segment
    // devient la section si aucune section n'est fournie.
    if (section != null && section.isNotEmpty) {
      return _Resolved(section, key);
    }
    final dot = key.indexOf('.');
    if (dot > 0) {
      return _Resolved(key.substring(0, dot), key.substring(dot + 1));
    }
    return _Resolved('', key);
  }

  Future<void> _persist(String section) async {
    final prefs = await SharedPreferences.getInstance();
    final data  = jsonEncode(_cache[section] ?? {});
    await prefs.setString('$_prefix$section', data);
  }
}

class _Resolved {
  final String section;
  final String key;
  const _Resolved(this.section, this.key);
}
