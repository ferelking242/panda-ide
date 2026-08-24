/// Gestionnaire des processus Node.js Extension Host.
///
/// Un process Node.js est spawné par extension active.
/// Chaque process charge host.js avec le chemin de l'extension en argument.
/// La communication passe par IpcBridge (stdin/stdout JSON-RPC).
library;
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'extension_registry.dart';
import 'ipc_bridge.dart';
import 'command_registry.dart';
import 'models/extension_manifest.dart';
import 'models/extension_message.dart';





/// Un Extension Host actif (1 process Node.js = 1 extension).
class ActiveExtensionHost {
  final InstalledExtension extension;
  final IpcBridge bridge;
  bool _activated = false;

  ActiveExtensionHost({required this.extension, required this.bridge});

  bool get isActivated => _activated;

  ExtensionManifest get manifest => extension.manifest;
  String get id => manifest.id;

  Future<void> markActivated() async => _activated = true;

  Future<void> dispose() async {
    await bridge.dispose();
  }
}

/// Gère le cycle de vie de tous les Extension Hosts.
class ExtensionHostManager {
  static final ExtensionHostManager instance = ExtensionHostManager._();
  ExtensionHostManager._();

  final Map<String, ActiveExtensionHost> _hosts = {};

  /// Chemin vers le binaire node (installé via node_feature).
  String? _nodeBinPath;

  /// Chemin vers host.js (extrait de assets/ au premier lancement).
  String? _hostJsPath;

  /// Handler pour tous les appels vscode.* venant des extensions.
  /// Doit être défini par l'UI avant d'activer les extensions.
  Future<dynamic> Function(String extensionId, IpcMessage msg)? apiCallHandler;

  // ── Initialisation ───────────────────────────────────────────────────────

  /// À appeler depuis main.dart après avoir localisé node et extrait host.js.
  void configure({required String nodeBinPath, required String hostJsPath}) {
    _nodeBinPath = nodeBinPath;
    _hostJsPath = hostJsPath;
  }

  bool get isConfigured => _nodeBinPath != null && _hostJsPath != null;

  // ── Activation d'extension ───────────────────────────────────────────────

  /// Active une extension : spawn le process Node.js et envoie "activate".
  Future<void> activate(InstalledExtension ext) async {
    if (!isConfigured) {
      throw StateError(
          'ExtensionHostManager not configured. Call configure() first.');
    }

    final id = ext.manifest.id;
    if (_hosts.containsKey(id)) return; // déjà active

    if (!ext.isRunnable) {
      throw StateError(
          'Extension $id is not runnable (disabled, no entry point, or requires native binaries).');
    }

    // Déterminer l'entry point
    final entryPoint = _resolveEntryPoint(ext);
    if (entryPoint == null) {
      throw StateError('Cannot resolve entry point for $id');
    }

    // Spawn Node.js
    final process = await Process.start(
      _nodeBinPath!,
      [_hostJsPath!, entryPoint],
      environment: {
        'PANDA_EXT_ID': id,
        'PANDA_EXT_PATH': ext.installPath,
        'PANDA_EXT_VERSION': ext.manifest.version,
        // Désactive les couleurs ANSI dans les logs Node.js
        'NO_COLOR': '1',
        'FORCE_COLOR': '0',
      },
      workingDirectory: ext.installPath,
    );

    // Attacher le bridge IPC
    final bridge = await IpcBridge.attach(process, (msg) async {
      final handler = apiCallHandler;
      if (handler == null) {
        throw StateError('No apiCallHandler registered');
      }
      return handler(id, msg);
    });

    final host = ActiveExtensionHost(extension: ext, bridge: bridge);
    _hosts[id] = host;

    // Envoyer "activate" avec le contexte d'extension
    try {
      await bridge.call('activate', [_buildActivationContext(ext)]);
      await host.markActivated();

      // Auto-register contributed commands into CommandPalette
      final contributes = ext.manifest.contributes;
      if (contributes.commands.isNotEmpty) {
        for (final cmd in contributes.commands) {
          final commandId = cmd['command'] as String?;
          if (commandId != null) {
            CommandRegistry.instance.register(
              command: commandId,
              extensionId: id,
              title: cmd['title'] as String?,
              category: cmd['category'] as String?,
              description: cmd['description'] as String?,
            );
          }
        }
        // ignore: avoid_print
        print('[ExtHostManager] Registered ${contributes.commands.length} commands for $id');
      }
    } catch (e) {
      await host.dispose();
      _hosts.remove(id);
      await ExtensionRegistry.instance.setError(id, e.toString());
      rethrow;
    }
  }

