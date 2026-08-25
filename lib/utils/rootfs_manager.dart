import 'dart:io';
import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panda/utils/panda_log.dart';

/// Supported terminal runtime environments.
enum TerminalType {
  debian('debian', 'Debian GNU/Linux (glibc)',
      'Most compatible — supports Chromium, patchright, all glibc packages'),
  alpine('alpine', 'Alpine Linux (musl)',
      'Lightweight — smaller rootfs, limited glibc compatibility'),
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

  const RootfsInfo({
    required this.version,
    required this.url,
    required this.sizeBytes,
  });

  factory RootfsInfo.fromJson(Map<String, dynamic> json) {
    return RootfsInfo(
      version: json['version'] as String,
      url: json['url'] as String,
      sizeBytes: json['size_bytes'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'url': url,
        'size_bytes': sizeBytes,
      };
}

/// Progress callback for downloads.
typedef ProgressCallback = void Function(double progress, int downloaded, int total);

/// RootfsManager handles downloading, caching, switching, and deleting
/// terminal rootfs images (Debian, Alpine, Bionic).
///
/// Key design:
/// - Download happens ONCE per terminal type on first install
/// - APK updates do NOT trigger re-download
/// - Switching terminals downloads new rootfs, optionally deletes old
/// - All rootfs data in app documents (deleted with uninstall)
class RootfsManager {
  static const String _githubBase =
      'https://github.com/ferelking242/panda-ide/releases/download/rootfs';

  static final Map<TerminalType, RootfsInfo> manifest = {
    TerminalType.debian: RootfsInfo(
      version: '1.0.0',
      url: '$_githubBase/debian-arm64-v1.0.0.tar.gz',
      sizeBytes: 90 * 1024 * 1024,
    ),
    TerminalType.alpine: RootfsInfo(
      version: '1.0.0',
      url: '$_githubBase/alpine-arm64-v1.0.0.tar.gz',
      sizeBytes: 4 * 1024 * 1024,
    ),
  };

  /// Rootfs directory for a terminal type.
  static Future<Directory> rootfsDir(TerminalType type) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminals/${type.id}');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Cache directory for downloads.
  static Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminals/_cache');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Check if rootfs is installed and valid.
  static Future<bool> isInstalled(TerminalType type) async {
    if (type == TerminalType.bionic) return true;
    final dir = await rootfsDir(type);
    final marker = File('${dir.path}/.panda-rootfs-version');
    if (!marker.existsSync()) return false;
    final installedVersion = marker.readAsStringSync().trim();
    final info = manifest[type];
    if (info == null) return false;
    return installedVersion == info.version && await _validateRootfs(dir, type);
  }

  /// Validate rootfs integrity.
  static Future<bool> _validateRootfs(Directory dir, TerminalType type) async {
    switch (type) {
      case TerminalType.debian:
        return File('${dir.path}/bin/sh').existsSync() &&
            File('${dir.path}/usr/bin/apt').existsSync();
      case TerminalType.alpine:
        return File('${dir.path}/bin/sh').existsSync() &&
            File('${dir.path}/sbin/apk').existsSync();
      case TerminalType.bionic:
        return true;
    }
  }

  /// Download and install a rootfs. Returns true on success.
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
      final archiveFile = File('${cacheDir.path}/${type.id}-${info.version}.tar.gz');

      // Download if not cached
      if (!archiveFile.existsSync()) {
        await _downloadFile(info.url, archiveFile, onProgress);
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
        PandaLog.e('RootfsManager', 'Validation failed for ${type.id}');
        await stagingDir.delete(recursive: true);
        return false;
      }

      // Write version marker
      await File('${stagingDir.path}/.panda-rootfs-version')
          .writeAsString(info.version, flush: true);

      // Atomic rename
      final target = await rootfsDir(type);
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      await stagingDir.rename(target.path);

      // Cleanup
      try {
        await archiveFile.delete();
      } catch (_) {}

      PandaLog.i('RootfsManager', '${type.displayName} installed OK');
      return true;
    } catch (e) {
      PandaLog.e('RootfsManager', 'Install failed: $e');
      return false;
    }
  }

  /// Delete a rootfs and its data.
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

  /// Format bytes to human-readable string.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Download file with progress.
  static Future<void> _downloadFile(
    String url,
    File file,
    ProgressCallback? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    final totalBytes = response.contentLength ?? 0;
    final bytes = <int>[];
    int downloaded = 0;

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      downloaded += chunk.length;
      onProgress?.call(
        totalBytes > 0 ? downloaded / totalBytes : 0,
        downloaded,
        totalBytes,
      );
    }

    await file.writeAsBytes(bytes, flush: true);
  }

  /// Extract tar.gz archive to destination.
  static Future<void> _extractTarball(File archive, Directory dest) async {
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
        final outFile = io.File(destPath);
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

    // Symlinks last
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
