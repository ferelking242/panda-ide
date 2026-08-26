import 'dart:io';

import 'package:flutter/services.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:archive/archive.dart';
import 'package:panda/utils/panda_log.dart';

/// Installs a minimal Debian ARM64 rootfs (glibc) for proot.
///
/// Replaces AlpineSetup to provide full glibc compatibility for
/// patchright, playwright, Chromium, and any manylinux wheel.
///
/// Rootfs is bundled in assets/runtimes/debian-arm64-rootfs.tar.gz.
/// Uses the same Termux pattern: staging → validate → atomic rename.
class DebianSetup {
  static const String _debianDirName = 'debian-arm64';
  static const String rootfsVersion = 'debian-bookworm-arm64 v1';
  static const String workspaceMount = '/root/workspace';
  static const String profileVersion = 'panda-debian-profile v4';

  static String? _cachedNativeLibDir;
  static String? _cachedProotBin;
  static String get debianDir {
    // Check RootfsManager paths (terminals/{id}/)
    for (final id in ['ubuntu', 'debian', 'alpine']) {
      final path = '$appDir/terminals/$id';
      if (File('$path/.panda-rootfs-version').existsSync()) {
        return path;
      }
    }
    // Fallback to legacy debian-arm64 path
    return '$runtimesDir/$_debianDirName';
  }

  /// Last error message for display in terminal UI.
  static String lastError = '';

  /// Staging directory for atomic extraction.
  static Directory get stagingDir =>
      Directory('$runtimesDir/$_debianDirName.staging');

  static Future<String> nativeLibDir() async {
    if (_cachedNativeLibDir != null) return _cachedNativeLibDir!;
    try {
      final value = await NativeChannel.getLibraryPath();
      PandaLog.d('DebianSetup', 'NativeChannel.getLibraryPath() => "$value"');
      if (value.isNotEmpty && Directory(value).existsSync()) {
        _cachedNativeLibDir = value;
        PandaLog.d('DebianSetup', 'Native lib dir resolved: $value');
        return value;
      }
      PandaLog.w('DebianSetup', 'Native lib dir invalid: "$value"');
    } catch (e) {
      PandaLog.e('DebianSetup', 'Failed to get native lib path: $e');
    }
    return '';
  }

  static Future<String?> prootLoaderPath() async {
    final dir = await nativeLibDir();
    final file = File('$dir/libproot-loader.so');
    return file.existsSync() ? file.path : null;
  }

  static Future<Map<String, String>> prootLinkEnvironment() async {
    final dir = await nativeLibDir();
    final loader = '$dir/libproot-loader.so';
    try {
      Directory(tempDir).createSync(recursive: true);
    } catch (_) {}
    return {
      if (dir.isNotEmpty) 'LD_LIBRARY_PATH': dir,
      if (File(loader).existsSync()) 'PROOT_LOADER': loader,
      'PROOT_TMP_DIR': tempDir,
      'PROOT_NO_SECCOMP': '1',
    };
  }

  static Map<String, String>? _cachedSessionEnv;

  static Future<Map<String, String>> prootSessionEnvironment({
    Map<String, String> extra = const {},
  }) async {
    if (_cachedSessionEnv != null) {
      return <String, String>{..._cachedSessionEnv!, ...extra};
    }
    final env = <String, String>{
      'HOME': '/root',
      'USER': 'root',
      'LOGNAME': 'root',
      'TERM': 'xterm-256color',
      'SHELL': '/bin/bash',
      'LANG': 'en_US.UTF-8',
      'LC_ALL': 'en_US.UTF-8',
      'DISPLAY': ':0',
      'ENV': '/root/.profile',
      'PATH':
          '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      'TMPDIR': '/tmp',
    };
    env.addAll(await prootLinkEnvironment());
    _cachedSessionEnv = Map.of(env);
    env.addAll(extra);
    return env;
  }

  static Future<String?> locateProotBinary(String rootfsDir,
      {bool useCache = true}) async {
    final cached = _cachedProotBin;
    if (useCache && cached != null && File(cached).existsSync()) return cached;
    final dir = await nativeLibDir();
    final candidate = '$dir/libproot.so';
    if (dir.isEmpty || !File(candidate).existsSync()) return null;
    try {
      final result = await Process.run(candidate, ['--version'],
          environment: await prootLinkEnvironment());
      final output = '${result.stdout}${result.stderr}';
      if (result.exitCode == 0 || output.contains('PRoot')) {
        _cachedProotBin = candidate;
        return candidate;
      }
    } catch (e) {
      PandaLog.w('DebianSetup', 'PRoot unavailable: $e');
    }
    return null;
  }

