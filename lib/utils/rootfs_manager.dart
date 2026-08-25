import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panda/utils/panda_log.dart';

/// Supported terminal runtime environments.
enum TerminalType {
  debian('debian', 'Debian GNU/Linux (glibc)', 'Most compatible — supports Chromium, patchright, all glibc packages'),
  alpine('alpine', 'Alpine Linux (musl)', 'Lightweight — smaller rootfs, limited glibc compatibility'),
  bionic('bionic', 'Android Bionic', 'Native Android — no download needed, limited Linux tools');

  final String id;
  final String displayName;
  final String description;

  const TerminalType(this.id, this.displayName, this.description);

  static TerminalType fromString(String value) {
    return TerminalType.values.firstWhere(
      (t) => t.id == value,
      orElse: () => TerminalType.debian,
    );
  }
}

/// Rootfs metadata for versioning and download.
class RootfsInfo {
  final String version;
  final String url;
  final int sizeBytes;
  final String sha256;

  const RootfsInfo({
    required this.version,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
  });

  factory RootfsInfo.fromJson(Map<String, dynamic> json) {
    return RootfsInfo(
      version: json['version'] as String,
      url: json['url'] as String,
      sizeBytes: json['size_bytes'] as int,
      sha256: json['sha256'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'url': url,
        'size_bytes': sizeBytes,
        'sha256': sha256,
      };
}

/// Download progress callback.
typedef ProgressCallback = void Function(double progress, int downloaded, int total);

/// RootfsManager handles downloading, caching, switching, and deleting
/// terminal rootfs images (Debian, Alpine, Bionic).
///
/// Key design principles:
/// - Download happens ONCE on first install per terminal type
/// - APK updates do NOT trigger re-download
/// - Switching terminals downloads the new rootfs, deletes the old
/// - All rootfs data lives in app documents (deleted with uninstall)
class RootfsManager {
  static RootfsInfo? _debianInfo;
  static RootfsInfo? _alpineInfo;

  // GitHub release URLs for rootfs tarballs
  static const String _githubReleaseBase =
      'https://github.com/ferelking242/panda-ide/releases/download/rootfs';

  /// Manifest: maps terminal type to release info
  static final Map<TerminalType, RootfsInfo> _manifest = {
    TerminalType.debian: RootfsInfo(
      version: '1.0.0',
      url: '$_githubReleaseBase/debian-arm64-v1.0.0.tar.gz',
      sizeBytes: 90 * 1024 * 1024, // ~90MB
    ),
    TerminalType.alpine: RootfsInfo(
      version: '1.0.0',
      url: '$_githubReleaseBase/alpine-arm64-v1.0.0.tar.gz',
      sizeBytes: 4 * 1024 * 1024, // ~4MB
    ),
  };

  /// Get the rootfs directory for a given terminal type.
  static Future<Directory> rootfsDir(TerminalType type) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminals/${type.id}');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Get the download cache directory.
  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminals/_cache');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Check if a rootfs is installed and valid for the given terminal type.
  static Future<bool> isInstalled(TerminalType type) async {
    if (type == TerminalType.bionic) return true; // Always available on Android

    final dir = await rootfsDir(type);
    final marker = File('${dir.path}/.panda-rootfs-version');
    if (!marker.existsSync()) return false;

    final installedVersion = marker.readAsStringSync().trim();
    final manifest = _manifest[type];
    if (manifest == null) return false;

    return installedVersion == manifest.version && await _validateRootfs(dir, type);
  }

  /// Validate rootfs integrity for a given type.
  static Future<bool> _validateRootfs(Directory dir, TerminalType type) async {
    switch (type) {
      case TerminalType.debian:
        return File('${dir.path}/bin/sh').existsSync() &&
            File('${dir.path}/usr/bin/apt').existsSync() &&
            File('${dir.path}/lib/aarch64-linux-gnu/libc.so.6').existsSync();
      case TerminalType.alpine:
        return File('${dir.path}/bin/sh').existsSync() &&
            File('${dir.path}/bin/busybox').existsSync() &&
            File('${dir.path}/sbin/apk').existsSync() &&
            File('${dir.path}/lib/ld-musl-aarch64.so.1').existsSync();
      case TerminalType.bionic:
        return true;
    }
  }

  /// Download and install a rootfs for the given terminal type.
  /// Returns true on success.
  static Future<bool> install(
    TerminalType type, {
    ProgressCallback? onProgress,
  }) async {
    if (type == TerminalType.bionic) return true;

    final manifest = _manifest[type];
    if (manifest == null) {
      PandaLog.e('RootfsManager', 'No manifest for terminal type: ${type.id}');
      return false;
    }

    // Check if already installed with same version
    if (await isInstalled(type)) {
      PandaLog.i('RootfsManager', '${type.displayName} already installed v${manifest.version}');
      return true;
    }

    PandaLog.i('RootfsManager', 'Downloading ${type.displayName} v${manifest.version}...');

    try {
      // Download to cache
      final cacheDir = await _cacheDir();
      final archiveFile = File('${cacheDir.path}/${type.id}-${manifest.version}.tar.gz');

      if (!archiveFile.existsSync()) {
        await _downloadFile(manifest.url, archiveFile, onProgress);
      }

      // Extract to staging
      final stagingDir = Directory('${cacheDir.path}/${type.id}.staging');
      if (stagingDir.existsSync()) {
        await stagingDir.delete(recursive: true);
      }
      await stagingDir.create(recursive: true);

      await _extractTarball(archiveFile, stagingDir);

      // Validate
      if (!await _validateRootfs(stagingDir, type)) {
        PandaLog.e('RootfsManager', 'Rootfs validation failed for ${type.id}');
        await stagingDir.delete(recursive: true);
        return false;
      }

      // Write version marker
      await File('${stagingDir.path}/.panda-rootfs-version')
          .writeAsString(manifest.version, flush: true);

      // Atomic rename: staging -> final
      final targetDir = await rootfsDir(type);
      if (targetDir.existsSync()) {
        await targetDir.delete(recursive: true);
      }
      await stagingDir.rename(targetDir.path);

      // Cleanup cache
      try { await archiveFile.delete(); } catch (_) {}

      PandaLog.i('RootfsManager', '${type.displayName} installed successfully');
      return true;
    } catch (e) {
      PandaLog.e('RootfsManager', 'Installation failed: $e');
      return false;
    }
  }

  /// Delete a rootfs and all its data.
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

  /// Get the currently active terminal type.
  static Future<TerminalType> getActiveTerminal() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('active_terminal') ?? 'debian';
    return TerminalType.fromString(value);
  }

  /// Set the active terminal type.
  static Future<void> setActiveTerminal(TerminalType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_terminal', type.id);
  }

  /// Get download progress for a terminal type.
  static Future<double> getDownloadProgress(TerminalType type) async {
    if (await isInstalled(type)) return 1.0;
    final cacheDir = await _cacheDir();
    final manifest = _manifest[type];
    if (manifest == null) return 0.0;
    final archive = File('${cacheDir.path}/${type.id}-${manifest.version}.tar.gz');
    if (!archive.existsSync()) return 0.0;
    return archive.lengthSync() / manifest.sizeBytes;
  }

  /// Get human-readable size string.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Download a file with progress callback.
  static Future<void> _downloadFile(
    String url,
    File file,
    ProgressCallback? onProgress,
  ) async {
    final client = http.Client();
    final request = await http.get(Uri.parse(url));
    final totalBytes = request.contentLength ?? 0;
    final bytes = <int>[];

    int downloaded = 0;
    await for (final chunk in request.bodyStream) {
      bytes.addAll(chunk);
      downloaded += chunk.length;
      onProgress?.call(
        totalBytes > 0 ? downloaded / totalBytes : 0,
        downloaded,
        totalBytes,
      );
    }

    await file.writeAsBytes(bytes, flush: true);
    await client.close();
  }

  /// Extract a tar.gz file to a destination directory.
  static Future<void> _extractTarball(File archive, Directory dest) async {
    // Use Dart's archive package
    import 'package:archive/archive.dart';

    final bytes = await archive.readAsBytes();
    final tarBytes = gzip.decode(bytes);
    final tarArchive = TarDecoder().decodeBytes(tarBytes);

    final symlinks = <ArchiveFile>[];

    for (final file in tarArchive) {
      final name = file.name.replaceFirst(RegExp(r'^\./'), '');
      if (name.isEmpty || name == '..' || name.contains('../')) continue;
      final destPath = '${dest.path}/$name';

      if (file.isSymbolicLink) {
        symlinks.add(file);
        continue;
      }

      if (file.isFile) {
        final outFile = File(destPath);
        await outFile.parent.create(recursive: true);
        final content = file.content;
        if (content is List<int>) {
          await outFile.writeAsBytes(content, flush: true);
        } else if (content != null) {
          await outFile.writeAsBytes(List<int>.from(content), flush: true);
        }
      } else {
        await Directory(destPath).create(recursive: true);
      }
    }

    // Create symlinks last
    for (final link in symlinks) {
      final name = link.name.replaceFirst(RegExp(r'^\./'), '');
      final destPath = '${dest.path}/$name';
      final target = link.symbolicLink;
      if (target == null || target.isEmpty) continue;
      try {
        final parent = File(destPath).parent;
        if (!parent.existsSync()) await parent.create(recursive: true);
        if (FileSystemEntity.typeSync(destPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          Link(destPath).deleteSync();
        }
        Link(destPath).createSync(target);
      } catch (e) {
        PandaLog.w('RootfsManager', 'Symlink failed: $name -> $target: $e');
      }
    }

    // Make binaries executable
    const execDirs = ['bin', 'sbin', 'usr/bin', 'usr/sbin', 'usr/local/bin', 'lib'];
    final targets = <String>[];
    for (final d in execDirs) {
      if (Directory('${dest.path}/$d').existsSync()) {
        targets.add('"${dest.path}/$d"');
      }
    }
    if (targets.isNotEmpty) {
      try {
        await Process.run('/system/bin/sh', ['-c', 'chmod -R 755 ${targets.join(' ')}']);
      } catch (_) {}
    }
  }
}
