/// Flutter Device — pilotage adb/Flutter depuis l'environnement Alpine.
///
/// Architecture (analyse du 23/08/2026) :
///   Terminal Alpine (proot) ──► adb ──► 127.0.0.1:<port wireless debugging>
///                                      └─► adbd du MÊME téléphone
/// Le réseau est partagé avec l'hôte Android (même netns), donc le loopback
/// atteint directement adbd : pas besoin de root ni de câble.
///
/// Fallback : Shizuku (`ShizukuService`) exécute pm install / am start avec
/// l'identité shell localement, sans réseau.
library;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/debian_setup.dart';
import '../utils/apk_service.dart';
import '../utils/constants.dart';
import 'shizuku_service.dart';





class AdbDevice {
  final String serial;
  final String state;
  final String model;
  const AdbDevice({required this.serial, required this.state, this.model = ''});

  bool get online => state == 'device';
}

/// Service singleton pilotant adb + flutter run dans le rootfs Alpine.
class FlutterDeviceService extends ChangeNotifier {
  FlutterDeviceService._();
  static final FlutterDeviceService instance = FlutterDeviceService._();

  static const _adbBin = '/usr/bin/adb';

  bool _adbReady = false;
  bool get adbReady => _adbReady;

  List<AdbDevice> _devices = const [];
  List<AdbDevice> get devices => _devices;

  String lastOutput = '';

  Process? _runProcess;

  // ── Exécution générique dans le rootfs (pattern ApkService) ────────────────

