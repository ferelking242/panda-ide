/// AdbService — pilote adb dans le rootfs Alpine VIA PROOT.
///
/// ⚠️ Les binaires adb vivent dans le rootfs : tout passe par ProotRunner
/// (pattern ApkService). Un Process.run('adb') direct ne trouverait rien.
///
/// - Le téléphone se connecte à LUI-MÊME (loopback refusé sur certains
///   Samsung → fallback IP WiFi automatique).
/// - À chaque connexion réussie, l'endpoint est écrit dans
///   `$appDir/adb_endpoint.txt` → le terminal réouvert se reconnecte seul.
library panda_device.adb_service;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:panda_sdk/panda_sdk.dart';

import 'proot_runner.dart';

class AdbService {
  final TerminalAPI _terminal;
  final StorageAPI _storage;
  final PandaLogger _log;
  final void Function(String line)? onLog;

  String? wifiIp;
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

  // ── Exécution via proot ────────────────────────────────────────────

  Future<ProcResult> _adb(List<String> args) {
    final quoted = args.map(_shellQuote).join(' ');
    onLog?.call('\$ adb $quoted');
    return ProotRunner.run('adb $quoted', onLine: onLog);
  }

  static String _shellQuote(String a) =>
      RegExp(r'^[A-Za-z0-9_:@./+=-]+$').hasMatch(a) ? a : "'$a'";

  // ── État ───────────────────────────────────────────────────────────

  Future<bool> isAvailable() async => (await _adb(['version'])).ok;

  Future<bool> hasConnectedDevice() async =>
      await firstDeviceSerial() != null;

  Future<String?> firstDeviceSerial() async {
    final r = await _adb(['devices']);
    if (!r.ok && r.exitCode != 0) return null;
    for (final line in r.output.split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[1] == 'device') return parts[0];
    }
    return null;
  }

  // ── Paramètres Android (façon Shizuku) ─────────────────────────────

  /// Ouvre les Options développeur. Tentatives host puis fallback.
  Future<void> openDeveloperSettings() async {
    for (final action in [
      'android.settings.APPLICATION_DEVELOPMENT_SETTINGS',
    ]) {
      try {
        await Process.run('am', ['start', '-a', action]);
        return;
      } catch (_) {}
    }
    _log.warning('Ouverture paramètres impossible depuis l\'app '
        '(nécessite Shizuku ou saisie manuelle)');
  }

  // ── Appairage ──────────────────────────────────────────────────────

  Future<bool> pair({required String port, required String code}) async {
    final candidates = <String>[
      '127.0.0.1:$port',
      if (wifiIp != null) '$wifiIp:$port',
    ];
    for (final addr in candidates) {
      final r = await _adb(['pair', addr, code]);
      if (r.output.contains('Successfully paired')) {
        _log.info('Appairé sur $addr');
        return true;
      }
    }
    _log.warning('Échec appairage ($candidates)');
    return false;
  }

  Future<bool> connect({required String port}) async {
    wifiIp ??= await _detectWifiIp();
    for (final addr in [
      if (wifiIp != null) '$wifiIp:$port',
      '127.0.0.1:$port',
    ]) {
      final r = await _adb(['connect', addr]);
      if (r.output.contains('connected to')) {
        _lastDebugPort = port;
        await _storage.set(_portKey, port);
        if (wifiIp != null) await _storage.set(_hostKey, wifiIp!);
        // Endpoint persistant pour reconnect auto du terminal
        try {
          final support = await getApplicationSupportDirectory();
          File('${support.parent.path}/adb_endpoint.txt')
              .writeAsStringSync(addr);
        } catch (_) {}
        _log.info('Connecté sur $addr');
        return true;
      }
    }
    return false;
  }

  Future<bool> reconnectLast() async {
    final port = _lastDebugPort ?? await _storage.get(_portKey);
    wifiIp ??= await _storage.get(_hostKey);
    if (port == null) return false;
    return connect(port: port);
  }

  Future<String?> _detectWifiIp() async {
    final r = await ProotRunner.run(
        "ip route | awk '/src/ {print \$NF}'");
    final ip = r.output.trim();
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip)) return ip;
    return null;
  }
}
