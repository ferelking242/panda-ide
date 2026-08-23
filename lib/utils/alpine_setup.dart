import 'dart:io';

import 'package:flutter/services.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:archive/archive.dart';
import 'package:panda/utils/panda_log.dart';

/// Installs the official Alpine minirootfs without trying to repair an archive
/// that has already lost Unix links and permissions.
class AlpineSetup {
  static const String _alpineDirName = 'alpine-linux';
  static const String rootfsVersion = 'alpine-3.22.5';
  static const String workspaceMount = '/root/workspace';
  static const String profileVersion = 'panda-profile v4';

  static String? _cachedNativeLibDir;
  static String? _cachedProotBin;
  static String get alpineDir => '$runtimesDir/$_alpineDirName';

  /// Last error message for display in terminal UI.
  static String lastError = '';

  /// Termux pattern (TermuxInstaller.java): the rootfs is extracted into a
  /// staging directory, validated there, then atomically renamed into place.
  static Directory get stagingDir =>
      Directory('$runtimesDir/$_alpineDirName.staging');

  static Future<String> nativeLibDir() async {
    if (_cachedNativeLibDir != null) return _cachedNativeLibDir!;
    try {
      final value = await NativeChannel.getLibraryPath();
      PandaLog.d('AlpineSetup', 'NativeChannel.getLibraryPath() => "$value"');
      if (value.isNotEmpty && Directory(value).existsSync()) {
        _cachedNativeLibDir = value;
        PandaLog.d('AlpineSetup', 'Native lib dir resolved: $value');
        return value;
      }
      PandaLog.w('AlpineSetup', 'Native lib dir invalid or missing: "$value" (isDir=${value.isNotEmpty ? Directory(value).existsSync() : false})');
    } catch (e) {
      PandaLog.e('AlpineSetup', 'Failed to get native lib path: $e');
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
    // PRoot extracts its internal loader into PROOT_TMP_DIR and chmods it:
    // the directory must exist or PRoot dies with "can't chmod ...".
    try {
      Directory(tempDir).createSync(recursive: true);
    } catch (_) {}
    return {
      if (dir.isNotEmpty) 'LD_LIBRARY_PATH': dir,
      if (File(loader).existsSync()) 'PROOT_LOADER': loader,
      'PROOT_TMP_DIR': tempDir,
      // Android 12+ kernels (Samsung notamment): le filtre seccomp de PRoot
      // fait echouer aleatoirement des syscalls du tracee sur les gros
      // fichiers -> apk: "Failed to create ...: I/O error" puis cascade de
      // "temporary error (try again later)". Desactiver seccomp corrige.
      'PROOT_NO_SECCOMP': '1',
    };
  }

  static Future<Map<String, String>> prootSessionEnvironment({
    Map<String, String> extra = const {},
  }) async {
    final env = <String, String>{
      'HOME': '/root',
      'USER': 'root',
      'LOGNAME': 'root',
      'TERM': 'xterm-256color',
      'SHELL': '/bin/sh',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
      'DISPLAY': ':0',
      'ENV': '/root/.profile',
      'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      'TMPDIR': '/tmp',
    };
    env.addAll(await prootLinkEnvironment());
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
      PandaLog.w('AlpineSetup', 'PRoot indisponible: $e');
    }
    return null;
  }

