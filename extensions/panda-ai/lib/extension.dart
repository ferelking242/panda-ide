/// Panda AI — Extension entry point.
///
/// Workflow:
///   1. Vérifie Python + pip dans le rootfs
///   2. Télécharge panda-ai depuis GitHub (ou depuis les assets bundled)
///   3. Installe les dépendances Python (pip install)
///   4. Démarre le serveur uvicorn (API OpenAI-compatible)
///   5. Lance le dashboard Next.js dans un WebView
library panda_ai;

import 'dart:async';

import 'package:panda_sdk/panda_sdk.dart';

import 'gateway_manager.dart';
import 'gateway_installer.dart';

class PandaAiExtension extends PandaExtension {
  @override
  String get id => 'dev.panda.ai';

  @override
  String get name => 'Panda AI';

  @override
  String get version => '1.0.0';

  GatewayManager? _manager;
  ExtensionContext? _ctx;

  /// État diffusé à la vue sidebar (dashboard_panel).
  final StreamController<AiState> _state =
      StreamController<AiState>.broadcast();
  Stream<AiState> get onState => _state.stream;

  @override
  Future<void> onActivate(ExtensionContext context) async {
    _ctx = context;
    _manager = GatewayManager(
      terminal: context.terminal,
      storage: context.storage,
      network: context.network,
      logger: context.logger,
      onLog: (line) => _state.add(AiState(logLine: line)),
      onStatus: (status) => _state.add(AiState(status: status)),
    );

    context.commands.register('$id.open', (_) => openDashboard());
    context.commands.register('$id.install', (_) => installGateway());
    context.commands.register('$id.start', (_) => startServer());
    context.commands.register('$id.stop', (_) => stopServer());
    context.commands.register('$id.status', (_) => showStatus());

    context.logger.info('Panda AI activé');
    // Vérification asynchrone au démarrage
    unawaited(_checkEnvironment());
  }

  @override
  Future<void> onDeactivate() async {
    await _manager?.stop();
    await _state.close();
  }

  // ── Vérification de l'environnement ─────────────────────────────

  Future<void> _checkEnvironment() async {
    _state.add(AiState(message: 'Vérification de l\'environnement…'));

    // 1. Python
    final python = await _manager!.findPython();
    if (python == null) {
      _state.add(AiState(
        message: 'Python introuvable',
        status: AiStatus.error,
      ));
      return;
    }
    _state.add(AiState(message: 'Python: $python ✓'));

    // 2. pip
    final pip = await _manager!.findPip();
    if (pip == null) {
      _state.add(AiState(
        message: 'pip introuvable',
        status: AiStatus.warning,
      ));
      return;
    }
    _state.add(AiState(message: 'pip: $pip ✓'));

    // 3. Gateway installé ?
    final installed = await GatewayInstaller.isInstalled();
    if (installed) {
      final version = await GatewayInstaller.getInstalledVersion();
      _state.add(AiState(
        message: 'Gateway installé (v$version)',
        status: AiStatus.ready,
      ));
    } else {
      _state.add(AiState(
        message: 'Gateway non installé — cliquez "Installer"',
        status: AiStatus.notInstalled,
      ));
    }
  }

  // ── Commands ────────────────────────────────────────────────────

  Future<void> openDashboard() async {
    if (_manager == null || !_manager!.isRunning) {
      // Vérifier l'installation d'abord
      final installed = await GatewayInstaller.isInstalled();
      if (!installed) {
        final go = await _ctx!.window.showConfirmation(
          'Panda AI n\'est pas installé.\n\n'
          'Voulez-vous l\'installer maintenant ?',
          title: 'Panda AI',
        );
        if (!go) return;
        await installGateway();
      }

      // Démarrer le serveur
      await startServer();
    }

    // Le dashboard est accessible via le WebView dans dashboard_panel.dart
    _state.add(AiState(
      message: 'Dashboard prêt',
      status: AiStatus.running,
    ));
  }

  Future<void> installGateway() async {
    _state.add(AiState(
      message: 'Installation en cours…',
      status: AiStatus.installing,
    ));

    try {
      await GatewayInstaller.install(
        onProgress: (msg) => _state.add(AiState(logLine: msg)),
      );

      final installed = await GatewayInstaller.isInstalled();
      if (installed) {
        final version = await GatewayInstaller.getInstalledVersion();
        _state.add(AiState(
          message: 'Gateway installé (v$version) ✓',
          status: AiStatus.ready,
        ));
      } else {
        _state.add(AiState(
          message: 'Installation échouée',
          status: AiStatus.error,
        ));
      }
    } catch (e) {
      _state.add(AiState(
        message: 'Erreur: $e',
        status: AiStatus.error,
      ));
    }
  }

  Future<void> startServer() async {
    _state.add(AiState(
      message: 'Démarrage du serveur…',
      status: AiStatus.starting,
    ));

    final dir = await GatewayInstaller.getInstallDir();
    await _manager!.start(dir);
  }

  Future<void> stopServer() async {
    await _manager!.stop();
    _state.add(AiState(
      message: 'Serveur arrêté',
      status: AiStatus.stopped,
    ));
  }

  Future<void> showStatus() async {
    final installed = await GatewayInstaller.isInstalled();
    final python = await _manager?.findPython();
    final running = _manager?.isRunning ?? false;

    final status = [
      'Python: ${python != null ? "✓" : "✗"}',
      'Gateway: ${installed ? "✓" : "✗"}',
      'Serveur: ${running ? "✓" : "✗"}',
      if (running) 'Port: ${_manager!.apiPort}',
    ].join('\n');

    await _ctx!.window.showInformation(
      status,
      actions: ['Installer', 'Démarrer', 'Arrêter'],
    );
  }

  /// Setter le provider (chatgpt/claude/pandagateway).
  void setProvider(String provider) {
    _manager?.setProvider(provider);
    _state.add(AiState(provider: provider));
  }
}

/// État diffusé à la vue sidebar.
class AiState {
  final String? message;
  final AiStatus? status;
  final String? logLine;
  final String? provider;

  const AiState({
    this.message,
    this.status,
    this.logLine,
    this.provider,
  });
}

/// Statuts possibles du gateway.
enum AiStatus {
  idle,
  notInstalled,
  installing,
  ready,
  starting,
  running,
  stopping,
  stopped,
  error,
  warning,
}
