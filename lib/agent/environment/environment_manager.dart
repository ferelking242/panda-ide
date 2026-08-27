import 'dart:io';

import 'executable_detector.dart';

/// Manages the execution environment detection and configuration.
class EnvironmentManager {
  Map<String, bool>? _detectedTools;
  DeviceInfo? _deviceInfo;

  /// Detect the current environment.
  Future<void> detect() async {
    _detectedTools = await ExecutableDetector.detectAll();
    _deviceInfo = await _detectDevice();
  }

  /// Get detected tools.
  Map<String, bool> get tools => _detectedTools ?? {};

  /// Check if a specific tool is available.
  bool hasTool(String name) => _detectedTools?[name] ?? false;

  /// Get device info.
  DeviceInfo get device => _deviceInfo ?? DeviceInfo.unknown();

  /// Get the environment PATH for process execution.
  String get path {
    return '/data/data/com.termux/files/usr/bin:'
        '/data/data/com.termux/files/usr/bin/applets:'
        '/data/user/0/com.pandaide.app/files/flutter/bin:'
        '/data/user/0/com.pandaide.app/files/dart-sdk/bin:'
        '${Platform.environment['PATH'] ?? ''}';
  }

  /// Get environment variables for process execution.
  Map<String, String> get environment => {
        'PATH': path,
        'HOME': '/data/data/com.termux/files/home',
        'TERM': 'xterm-256color',
      };

  Future<DeviceInfo> _detectDevice() async {
    try {
      final memInfo = await File('/proc/meminfo').readAsString();
      final totalRam = _parseMemInfo(memInfo);
      return DeviceInfo(totalRamMB: totalRam);
    } catch (_) {
      return DeviceInfo.unknown();
    }
  }

  int _parseMemInfo(String content) {
    for (final line in content.split('\n')) {
      if (line.startsWith('MemTotal:')) {
        final kb = int.tryParse(
          line.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (kb != null) return kb ~/ 1024;
      }
    }
    return 4096; // default assumption
  }
}

class DeviceInfo {
  final int totalRamMB;

  const DeviceInfo({required this.totalRamMB});

  factory DeviceInfo.unknown() => const DeviceInfo(totalRamMB: 4096);

  int get maxConcurrentAgents {
    if (totalRamMB >= 8192) return 3;
    if (totalRamMB >= 6144) return 2;
    if (totalRamMB >= 4096) return 2;
    return 1;
  }

  int get maxContextTokens {
    if (totalRamMB >= 8192) return 120000;
    if (totalRamMB >= 6144) return 80000;
    if (totalRamMB >= 4096) return 40000;
    return 20000;
  }
}