  static bool _isSymlink(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link;

  static bool isRootfsComplete() => isRootfsCompleteIn(alpineDir);

  static bool isRootfsCompleteIn(String dir) {
    return File('$dir/.panda-rootfs-version').existsSync() &&
        File('$dir/bin/busybox').existsSync() &&
        _isSymlink('$dir/bin/sh') &&
        File('$dir/sbin/apk').existsSync() &&
        File('$dir/lib/ld-musl-aarch64.so.1').existsSync() &&
        Directory('$dir/etc/apk/keys').existsSync() &&
        Directory('$dir/root').existsSync();
  }

  /// Batch chmod: one process for the whole tree instead of one spawn per
  /// file (Termux uses Os.chmod per entry; without FFI a single
  /// `/system/bin/sh -c 'chmod -R ...'` is the closest equivalent).
  ///
  /// The Dart `archive` package drops Unix permission bits, so everything is
  /// written 0644/0755. We restore what matters for execution:
  ///   - 755 recursively on every directory holding executables AND on lib/
  ///     (the kernel requires the exec bit on ELF interpreters such as
  ///     /lib/ld-musl-aarch64.so.1 even when they are only mmap'd),
  ///   - 1777 on tmp directories so guests can share /tmp.
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
        PandaLog.w('AlpineSetup', 'chmod via /system/bin/sh failed: ${r.stderr}');
      }
    } catch (e) {
      PandaLog.w('AlpineSetup', 'chmod via /system/bin/sh unavailable: $e');
    }
    for (final d in tmpDirs) {
      if (!Directory('$rootPath/$d').existsSync()) continue;
      try {
        await Process.run('/system/bin/sh',
            ['-c', 'chmod 1777 "$rootPath/$d"']);
      } catch (_) {}
    }
  }

  static bool isDirAccessible(String path) {
    if (path.trim().isEmpty) return false;
    try {
      final directory = Directory(path);
      if (!directory.existsSync()) return false;
      directory.listSync(followLinks: false).take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Termux pattern (TermuxInstaller.java):
  ///   1. clear the staging directory left over from a broken install,
  ///   2. extract the archive into staging (files, dirs, then symlinks),
  ///   3. make binaries executable,
  ///   4. validate the staging rootfs,
  ///   5. delete the old prefix and atomically rename staging into place.
  static Future<bool> ensureAlpineRootfs({bool force = false}) async {
    final destination = Directory(alpineDir);
    final marker = File('${destination.path}/.panda-rootfs-version');
    final current = marker.existsSync() ? marker.readAsStringSync().trim() : '';
    if (!force && current == rootfsVersion && isRootfsComplete()) {
      PandaLog.d('AlpineSetup', 'Rootfs already complete v$rootfsVersion');
      await ensureAlpineRuntimeFiles();
      return true;
    }

    PandaLog.i('AlpineSetup',
        'Starting rootfs extraction (current=$current, force=$force)');
    lastError = '';
    final sw = Stopwatch()..start();

    try {
      // [1/6] Clean staging + destination leftovers
      PandaLog.d('AlpineSetup', '[1/6] Cleaning staging directory');
      try {
        if (stagingDir.existsSync()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (e) {
        PandaLog.w('AlpineSetup', '[1/6] Failed to clean staging: $e');
      }
      await stagingDir.create(recursive: true);

      // [2/6] Write the archive from assets to a real file
      PandaLog.d('AlpineSetup', '[2/6] Loading alpine-rootfs.tar.gz from assets');
      await Directory(tempDir).create(recursive: true);
      final archive = File('$tempDir/alpine-rootfs.tar.gz');
      final bytes = await rootBundle.load('assets/runtimes/alpine-rootfs.tar.gz');
      await archive.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      PandaLog.d('AlpineSetup',
          '[2/6] Archive written (${bytes.lengthInBytes} bytes)');

      // [3/6] Decompress gzip
      final archiveBytes = await archive.readAsBytes();
      final List<int> tarBytes;
      try {
        tarBytes = gzip.decode(archiveBytes);
      } catch (e) {
        lastError = 'Gzip decompression failed: $e';
        throw StateError(lastError);
      }
      PandaLog.d('AlpineSetup',
          '[3/6] Decompressed: ${tarBytes.length} bytes');

      // [4/6] Extract into STAGING: files + dirs first, symlinks afterwards
      PandaLog.i('AlpineSetup',
          '[4/6] Extracting -> ${stagingDir.path}');
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
          PandaLog.w('AlpineSetup', 'Symlink failed: $name -> $target: $e');
        }
      }
      PandaLog.d('AlpineSetup',
          '[4/6] Extracted: $filesWritten files, $dirsCreated dirs, $symlinksCreated symlinks');

      // Make every binary executable (Dart archive does not preserve modes)
      await _makeBinariesExecutable(stagingDir.path);

      // Runtime files inside staging BEFORE validation/rename
      await _ensureRuntimeFilesIn(stagingDir.path);

      // [5/6] Validate staging, then write the version marker there
      PandaLog.d('AlpineSetup', '[5/6] Validating staging rootfs...');
      final checks = {
        'bin/busybox': File('${stagingDir.path}/bin/busybox').existsSync(),
        'bin/sh symlink': _isSymlink('${stagingDir.path}/bin/sh'),
        'sbin/apk': File('${stagingDir.path}/sbin/apk').existsSync(),
        'lib/ld-musl':
            File('${stagingDir.path}/lib/ld-musl-aarch64.so.1').existsSync(),
        'etc/apk/keys':
            Directory('${stagingDir.path}/etc/apk/keys').existsSync(),
        'root dir': Directory('${stagingDir.path}/root').existsSync(),
      };
      for (final entry in checks.entries) {
        PandaLog.d('AlpineSetup', '[5/6] ${entry.key}: ${entry.value ? "OK" : "MISSING"}');
      }
      if (checks.values.any((ok) => !ok)) {
        final missing =
            checks.entries.where((e) => !e.value).map((e) => e.key).toList();
        lastError = 'Rootfs invalide: ${missing.join(', ')}';
        throw StateError(lastError);
      }
      await File('${stagingDir.path}/.panda-rootfs-version')
          .writeAsString(rootfsVersion, flush: true);

      // [6/6] Atomic rename staging -> final (TermuxInstaller step 6)
      PandaLog.i('AlpineSetup', '[6/6] Renaming staging -> ${destination.path}');
      try {
        if (destination.existsSync()) {
          await destination.delete(recursive: true);
        }
        await stagingDir.rename(destination.path);
      } catch (e) {
        PandaLog.w('AlpineSetup', 'Rename failed ($e), copying instead');
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

      await ensureAlpineRuntimeFiles();
      final ok = isRootfsComplete();
      if (ok) {
        PandaLog.i('AlpineSetup',
            'Alpine rootfs ready (${sw.elapsedMilliseconds}ms)');
      } else {
        lastError = 'Rootfs validation failed after rename';
        PandaLog.e('AlpineSetup', lastError);
      }
      return ok;
    } catch (e) {
      if (lastError.isEmpty) lastError = e.toString();
      PandaLog.e('AlpineSetup', 'Échec rootfs Alpine: $e');
      // Never leave a half-extracted staging dir behind.
      try {
        if (stagingDir.existsSync()) await stagingDir.delete(recursive: true);
      } catch (_) {}
      return false;
    }
  }

  /// Recursively copy a directory (fallback if rename fails across mounts).
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

  static void _write(String file, String content, {bool overwrite = true}) {
    try {
      final target = File(file);
      if (!overwrite && target.existsSync() && target.lengthSync() > 0) return;
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(content, flush: true);
    } catch (e) {
      PandaLog.w('AlpineSetup', 'Écriture impossible ($file): $e');
    }
  }

  static String pandaProfileScript() => '''
# $profileVersion - generated by Panda IDE
unset LD_LIBRARY_PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="\${HOME:-/root}"
export TERM="\${TERM:-xterm-256color}"
# NOTE: pkg/apt/apt-get are NOT defined as shell functions here — busybox
# ash rejects function names containing '-' (POSIX), which aborted the whole
# profile. Real executable wrappers are installed in /usr/local/bin instead.
alias ls='ls --color=auto'
alias ll='ls -la --color=auto'
alias la='ls -la'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
# NOTE: no background 'apk update &' here — it races the user's own apk
# commands and dies with "Unable to lock database" forever (the success
# marker is never written when the lock is lost). Run `apk update` manually.

# ── Prompt: busybox-ash compatible (no PROMPT_COMMAND, no bash \033/\w).
# Real ESC bytes via printf, re-evaluated on every prompt display through
# PS1 command substitution (busybox ASH_EXPAND_PRMT, enabled on Alpine).
__panda_esc() { printf '\\033'; }
__panda_git() {
  command -v git >/dev/null 2>&1 || return 0
  local b
  b=\$(git symbolic-ref --short HEAD 2>/dev/null) || return 0
  [ -n "\$(git status --porcelain 2>/dev/null)" ] && b="\$b *"
  printf ' %s[38;5;141m%s%s[0m' "\$(__panda_esc)" "\$b" "\$(__panda_esc)"
}
__panda_ps() {
  local code=\$? e p c=75
  e=\$(__panda_esc)
  [ "\$code" -ne 0 ] && c=203
  case "\$PWD" in
    "\$HOME") p='~' ;;
    "\$HOME"/*) p="~\${PWD#\$HOME}" ;;
    *) p="\$PWD" ;;
  esac
  printf '%s[38;5;110m╭─ %s[38;5;183m%s%s %s[38;5;%sm[%s]%s[0m\\n%s[38;5;%sm╰─❯ %s[0m ' \\
    "\$e" "\$e" "\$p" "\$(__panda_git)" "\$e" "\$c" "\$code" "\$e" "\$e" "\$c" "\$e"
}
PS1='\$(__panda_ps)'
''';

  static Future<void> ensureAlpineRuntimeFiles() async =>
      _ensureRuntimeFilesIn(alpineDir);

  static Future<void> _ensureRuntimeFilesIn(String dir) async {
    if (!Directory(dir).existsSync()) return;
    for (final name in const [
      'root', 'root/workspace', 'tmp', 'var/tmp', 'dev', 'proc', 'sys',
      'etc/apk', 'etc/profile.d', 'usr/local/bin',
    ]) {
      Directory('$dir/$name').createSync(recursive: true);
    }

    // Ensure all binaries are executable (fix for rootfs extracted by Dart archive)
    await _makeBinariesExecutable(dir);

    _write('$dir/etc/resolv.conf',
        'nameserver 1.1.1.1\nnameserver 8.8.8.8\n');
    _write('$dir/etc/hosts',
        '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n',
        overwrite: false);
    _write('$dir/etc/apk/repositories',
        'https://dl-cdn.alpinelinux.org/alpine/v3.22/main\n'
        'https://dl-cdn.alpinelinux.org/alpine/v3.22/community\n');
    final profile = pandaProfileScript();
    _write('$dir/etc/profile.d/panda.sh', profile);
    _write('$dir/etc/profile',
        'for f in /etc/profile.d/*.sh; do [ -r "\$f" ] && . "\$f"; done\n');
    _write('$dir/root/.profile', profile);
    _write('$dir/root/.bashrc', profile);

    // apk wrappers so `pkg`, `apt` and `apt-get` behave like Termux's apt.
    // Executable scripts (not functions) because busybox ash cannot define
    // functions with '-' in their name.
    const apkWrapper = '#!/bin/sh\nexec /sbin/apk "\$@"\n';
    for (final name in const ['pkg', 'apt', 'apt-get']) {
      _write('$dir/usr/local/bin/$name', apkWrapper);
    }
    try {
      await Process.run('/system/bin/sh', [
        '-c',
        'chmod 755 "$dir/usr/local/bin/pkg" "$dir/usr/local/bin/apt" "$dir/usr/local/bin/apt-get"',
      ]);
    } catch (_) {}
  }
}
