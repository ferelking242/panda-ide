import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panda/utils/panda_log.dart';

/// Supported terminal runtime environments.
enum TerminalType {
  ubuntu('ubuntu', 'Ubuntu 24.04 LTS (glibc)',
      'Best compatibility — glibc native, apt works, most packages supported'),
  debian('debian', 'Debian GNU/Linux (glibc)',
      'Most compatible — supports Chromium, patchright, all glibc packages'),
  alpine('alpine', 'Alpine Linux (musl)',
      'Lightweight — smaller rootfs, limited glibc compatibility'),
  bionic('bionic', 'Android Bionic',
      'Native Android — no download needed, limited Linux tools');

  final String id;
  final String displayName;
  final String description;

  const TerminalType(this.id, this.displayName, this.description);

  static TerminalType fromString(String value) {
    return TerminalType.values.firstWhere(
      (t) => t.id == value,
      orElse: () => TerminalType.ubuntu,
    );
  }
}

/// Rootfs metadata for versioning and download.
class RootfsInfo {
  final String version;
  final String url;
  final int sizeBytes;

  const RootfsInfo({
    required this.version,
    required this.url,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'url': url,
        'size_bytes': sizeBytes,
      };
}

/// Progress callback for downloads.
typedef ProgressCallback = void Function(
    double progress, int downloaded, int total);

/// RootfsManager handles downloading, caching, switching, and deleting
/// terminal rootfs images (Ubuntu, Debian, Alpine, Bionic).
///
/// Extraction uses Android's native tar (the Kern approach) instead of
/// Dart's archive library which fails on symlink-heavy rootfs.
class RootfsManager {
  static const String _githubBase =
      'https://github.com/ferelking242/panda-ide/releases/download/v1.0.0';

  static final Map<TerminalType, RootfsInfo> manifest = {
    TerminalType.ubuntu: RootfsInfo(
      version: '1.0.0',
      url: '$_githubBase/ubuntu-arm64-rootfs.tar.gz',
      sizeBytes: 29 * 1024 * 1024,
    ),
    TerminalType.debian: RootfsInfo(
      version: '1.0.0',
      url: '$_githubBase/debian-arm64-rootfs.tar.gz',
      sizeBytes: 103 * 1024 * 1024,
    ),
    TerminalType.alpine: RootfsInfo(
      version: '1.0.0',
      url: '$_githubBase/alpine-arm64-rootfs.tar.gz',
      sizeBytes: 4 * 1024 * 1024,
    ),
  };

  static Future<Directory> rootfsDir(TerminalType type) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminals/${type.id}');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminals/_cache');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<bool> isInstalled(TerminalType type) async {
    if (type == TerminalType.bionic) return true;
    final dir = await rootfsDir(type);
    final marker = File('${dir.path}/.panda-rootfs-version');
    if (!marker.existsSync()) return false;
    final installedVersion = marker.readAsStringSync().trim();
    final info = manifest[type];
    if (info == null) return false;
    return installedVersion == info.version &&
        await _validateRootfs(dir, type);
  }

  /// Check if a file/dir exists via multiple candidate paths.
  static bool _exists(Directory base, List<String> candidates) {
    for (final c in candidates) {
      if (File('${base.path}/$c').existsSync()) return true;
      if (Directory('${base.path}/$c').existsSync()) return true;
    }
    return false;
  }

  static Future<bool> _validateRootfs(
      Directory dir, TerminalType type) async {
    switch (type) {
      case TerminalType.ubuntu:
      case TerminalType.debian:
        final shOk = _exists(dir, ['bin/sh', 'usr/bin/sh', 'usr/bin/bash']);
        final aptOk =
            _exists(dir, ['usr/bin/apt', 'bin/apt', 'usr/bin/apt-get']);
        PandaLog.i('RootfsManager',
            'Validate ${type.id}: sh=$shOk apt=$aptOk');
        return shOk && aptOk;
      case TerminalType.alpine:
        return _exists(dir, ['bin/sh', 'usr/bin/sh']) &&
            _exists(dir, ['sbin/apk', 'usr/sbin/apk', 'bin/apk']);
      case TerminalType.bionic:
        return true;
    }
  }

