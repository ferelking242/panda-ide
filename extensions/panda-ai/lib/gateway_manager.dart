import 'dart:async';

import 'package:panda_sdk/panda_sdk.dart';

import 'gateway_installer.dart';
import 'extension.dart';

/// GatewayManager — gère le cycle de vie du serveur Python uvicorn.
///
/// Lance le gateway dans le rootfs PRoot via le terminal.
class GatewayManager {
  final TerminalAPI terminal;
  final PandaLogger logger;
  final void Function(String line)? onLog;
  final void Function(AiStatus status)? onStatus;

  Terminal? _serverTerminal;
  bool _isRunning = false;
  String _statusMessage = 'Gateway arrêté';
  String _provider = 'chatgpt';
  String _token = '';

  // Getters
  bool get isRunning => _isRunning;
  int get apiPort => 8000;
  String get provider => _provider;
  String get apiBaseUrl => 'http://127.0.0.1:${apiPort}/v1';
  String get statusMessage => _statusMessage;

  GatewayManager({
    required this.terminal,
    required this.logger,
    this.onLog,
    this.onStatus,
  });

  void setProvider(String p) => _provider = p;
  void setToken(String t) => _token = t;

  /// Vérifie si Python est disponible dans le rootfs.
  Future<String?> findPython() async {
    final result = await ProotRunner.run(
      'which python3 && python3 --version',
      terminal: terminal,
    );
    if (result.output.contains('Python')) {
      return 'python3 (in PRoot)';
    }
    return null;
  }

  /// Vérifie si pip est disponible.
  Future<String?> findPip() async {
    final result = await ProotRunner.run(
      'which pip3 && pip3 --version',
      terminal: terminal,
    );
    if (result.output.contains('pip')) {
      return 'pip3 (in PRoot)';
    }
    return null;
  }

  // ── Démarrage ──────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRunning) return;

    _setStatus('Démarrage du gateway…');
    _addLog('▶ Démarrage Panda AI Gateway');

    // Vérifier que le gateway est installé
    final installed = await GatewayInstaller.isInstalled(terminal);
    if (!installed) {
      _setStatus('Gateway non installé');
      _addLog('✗ Installez d\'abord le gateway');
      onStatus?.call(AiStatus.error);
      return;
    }

    // Vérifier Python
    final python = await findPython();
    if (python == null) {
      _setStatus('Python introuvable');
      _addLog('✗ Python introuvable dans le rootfs');
      onStatus?.call(AiStatus.error);
      return;
    }

    _addLog('Python: $python');
    _addLog('Répertoire: ${GatewayInstaller.installDir}');

    try {
      // Créer un terminal dédié pour le serveur
      _serverTerminal = await terminal.createTerminal(name: 'PandaAI-Server');

      // Lancer uvicorn
      final envVars = 'PROVIDER=$_provider HEADLESS=true API_PORT=8000';
      final cmd = 'cd ${GatewayInstaller.installDir} && '
          '$envVars python3 -m uvicorn src.api.server:app '
          '--host 127.0.0.1 --port 8000 --log-level info 2>&1';

      _addLog('Commande: $cmd');

      // Écouter la sortie
      _serverTerminal!.output?.listen((data) {
        final line = data.toString().trim();
        if (line.isNotEmpty) {
          _addLog(line);

          // Détecter le démarrage
          if (!_isRunning &&
              (line.contains('Application startup complete') ||
                  line.contains('Uvicorn running') ||
                  line.contains('Started server process'))) {
            _isRunning = true;
            _setStatus('Gateway actif sur :8000');
            _addLog('✓ API disponible sur http://127.0.0.1:8000');
            onStatus?.call(AiStatus.running);
          }

          // Détecter l'erreur X server
          if (line.contains('Missing X server') ||
              line.contains('DEGRADED')) {
            _addLog('⚠ Mode dégradé (pas de X server pour Chromium)');
          }
        }
      });

      // Envoyer la commande
      await _serverTerminal!.sendText(cmd);

      _addLog('PID serveur lancé');
    } catch (e) {
      _setStatus('Erreur démarrage: $e');
      _addLog('✗ Erreur: $e');
      onStatus?.call(AiStatus.error);
    }
  }

  // ── Arrêt ─────────────────────────────────────────────────────────

  Future<void> stop() async {
    _setStatus('Arrêt en cours…');
    _addLog('■ Arrêt du gateway');

    // Envoyer Ctrl+C pour arrêter uvicorn
    if (_serverTerminal != null) {
      await _serverTerminal!.sendText('\x03'); // Ctrl+C
      await Future.delayed(const Duration(seconds: 1));
    }

    _isRunning = false;
    _setStatus('Gateway arrêté');
    onStatus?.call(AiStatus.stopped);
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _setStatus(String msg) => _statusMessage = msg;

  void _addLog(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    onLog?.call('[$ts] $line');
  }
}
