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
      final archiveFile = File(
          '${cacheDir.path}/${type.id}-${info.version}.tar.gz');

      if (!archiveFile.existsSync()) {
        await _downloadFile(info.url, archiveFile, onProgress);
      }

      // Verify gzip magic bytes
      try {
        final first = await archiveFile.openRead(0, 2).first;
        if (first.length < 2 ||
            first[0] != 0x1f ||
            first[1] != 0x8b) {
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

      // Extract
      final staging =
          Directory('${cacheDir.path}/${type.id}.staging');
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);
      await _extractTarball(archiveFile, staging);

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
      onProgress?.call(
          total > 0 ? dl / total : 0, dl, total);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Extract tar.gz with Android symlink fallback.
  /// On Android, filesystem symlinks may fail silently.
  /// When they do, we copy the target content as real files/dirs.
  static Future<void> _extractTarball(
      File archive, Directory dest) async {
    final bytes = await archive.readAsBytes();
    final tarBytes = GZipDecoder().decodeBytes(bytes);
    final tarArchive = TarDecoder().decodeBytes(tarBytes);

    final symlinks = <ArchiveFile>[];

    // Pass 1: extract regular files and directories
    for (final file in tarArchive) {
      final name = file.name.replaceFirst(RegExp(r'^\./'), '');
      if (name.isEmpty || name == '..' || name.contains('../')) {
        continue;
      }
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
          await outFile.writeAsBytes(
              List<int>.from(content), flush: true);
        }
      } else if (file.isDirectory) {
        await Directory(destPath).create(recursive: true);
      }
    }

    // Pass 2: create symlinks with fallback
    int ok = 0, copied = 0, skipped = 0;
    for (final link in symlinks) {
      final name =
          link.name.replaceFirst(RegExp(r'^\./'), '');
      final destPath = '${dest.path}/$name';
      final target = link.symbolicLink;
      if (target == null || target.isEmpty) {
        skipped++;
        continue;
      }

      final parent = File(destPath).parent;
      if (!parent.existsSync()) {
        await parent.create(recursive: true);
      }

      // Remove existing entry
      final existing =
          FileSystemEntity.typeSync(destPath, followLinks: false);
      if (existing != FileSystemEntityType.notFound) {
        try {
          Link(destPath).deleteSync();
        } catch (_) {}
        if (existing == FileSystemEntityType.file) {
          try {
            File(destPath).deleteSync();
          } catch (_) {}
        } else if (existing == FileSystemEntityType.directory) {
          try {
            Directory(destPath).deleteSync(recursive: true);
          } catch (_) {}
        }
      }

      // Try symlink
      bool symlinkOk = false;
      try {
        Link(destPath).createSync(target);
        // Verify
        final type = FileSystemEntity.typeSync(
            destPath, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          symlinkOk = true;
        }
      } catch (_) {
        symlinkOk = false;
      }

      if (symlinkOk) {
        ok++;
      } else {
        // Fallback: copy target
        await _copyLinkTarget(dest, name, target);
        copied++;
      }
    }

    PandaLog.i('RootfsManager',
        'Extract: ${symlinks.length} symlinks — '
        '$ok OK, $copied copied, $skipped skipped');

    // chmod
    const dirs = [
      'bin', 'sbin', 'usr/bin', 'usr/sbin', 'usr/local/bin'
    ];
    for (final d in dirs) {
      final p = '${dest.path}/$d';
      if (Directory(p).existsSync()) {
        try {
          await Process.run(
              '/system/bin/sh', ['-c', 'chmod -R 755 "$p"']);
        } catch (_) {}
      }
    }
  }

  /// Copy the content a symlink was supposed to point to.
  static Future<void> _copyLinkTarget(
      Directory rootfsDest, String name, String target) async {
    final symlinkPath = '${rootfsDest.path}/$name';

    // Resolve absolute target relative to rootfs
    String resolved;
    if (target.startsWith('/')) {
      resolved = '${rootfsDest.path}$target';
    } else {
      final dir = File(symlinkPath).parent.path;
      resolved = '$dir/$target';
    }

    // Normalize ../
    final parts = <String>[];
    for (final seg in resolved.split('/')) {
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (seg.isNotEmpty && seg != '.') {
        parts.add(seg);
      }
    }
    resolved = parts.join('/');

    final targetDir = Directory(resolved);
    final targetFile = File(resolved);

    if (targetDir.existsSync()) {
      await _copyDir(targetDir, Directory(symlinkPath));
      PandaLog.i('RootfsManager',
          'Copied dir: $name -> $target');
    } else if (targetFile.existsSync()) {
      try {
        final c = await targetFile.readAsBytes();
        await File(symlinkPath)
            .writeAsBytes(c, flush: true);
        PandaLog.i('RootfsManager',
            'Copied file: $name -> $target');
      } catch (e) {
        PandaLog.w('RootfsManager',
            'Copy failed: $name: $e');
      }
    } else {
      PandaLog.w('RootfsManager',
          'Target not found: $name -> $target');
    }
  }

  /// Recursively copy a directory tree.
  static Future<void> _copyDir(
      Directory src, Directory dst) async {
    if (!dst.existsSync()) await dst.create(recursive: true);
    await for (final entity
        in src.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      final destPath = '${dst.path}/$name';
      if (entity is File) {
        try {
          final c = await entity.readAsBytes();
          await File(destPath).writeAsBytes(c, flush: true);
        } catch (_) {}
      } else if (entity is Directory) {
        await _copyDir(entity, Directory(destPath));
      } else if (entity is Link) {
        try {
          final t = entity.targetSync();
          if (!Link(destPath).existsSync()) {
            Link(destPath).createSync(t);
          }
        } catch (_) {}
      }
    }
  }
}
