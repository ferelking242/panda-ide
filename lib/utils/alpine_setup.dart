import 'dart:io';

import 'package:flutter/services.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:panda/utils/panda_log.dart';

/// Installs the official Alpine minirootfs without trying to repair an archive
/// that has already lost Unix links and permissions.
class AlpineSetup {
  static const String _alpineDirName = 'alpine-linux';
  static const String rootfsVersion = 'alpine-3.22.5';
  static const String workspaceMount = '/root/workspace';
  static const String profileVersion = 'panda-profile v3';

  static String? _cachedNativeLibDir;
  static String? _cachedProotBin;
  static String get alpineDir => '$runtimesDir/$_alpineDirName';

  static Future<String> nativeLibDir() async {
    if (_cachedNativeLibDir != null) return _cachedNativeLibDir!;
    try {
      final value = await NativeChannel.getLibraryPath();
      if (value.isNotEmpty && Directory(value).existsSync()) {
        _cachedNativeLibDir = value;
        return value;
      }
    } catch (_) {}
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
    return {
      if (dir.isNotEmpty) 'LD_LIBRARY_PATH': dir,
      if (File(loader).existsSync()) 'PROOT_LOADER': loader,
      'PROOT_TMP_DIR': tempDir,
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

  static bool isRootfsComplete() {
    final dir = alpineDir;
    return File('$dir/.panda-rootfs-version').existsSync() &&
        File('$dir/bin/busybox').existsSync() &&
        _isSymlink('$dir/bin/sh') &&
        File('$dir/sbin/apk').existsSync() &&
        File('$dir/lib/ld-musl-aarch64.so.1').existsSync() &&
        Directory('$dir/etc/apk/keys').existsSync() &&
        Directory('$dir/root').existsSync();
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

  static Future<bool> ensureAlpineRootfs({bool force = false}) async {
    final destination = Directory(alpineDir);
    final marker = File('${destination.path}/.panda-rootfs-version');
    final current = marker.existsSync() ? marker.readAsStringSync().trim() : '';
    if (!force && current == rootfsVersion && isRootfsComplete()) {
      await ensureAlpineRuntimeFiles();
      return true;
    }

    try {
      if (destination.existsSync()) {
        await destination.delete(recursive: true);
      }
      await destination.create(recursive: true);
      final archive = File('$tempDir/alpine-rootfs.tar.gz');
      await Directory(tempDir).create(recursive: true);
      final bytes = await rootBundle.load('assets/runtimes/alpine-rootfs.tar.gz');
      await archive.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      final busybox = '${await nativeLibDir()}/libbusybox.so';
      if (!File(busybox).existsSync()) {
        throw StateError('libbusybox.so absent des bibliothèques natives');
      }
      final result = await Process.run(
        busybox,
        ['tar', '-xzpf', archive.path, '-C', destination.path],
        environment: await prootLinkEnvironment(),
      ).timeout(const Duration(minutes: 2));
      if (result.exitCode != 0) {
        throw StateError('désarchivage BusyBox échoué: ${result.stderr}');
      }
      await archive.delete();

      if (!isRootfsComplete()) {
        throw StateError('rootfs Alpine invalide après extraction');
      }
      await marker.writeAsString(rootfsVersion, flush: true);
      await ensureAlpineRuntimeFiles();
      return isRootfsComplete();
    } catch (e) {
      PandaLog.e('AlpineSetup', 'Échec rootfs Alpine: $e');
      return false;
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
pkg() { apk "\$@"; }
apt() { apk "\$@"; }
apt-get() { apk "\$@"; }
alias ls='ls --color=auto'
alias ll='ls -la --color=auto'
alias la='ls -la'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
if [ ! -f /root/.panda-apk-updated ]; then
  (apk update && touch /root/.panda-apk-updated) &
fi
__panda_git() {
  command -v git >/dev/null 2>&1 || return
  local b
  b=\$(git symbolic-ref --short HEAD 2>/dev/null) || return
  [ -n "\$(git status --porcelain 2>/dev/null)" ] && b="\$b *"
  printf ' \033[38;5;141m %s\033[0m' "\$b"
}
__panda_prompt() {
  local code=\$?
  local c='\033[38;5;75m'
  [ "\$code" -ne 0 ] && c='\033[38;5;203m'
  PS1="\033[38;5;110m╭─ \033[38;5;183m\w\033[0m\$(__panda_git) \033[38;5;110m[\${code}]\033[0m\\n\${c}╰─❯ \033[0m"
}
PROMPT_COMMAND=__panda_prompt
__panda_prompt
''';

  static Future<void> ensureAlpineRuntimeFiles() async {
    final dir = alpineDir;
    if (!Directory(dir).existsSync()) return;
    for (final name in const [
      'root', 'root/workspace', 'tmp', 'var/tmp', 'dev', 'proc', 'sys',
      'etc/apk', 'etc/profile.d', 'usr/local/bin',
    ]) {
      Directory('$dir/$name').createSync(recursive: true);
    }
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
  }
}