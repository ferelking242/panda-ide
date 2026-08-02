/// Registre des extensions installées.
/// Persiste via SharedPreferences, gère l'état enable/disable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/extension_manifest.dart';

enum ExtensionState { enabled, disabled, installing, error }

class InstalledExtension {
  final ExtensionManifest manifest;
  final String installPath; // chemin absolu vers le dossier extrait du .vsix
  ExtensionState state;
  String? errorMessage;

  InstalledExtension({
    required this.manifest,
    required this.installPath,
    this.state = ExtensionState.enabled,
    this.errorMessage,
  });

  bool get isEnabled => state == ExtensionState.enabled;
  bool get isRunnable =>
      isEnabled && manifest.hasRunnableEntryPoint && !manifest.requiresNativeBinaries;

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'installPath': installPath,
    'state': state.name,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  factory InstalledExtension.fromJson(Map<String, dynamic> json) {
    final stateStr = json['state'] as String? ?? 'enabled';
    return InstalledExtension(
      manifest: ExtensionManifest.fromJson(
          json['manifest'] as Map<String, dynamic>),
      installPath: json['installPath'] as String,
      state: ExtensionState.values.firstWhere(
        (e) => e.name == stateStr,
        orElse: () => ExtensionState.enabled,
      ),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// Singleton qui gère le catalogue des extensions installées.
class ExtensionRegistry {
  static const _prefsKey = 'panda_extensions_registry';
  static final ExtensionRegistry instance = ExtensionRegistry._();
  ExtensionRegistry._();

  final Map<String, InstalledExtension> _extensions = {};
  bool _loaded = false;

  // ── Lecture ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final item in list) {
        try {
          final ext = InstalledExtension.fromJson(item);
          // Vérifier que le dossier d'installation existe encore
          if (Directory(ext.installPath).existsSync()) {
            _extensions[ext.manifest.id] = ext;
          }
        } catch (e) {
          // Extension corrompue → on ignore silencieusement
        }
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _extensions.values.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  // ── Accès ────────────────────────────────────────────────────────────────

  List<InstalledExtension> get all {
    _assertLoaded();
    return _extensions.values.toList();
  }

  List<InstalledExtension> get enabled {
    _assertLoaded();
    return _extensions.values.where((e) => e.isEnabled).toList();
  }

  List<InstalledExtension> get runnable {
    _assertLoaded();
    return _extensions.values.where((e) => e.isRunnable).toList();
  }

  InstalledExtension? get(String id) => _extensions[id];

  bool isInstalled(String id) => _extensions.containsKey(id);

  /// Returns the ids of all installed extensions.
  List<String> allInstalled() => _extensions.keys.toList();

  // ── Mutations ────────────────────────────────────────────────────────────

  Future<void> register(InstalledExtension ext) async {
    _extensions[ext.manifest.id] = ext;
    await _save();
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final ext = _extensions[id];
    if (ext == null) return;
    ext.state = enabled ? ExtensionState.enabled : ExtensionState.disabled;
    await _save();
  }

  Future<void> setError(String id, String message) async {
    final ext = _extensions[id];
    if (ext == null) return;
    ext.state = ExtensionState.error;
    ext.errorMessage = message;
    await _save();
  }

  Future<void> unregister(String id) async {
    _extensions.remove(id);
    await _save();
  }

  // ── Requêtes utilitaires ─────────────────────────────────────────────────

  /// Extensions à activer pour un langage donné.
  List<InstalledExtension> forLanguage(String languageId) {
    return runnable
        .where((e) =>
            e.manifest.activationEvents.activatesForLanguage(languageId))
        .toList();
  }

  /// Extensions à activer pour une commande donnée.
  List<InstalledExtension> forCommand(String commandId) {
    return runnable
        .where((e) =>
            e.manifest.activationEvents.activatesForCommand(commandId))
        .toList();
  }

  /// Extensions qui s'activent au démarrage.
  List<InstalledExtension> get startupExtensions =>
      runnable.where((e) => e.manifest.activationEvents.activatesOnStartup).toList();

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _assertLoaded() {
    assert(_loaded, 'ExtensionRegistry.load() must be called before accessing extensions.');
  }

  /// Chemin racine pour toutes les extensions installées.
  static Future<String> extensionsRoot() async {
    // On utilise le dossier de données de l'app Android
    // getApplicationDocumentsDirectory() n'est pas importé ici pour rester
    // sans dépendance path_provider — le chemin est passé depuis main.dart.
    throw UnimplementedError(
        'Call ExtensionRegistry.setRoot() from main.dart with getApplicationDocumentsDirectory()');
  }

  static String? _root;
  static void setRoot(String path) => _root = path;

  /// Chemin d'installation pour une extension donnée.
  static String installPathFor(String extensionId, String version) {
    assert(_root != null, 'Call ExtensionRegistry.setRoot() first.');
    return p.join(_root!, 'extensions', '$extensionId-$version');
  }
}
