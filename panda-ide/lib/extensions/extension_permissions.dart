/// Système de permissions des extensions Panda IDE.
///
/// Deux familles :
///   1. Permissions SANDBOX IDE (terminal, network, storage…) — accordées
///      après consentement à l'installation, persistées localement.
///   2. Permissions TÉLÉPHONE (clipboard, camera, microphone, location…) —
///      déclenchent la vraie permission runtime Android via platform channel,
///      avec dialog de rationale avant (pattern Google Play).
///
/// Toutes les demandes passent par [ExtensionPermissionManager] :
/// les extensions n'obtiennent JAMAIS un accès direct aux APIs sensibles.
library;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';




// ═══════════════════════════════════════════════════════════════
// MODÈLE
// ═══════════════════════════════════════════════════════════════

enum PermissionScope { ideSandbox, phone }

enum PandaPermission {
  // Sandbox IDE
  terminal(PermissionScope.ideSandbox, 'Terminal',
      'Exécuter des commandes dans le terminal intégré'),
  network(PermissionScope.ideSandbox, 'Réseau',
      'Effectuer des requêtes réseau'),
  storage(PermissionScope.ideSandbox, 'Stockage IDE',
      'Lire/écrire dans le dossier de travail'),
  notifications(PermissionScope.ideSandbox, 'Notifications',
      'Afficher des notifications dans l\'IDE'),

  // Téléphone (runtime Android)
  clipboard(PermissionScope.phone, 'Presse-papiers',
      'Lire et écrire le presse-papiers du téléphone',
      androidPermission: 'android.permission.READ_CLIPBOARD'),
  camera(PermissionScope.phone, 'Caméra',
      'Utiliser la caméra du téléphone',
      androidPermission: 'android.permission.CAMERA'),
  microphone(PermissionScope.phone, 'Microphone',
      'Enregistrer l\'audio du microphone',
      androidPermission: 'android.permission.RECORD_AUDIO'),
  location(PermissionScope.phone, 'Localisation',
      'Accéder à la position de l\'appareil',
      androidPermission: 'android.permission.ACCESS_FINE_LOCATION'),
  contacts(PermissionScope.phone, 'Contacts',
      'Lire les contacts du téléphone',
      androidPermission: 'android.permission.READ_CONTACTS'),
  bluetooth(PermissionScope.phone, 'Bluetooth',
      'Se connecter aux appareils Bluetooth',
      androidPermission: 'android.permission.BLUETOOTH_CONNECT'),
  phoneState(PermissionScope.phone, 'État du téléphone',
      'Lire les informations de l\'appareil',
      androidPermission: 'android.permission.READ_PHONE_STATE');

  const PandaPermission(this.scope, this.label, this.rationale,
      {this.androidPermission});

  final PermissionScope scope;
  final String label;
  final String rationale;
  final String? androidPermission;

  static PandaPermission? tryParse(String name) => PandaPermission.values
      .where((p) => p.name == name.trim())
      .firstOrNull;
}

/// Résultat d'une demande de permission.
enum PermissionResult { granted, denied, permanentlyDenied, unknown }

// ═══════════════════════════════════════════════════════════════
// MANAGER
// ═══════════════════════════════════════════════════════════════

/// Gestionnaire central des permissions d'extensions.
///
/// Usage côté extension (via panda_sdk) :
/// ```dart
/// final ok = await context.permissions.request('clipboard');
/// if (ok) { final text = await context.clipboard.read(); }
/// ```
class ExtensionPermissionManager {
  ExtensionPermissionManager._();
  static final ExtensionPermissionManager instance =
      ExtensionPermissionManager._();

  static const _channel = MethodChannel('panda.ide.permissions');

  /// Fichier de persistance des accords (injecté par l'app).
  String grantsFilePath = '.panda/extension_grants.json';

