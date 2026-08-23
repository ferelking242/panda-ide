/// AdbService — pilote adb dans le rootfs Alpine.
///
/// Points clés :
/// - Le téléphone se connecte à LUI-MÊME : `adb pair/connect IP:port`
///   (loopback refusé sur certains Samsung → fallback IP WiFi automatique).
/// - Le port d'appairage vient de la POPUP du code ; le port de débogage
///   vient de l'écran principal. Ce sont deux ports différents !
library panda_device.adb_service;

import 'dart:io';

import 'package:panda_sdk/panda_sdk.dart';

class AdbService {
  final TerminalAPI _terminal;
  final StorageAPI _storage;
  final PandaLogger _log;
  final void Function(String line)? onLog;

  /// IP WiFi détectée lors de l'appairage (ex: 192.168.1.65).
  String? wifiIp;

  /// Dernier port de débogage utilisé (mémorisé pour reconnect rapide).
  String? get lastDebugPort => _lastDebugPort;
  String? _lastDebugPort;

  static const _hostKey = 'adb.wifiIp';
  static const _portKey = 'adb.debugPort';

  AdbService({
    required TerminalAPI terminal,
    required StorageAPI storage,
    required PandaLogger logger,
    this.onLog,
  })  : _terminal = terminal,
        _storage = storage,
        _log = logger;

  // ── Exécution ──────────────────────────────────────────────────────

  Future<ProcessResult> _adb(List<String> args) async {
    onLog?.call('\$ adb ${args.join(' ')}');
    final r = await Process.run('adb', args,
        stdoutEncoding: utf8Safe, stderrEncoding: utf8Safe);
    final out = '${r.stdout}${r.stderr}'.trim();
    if (out.isNotEmpty) onLog?.call(out);
    return r;
  }

  // utf8 safe wrapper (les sorties adb peuvent contenir des octets exotiques)
  static const utf8Safe = _Utf8SafeCodec();

  // ── État ───────────────────────────────────────────────────────────

  Future<bool> isAvailable() async {
    final r = await _adb(['version']);
    return r.exitCode == 0;
  }

  Future<bool> hasConnectedDevice() async =>
      await firstDeviceSerial() != null;

  /// Premier appareil en état "device", sinon null.
  Future<String?> firstDeviceSerial() async {
    final r = await _adb(['devices']);
    if (r.exitCode != 0) return null;
    for (final line in r.stdout.toString().split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[1] == 'device') return parts[0];
    }
    return null;
  }

  // ── Paramètres Android (façon Shizuku) ─────────────────────────────

  /// Ouvre l'écran « Débogage sans fil » directement si possible,
  /// sinon les Options développeur.
  Future<void> openDeveloperSettings() async {
    // Intent direct vers Débogage sans fil (Android 11+) via Shizuku-like am
    const deepLink =
        '#Intent;action=android.settings.APPLICATION_DEVELOPMENT_SETTINGS;end';
    try {
      final r = await Process.run(
          'am', ['start', '-a', 'android.intent.action.VIEW', '-d', deepLink]);
      if (r.exitCode != 0) throw Exception(r.stderr);
    } catch (_) {
      // Fallback : panneau général des paramètres
      try {
        await Process.run('am', [
          'start', '-a', 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS'
        ]);
      } catch (e) {
        _log.warning('Impossible d\'ouvrir les paramètres : $e');
      }
    }
  }

  // ── Appairage ──────────────────────────────────────────────────────

  /// Appaire avec le port+code de la popup.
  /// Stratégie : loopback → IP WiFi → redemande à l'utilisateur rien,
  /// retourne false (l'extension affichera l'erreur).
  Future<bool> pair({required String port, required String code}) async {
    final candidates = <String>[
      '127.0.0.1:$port',
      if (wifiIp != null) '$wifiIp:$port',
    ];

    for (final addr in candidates) {
      final r = await _adb(['pair', addr, code]);
      final out = r.stdout.toString() + r.stderr.toString();
      if (out.contains('Successfully paired')) {
        _log.info('Appairé sur $addr');
        return true;
      }
    }
    _log.warning('Échec appairage (ports essayés: $candidates)');
    return false;
  }

  /// Se connecte au port de DÉBOGAGE (écran principal).
  Future<bool> connect({required String port}) async {
    // Récupère l'IP WiFi locale une fois (ip route / hostname -I)
    wifiIp ??= await _detectWifiIp();
    final candidates = <String>[
      if (wifiIp != null) '$wifiIp:$port',
      '127.0.0.1:$port',
    ];

    for (final addr in candidates) {
      final r = await _adb(['connect', addr]);
      final out = r.stdout.toString() + r.stderr.toString();
      if (out.contains('connected to')) {
        _lastDebugPort = port;
        await _storage.set(_portKey, port);
        if (wifiIp != null) await _storage.set(_hostKey, wifiIp!);
        _log.info('Connecté sur $addr');
        return true;
      }
    }
    return false;
  }

  /// Reconnexion rapide avec le dernier port connu.
  Future<bool> reconnectLast() async {
    final port = _lastDebugPort ?? await _storage.get(_portKey);
    wifiIp ??= await _storage.get(_hostKey);
    if (port == null) return false;
    return connect(port: port);
  }

  Future<String?> _detectWifiIp() async {
    try {
      final r =
          await Process.run('sh', ['-c', 'ip route | awk \'/src/ {print \$NF}\'']);
      final ip = r.stdout.toString().trim();
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) return ip;
    } catch (_) {}
    return null;
  }
}

/// Encoding tolérant pour les sorties adb.
class _Utf8SafeCodec extends Encoding {
  const _Utf8SafeCodec();

  @override
  Converter<List<int>, String> get decoder => const Utf8AllowMalformed();
  @override
  Converter<String, List<int>> get encoder => utf8.encoder;
  @override
  String get name => 'utf8';
}

class Utf8AllowMalformed extends Converter<List<int>, String> {
  const Utf8AllowMalformed();

  @override
  String convert(List<int> input, [int start = 0, int? end]) =>
      utf8.decode(input, allowMalformed: true);
}
