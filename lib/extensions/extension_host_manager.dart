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
import 'terminal_node.dart';





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

  /// Chemin vers host.js (extrait de assets/ au premier lancement).
  String? _hostJsPath;

  /// Handler pour tous les appels vscode.* venant des extensions.
  /// Doit être défini par l'UI avant d'activer les extensions.
  Future<dynamic> Function(String extensionId, IpcMessage msg)? apiCallHandler;

  /// Loader installé par ExtensionHostSetup. L'initialisation Android est
  /// volontairement différée, mais une action utilisateur peut arriver avant
  /// la fin de cette initialisation.
  Future<void> Function()? _configurationLoader;
  String? _configurationError;

  // ── Initialisation ───────────────────────────────────────────────────────

  /// À appeler depuis main.dart après avoir validé le Node du terminal.
  void configure({required String hostJsPath}) {
    _hostJsPath = hostJsPath;
    _configurationError = null;
  }

  bool get isConfigured => _hostJsPath != null;

  void setConfigurationLoader(Future<void> Function() loader) {
    _configurationLoader = loader;
  }

  Future<void> _ensureConfigured() async {
    if (isConfigured) return;
    final loader = _configurationLoader;
    if (loader != null) {
      await loader();
    }
    if (!isConfigured) {
      throw StateError(
        'Extension host indisponible : Node.js ou host.js est manquant. '
        '${_configurationError ?? "Exécutez « panda update » puis réessayez."}',
      );
    }
  }

  // ── Activation d'extension ───────────────────────────────────────────────

  /// Active une extension : spawn le process Node.js et envoie "activate".
  Future<void> activate(InstalledExtension ext) async {
    await _ensureConfigured();

    final id = ext.manifest.id;
    final existing = _hosts[id];
    if (existing != null) {
      if (!existing.bridge.isClosed) return; // déjà active
      // A crashed Node process must not permanently block lazy reactivation.
      _hosts.remove(id);
    }

    if (!ext.isRunnable) {
      throw StateError(
          'Extension $id is not runnable (disabled, no entry point, or requires native binaries).');
    }

    // Déterminer l'entry point
    final entryPoint = _resolveEntryPoint(ext);
    if (entryPoint == null) {
      throw StateError('Cannot resolve entry point for $id');
    }

    // Android's terminal Node binary is a Linux guest executable. It must be
    // started through the same PRoot wrapper as the terminal, never with a
    // direct Process.start() from the Android host.
    final process = await TerminalNodeLauncher.instance.startNode(
      arguments: [_hostJsPath!, entryPoint],
      environment: {
        'PANDA_EXT_ID': id,
        'PANDA_EXT_PATH': ext.installPath,
        'PANDA_EXT_VERSION': ext.manifest.version,
        'HOME': ext.installPath,
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

  /// Activate installed extensions which contribute [viewId].
  Future<void> activateForView(String viewId) async {
    await ExtensionRegistry.instance.load();
    final exts = ExtensionRegistry.instance.all.where((ext) {
      final views = ext.manifest.contributes.views;
      final containers = ext.manifest.contributes.viewsContainers;
      return views.any((view) => view['id']?.toString() == viewId) ||
          containers.any((container) => container['id']?.toString() == viewId);
    });
    // A view click must report activation errors to the UI. Swallowing the
    // error made a broken provider look like a successful sidebar action.
    await Future.wait(exts.map(activate));
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
  bool isActive(String extensionId) =>
      _hosts[extensionId]?.bridge.isClosed == false;
  ActiveExtensionHost? getHost(String extensionId) => _hosts[extensionId];

  /// Retourne l'IpcBridge d'une extension active — utilisé par LanguageFeatureRouter.
  IpcBridge? getBridge(String extensionId) {
    final bridge = _hosts[extensionId]?.bridge;
    return bridge != null && !bridge.isClosed ? bridge : null;
  }

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
    final main = ext.manifest.main ?? ext.manifest.browser;
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
