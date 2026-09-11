import 'dart:io';

import 'package:flutter/services.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:archive/archive.dart';
import 'package:panda/utils/panda_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/flutter_pub_environment.dart';

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
  static const String profileVersion = 'panda-debian-profile v8';
  static const String terminalPathPreferenceKey = 'terminal.path';
  static const String defaultGuestPath =
      '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

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

  static String prootL2sDir(String rootfsPath) => '$rootfsPath/.panda-proot-l2s';

  /// PRoot's link2symlink store must be inside the rootfs and bind-mounted
  /// onto the same guest path. Otherwise a hard link created by Git/Pub is
  /// represented by a symlink to the Android host path, which is not resolvable
  /// after the process enters the guest.
  static Future<void> ensureProotL2sDir(String rootfsPath) async {
    await Directory(prootL2sDir(rootfsPath)).create(recursive: true);
  }

  /// Common PRoot arguments used by every guest process.
  ///
  /// Keep this in one place. Pub, apk, the terminal and the agent must see the
  /// same link translation and device filesystem; a single divergent launcher
  /// is enough to produce broken Git objects in a Pub cache.
  static Future<List<String>> prootArguments({
    required String rootfsPath,
    List<String> extraBinds = const [],
  }) async {
    await ensureProotL2sDir(rootfsPath);
    bool hostExists(String path) =>
        FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;

    final standardBinds = <String>[
      '/dev',
      '/proc',
      '/sys',
      '${prootL2sDir(rootfsPath)}:${prootL2sDir(rootfsPath)}',
      if (hostExists('/dev/pts')) '/dev/pts',
      if (hostExists('/proc/self/fd')) '/proc/self/fd:/dev/fd',
      if (hostExists('/proc/self/fd/0')) '/proc/self/fd/0:/dev/stdin',
      if (hostExists('/proc/self/fd/1')) '/proc/self/fd/1:/dev/stdout',
      if (hostExists('/proc/self/fd/2')) '/proc/self/fd/2:/dev/stderr',
    ];
    return <String>[
      '-0',
      '--link2symlink',
      '--sysvipc',
      '--kill-on-exit',
      '--rootfs=$rootfsPath',
      ...standardBinds.expand((bind) => ['-b', bind]),
      ...extraBinds.expand((bind) => ['-b', bind]),
    ];
  }

  static Future<Map<String, String>> prootLinkEnvironment({
    String? rootfsPath,
  }) async {
    final dir = await nativeLibDir();
    final loader = '$dir/libproot-loader.so';
    final resolvedRootfs = rootfsPath ?? debianDir;
    try {
      Directory(tempDir).createSync(recursive: true);
      await ensureProotL2sDir(resolvedRootfs);
    } catch (_) {}
    return {
      if (dir.isNotEmpty) 'LD_LIBRARY_PATH': dir,
      if (File(loader).existsSync()) 'PROOT_LOADER': loader,
      'PROOT_TMP_DIR': tempDir,
      'PROOT_L2S_DIR': prootL2sDir(resolvedRootfs),
      'PROOT_NO_SECCOMP': '1',
    };
  }

  static Future<Map<String, String>> prootSessionEnvironment({
    Map<String, String> extra = const {},
    String? flutterProjectPath,
    String? rootfsPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(terminalPathPreferenceKey)?.trim() ?? '';
    final effectivePath = _mergePath(defaultGuestPath, savedPath);
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
      'PATH': effectivePath,
      'TMPDIR': '/tmp',
      ...await prootLinkEnvironment(rootfsPath: rootfsPath),
    };
    if (flutterProjectPath != null &&
        flutterProjectPath.trim().isNotEmpty) {
      env.addAll(FlutterPubEnvironment.forProject(flutterProjectPath));
    }
    env.addAll(extra);
    return env;
  }

  /// Persists a PATH assignment typed in the integrated shell.
  ///
  /// Bash starts from a generated profile, so a normal `export PATH=...`
  /// otherwise disappears with the terminal session. We only accept simple
  /// PATH assignments and expand `$PATH` against the previously saved value;
  /// arbitrary shell code is never executed by the Flutter process.
  static Future<void> persistTerminalPathCommand(String command) async {
    final match = RegExp(
      r'^\s*(?:export\s+)?PATH\s*=\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(command);
    if (match == null) return;

    var value = match.group(1)!.trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final previous = _mergePath(
      defaultGuestPath,
      prefs.getString(terminalPathPreferenceKey)?.trim() ?? '',
    );
    value = value
        .replaceAll(r'${PATH}', previous)
        .replaceAll(r'$PATH', previous);
    final normalized = _mergePath(defaultGuestPath, value);
    await prefs.setString(terminalPathPreferenceKey, normalized);
  }

  static String _mergePath(String base, String additions) {
    final values = <String>[];
    for (final value in '$base:$additions'.split(':')) {
      final item = value.trim();
      if (item.isEmpty || item == r'$PATH' || values.contains(item)) continue;
      values.add(item);
    }
    return values.join(':');
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
          environment: await prootLinkEnvironment(rootfsPath: rootfsDir));
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
          await outFile.writeAsBytes(content, flush: true);
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
# Keep the PATH injected by Flutter/PRoot. Replacing it here used to erase
# entries users had added for Flutter, Android SDK and custom toolchains.
export PATH="\${PATH:-$defaultGuestPath}"
export HOME="\${HOME:-/root}"
export TERM="\${TERM:-xterm-256color}"
# Only set locale if available — avoids "cannot change locale" warnings
if locale -a 2>/dev/null | grep -qi en_US.UTF-8; then
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
fi
# Fix Android group warnings (groups command fails for UID-based GIDs)
if [ -f /etc/group ]; then
  for g in 1077 3003 9997 20658 50658; do
    grep -q "^_g\$g:" /etc/group 2>/dev/null || echo "_g\$g:x:\$g:" >> /etc/group 2>/dev/null
  done
fi
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
    printf '%s' "\$b"
}