  Future<Process> _startInRootfs(
    List<String> command, {
    void Function(String line)? onLine,
    Map<String, String> extraEnv = const {},
    List<String> extraBinds = const [],
    String workingDir = '/root',
  }) async {
    final prootBin = await DebianSetup.locateProotBinary(DebianSetup.debianDir);
    if (prootBin == null) {
      throw StateError('PRoot introuvable');
    }

    final prootArgs = <String>[
      '-0',
      '--link2symlink',
      '--kill-on-exit',
      '--rootfs=${DebianSetup.debianDir}',
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      ...extraBinds.expand((b) => ['-b', b]),
      '-w', workingDir,
      '/bin/sh',
      '-c',
      command.join(' '),
    ];

    final env = await DebianSetup.prootSessionEnvironment();
    // ⚠️ NE PAS retirer : libproot.so a besoin de cette var AU LINK
        // pour trouver libtalloc.so (sinon CANNOT LINK EXECUTABLE).;
    env.addAll(extraEnv);

    final process = await Process.start(
      prootBin,
      prootArgs,
      workingDirectory: appDir,
      environment: env,
    );

    if (onLine != null) {
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine);
    }
    return process;
  }

  Future<List<String>> _collectInRootfs(
    List<String> command, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, String> extraEnv = const {},
    List<String> extraBinds = const [],
  }) async {
    final process = await _startInRootfs(command,
        extraEnv: extraEnv, extraBinds: extraBinds);
    final out = <String>[];
    final sub1 = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(out.add);
    final sub2 = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(out.add);
    await process.exitCode.timeout(timeout, onTimeout: () {
      process.kill(ProcessSignal.sigterm);
      return -1;
    });
    await sub1.cancel();
    await sub2.cancel();
    lastOutput = out.join('\n');
    return out;
  }

  // ── ADB ────────────────────────────────────────────────────────────────────

  /// Installe android-tools (adb) dans le rootfs si absent.
  Future<bool> ensureAdb({void Function(String line)? onLine}) async {
    final check = await _collectInRootfs(['test -x $_adbBin && echo OK'],
        timeout: const Duration(seconds: 10));
    if (check.contains('OK')) {
      _adbReady = true;
      notifyListeners();
      return true;
    }
    final res = await ApkService.run(['add', '--no-cache', 'android-tools'],
        onLine: onLine);
    _adbReady = res.ok;
    notifyListeners();
    return res.ok;
  }

  Future<List<AdbDevice>> refreshDevices() async {
    if (!_adbReady) await ensureAdb();
    final lines =
        await _collectInRootfs([_adbBin, 'devices', '-l'], timeout: const Duration(seconds: 15));
    final found = <AdbDevice>[];
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.contains('device:') && !trimmed.contains('offline')
          && !trimmed.contains('unauthorized')) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final modelMatch = RegExp(r'model:(\S+)').firstMatch(trimmed);
      found.add(AdbDevice(
        serial: parts.first,
        state: parts[1],
        model: modelMatch?.group(1) ?? '',
      ));
    }
    _devices = found;
    notifyListeners();
    return found;
  }

  /// Appairage Wireless Debugging (Android 11+) vers soi-même.
  Future<bool> pair(String port, String pairingCode,
      {void Function(String line)? onLine}) async {
    if (!_adbReady) await ensureAdb(onLine: onLine);
    final proc = await _startInRootfs(
      ['$_adbBin pair 127.0.0.1:$port ${pairingCode.trim()}'],
      onLine: onLine,
    );
    final code = await proc.exitCode;
    notifyListeners();
    return code == 0;
  }

  /// Connexion au port de débogage sans fil (pas celui d'appairage).
  Future<bool> connect(String port, {void Function(String line)? onLine}) async {
    if (!_adbReady) await ensureAdb(onLine: onLine);
    final proc = await _startInRootfs(
      ['$_adbBin connect 127.0.0.1:$port'],
      onLine: onLine,
    );
    final code = await proc.exitCode;
    await refreshDevices();
    return code == 0;
  }

  Future<String> flutterDoctor() async {
    final out = await _collectInRootfs(
      ['flutter doctor --no-version-check 2>&1 || echo FLUTTER_NOT_IN_PATH'],
      timeout: const Duration(minutes: 2),
      extraEnv: _flutterEnv(),
      extraBinds: _flutterBinds(),
    );
    return out.join('\n');
  }

  Map<String, String> _flutterEnv() => {
        'FLUTTER_ROOT': '/opt/flutter',
        'PUB_CACHE': '/opt/flutter/.pub-cache',
        'FLUTTER_SUPPRESS_ANALYTICS': 'true',
        'PATH':
            '/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        'ANDROID_HOME': '/opt/android-sdk',
      };

  List<String> _flutterBinds() => [
        '$runtimesDir/flutter:/opt/flutter',
        if (Directory('$runtimesDir/android-sdk').existsSync())
          '$runtimesDir/android-sdk:/opt/android-sdk',
      ];

  // ── flutter run (preview native sur le même téléphone) ────────────────────

  bool _running = false;
  bool get isRunning => _running;

  /// Lance `flutter run` dans le projet monté sur /root/workspace.
  /// [deviceId] : serial adb, ou 'web-server' pour un preview navigateur.
  Future<bool> startRun({
    required String deviceId,
    void Function(String line)? onLine,
  }) async {
    if (_running) return false;
    final dartTarget = deviceId == 'web-server'
        ? '-d web-server --web-hostname 127.0.0.1 --web-port 8090'
        : '-d $deviceId';
    try {
      _runProcess = await _startInRootfs([
        'cd /root/workspace 2>/dev/null || exit 1\n'
            'flutter pub get && flutter run $dartTarget'
      ],
          onLine: onLine,
          extraEnv: _flutterEnv(),
          extraBinds: _flutterBinds());
      _running = true;
      notifyListeners();
      unawaited(_runProcess!.exitCode.whenComplete(() {
        _running = false;
        _runProcess = null;
        notifyListeners();
      }));
      return true;
    } catch (_) {
      _running = false;
      notifyListeners();
      return false;
    }
  }

  /// Envoie une touche au process flutter run : 'r' reload, 'R' restart, 'q' quit.
  void sendRunKey(String key) {
    _runProcess?.stdin.writeln(key);
  }

  void stopRun() {
    _runProcess?.kill(ProcessSignal.sigterm);
    _runProcess = null;
    _running = false;
    notifyListeners();
  }

  // ── Fallback Shizuku (install APK sans réseau) ────────────────────────────

  Future<bool> shizukuAvailable() => ShizukuService.instance.isAvailable();

  Future<bool> shizukuInstallApk(String apkPathOnAndroid) =>
      ShizukuService.instance.pmInstall(apkPathOnAndroid).then((r) => r.ok);

  // ── Vérification et installation automatique de packages ─────────────────

  /// Vérifie si un binaire est disponible dans le rootfs Alpine.
  Future<bool> checkPackage(String bin) async {
    final out = await _collectInRootfs(['which $bin 2>/dev/null && echo OK'],
        timeout: const Duration(seconds: 10));
    return out.any((l) => l.trim() == 'OK');
  }

  /// Installe une liste de packages manquants via apk add.
  Future<void> installPackages(List<String> packages,
      {void Function(String line)? onLine}) async {
    if (packages.isEmpty) return;
    await ApkService.run(['add', '--no-cache', ...packages],
        onLine: onLine);
  }

  // ── Découverte automatique du port de débogage (mDNS) ─────────────────────

  /// Tente de découvrir le port de débogage via adb mdns services.
  /// Retourne le port de connexion (pas le port d'appairage).
  Future<String?> discoverDebugPort() async {
    if (!_adbReady) return null;
    try {
      final lines = await _collectInRootfs(
        ['$_adbBin mdns services 2>/dev/null'],
        timeout: const Duration(seconds: 10),
      );
      for (final line in lines) {
        // Chercher _adb-tls-connect._tcp → contient le port de connexion
        if (line.contains('_adb-tls-connect')) {
          final portMatch = RegExp(r':(\d{4,5})').firstMatch(line);
          if (portMatch != null) return portMatch.group(1);
        }
      }
      // Fallback : chercher n'importe quel port dans le résultat
      for (final line in lines) {
        final portMatch = RegExp(r':(\d{4,5})').firstMatch(line);
        if (portMatch != null) return portMatch.group(1);
      }
    } catch (_) {}
    return null;
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  /// Vérifie si la permission POST_NOTIFICATIONS est accordée.
  Future<bool> isPostNotificationsGranted() async {
    // Sur Android < 13, toujours accordé
    if (await _getSdkVersion() < 33) return true;
    try {
      final result = await MethodChannel('panda.ide/permissions')
          .invokeMethod<bool>('isPostNotificationsGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Demande la permission POST_NOTIFICATIONS.
  Future<void> requestPostNotificationsPermission() async {
    try {
      await MethodChannel('panda.ide/permissions')
          .invokeMethod('requestPostNotificationsPermission');
    } catch (_) {}
  }

  Future<int> _getSdkVersion() async {
    try {
      final result = await MethodChannel('panda.ide/permissions')
          .invokeMethod<int>('getSdkVersion');
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