  final Map<String, Set<String>> _grants = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = File(grantsFilePath);
      if (await f.exists()) {
        final doc = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        doc.forEach((ext, perms) {
          _grants[ext] = (perms as List).map((e) => e.toString()).toSet();
        });
      }
    } catch (_) {
      // fichier corrompu → repart à vide
    }
  }

  Future<void> _persist() async {
    try {
      final f = File(grantsFilePath);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(
          _grants.map((k, v) => MapEntry(k, v.toList()))));
    } catch (_) {}
  }

  // ── Consultation ─────────────────────────────────────────────────

  Future<bool> isGranted(String extensionId, PandaPermission perm) async {
    await _ensureLoaded();
    return _grants[extensionId]?.contains(perm.name) ?? false;
  }

  /// Toutes les permissions accordées à une extension.
  Future<List<PandaPermission>> grantedFor(String extensionId) async {
    await _ensureLoaded();
    final names = _grants[extensionId] ?? const {};
    return PandaPermission.values.where((p) => names.contains(p.name)).toList();
  }

  // ── Demandes ─────────────────────────────────────────────────────

  /// Accorde une permission sandbox (consentement install).
  Future<void> grantIde(String extensionId, PandaPermission perm) async {
    assert(perm.scope == PermissionScope.ideSandbox);
    await _ensureLoaded();
    (_grants[extensionId] ??= {}).add(perm.name);
    await _persist();
  }

  /// Révoque tout (désinstallation de l'extension).
  Future<void> revokeAll(String extensionId) async {
    await _ensureLoaded();
    _grants.remove(extensionId);
    await _persist();
  }

  /// Demande une permission téléphone (runtime Android).
  ///
  /// [showRationale] doit afficher le dialog d'explication et retourner
  /// true si l'utilisateur accepte de continuer. Retourne true si accordée.
  Future<PermissionResult> request(
    String extensionId,
    PandaPermission perm, {
    required Future<bool> Function(PandaPermission perm) showRationale,
  }) async {
    await _ensureLoaded();

    // Déjà accordée côté IDE ?
    if (await isGranted(extensionId, perm)) return PermissionResult.granted;

    if (perm.scope == PermissionScope.ideSandbox) {
      // Les permissions sandbox demandent juste le consentement utilisateur
      final ok = await showRationale(perm);
      if (!ok) return PermissionResult.denied;
      await grantIde(extensionId, perm);
      return PermissionResult.granted;
    }

    // Permission téléphone → rationale puis channel natif
    if (perm.androidPermission == null) return PermissionResult.unknown;

    final wantsIt = await showRationale(perm);
    if (!wantsIt) return PermissionResult.denied;

    bool nativeGranted;
    try {
      nativeGranted = await _channel.invokeMethod<bool>('requestPermission', {
            'permission': perm.androidPermission,
            'extensionId': extensionId,
          }) ??
          false;
    } on MissingPluginException {
      // Side native pas encore buildée → refus safe
      nativeGranted = false;
    } on PlatformException {
      nativeGranted = false;
    }

    if (nativeGranted) {
      (_grants[extensionId] ??= {}).add(perm.name);
      await _persist();
      return PermissionResult.granted;
    }
    return PermissionResult.denied;
  }
}

// ═══════════════════════════════════════════════════════════════
// APIs GARDÉES (accessibles seulement après permission)
// ═══════════════════════════════════════════════════════════════

/// Presse-papiers pour extensions — exige la permission `clipboard`.
class ExtensionClipboard {
  ExtensionClipboard._();

  static Future<bool> _check(String extensionId) async =>
      ExtensionPermissionManager.instance
          .isGranted(extensionId, PandaPermission.clipboard);

  static Future<String?> read(String extensionId) async {
    if (!await _check(extensionId)) return null; // silencieux : pas accordé
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  static Future<bool> write(String extensionId, String text) async {
    if (!await _check(extensionId)) return false;
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }
}

/// Redirections / intents pour extensions — exige `network` ou rien
/// (ouvrir des URLs est sans danger ; ouvrir des paramètres système
/// demande le consentement via rationale).
class ExtensionIntents {
  ExtensionIntents._();

  /// Ouvre une URL externe (navigateur).
  static Future<bool> openUrl(String url) async {
    try {
      await _intentsChannel
          .invokeMethod('openUrl', {'url': url});
      return true;
    } on Exception {
      return false;
    }
  }

  /// Ouvre un écran de réglages Android (ex: options développeur).
  /// [action] : nom d'action Android complet.
  static Future<bool> openAndroidSettings(String action) async {
    try {
      await _intentsChannel
          .invokeMethod('openSettings', {'action': action});
      return true;
    } on Exception {
      return false;
    }
  }

  static const _intentsChannel = MethodChannel('panda.ide.intents');
}