__panda_ps() {
    local p
    case "\$PWD" in
        "\$HOME") p="~" ;;
        "\$HOME"/*) p="~\${PWD#\$HOME}" ;;
        *) p="\$PWD" ;;
    esac
    local g="\$(__panda_git)"
    PS1="\\[\\033[38;5;110m\\]╭─ \\[\\033[38;5;183m\\]\$p"
    [ -n "\$g" ] && PS1+=" \\[\\033[38;5;141m\\]\$g"
    PS1+="\\[\\033[0m\\]\\n\\[\\033[38;5;110m\\]╰─❯ \\[\\033[0m\\]"
  }
__panda_prompt() {
    local code=\$?
    printf '\\033]777;PANDA_STATUS;%s\\007' "\$code"
    __panda_ps
}
PROMPT_COMMAND=__panda_prompt
__panda_ps
''';

  /// Single, repeatable setup command exposed inside every Panda terminal.
  /// It installs the common toolchain in the selected guest distribution,
  /// rather than pretending that the Android host has Node.js or Git.
  static String pandaUpdateScript() => r'''#!/bin/sh
set -u

usage() {
  echo "Usage: panda update | panda doctor"
  echo "  update  Install or refresh Git, Node.js, npm, Python and build tools"
  echo "  doctor  Show the tools currently available in this terminal"
}

case "${1:-}" in
  update|setup)
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y --no-install-recommends \
        ca-certificates curl wget git nodejs npm python3 python3-pip \
        build-essential pkg-config
    elif command -v apk >/dev/null 2>&1; then
      apk update
      apk add --no-cache ca-certificates curl wget git nodejs npm \
        python3 py3-pip build-base pkgconf
    else
      echo "No supported package manager found. Select an Ubuntu, Debian or Alpine terminal."
      exit 1
    fi
    echo "Panda toolchain updated."
    "$0" doctor
    ;;
  doctor)
    for tool in git node npm python3 pip3; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '%-8s %s\n' "$tool" "$("$tool" --version 2>/dev/null | head -n 1)"
      else
        printf '%-8s %s\n' "$tool" "not installed"
      fi
    done
    ;;
  *)
    usage
    exit 2
    ;;
esac
''';

  static Future<void> ensureDebianRuntimeFiles() async =>
      _ensureRuntimeFilesIn(debianDir);

  /// Prepare the exact rootfs selected by the terminal.
  ///
  /// The old convenience method derives a legacy path for callers that do not
  /// know the active distro.  A terminal session does know it, so it must use
  /// this method or an Ubuntu session can inherit Debian/Alpine runtime files.
  static Future<void> ensureRuntimeFilesForRootfs(String rootfsPath) async =>
      _ensureRuntimeFilesIn(rootfsPath);

  static Future<void> _ensureRuntimeFilesIn(String dir) async {
    if (!Directory(dir).existsSync()) return;

    final readyMarker = File('$dir/.panda-runtime-ready');
    final profileMarker = File('$dir/.panda-profile-version');

    // Always update profile files if profileVersion changed, even when
    // rootfs is already ready — ensures bash PS1 prompt works.
    final profileNeedsUpdate = !profileMarker.existsSync() ||
        profileMarker.readAsStringSync().trim() != profileVersion;
    if (profileNeedsUpdate) {
      final profile = pandaProfileScript();
      _write('$dir/etc/profile.d/panda.sh', profile);
      _write('$dir/etc/profile',
          'for f in /etc/profile.d/*.sh; do [ -r "\$f" ] && . "\$f"; done\n');
      _write('$dir/root/.profile', profile);
      _write('$dir/root/.bashrc', profile);
      try {
        profileMarker.writeAsStringSync(profileVersion);
      } catch (_) {}
    }

    for (final name in const [
      '.panda-proot-l2s',
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

    // resolv.conf can be a stale file (or a symlink into a systemd path that
    // does not exist inside PRoot). Always replace it when a session starts.
    final resolv = File('$dir/etc/resolv.conf');
    try {
      if (FileSystemEntity.typeSync(resolv.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await resolv.delete();
      }
    } catch (_) {}
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
    _write('$dir/usr/local/bin/panda', pandaUpdateScript());

    try {
      readyMarker.writeAsStringSync(rootfsVersion, flush: true);
      PandaLog.i('DebianSetup', 'Runtime files ready (marker written)');
    } catch (_) {}
  }
}
