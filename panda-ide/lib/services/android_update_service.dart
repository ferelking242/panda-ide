import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '2.3.3',
);
const appBuildNumber = int.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: 39,
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

class AndroidUpdateService {
  static const _channel = MethodChannel('panda/update');
  static const _latestReleaseUrl =
      'https://api.github.com/repos/ferelking242/panda-ide/releases/latest';

  static Future<AndroidUpdateInfo?> checkForUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    final response = await http.get(
      Uri.parse(_latestReleaseUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final release = jsonDecode(response.body);
    if (release is! Map) return null;
    final tag = release['tag_name']?.toString() ?? '';
    final match = RegExp(r'^v(.+)-build[.-](\d+)$').firstMatch(tag);
    if (match == null) return null;

    final buildNumber = int.tryParse(match.group(2)!) ?? 0;
    if (buildNumber <= appBuildNumber) return null;

    final assets = release['assets'];
    if (assets is! List) return null;
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
    if (apk == null) return null;

    return AndroidUpdateInfo(
      version: match.group(1)!,
      buildNumber: buildNumber,
      releaseUrl: release['html_url']?.toString() ?? '',
      apkUrl: apk['browser_download_url']?.toString() ?? '',
      apkName: apk['name']?.toString() ?? 'panda-ide-update.apk',
      notes: release['body']?.toString() ?? '',
    );
  }

  /// Download APK to local storage with progress callback (0.0–1.0).
  /// Returns the local file path when done.
  static Future<String> downloadApkWithProgress(
    AndroidUpdateInfo update, {
    required void Function(double progress) onProgress,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Android only');
    }
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/${update.apkName}');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await client.send(request);
      final totalBytes = response.contentLength ?? 0;
      int received = 0;

      final sink = dest.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress((received / totalBytes).clamp(0.0, 1.0));
        }
      }
      await sink.close();
    } finally {
      client.close();
    }

    return dest.path;
  }

  /// Install an APK that was already downloaded locally.
  static Future<bool> installLocalApk(String filePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final result = await _channel.invokeMethod<bool>(
      'installLocalApk',
      {'path': filePath},
    );
    return result == true;
  }

  /// Legacy: download + install in one shot via native channel.
  static Future<bool> install(AndroidUpdateInfo update) async {
    if (update.apkUrl.isEmpty) return false;
    final result = await _channel.invokeMethod<bool>(
      'downloadAndInstallApk',
      {'url': update.apkUrl, 'filename': update.apkName},
    );
    return result == true;
  }
}