  /// Désactive une extension : envoie "deactivate" puis ferme le process.
  Future<void> deactivate(String extensionId) async {
    final host = _hosts[extensionId];
    if (host == null) return;

    try {
      if (host.isActivated) {
        await host.bridge.call('deactivate').timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // On ferme quand même si deactivate plante
    }

    await host.dispose();
    _hosts.remove(extensionId);
  }

  /// Active toutes les extensions marquées comme "startup".
  Future<void> activateStartupExtensions() async {
    await ExtensionRegistry.instance.load();
    final startups = ExtensionRegistry.instance.startupExtensions;
    await Future.wait(startups.map((e) => _safeActivate(e)));
  }

  /// Active les extensions pour un langage donné (lazy activation).
  Future<void> activateForLanguage(String languageId) async {
    await ExtensionRegistry.instance.load();
    final exts = ExtensionRegistry.instance.forLanguage(languageId);
    await Future.wait(exts.map((e) => _safeActivate(e)));
  }

  /// Active les extensions pour une commande donnée.
  Future<void> activateForCommand(String commandId) async {
    await ExtensionRegistry.instance.load();
    final exts = ExtensionRegistry.instance.forCommand(commandId);
    await Future.wait(exts.map((e) => _safeActivate(e)));
  }

  // ── Envoi d'events à toutes les extensions actives ───────────────────────

  /// Notifie toutes les extensions d'un événement éditeur.
  void broadcastEvent(String event, [dynamic data]) {
    for (final host in _hosts.values) {
      if (host.isActivated) {
        host.bridge.fireEvent(event, data);
      }
    }
  }

  /// Notifie une extension spécifique d'un événement.
  void sendEvent(String extensionId, String event, [dynamic data]) {
    _hosts[extensionId]?.bridge.fireEvent(event, data);
  }

  // ── Introspection ────────────────────────────────────────────────────────

  List<ActiveExtensionHost> get activeHosts => _hosts.values.toList();
  bool isActive(String extensionId) => _hosts.containsKey(extensionId);
  ActiveExtensionHost? getHost(String extensionId) => _hosts[extensionId];

  /// Retourne l'IpcBridge d'une extension active — utilisé par LanguageFeatureRouter.
  IpcBridge? getBridge(String extensionId) => _hosts[extensionId]?.bridge;

  // ── Dispose ──────────────────────────────────────────────────────────────

  Future<void> disposeAll() async {
    final futures = _hosts.keys.map(deactivate).toList();
    await Future.wait(futures);
    _hosts.clear();
  }

  // ── Helpers privés ────────────────────────────────────────────────────────

  Future<void> _safeActivate(InstalledExtension ext) async {
    try {
      await activate(ext);
    } catch (e) {
      // On logue mais on n'interrompt pas l'activation des autres
      // ignore: avoid_print
      print('[ExtHostManager] Failed to activate ${ext.manifest.id}: $e');
    }
  }

  /// Résout le chemin absolu de l'entry point de l'extension.
  String? _resolveEntryPoint(InstalledExtension ext) {
    final base = ext.installPath;
    final main = ext.manifest.main;
    if (main == null) return null;

    // Normalise le chemin (peut commencer par "./")
    final cleaned = main.replaceFirst(RegExp(r'^\.\/'), '');
    // Ajoute .js si pas d'extension
    final withExt = p.extension(cleaned).isEmpty ? '$cleaned.js' : cleaned;
    final full = p.join(base, withExt);

    return File(full).existsSync() ? full : null;
  }

  /// Construit l'objet context passé à activate(context).
  Map<String, dynamic> _buildActivationContext(InstalledExtension ext) {
    return {
      'extensionPath': ext.installPath,
      'extensionUri': 'file://${ext.installPath}',
      'globalStoragePath':
          p.join(ext.installPath, '..', '.storage', ext.manifest.id),
      'storagePath': p.join(ext.installPath, '..', '.storage', ext.manifest.id),
      'logPath': p.join(ext.installPath, '..', '.logs', ext.manifest.id),
      'workspaceState': <String, dynamic>{},
      'globalState': <String, dynamic>{},
      'subscriptions': <dynamic>[],
      'extension': {
        'id': ext.manifest.id,
        'extensionPath': ext.installPath,
        'isActive': true,
        'packageJSON': ext.manifest.raw,
      },
    };
  }
}
