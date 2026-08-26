import 'dart:io';
import 'dart:typed_data';

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
/// Extraction strategy (Kern approach):
/// 1. Download .tar.gz
/// 2. Decompress gzip → .tar using Dart's GZipCodec (always works)
/// 3. Extract .tar using Android's native tar (handles symlinks natively)
/// 4. Repair any broken symlinks by copying target files
/// 5. Validate with simple file existence checks (no symlink chains)
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

  /// Validate rootfs using simple file existence checks.
  /// Mirrors Kern's rootfsLooksComplete: check non-symlink files directly.
  static Future<bool> _validateRootfs(
      Directory dir, TerminalType type) async {
    switch (type) {
      case TerminalType.ubuntu:
      case TerminalType.debian:
        // Check real files (not symlinks) — same strategy as Kern.
        // usr/bin/bash is always a real file in Ubuntu/Debian rootfs.
        final bashOk = File('${dir.path}/usr/bin/bash').existsSync();
        // usr/bin/apt-get is always a real file.
        final aptOk = File('${dir.path}/usr/bin/apt-get').existsSync();
        // etc/os-release is always a real file.
        final osRelease = File('${dir.path}/etc/os-release').existsSync();
        // var/lib/dpkg/status is always a real file.
        final dpkgOk = File('${dir.path}/var/lib/dpkg/status').existsSync();
        PandaLog.i('RootfsManager',
            'Validate ${type.id}: bash=$bashOk apt=$aptOk os=$osRelease dpkg=$dpkgOk');
        return bashOk && aptOk && osRelease && dpkgOk;
      case TerminalType.alpine:
        // Alpine has real /bin/sh (no usrmerge).
        final shOk = File('${dir.path}/bin/sh').existsSync();
        final apkOk = File('${dir.path}/sbin/apk').existsSync();
        PandaLog.i('RootfsManager',
            'Validate alpine: sh=$shOk apk=$apkOk');
        return shOk && apkOk;
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

      // Step 1: Decompress gzip → tar using Dart's GZipCodec.
      // This always works — no dependency on Android's native gzip support.
      PandaLog.i('RootfsManager', 'Decompressing gzip...');
      final tarFile = File('${cacheDir.path}/${type.id}-${info.version}.tar');
      if (!tarFile.existsSync()) {
        try {
          final gzipBytes = await archiveFile.readAsBytes();
          final tarBytes = Uint8List.fromList(gzip.decode(gzipBytes));
          await tarFile.writeAsBytes(tarBytes, flush: true);
          PandaLog.i('RootfsManager',
              'Decompressed: ${gzipBytes.length} → ${tarBytes.length} bytes');
        } catch (e) {
          PandaLog.e('RootfsManager', 'Gzip decompression failed: $e');
          await archiveFile.delete();
          return false;
        }
      }

      // Step 2: Extract tar using Android's native tar (no -z flag).
      final staging = Directory('${cacheDir.path}/${type.id}.staging');
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);

      final extracted = await _extractWithNativeTar(tarFile, staging);
      if (!extracted) {
        PandaLog.e('RootfsManager', 'Extraction failed for ${type.id}');
        await staging.delete(recursive: true);
        await tarFile.delete();
        return false;
      }

      // Step 3: Repair broken symlinks by copying target files.
      // On Android, symlinks may fail due to SELinux restrictions.
      await _repairBrokenSymlinks(staging);

      // Step 4: Validate
      if (!await _validateRootfs(staging, type)) {
        PandaLog.e('RootfsManager', 'Validation failed for ${type.id}');
        // Dump directory listing for debugging
        try {
          final listing = staging.listSync().take(30).map((e) => e.path).join('\n');
          PandaLog.e('RootfsManager', 'Top-level contents:\n$listing');
        } catch (_) {}
        await staging.delete(recursive: true);
        await tarFile.delete();
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
      try {
        await tarFile.delete();
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

  /// Repair broken symlinks in extracted rootfs.
  ///
  /// On Android, symlinks may not be created correctly due to SELinux.
  /// For each broken symlink, we either:
  /// - Create a copy of the target file, or
  /// - Create a relative symlink that works
  static Future<void> _repairBrokenSymlinks(Directory root) async {
    int fixed = 0;
    int skipped = 0;
    int copied = 0;

    try {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! Link) continue;

        // Check if the symlink target exists
        if (entity.existsSync()) continue; // Symlink works fine

        // Try to resolve the target
        final target = entity.target;
        File? targetFile;

        if (target.startsWith('/')) {
          // Absolute symlink — resolve relative to root
          targetFile = File('${root.path}$target');
        } else {
          // Relative symlink — resolve relative to parent
          final parentDir = Directory(entity.parent.path);
          targetFile = File('${parentDir.path}/$target');
          // Normalize path (resolve ..)
          final normalized = targetFile.path.replaceAll(RegExp(r'[^/]+/\.\./'), '');
          targetFile = File(normalized);
        }

        if (targetFile.existsSync()) {
          // Copy the target file instead of creating a symlink
          try {
            final data = await targetFile.readAsBytes();
            // Delete the broken link
            await entity.delete();
            // Create a real file with the same content
            await File(entity.path).writeAsBytes(data, flush: true);
            copied++;
          } catch (_) {
            skipped++;
          }
        } else {
          skipped++;
        }

        fixed++;
      }
    } catch (e) {
      PandaLog.e('RootfsManager', 'Symlink repair error: $e');
    }

    if (copied > 0 || skipped > 0) {
      PandaLog.i('RootfsManager',
          'Symlink repair: copied=$copied skipped=$skipped');
    }
  }

  /// Extract tar using Android's native tar (no -z flag needed).
  ///
  /// Since we already decompressed gzip → tar with Dart, we only need
  /// native tar to handle the tar format (including symlinks and hard links).
  /// This is the Kern approach: use Android's toybox tar for extraction.
  static Future<bool> _extractWithNativeTar(
      File archive, Directory dest) async {
    PandaLog.i('RootfsManager',
        'Extracting with native tar: ${archive.path} -> ${dest.path}');

    // Primary: Android's /system/bin/tar (toybox)
    final result = await Process.run(
      '/system/bin/tar',
      ['-xf', archive.path, '-C', dest.path],
    );

    if (result.exitCode == 0) {
      int fileCount = 0;
      try {
        await for (final _ in dest.list(recursive: true)) {
          fileCount++;
          if (fileCount > 5000) break; // Safety limit
        }
      } catch (_) {}
      PandaLog.i('RootfsManager',
          'Native tar extraction OK: $fileCount+ entries');
      return fileCount > 10; // Sanity check: rootfs should have many files
    }

    PandaLog.w('RootfsManager',
        'Native tar failed (exit ${result.exitCode}): ${result.stderr}');

    // Fallback 1: busybox tar
    try {
      final fallback1 = await Process.run(
        'busybox',
        ['tar', '-xf', archive.path, '-C', dest.path],
      );
      if (fallback1.exitCode == 0) {
        PandaLog.i('RootfsManager', 'Busybox tar extraction OK');
        return true;
      }
    } catch (_) {}

    // Fallback 2: /system/bin/busybox tar
    try {
      final fallback2 = await Process.run(
        '/system/bin/busybox',
        ['tar', '-xf', archive.path, '-C', dest.path],
      );
      if (fallback2.exitCode == 0) {
        PandaLog.i('RootfsManager', '/system/bin/busybox tar OK');
        return true;
      }
    } catch (_) {}

    // Fallback 3: tar with verbose to get error details
    try {
      final fallback3 = await Process.run(
        '/system/bin/tar',
        ['-xvf', archive.path, '-C', dest.path],
      );
      PandaLog.e('RootfsManager',
          'Tar verbose stderr: ${fallback3.stderr}');
      // Even with warnings, check if files were extracted
      int count = 0;
      try {
        await for (final _ in dest.list(recursive: true)) {
          count++;
          if (count > 10) break;
        }
      } catch (_) {}
      if (count > 0) {
        PandaLog.i('RootfsManager',
            'Tar extracted $count+ entries despite warnings');
        return true;
      }
    } catch (_) {}

    PandaLog.e('RootfsManager', 'All tar methods failed');
    return false;
  }
}
