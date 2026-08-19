import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:panda/utils/panda_log.dart';

class AlpineSetup {
  static Future<bool> _testProotBinary(String candidate) async {
    final file = File(candidate);
    if (!file.existsSync()) return false;
    try {
      final result = await Process.run(candidate, ['--version']).timeout(
        const Duration(milliseconds: 1500),
      );
      return result.exitCode == 0 ||
          (result.stdout.toString() + result.stderr.toString()).contains('PRoot');
    } catch (_) {
      return false;
    }
  }

  /// Locates a working proot binary following an ordered resolution:
  /// 1. Native library path: ${await NativeChannel.getLibraryPath()}/libproot.so
  /// 2. Bin directory: $binDir/proot
  /// 3. Rootfs candidates: $rootfsDir/proot, $rootfsDir/bin/proot, etc.
  static Future<String?> locateProotBinary(String rootfsDir) async {
    final candidates = <String>[];
    try {
      final sharedPath = await NativeChannel.getLibraryPath();
      if (sharedPath.isNotEmpty) {
        candidates.add('$sharedPath/libproot.so');
      }
    } catch (_) {}

    candidates.addAll([
      '$binDir/proot',
      '$rootfsDir/proot',
      '$rootfsDir/bin/proot',
      '$rootfsDir/rootfs/proot',
      '$rootfsDir/rootfs/bin/proot',
    ]);

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        if (await _testProotBinary(candidate)) {
          return candidate;
        }
      }
    }

    // Nominal fallback: if libproot.so exists in native library dir, return it
    try {
      final sharedPath = await NativeChannel.getLibraryPath();
      final libProot = '$sharedPath/libproot.so';
      if (File(libProot).existsSync()) {
        return libProot;
      }
    } catch (_) {}

    // Legacy fallback: if $binDir/proot exists
    if (File('$binDir/proot').existsSync()) {
      return '$binDir/proot';
    }

    return null;
  }

  /// Ensures Alpine Linux rootfs is present and intact.
  /// Re-extracts from assets/runtimes/alpine-proot.zip if incomplete or missing.
  static Future<bool> ensureAlpineRootfs({bool force = false}) async {
    final alpineDir = '$runtimesDir/alpine-linux';
    final busybox1 = File('$alpineDir/bin/busybox');
    final busybox2 = File('$alpineDir/rootfs/bin/busybox');
    final etcDir = Directory('$alpineDir/etc');
    final usrDir = Directory('$alpineDir/usr');

    final isRootfsComplete = (busybox1.existsSync() || busybox2.existsSync()) &&
        etcDir.existsSync() &&
        usrDir.existsSync();

    if (isRootfsComplete && !force) {
      return true;
    }

    PandaLog.i('AlpineSetup', 'Installing / repairing Alpine Linux rootfs...');
    try {
      final runtimesDirectory = Directory(runtimesDir);
      if (!runtimesDirectory.existsSync()) {
        runtimesDirectory.createSync(recursive: true);
      }

      final zipPath = '$runtimesDir/alpine-proot.zip';
      final zipBytes = await rootBundle.load('assets/runtimes/alpine-proot.zip');
      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipBytes.buffer.asUint8List(), flush: true);

      await ZipFile.extractToDirectory(
        zipFile: zipFile,
        destinationDir: runtimesDirectory,
      );

      try {
        if (zipFile.existsSync()) zipFile.deleteSync();
      } catch (_) {}

      PandaLog.i('AlpineSetup', 'Alpine Linux rootfs installed successfully.');
      return true;
    } catch (e) {
      PandaLog.e('AlpineSetup', 'Failed to extract Alpine rootfs: $e');
      return false;
    }
  }

  /// (Re)writes essential runtime configuration files:
  /// /etc/resolv.conf (with DNS servers), /etc/hosts, /etc/passwd, /root/.profile, /root/.bashrc.
  static Future<void> ensureAlpineRuntimeFiles() async {
    final alpineDir = '$runtimesDir/alpine-linux';
    if (!Directory(alpineDir).existsSync()) return;

    try {
      // 1. etc/resolv.conf
      final resolv = File('$alpineDir/etc/resolv.conf');
      resolv.parent.createSync(recursive: true);
      String dnsServers = 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 1.0.0.1\n';
      try {
        final dns1 = Process.runSync('getprop', ['net.dns1']).stdout.toString().trim();
        final dns2 = Process.runSync('getprop', ['net.dns2']).stdout.toString().trim();
        if (dns1.isNotEmpty && dns1 != 'null') {
          dnsServers = 'nameserver $dns1\n';
          if (dns2.isNotEmpty && dns2 != 'null') dnsServers += 'nameserver $dns2\n';
          dnsServers += 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n';
        }
      } catch (_) {}
      resolv.writeAsStringSync(dnsServers, flush: true);

      // 2. etc/hosts
      final hosts = File('$alpineDir/etc/hosts');
      if (!hosts.existsSync() || hosts.lengthSync() == 0) {
        hosts.writeAsStringSync('127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n', flush: true);
      }

      // 3. etc/passwd minimal
      final passwd = File('$alpineDir/etc/passwd');
      if (!passwd.existsSync() || passwd.lengthSync() == 0) {
        passwd.writeAsStringSync('root:x:0:0:root:/root:/bin/sh\n', flush: true);
      }

      // 4. root/.profile & root/.bashrc
      final rootDir = Directory('$alpineDir/root');
      if (!rootDir.existsSync()) {
        rootDir.createSync(recursive: true);
      }

      const gitBranchFn = r"""# Git branch helper
__git_branch() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  echo " \033[38;5;214m🌿 ${branch}\033[0m"
}
pkg() {
  apk "$@"
}
apt() {
  apk "$@"
}
winget() {
  echo -e "\033[38;5;208m[Panda Linux]\033[0m 'winget' est pour Windows. Utilisez \033[1m'apk add <paquet>'\033[0m."
}
""";
      const richPS1 = r"""# Flash Prompt
export PS1='\[\033[38;5;141m\]🐼 panda \[\033[38;5;75m\]📁 \w\[\033[0m\]$(__git_branch) \[\033[38;5;118m\]➜\[\033[0m\] '
""";
      final aliases = [
        'alias ls="ls --color=auto"',
        'alias ll="ls -la --color=auto"',
        'alias la="ls -la"',
        'alias grep="grep --color=auto"',
        'alias cp="cp -i"',
        'alias mv="mv -i"',
        'alias ..="cd .."',
        'alias ...="cd ../.."',
      ];

      final fullProfile = '${gitBranchFn.trimRight()}\n${richPS1.trimRight()}\n${aliases.join("\n")}\n';

      final profileFile = File('$alpineDir/root/.profile');
      final bashrcFile = File('$alpineDir/root/.bashrc');

      profileFile.writeAsStringSync(fullProfile, flush: true);
      bashrcFile.writeAsStringSync(fullProfile, flush: true);
    } catch (e) {
      PandaLog.w('AlpineSetup', 'Error writing Alpine runtime files: $e');
    }
  }
}
