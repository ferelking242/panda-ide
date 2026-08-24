/// ShizukuService — wraps the native Shizuku bridge via MethodChannel.
///
/// Shizuku provides ADB-level shell access on Android without root,
/// using a privileged server started once via ADB pairing / wireless debugging.
///
/// Usage:
///   final ok = await ShizukuService.instance.isAvailable();
///   if (ok) {
///     final result = await ShizukuService.instance.exec('pm install -r /path/to.apk');
///   }
import 'dart:async';
import 'package:flutter/services.dart';

library;


class ShizukuExecResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ShizukuExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;

  @override
  String toString() =>
      'ShizukuExecResult(exit=$exitCode, out=$stdout, err=$stderr)';
}

class ShizukuService {
  ShizukuService._();
  static final ShizukuService instance = ShizukuService._();

  static const _channel = MethodChannel('com.panda.ide/shizuku');

  // ── Availability ─────────────────────────────────────────────────────────

  /// Returns true if the Shizuku app is installed AND its server is running.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Returns true if Panda IDE currently holds Shizuku permission.
  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Requests Shizuku permission; shows the system dialog if needed.
  /// Returns true if the user granted the permission.
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ── Execution ─────────────────────────────────────────────────────────────

  /// Executes a shell command via the Shizuku privileged binder.
  /// The command runs with ADB-level privileges (uid=2000).
  Future<ShizukuExecResult> exec(String command) async {
    try {
      final raw = await _channel.invokeMethod<Map>('exec', {'command': command});
      if (raw == null) {
        return const ShizukuExecResult(
            exitCode: -1, stdout: '', stderr: 'Null response from native');
      }
      return ShizukuExecResult(
        exitCode: (raw['exitCode'] as int?) ?? -1,
        stdout: (raw['stdout'] as String?) ?? '',
        stderr: (raw['stderr'] as String?) ?? '',
      );
    } on PlatformException catch (e) {
      return ShizukuExecResult(
          exitCode: -1, stdout: '', stderr: e.message ?? e.toString());
    }
  }

  /// Installs an APK using `pm install` via Shizuku.
  /// Returns success/failure with a reason string.
  Future<({bool ok, String message})> pmInstall(String apkPath,
      {bool replace = true}) async {
    final flags = replace ? '-r -t' : '-t';
    final result = await exec('pm install $flags "$apkPath"');
    final ok = result.success || result.stdout.contains('Success');
    return (ok: ok, message: result.success ? result.stdout : result.stderr);
  }

  // ── State stream ──────────────────────────────────────────────────────────

  /// Emits true/false whenever Shizuku server availability changes.
  Stream<bool> get availabilityStream {
    const eventChannel = EventChannel('com.panda.ide/shizuku_events');
    return eventChannel
        .receiveBroadcastStream()
        .map((e) => e == true || e == 'connected');
  }
}