  static bool _isSymlink(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link;

  /// Check if the rootfs is complete — Debian validation.
  static bool isRootfsComplete() => isRootfsCompleteIn(debianDir);

  static bool isRootfsCompleteIn(String dir) {
    if (!File('$dir/.panda-rootfs-version').existsSync()) return false;
    // Ubuntu uses symlinks (bin -> usr/bin), check both paths
    final hasSh = File('$dir/bin/sh').existsSync() ||
        File('$dir/usr/bin/sh').existsSync() ||
        File('$dir/usr/bin/bash').existsSync();
    final hasApt = File('$dir/usr/bin/apt').existsSync() ||
        File('$dir/bin/apt').existsSync();
    final hasPython = File('$dir/usr/bin/python3').existsSync() ||
        File('$dir/bin/python3').existsSync();
    final hasLibc = File('$dir/lib/aarch64-linux-gnu/libc.so.6').existsSync() ||
        File('$dir/usr/lib/aarch64-linux-gnu/libc.so.6').existsSync() ||
        File('$dir/lib/libc.so.6').existsSync();
    return hasSh && hasApt && hasPython && hasLibc &&
        Directory('$dir/etc/apt').existsSync() &&
        Directory('$dir/root').existsSync();
  }

  /// Ensure Debian rootfs is installed.

  /// Check if a directory is accessible (exists and is a directory).
  static bool isDirAccessible(String path) {
    try {
      final dir = Directory(path);
      return dir.existsSync() && dir.statSync().type == FileSystemEntityType.directory;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> ensureDebianRootfs({bool force = false}) async {
    final destination = Directory(debianDir);
    final marker = File('${destination.path}/.panda-rootfs-version');
    final current =
        marker.existsSync() ? marker.readAsStringSync().trim() : '';
    if (!force && current == rootfsVersion && isRootfsComplete()) {
      PandaLog.d('DebianSetup', 'Rootfs already complete v$rootfsVersion');
      await ensureDebianRuntimeFiles();
      return true;
    }

    PandaLog.i('DebianSetup',
        'Starting rootfs extraction (current=$current, force=$force)');
    lastError = '';
    final sw = Stopwatch()..start();

    try {
      // [1/6] Clean staging
      PandaLog.d('DebianSetup', '[1/6] Cleaning staging directory');
      try {
        if (stagingDir.existsSync()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (e) {
        PandaLog.w('DebianSetup', '[1/6] Failed to clean staging: $e');
      }
      await stagingDir.create(recursive: true);

      // [2/6] Write archive from assets
      PandaLog.d(
          'DebianSetup', '[2/6] Loading debian-arm64-rootfs.tar.gz from assets');
      await Directory(tempDir).create(recursive: true);
      final archive = File('$tempDir/debian-arm64-rootfs.tar.gz');
      try {
        final bytes =
            await rootBundle.load('assets/runtimes/debian-arm64-rootfs.tar.gz');
        await archive.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        PandaLog.d(
            'DebianSetup', '[2/6] Archive written (${bytes.lengthInBytes} bytes)');
      } catch (e) {
        lastError =
            'debian-arm64-rootfs.tar.gz not found in assets. '
            'Run: bash scripts/build_debian_rootfs.sh';
        throw StateError(lastError);
      }

      // [3/6] Decompress gzip
      final archiveBytes = await archive.readAsBytes();
      final List<int> tarBytes;
      try {
        tarBytes = gzip.decode(archiveBytes);
      } catch (e) {
        lastError = 'Gzip decompression failed: $e';
        throw StateError(lastError);
      }
      PandaLog.d('DebianSetup', '[3/6] Decompressed: ${tarBytes.length} bytes');

      // [4/6] Extract into STAGING
      PandaLog.i('DebianSetup', '[4/6] Extracting -> ${stagingDir.path}');
      final tarArchive = TarDecoder().decodeBytes(tarBytes);
      final symlinks = <ArchiveFile>[];
      int filesWritten = 0, dirsCreated = 0;
      for (final file in tarArchive) {
        final name = file.name.replaceFirst(RegExp(r'^\./'), '');
        if (name.isEmpty || name == '..' || name.contains('../')) continue;
        final destPath = '${stagingDir.path}/$name';
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
          filesWritten++;
        } else {
          await Directory(destPath).create(recursive: true);
          dirsCreated++;
        }
      }

      int symlinksCreated = 0;
      for (final link in symlinks) {
        final name = link.name.replaceFirst(RegExp(r'^\./'), '');
        final destPath = '${stagingDir.path}/$name';
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
          symlinksCreated++;
        } catch (e) {
          PandaLog.w('DebianSetup', 'Symlink failed: $name -> $target: $e');
        }
      }
      PandaLog.d('DebianSetup',
          '[4/6] Extracted: $filesWritten files, $dirsCreated dirs, $symlinksCreated symlinks');

      // Make binaries executable
      await _makeBinariesExecutable(stagingDir.path);

      // Runtime files BEFORE validation
      await _ensureRuntimeFilesIn(stagingDir.path);

      // [5/6] Validate staging
      PandaLog.d('DebianSetup', '[5/6] Validating staging rootfs...');
      final checks = {
        'bin/sh': File('${stagingDir.path}/bin/sh').existsSync(),
        'usr/bin/apt': File('${stagingDir.path}/usr/bin/apt').existsSync(),
        'usr/bin/python3':
            File('${stagingDir.path}/usr/bin/python3').existsSync(),
        'lib/libc.so.6 (glibc)':
            File('${stagingDir.path}/lib/aarch64-linux-gnu/libc.so.6')
                .existsSync(),
        'etc/apt': Directory('${stagingDir.path}/etc/apt').existsSync(),
        'root dir': Directory('${stagingDir.path}/root').existsSync(),
      };
      for (final entry in checks.entries) {
        PandaLog.d(
            'DebianSetup', '[5/6] ${entry.key}: ${entry.value ? "OK" : "MISSING"}');
      }
      if (checks.values.any((ok) => !ok)) {
        final missing =
            checks.entries.where((e) => !e.value).map((e) => e.key).toList();
        lastError = 'Rootfs invalid: ${missing.join(', ')}';
        throw StateError(lastError);
      }
      await File('${stagingDir.path}/.panda-rootfs-version')
          .writeAsString(rootfsVersion, flush: true);

      // [6/6] Atomic rename
      PandaLog.i(
          'DebianSetup', '[6/6] Renaming staging -> ${destination.path}');
      try {
        if (destination.existsSync()) {
          await destination.delete(recursive: true);
        }
        await stagingDir.rename(destination.path);
      } catch (e) {
        PandaLog.w('DebianSetup', 'Rename failed ($e), copying instead');
        try {
          if (destination.existsSync()) {
            await destination.delete(recursive: true);
          }
          await _copyDirectory(stagingDir, destination);
          try {
            await stagingDir.delete(recursive: true);
          } catch (_) {}
        } catch (e2) {
          lastError = 'Failed to move staging to final: $e2';
          throw StateError(lastError);
        }
      }

      try {
        await archive.delete();
      } catch (_) {}

      await ensureDebianRuntimeFiles();
      final ok = isRootfsComplete();
      if (ok) {
        PandaLog.i(
            'DebianSetup', 'Debian rootfs ready (${sw.elapsedMilliseconds}ms)');
      } else {
        lastError = 'Rootfs validation failed after rename';
        PandaLog.e('DebianSetup', lastError);
      }
      return ok;
    } catch (e) {
      if (lastError.isEmpty) lastError = e.toString();
      PandaLog.e('DebianSetup', 'Debian rootfs failed: $e');
      try {
        if (stagingDir.existsSync()) await stagingDir.delete(recursive: true);
      } catch (_) {}
      return false;
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false, followLinks: false)) {
      final name = entity.path.split('/').last;
      final destPath = '${dest.path}/$name';
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is Link) {
        final target = await entity.target();
        await Link(destPath).create(target);
      }
    }
  }

  static Future<void> _makeBinariesExecutable(String rootPath) async {
    const execDirs = [
      'bin', 'sbin', 'usr/bin', 'usr/sbin', 'usr/local/bin',
      'lib', 'usr/lib',
    ];
    const tmpDirs = ['tmp', 'var/tmp'];
    final targets = <String>[];
    for (final d in execDirs) {
      if (Directory('$rootPath/$d').existsSync()) targets.add('"$rootPath/$d"');
    }
    if (targets.isEmpty) return;
    final list = targets.join(' ');
    try {
      final r = await Process.run(
          '/system/bin/sh', ['-c', 'chmod -R 755 $list']);
      if (r.exitCode != 0) {
        PandaLog.w('DebianSetup', 'chmod failed: ${r.stderr}');
      }
    } catch (e) {
      PandaLog.w('DebianSetup', 'chmod unavailable: $e');
    }
    for (final d in tmpDirs) {
      if (!Directory('$rootPath/$d').existsSync()) continue;
      try {
        await Process.run(
            '/system/bin/sh', ['-c', 'chmod 1777 "$rootPath/$d"']);
      } catch (_) {}
    }
  }

  static void _write(String file, String content, {bool overwrite = true}) {
    try {
      final target = File(file);
      if (!overwrite && target.existsSync() && target.lengthSync() > 0) return;
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(content, flush: true);
    } catch (e) {
      PandaLog.w('DebianSetup', 'Write failed ($file): $e');
    }
  }

  static String pandaProfileScript() => '''
# $profileVersion - generated by Panda IDE (Debian)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="\${HOME:-/root}"
export TERM="\${TERM:-xterm-256color}"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
alias ls='ls --color=auto'
alias ll='ls -la --color=auto'
alias la='ls -la'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

__panda_git() {
    command -v git >/dev/null 2>&1 || return 0
    local b
    b=\$(git symbolic-ref --short HEAD 2>/dev/null) || return 0
    [ -n "\$(git status --porcelain 2>/dev/null)" ] && b="\$b *"
    echo -ne "\033[38;5;141m\$b\033[0m"
}

  __panda_ps() {
    local p
    case "\$PWD" in
        "\$HOME") p="~" ;;
        "\$HOME"/*) p="~\${PWD#\$HOME}" ;;
        *) p="\$PWD" ;;
    esac
    echo -ne "\001\033[38;5;110m\002╭─ \001\033[38;5;183m\002\$p\001\033[0m\002"
    local g="\$(\$__panda_git)"
    [ -n "\$g" ] && echo -ne " \$g"
    echo -ne "\n"
    echo -ne "\001\033[38;5;110m\002╰─❯ \001\033[0m\002"
  }
PS1='\$(__panda_ps)'
''';

  static Future<void> ensureDebianRuntimeFiles() async =>
      _ensureRuntimeFilesIn(debianDir);

  static Future<void> _ensureRuntimeFilesIn(String dir) async {
    if (!Directory(dir).existsSync()) return;

    final readyMarker = File('$dir/.panda-runtime-ready');
    if (readyMarker.existsSync() &&
        readyMarker.readAsStringSync().trim() == rootfsVersion) {
      return;
    }

    for (final name in const [
      'root',
      'root/workspace',
      'tmp',
      'var/tmp',
      'dev',
      'proc',
      'sys',
      'etc/apt',
      'etc/apt/apt.conf.d',
      'etc/profile.d',
      'usr/local/bin',
    ]) {
      Directory('$dir/$name').createSync(recursive: true);
    }

    await _makeBinariesExecutable(dir);

    _write('$dir/etc/resolv.conf',
        'nameserver 1.1.1.1\nnameserver 8.8.8.8\n');
    _write('$dir/etc/hosts',
        '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n',
        overwrite: false);

    // Debian apt config
    _write('$dir/etc/apt/apt.conf.d/99norecommends',
        'APT::Install-Recommends "false";\n');

    final profile = pandaProfileScript();
    _write('$dir/etc/profile.d/panda.sh', profile);
    _write('$dir/etc/profile',
        'for f in /etc/profile.d/*.sh; do [ -r "\$f" ] && . "\$f"; done\n');
    _write('$dir/root/.profile', profile);
    _write('$dir/root/.bashrc', profile);

    try {
      readyMarker.writeAsStringSync(rootfsVersion);
      PandaLog.i('DebianSetup', 'Runtime files ready (marker written)');
    } catch (_) {}
  }
}
