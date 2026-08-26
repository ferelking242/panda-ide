import 'dart:io';
import 'package:archive/archive.dart';
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
  bionic('bionic', 'Android Bionic', 'Native Android — no download needed, limited Linux tools');

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
/// terminal rootfs images (Ubuntu, Debian, Alpine, Bionic).
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

  /// Check if a file exists, trying multiple paths for symlink fallback.
  static bool _fileExists(Directory base, List<String> candidates) {
    for (final candidate in candidates) {
      final file = File('${base.path}/$candidate');
      if (file.existsSync()) return true;
      // Also try the directory version (some checks want dir existence)
      final dir = Directory('${base.path}/$candidate');
      if (dir.existsSync()) return true;
    }
    return false;
  }

  /// Validate rootfs integrity.
  static Future<bool> _validateRootfs(Directory dir, TerminalType type) async {
    switch (type) {
      case TerminalType.ubuntu:
      case TerminalType.debian:
        // Ubuntu/Debian have: bin -> usr/bin (symlink), usr/bin/sh -> dash (symlink)
        // On Android, symlinks may not work — check multiple paths
        final shExists = _fileExists(dir, [
          'bin/sh',
          'usr/bin/sh',
          'usr/bin/bash',
        ]);
        final aptExists = _fileExists(dir, [
          'usr/bin/apt',
          'bin/apt',
          'usr/bin/apt-get',
        ]);
        PandaLog.i('RootfsManager',
            'Validation ${type.id}: sh=$shExists apt=$aptExists');
        return shExists && aptExists;
      case TerminalType.alpine:
        return _fileExists(dir, [
          'bin/sh',
          'usr/bin/sh',
        ]) && _fileExists(dir, [
          'sbin/apk',
          'usr/sbin/apk',
          'bin/apk',
        ]);
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

      // Verify the downloaded file is actually a gzip
      try {
        final firstBytes = await archiveFile.openRead(0, 2).first;
        if (firstBytes.length < 2 || firstBytes[0] != 0x1f || firstBytes[1] != 0x8b) {
          PandaLog.e('RootfsManager', 'Downloaded file is NOT a valid gzip archive!');
          await archiveFile.delete();
          return false;
        }
      } catch (_) {
        // File might be empty
        if (archiveFile.lengthSync() < 100) {
          PandaLog.e('RootfsManager', 'Downloaded file too small, likely corrupt');
          await archiveFile.delete();
          return false;
        }
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
        PandaLog.e('RootfsManager',
            'staging exists: ${stagingDir.existsSync()}, '
            'contents: ${stagingDir.listSync().length} entries');
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
    } catch (e, stack) {
      PandaLog.e('RootfsManager', 'Install failed: $e\n$stack');
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
    final value = prefs.getString('active_terminal') ?? 'ubuntu';
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
  /// Handles Android symlink limitations by falling back to copies.
  static Future<void> _extractTarball(File archive, Directory dest) async {
    final bytes = await archive.readAsBytes();
    final tarBytes = GZipDecoder().decodeBytes(bytes);
    final tarArchive = TarDecoder().decodeBytes(tarBytes);

    // Collect symlinks to process after regular files
    final symlinks = <ArchiveFile>[];

    // First pass: extract all regular files and directories
    for (final file in tarArchive) {
      final name = file.name.replaceFirst(RegExp(r'^\./'), '');
      if (name.isEmpty || name == '..' || name.contains('../')) continue;

      if (file.isSymbolicLink) {
        symlinks.add(file);
        continue;
      }

      final destPath = '${dest.path}/$name';

      if (file.isFile) {
        final outFile = File(destPath);
        await outFile.parent.create(recursive: true);
        final content = file.content;
        if (content is List<int>) {
          await outFile.writeAsBytes(content, flush: true);
        } else if (content != null) {
          await outFile.writeAsBytes(List<int>.from(content), flush: true);
        }
      } else if (file.isDirectory) {
        await Directory(destPath).create(recursive: true);
      }
    }

    // Second pass: create symlinks, with Android fallback
    int symlinkSuccess = 0;
    int symlinkCopied = 0;

    for (final link in symlinks) {
      final name = link.name.replaceFirst(RegExp(r'^\./'), '');
      final destPath = '${dest.path}/$name';
      final target = link.symbolicLink;
      if (target == null || target.isEmpty) continue;

      final parent = File(destPath).parent;
      if (!parent.existsSync()) await parent.create(recursive: true);

      // Remove existing entry if any
      if (FileSystemEntity.typeSync(destPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        try {
          Link(destPath).deleteSync();
        } catch (_) {
          try { File(destPath).deleteSync(); } catch (_) {}
          try { Directory(destPath).deleteSync(recursive: true); } catch (_) {}
        }
      }

      // Try creating symlink
      bool symlinkOk = false;
      try {
        Link(destPath).createSync(target);
        // Verify it actually works
        if (FileSystemEntity.typeSync(destPath, followLinks: false) !=
            FileSystemEntityType.notFound) {
          symlinkOk = true;
          symlinkSuccess++;
        }
      } catch (e) {
        symlinkOk = false;
      }

      // If symlink failed, copy the target content
      if (!symlinkOk) {
        await _copySymlinkTarget(dest, name, target);
        symlinkCopied++;
      }
    }

    PandaLog.i('RootfsManager',
        'Extraction: ${tarArchive.length} entries, '
        '$symlinkSuccess symlinks OK, $symlinkCopied copied');

    // Make binaries executable
    const execDirs = ['bin', 'sbin', 'usr/bin', 'usr/sbin', 'usr/local/bin'];
    for (final d in execDirs) {
      final dirPath = '${dest.path}/$d';
      if (Directory(dirPath).existsSync()) {
        try {
          await Process.run(
              '/system/bin/sh', ['-c', 'chmod -R 755 "$dirPath" 2>/dev/null']);
        } catch (_) {}
      }
    }
  }

  /// Copy the content that a symlink was supposed to point to.
  /// Handles both file symlinks and directory symlinks.
  static Future<void> _copySymlinkTarget(
      Directory rootfsDest, String symlinkName, String target) async {
    final symlinkPath = '${rootfsDest.path}/$symlinkName';

    // Resolve the target path relative to the rootfs
    String resolvedTarget;
    if (target.startsWith('/')) {
      // Absolute path — resolve relative to rootfs
      resolvedTarget = '${rootfsDest.path}$target';
    } else {
      // Relative path — resolve from the symlink's directory
      final symlinkDir = File(symlinkPath).parent.path;
      resolvedTarget = '$symlinkDir/$target';
    }

    // Normalize (resolve ..)
    resolvedTarget = resolvedTarget.replaceAll(RegExp(r'[^/]+/\.\.'), '');

    // Check what the target is
    final targetFile = File(resolvedTarget);
    final targetDir = Directory(resolvedTarget);

    if (targetDir.existsSync()) {
      // Directory symlink — copy entire directory
      await _copyDirectory(targetDir, Directory(symlinkPath));
      PandaLog.i('RootfsManager',
          'Copied dir symlink: $symlinkName -> $target');
    } else if (targetFile.existsSync()) {
      // File symlink — copy file
      try {
        final content = await targetFile.readAsBytes();
        await File(symlinkPath).writeAsBytes(content, flush: true);
        symlinkSuccess++;
        PandaLog.i('RootfsManager',
            'Copied file symlink: $symlinkName -> $target');
      } catch (e) {
        PandaLog.w('RootfsManager',
            'Failed to copy file symlink: $symlinkName: $e');
      }
    } else {
      PandaLog.w('RootfsManager',
          'Symlink target not found: $symlinkName -> $target (resolved: $resolvedTarget)');
    }
  }

  /// Recursively copy a directory.
  static Future<void> _copyDirectory(Directory source, Directory dest) async {
    if (!dest.existsSync()) {
      await dest.create(recursive: true);
    }
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      final destPath = '${dest.path}/$name';
      if (entity is File) {
        try {
          final content = await entity.readAsBytes();
          await File(destPath).writeAsBytes(content, flush: true);
        } catch (_) {}
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is Link) {
        try {
          final linkTarget = entity.targetSync();
          if (!Link(destPath).existsSync()) {
            Link(destPath).createSync(linkTarget);
          }
        } catch (_) {}
      }
    }
  }
}
