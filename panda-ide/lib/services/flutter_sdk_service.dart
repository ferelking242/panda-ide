/// FlutterSdkService — manages the embedded Flutter SDK runtime.
///
/// The Flutter SDK lives at $runtimesDir/flutter/ and contains:
///   bin/flutter  — CLI
///   bin/dart     — Dart SDK (replaces the standalone dart runtime)
///   .pub-cache/  — global pub cache
///
/// This service checks installation state and provides the env-var map
/// that the terminal PTY must inject.
library;

import 'dart:io';
import '../utils/constants.dart';

/// All env vars the PTY should inject when Flutter SDK is present.
Map<String, String> flutterEnvVars({required String sharedPath}) {
  final flutterRoot = '$runtimesDir/flutter';
  final androidSdk  = '$runtimesDir/android-sdk';
  return {
    'FLUTTER_ROOT': flutterRoot,
    'PUB_CACHE'   : '$flutterRoot/.pub-cache',
    'PUB_HOSTED_URL'        : 'https://pub.dartlang.org',
    'FLUTTER_STORAGE_BASE_URL': 'https://storage.googleapis.com',
    'ANDROID_HOME'    : androidSdk,
    'ANDROID_SDK_ROOT': androidSdk,
    // Tell Flutter/Dart not to prompt for analytics
    'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    'DART_VM_OPTIONS': '--disable-dart-dev',
  };
}

/// Full PATH string to inject when Flutter SDK is present.
String buildFullPath({
  required String sharedPath,
  required String existingPath,
}) {
  final flutterBin    = '$runtimesDir/flutter/bin';
  final platformTools = '$runtimesDir/android-sdk/platform-tools';
  final buildTools    = '$runtimesDir/android-sdk/build-tools/current';

  // Prepend Flutter paths so they shadow any system Dart/flutter
  final extra = [flutterBin, platformTools, buildTools]
      .where((p) => !existingPath.contains(p))
      .join(':');

  return extra.isEmpty ? existingPath : '$extra:$existingPath';
}

class FlutterSdkService {
  FlutterSdkService._();
  static final FlutterSdkService instance = FlutterSdkService._();

  static const _flutterBin = '$runtimesDir/flutter/bin/flutter';
  static const _dartBin    = '$runtimesDir/flutter/bin/dart';

  // ── Installation state ────────────────────────────────────────────────────

  bool get isInstalled => File(_flutterBin).existsSync();

  bool get isDartInstalled => File(_dartBin).existsSync();

  /// Returns installed Flutter version string, or null if not installed.
  Future<String?> installedVersion() async {
    if (!isInstalled) return null;
    try {
      final r = await Process.run(
        _flutterBin,
        ['--version', '--machine'],
        environment: {'HOME': homeDir},
        runInShell: false,
      );
      if (r.exitCode != 0) return null;
      // Output contains "flutterVersion": "3.x.x"
      final match = RegExp(r'"flutterVersion"\s*:\s*"([^"]+)"')
          .firstMatch(r.stdout.toString());
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  // ── Setup verification ────────────────────────────────────────────────────

  /// Runs `flutter doctor --no-version-check` and returns the raw output.
  /// Useful for verifying the installation after download.
  Future<String> runDoctor() async {
    if (!isInstalled) return 'Flutter SDK not installed.';
    try {
      final r = await Process.run(
        _flutterBin,
        ['doctor', '--no-version-check'],
        environment: {
          'HOME'       : homeDir,
          'FLUTTER_ROOT': '$runtimesDir/flutter',
          'PUB_CACHE'  : '$runtimesDir/flutter/.pub-cache',
          'FLUTTER_SUPPRESS_ANALYTICS': 'true',
          'PATH'       : '$runtimesDir/flutter/bin:/bin:/usr/bin',
        },
        runInShell: false,
      );
      return r.stdout.toString() + r.stderr.toString();
    } catch (e) {
      return 'Error running flutter doctor: $e';
    }
  }

  // ── Pre-cache ─────────────────────────────────────────────────────────────

  /// Runs `flutter precache --android` after initial install.
  /// Call this once immediately after extraction completes.
  Future<bool> precache() async {
    if (!isInstalled) return false;
    try {
      final r = await Process.run(
        _flutterBin,
        ['precache', '--android', '--no-ios', '--no-web',
         '--no-macos', '--no-windows', '--no-linux', '--no-fuchsia'],
        environment: {
          'HOME'       : homeDir,
          'FLUTTER_ROOT': '$runtimesDir/flutter',
          'PUB_CACHE'  : '$runtimesDir/flutter/.pub-cache',
          'FLUTTER_SUPPRESS_ANALYTICS': 'true',
          'PATH'       : '$runtimesDir/flutter/bin:/bin:/usr/bin',
        },
        runInShell: false,
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
