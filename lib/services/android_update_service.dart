import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '2.3.3',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 50,
);

class AndroidUpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseUrl;
  final String apkUrl;
  final String apkName;
  final String notes;

  const AndroidUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseUrl,
    required this.apkUrl,
    required this.apkName,
    required this.notes,
  });

  String get tag => 'v$version-build.$buildNumber';
}

class AndroidUpdateState {
  final String status; // 'idle' | 'checking' | 'available' | 'downloading' | 'downloaded' | 'installing' | 'error'
  final double progress; // 0.0 to 1.0
  final String? bytesText;
  final AndroidUpdateInfo? updateInfo;
  final String? errorMessage;

  const AndroidUpdateState({
    this.status = 'idle',
    this.progress = 0.0,
    this.bytesText,
    this.updateInfo,
    this.errorMessage,
  });

  AndroidUpdateState copyWith({
    String? status,
    double? progress,
    String? bytesText,
    AndroidUpdateInfo? updateInfo,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AndroidUpdateState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesText: bytesText ?? this.bytesText,
      updateInfo: updateInfo ?? this.updateInfo,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AndroidUpdateService {
  static const _channel = MethodChannel('panda/update');
  static const _latestReleaseUrl =
      'https://api.github.com/repos/ferelking242/panda-ide/releases/latest';

  static final stateNotifier = ValueNotifier<AndroidUpdateState>(const AndroidUpdateState());
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final Map args = (call.arguments is Map) ? call.arguments as Map : {};
        final double p = (args['progress'] as num?)?.toDouble() ?? 0.0;
        final int bytes = (args['bytes'] as num?)?.toInt() ?? 0;
        final int total = (args['total'] as num?)?.toInt() ?? 0;
        final bytesMb = (bytes / (1024 * 1024)).toStringAsFixed(1);
        final totalMb = total > 0 ? (total / (1024 * 1024)).toStringAsFixed(1) : '?';

        stateNotifier.value = stateNotifier.value.copyWith(
          status: 'downloading',
          progress: p < 0 ? 0.0 : p.clamp(0.0, 1.0),
          bytesText: '$bytesMb / $totalMb MB',
        );
      } else if (call.method == 'onStatus') {
        final status = call.arguments?.toString();
        stateNotifier.value = stateNotifier.value.copyWith(
          status: status == 'downloaded' ? 'downloaded' : 'installing',
          progress: status == 'downloaded' ? 1.0 : stateNotifier.value.progress,
        );
      }
    });
  }

  static Future<AndroidUpdateInfo?> checkForUpdate() async {
    init();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    stateNotifier.value = stateNotifier.value.copyWith(status: 'checking');

    try {
      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        stateNotifier.value = stateNotifier.value.copyWith(status: 'idle');
        return null;
      }

      final release = jsonDecode(response.body);
      if (release is! Map) {
        stateNotifier.value = stateNotifier.value.copyWith(status: 'idle');
        return null;
      }
      final tag = release['tag_name']?.toString() ?? '';
      final match = RegExp(r'^v(.+)-build[.-](\d+)$').firstMatch(tag);
      if (match == null) {
        stateNotifier.value = stateNotifier.value.copyWith(status: 'idle');
        return null;
      }

      final buildNumber = int.tryParse(match.group(2)!) ?? 0;
      if (buildNumber <= appBuildNumber) {
        stateNotifier.value = stateNotifier.value.copyWith(status: 'idle');
        return null;
      }

      final assets = release['assets'];
      if (assets is! List) {
        stateNotifier.value = stateNotifier.value.copyWith(status: 'idle');
        return null;
      }
      Map? apk;
      for (final item in assets.whereType<Map>()) {
        final name = item['name']?.toString().toLowerCase() ?? '';
        if (name.endsWith('.apk') && name.contains('arm64')) {
          apk = item;
          break;
        }
      }
      if (apk == null) {
        for (final item in assets.whereType<Map>()) {
          final name = item['name']?.toString().toLowerCase() ?? '';
          if (name.endsWith('.apk')) {
            apk = item;
            break;
          }
        }
      }
      if (apk == null) {
        stateNotifier.value = stateNotifier.value.copyWith(status: 'idle');
        return null;
      }

      final update = AndroidUpdateInfo(
        version: match.group(1)!,
        buildNumber: buildNumber,
        releaseUrl: release['html_url']?.toString() ?? '',
        apkUrl: apk['browser_download_url']?.toString() ?? '',
        apkName: apk['name']?.toString() ?? 'panda-ide-update.apk',
        notes: release['body']?.toString() ?? '',
      );

      stateNotifier.value = stateNotifier.value.copyWith(
        status: 'available',
        updateInfo: update,
      );

      return update;
    } catch (e) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: 'idle',
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  static Future<AndroidUpdateInfo?> checkAndDownload() async {
    final update = await checkForUpdate();
    if (update == null) return null;
    await download(update);
    return update;
  }

  static Future<bool> download(AndroidUpdateInfo update) async {
    init();
    if (update.apkUrl.isEmpty) return false;

    stateNotifier.value = stateNotifier.value.copyWith(
      status: 'downloading',
      progress: 0.0,
      updateInfo: update,
      clearError: true,
    );

    try {
      final result = await _channel.invokeMethod<bool>(
        'downloadApk',
        {'url': update.apkUrl, 'filename': update.apkName},
      );
      if (result == true) {
        stateNotifier.value = stateNotifier.value.copyWith(
          status: 'downloaded',
          progress: 1.0,
          updateInfo: update,
        );
      }
      return result == true;
    } catch (error) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: 'error',
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  static Future<bool> installDownloaded(AndroidUpdateInfo update) async {
    init();
    stateNotifier.value = stateNotifier.value.copyWith(
      status: 'installing',
      progress: 1.0,
      updateInfo: update,
      clearError: true,
    );
    try {
      final result = await _channel.invokeMethod<bool>(
        'installDownloadedApk',
        {'filename': update.apkName},
      );
      return result == true;
    } catch (error) {
      stateNotifier.value = stateNotifier.value.copyWith(
        status: 'error',
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  /// Compatibility helper for callers that still request an install directly.
  /// It now downloads first and leaves installation as a separate action.
  static Future<bool> install(AndroidUpdateInfo update) async {
    if (stateNotifier.value.status != 'downloaded') {
      final downloaded = await download(update);
      if (!downloaded) return false;
    }
    return installDownloaded(update);
  }
}
