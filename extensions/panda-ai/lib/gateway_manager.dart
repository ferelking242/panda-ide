import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:panda_sdk/panda_sdk.dart';

import 'gateway_installer.dart';
import 'extension.dart';

/// GatewayManager — gère le cycle de vie du serveur Python uvicorn.
///
/// Lance le gateway en mode extension : lit la config depuis le répertoire
/// installé dans le stockage de l'app.
class GatewayManager {
  final TerminalAPI terminal;
  final StorageAPI storage;
  final NetworkAPI network;
  final PandaLogger logger;
  final void Function(String line)? onLog;
  final void Function(AiStatus status)? onStatus;

  Process? _pythonProcess;
  int _apiPort = 8000;
  String _provider = 'chatgpt';
  String _token = '';
  bool _isRunning = false;
  String _statusMessage = 'Gateway arrêté';

  // Getters
  bool get isRunning => _isRunning;
  int get apiPort => _apiPort;
  String get provider => _provider;
  String get apiBaseUrl => 'http://127.0.0.1:$_apiPort/v1';
  String get statusMessage => _statusMessage;

  GatewayManager({
    required this.terminal,
    required this.storage,
    required this.network,
    required this.logger,
    this.onLog,
    this.onStatus,
  });

  void setProvider(String p) {
    _provider = p;
  }

  void setToken(String t) {
    _token = t;
  }

  /// Public wrapper so UI can detect Python without starting the server.
  Future<String?> findPython() => _findPython();

  /// Public wrapper so UI can detect pip.
  Future<String?> findPip() => _findPip();

  // ── Démarrage ──────────────────────────────────────────────────────

  Future<void> start(String installDir) async {
    if (_isRunning) return;

    _setStatus('Démarrage du gateway…');
    _addLog('▶ Démarrage Panda AI Gateway');

    final pythonBin = await _findPython();
    if (pythonBin == null) {
      _setStatus('Python introuvable');
      _addLog('✗ Python introuvable — installez Python via le terminal');
      onStatus?.call(AiStatus.error);
      return;
    }

    _addLog('Python: $pythonBin');
    _addLog('Répertoire: $installDir');

    // Construire les variables d'environnement
    final env = <String, String>{
      'API_HOST': '127.0.0.1',
      'API_PORT': '$_apiPort',
      'PROVIDER': _provider,
      'BROWSER_MODE': 'android',
      'WEBVIEW_BRIDGE_PORT': '9221',
      'HEADLESS': 'true',
      'SLOW_MO': '0',
      'LOG_LEVEL': 'INFO',
      'VERBOSE': 'false',
      'RESPONSE_TIMEOUT': '180000',
      'SELECTOR_TIMEOUT': '15000',
      'POLL_INTERVAL_MS': '500',
      if (_token.isNotEmpty) 'API_TOKEN': _token,
    };

    // Charger l'env file si présent
    final envFile = File('$installDir/android.env');
    if (await envFile.exists()) {
      final lines = await envFile.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = trimmed.indexOf('=');
        if (eq < 0) continue;
        final key = trimmed.substring(0, eq).trim();
        final val = trimmed.substring(eq + 1).trim();
        env.putIfAbsent(key, () => val);
      }
    }

    try {
      _pythonProcess = await Process.start(
        pythonBin,
        [
          '-m', 'uvicorn', 'src.api.server:app',
          '--host', '127.0.0.1',
          '--port', '$_apiPort',
          '--log-level', 'info',
        ],
        workingDirectory: installDir,
        environment: env,
        runInShell: false,
      );

      _addLog('PID Python: ${_pythonProcess!.pid}');
      _listenProcess(_pythonProcess!);
    } catch (e) {
      _setStatus('Erreur démarrage: $e');
      _addLog('✗ Erreur: $e');
      onStatus?.call(AiStatus.error);
    }
  }

  void _listenProcess(Process proc) {
    bool started = false;

    void onLine(String line) {
      _addLog(line);
      if (!started &&
          (line.contains('Application startup complete') ||
              line.contains('Uvicorn running') ||
              line.contains('Started server process'))) {
        started = true;
        _isRunning = true;
        _setStatus('Gateway actif sur :$_apiPort');
        _addLog('✓ API disponible sur http://127.0.0.1:$_apiPort');
        onStatus?.call(AiStatus.running);
      }
    }

    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);

    proc.exitCode.then((code) {
      if (_isRunning) {
        _isRunning = false;
        _setStatus('Gateway arrêté (code $code)');
        _addLog('■ Processus terminé (code $code)');
        onStatus?.call(AiStatus.stopped);

        // Auto-restart on crash
        if (code != 0) {
          _addLog('⚠ Crash détecté — redémarrage automatique dans 3s…');
          Future.delayed(const Duration(seconds: 3), () async {
            final dir = await GatewayInstaller.getInstallDir();
            start(dir);
          });
        }
      }
    });
  }

  // ── Arrêt ─────────────────────────────────────────────────────────

  Future<void> stop() async {
    _setStatus('Arrêt en cours…');
    _addLog('■ Arrêt du gateway');

    _pythonProcess?.kill();
    _pythonProcess = null;

    await Future.delayed(const Duration(milliseconds: 500));
    _isRunning = false;
    _setStatus('Gateway arrêté');
    onStatus?.call(AiStatus.stopped);
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Future<String?> _findPython() async {
    final candidates = [
      '/data/data/com.termux.app/files/usr/bin/python3',
      '/usr/bin/python3',
      '/usr/local/bin/python3',
      '/usr/bin/python',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    // Essai via PATH
    try {
      final result = await Process.run('which', ['python3']);
      if (result.exitCode == 0) {
        final p = (result.stdout as String).trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _findPip() async {
    final candidates = [
      '/data/data/com.termux.app/files/usr/bin/pip3',
      '/data/data/com.termux.app/files/usr/bin/pip',
      '/usr/bin/pip3',
      '/usr/local/bin/pip3',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    try {
      final r = await Process.run('which', ['pip3']);
      if (r.exitCode == 0) {
        final p = (r.stdout as String).trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  void _setStatus(String msg) {
    _statusMessage = msg;
  }

  void _addLog(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    onLog?.call('[$ts] $line');
  }
}