  static Future<bool> install(
    TerminalType type, {
    ProgressCallback? onProgress,
  }) async {
    if (type == TerminalType.bionic) return true;
    final info = manifest[type];
    if (info == null) {
      PandaLog.e('RootfsManager', 'No manifest for: ${type.id}');
      return false;
    }
    if (await isInstalled(type)) {
      PandaLog.i('RootfsManager', '${type.displayName} already installed');
      return true;
    }

    PandaLog.i('RootfsManager', 'Downloading ${type.displayName}...');
    try {
      final cacheDir = await _cacheDir();
      final archiveFile =
          File('${cacheDir.path}/${type.id}-${info.version}.tar.gz');

      if (!archiveFile.existsSync()) {
        await _downloadFile(info.url, archiveFile, onProgress);
      }

      // Verify gzip magic bytes
      try {
        final first = await archiveFile.openRead(0, 2).first;
        if (first.length < 2 || first[0] != 0x1f || first[1] != 0x8b) {
          PandaLog.e('RootfsManager', 'Not a valid gzip archive');
          await archiveFile.delete();
          return false;
        }
      } catch (_) {
        if (archiveFile.lengthSync() < 100) {
          PandaLog.e('RootfsManager', 'File too small');
          await archiveFile.delete();
          return false;
        }
      }

      // Extract to staging directory using native tar (Kern approach)
      final staging = Directory('${cacheDir.path}/${type.id}.staging');
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);

      final extracted = await _extractWithNativeTar(archiveFile, staging);
      if (!extracted) {
        PandaLog.e('RootfsManager', 'Extraction failed for ${type.id}');
        await staging.delete(recursive: true);
        return false;
      }

      // Validate
      if (!await _validateRootfs(staging, type)) {
        PandaLog.e('RootfsManager', 'Validation failed for ${type.id}');
        await staging.delete(recursive: true);
        return false;
      }

      // Write marker
      await File('${staging.path}/.panda-rootfs-version')
          .writeAsString(info.version, flush: true);

      // Atomic rename
      final target = await rootfsDir(type);
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      await staging.rename(target.path);

      try {
        await archiveFile.delete();
      } catch (_) {}

      PandaLog.i('RootfsManager', '${type.displayName} installed OK');
      return true;
    } catch (e, stack) {
      PandaLog.e('RootfsManager', 'Install failed: $e\n$stack');
      return false;
    }
  }

  static Future<bool> delete(TerminalType type) async {
    if (type == TerminalType.bionic) return false;
    try {
      final dir = await rootfsDir(type);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        PandaLog.i('RootfsManager', '${type.displayName} deleted');
      }
      return true;
    } catch (e) {
      PandaLog.e('RootfsManager', 'Delete failed: $e');
      return false;
    }
  }

  static Future<TerminalType> getActiveTerminal() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('active_terminal') ?? 'ubuntu';
    return TerminalType.fromString(v);
  }

  static Future<void> setActiveTerminal(TerminalType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_terminal', type.id);
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<void> _downloadFile(
    String url,
    File file,
    ProgressCallback? onProgress,
  ) async {
    final req = http.Request('GET', Uri.parse(url));
    final resp = await http.Client().send(req);
    final total = resp.contentLength ?? 0;
    final bytes = <int>[];
    int dl = 0;
    await for (final chunk in resp.stream) {
      bytes.addAll(chunk);
      dl += chunk.length;
      onProgress?.call(total > 0 ? dl / total : 0, dl, total);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Extract tar.gz using Android's native /system/bin/tar.
  ///
  /// This is the Kern approach: Android ships toybox tar which handles
  /// symlinks, hard links, and permissions natively. This completely
  /// avoids the Dart archive library's broken symlink handling.
  static Future<bool> _extractWithNativeTar(
      File archive, Directory dest) async {
    PandaLog.i('RootfsManager',
        'Extracting with native tar: ${archive.path} -> ${dest.path}');

    // Primary: Android's /system/bin/tar (toybox)
    final result = await Process.run(
      '/system/bin/tar',
      ['-xzf', archive.path, '-C', dest.path],
    );

    if (result.exitCode == 0) {
      int fileCount = 0;
      try {
        await for (final _ in dest.list(recursive: true)) {
          fileCount++;
        }
      } catch (_) {}
      PandaLog.i('RootfsManager',
          'Native tar extraction OK: $fileCount entries');
      return true;
    }

    PandaLog.w('RootfsManager',
        'Native tar failed (exit ${result.exitCode}): ${result.stderr}');

    // Fallback 1: busybox tar
    final fallback1 = await Process.run(
      'busybox',
      ['tar', '-xzf', archive.path, '-C', dest.path],
    );
    if (fallback1.exitCode == 0) {
      PandaLog.i('RootfsManager', 'Busybox tar extraction OK');
      return true;
    }

    // Fallback 2: /system/bin/busybox tar
    final fallback2 = await Process.run(
      '/system/bin/busybox',
      ['tar', '-xzf', archive.path, '-C', dest.path],
    );
    if (fallback2.exitCode == 0) {
      PandaLog.i('RootfsManager', '/system/bin/busybox tar OK');
      return true;
    }

    PandaLog.e('RootfsManager', 'All tar methods failed');
    return false;
  }
}
