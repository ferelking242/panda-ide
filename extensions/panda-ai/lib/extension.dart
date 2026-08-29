/// Panda AI — Extension entry point.
///
/// Workflow:
///   1. Vérifie Python + pip dans le rootfs PRoot
///   2. Clone panda-ai depuis GitHub
///   3. Installe les dépendances Python (pip install)
///   4. Démarre le serveur uvicorn (API OpenAI-compatible) en headless
///   5. Affiche le dashboard Next.js dans un WebView
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
  String get version => '1.1.0';

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

    final python = await _manager!.findPython();
    if (python == null) {
      _state.add(AiState(
        message: 'Python introuvable — installez via le terminal',
        status: AiStatus.error,
      ));
      return;
    }
    _state.add(AiState(message: 'Python ✓'));

    final pip = await _manager!.findPip();
    if (pip == null) {
      _state.add(AiState(
        message: 'pip introuvable — installez via le terminal',
        status: AiStatus.warning,
      ));
      return;
    }
    _state.add(AiState(message: 'pip ✓'));

    final installed = await GatewayInstaller.isInstalled(_ctx!.terminal);
    if (installed) {
      final version = await GatewayInstaller.getInstalledVersion(_ctx!.terminal);
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
      final installed = await GatewayInstaller.isInstalled(_ctx!.terminal);
      if (!installed) {
        final go = await _ctx!.window.showConfirmation(
          'Panda AI n\'est pas installé.\n\n'
          'Voulez-vous l\'installer maintenant ?',
          title: 'Panda AI',
        );
        if (!go) return;
        await installGateway();
      }
      await startServer();
    }
    _state.add(AiState(
      message: 'Dashboard prêt — port 8000',
      status: AiStatus.running,
    ));
  }

  Future<void> installGateway() async {
    _state.add(AiState(
      message: 'Installation en cours…',
      status: AiStatus.installing,
    ));

    try {
      final ok = await GatewayInstaller.install(
        terminal: _ctx!.terminal,
        onProgress: (msg) => _state.add(AiState(logLine: msg)),
      );

      if (ok) {
        final version = await GatewayInstaller.getInstalledVersion(_ctx!.terminal);
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
    await _manager!.start();
  }

  Future<void> stopServer() async {
    await _manager!.stop();
    _state.add(AiState(
      message: 'Serveur arrêté',
      status: AiStatus.stopped,
    ));
  }

  Future<void> showStatus() async {
    final installed = await GatewayInstaller.isInstalled(_ctx!.terminal);
    final python = await _manager?.findPython();
    final running = _manager?.isRunning ?? false;

    final status = [
      'Python: ${python != null ? "✓" : "✗"}',
      'Gateway: ${installed ? "✓" : "✗"}',
      'Serveur: ${running ? "✓ (port 8000)" : "✗"}',
    ].join('\n');

    await _ctx!.window.showInformation(
      status,
      actions: ['Installer', 'Démarrer', 'Arrêter'],
    );
  }

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

  const AiState({this.message, this.status, this.logLine, this.provider});
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
