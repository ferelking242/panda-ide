import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:panda/utils/panda_log.dart';

/// Provisioning et résolution du runtime Alpine/PRoot embarqué dans Panda.
///
/// Panda est **autonome** : PRoot et toutes ses dépendances natives
/// (libtalloc.so, libandroid-shmem.so, loader PRoot) sont livrés dans
/// `android/app/src/main/jniLibs/arm64-v8a/` et extraits par Android dans
/// `applicationInfo.nativeLibraryDir`. Aucune installation Termux n'est
/// requise, et rien n'est téléchargé au runtime.
class AlpineSetup {
  static const String _alpineDirName = 'alpine-linux';

  static String? _cachedNativeLibDir;
  static String? _cachedProotBin;

  static String get alpineDir => '$runtimesDir/$_alpineDirName';

  /// Répertoire des libs natives extraites de l'APK.
  static Future<String> nativeLibDir() async {
    final cached = _cachedNativeLibDir;
    if (cached != null) return cached;
    try {
      final path = await NativeChannel.getLibraryPath();
      if (path.isNotEmpty && Directory(path).existsSync()) {
        _cachedNativeLibDir = path;
        return path;
      }
    } catch (_) {}
    return '';
  }

  /// Chemin du loader PRoot embarqué (`libproot-loader.so`), ou null.
  static Future<String?> prootLoaderPath() async {
    final dir = await nativeLibDir();
    if (dir.isEmpty) return null;
    final loader = File('$dir/libproot-loader.so');
    return loader.existsSync() ? loader.path : null;
  }

  /// Environnement minimal nécessaire pour que le linker Bionic résolve
  /// les dépendances ELF de PRoot (libtalloc.so, libandroid-shmem.so) et
  /// que PRoot trouve son loader.
  ///
  /// C'est la cause exacte de
  /// `library "libtalloc.so.2" not found: needed by main executable` :
  /// PRoot était lancé avec `LD_LIBRARY_PATH` vide alors que son RUNPATH
  /// pointe vers un chemin Termux inexistant.
  static Future<Map<String, String>> prootLinkEnvironment() async {
    final env = <String, String>{};
    final dir = await nativeLibDir();
    if (dir.isNotEmpty) {
      env['LD_LIBRARY_PATH'] = dir;
      final loader = File('$dir/libproot-loader.so');
      if (loader.existsSync()) {
        env['PROOT_LOADER'] = loader.path;
      }
    }
    try {
      final tmp = Directory(tempDir);
      if (!tmp.existsSync()) tmp.createSync(recursive: true);
      env['PROOT_TMP_DIR'] = tempDir;
    } catch (_) {}
    return env;
  }

  /// Environnement complet d'une session PRoot (link env + env invité).
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

  /// Teste réellement un binaire PRoot candidat (exécution + link ELF),
  /// avec l'environnement natif complet.
  static Future<bool> _testProotBinary(String candidate) async {
    final file = File(candidate);
    if (!file.existsSync()) return false;
    try {
      final env = await prootLinkEnvironment();
      final result = await Process.run(
        candidate,
        ['--version'],
        environment: env,
      ).timeout(const Duration(seconds: 5));
      final output = '${result.stdout}${result.stderr}';
      if (result.exitCode == 0 || output.contains('PRoot')) return true;
      PandaLog.w('AlpineSetup', 'PRoot candidate rejected ($candidate): '
          'exit=${result.exitCode} ${output.trim()}');
      return false;
    } catch (e) {
      PandaLog.w('AlpineSetup', 'PRoot candidate failed ($candidate): $e');
      return false;
    }
  }

  /// Résolution ordonnée du binaire PRoot :
  /// 1. `${nativeLibraryDir}/libproot.so` (embarqué dans l'APK — prioritaire)
  /// 2. anciens chemins ($binDir/proot, rootfs/proot…) — compatibilité seulement
  ///
  /// Chaque candidat est réellement exécuté. Aucun repli sur le shell Android.
  static Future<String?> locateProotBinary(String rootfsDir,
      {bool useCache = true}) async {
    final cached = _cachedProotBin;
    if (useCache && cached != null && File(cached).existsSync()) {
      return cached;
    }

    final candidates = <String>[];
    final nativeDir = await nativeLibDir();
    if (nativeDir.isNotEmpty) {
      candidates.add('$nativeDir/libproot.so');
    }
    candidates.addAll([
      '$binDir/proot',
      '$rootfsDir/proot',
      '$rootfsDir/bin/proot',
      '$rootfsDir/rootfs/proot',
      '$rootfsDir/rootfs/bin/proot',
    ]);

    for (final candidate in candidates) {
      if (!File(candidate).existsSync()) continue;
      if (await _testProotBinary(candidate)) {
        _cachedProotBin = candidate;
        return candidate;
      }
    }

    PandaLog.e('AlpineSetup',
        'Aucun binaire PRoot exécutable trouvé parmi: ${candidates.join(", ")}');
    return null;
  }

  static Future<void> _chmodExec(String path, {bool recursive = false}) async {
    for (final tool in const ['/system/bin/chmod', 'chmod']) {
      try {
        final args = recursive ? ['-R', '755', path] : ['755', path];
        final r = await Process.run(tool, args)
            .timeout(const Duration(seconds: 30));
        if (r.exitCode == 0) return;
      } catch (_) {}
    }
  }

  /// Vérifie que le rootfs est complet : bin/busybox, bin/sh, etc/, usr/, root/.
  static bool isRootfsComplete() {
    final dir = alpineDir;
    final busybox = File('$dir/bin/busybox').existsSync() ||
        File('$dir/rootfs/bin/busybox').existsSync();
    final sh = FileSystemEntity.typeSync('$dir/bin/sh',
            followLinks: false) !=
        FileSystemEntityType.notFound;
    return busybox &&
        sh &&
        Directory('$dir/etc').existsSync() &&
        Directory('$dir/usr').existsSync() &&
        Directory('$dir/root').existsSync();
  }

  /// Installe / répare le rootfs Alpine. Idempotent.
  static Future<bool> ensureAlpineRootfs({bool force = false}) async {
    final dir = alpineDir;

    if (isRootfsComplete() && !force) {
      return true;
    }

    final needsExtraction = force ||
        !(File('$dir/bin/busybox').existsSync() ||
            File('$dir/rootfs/bin/busybox').existsSync()) ||
        !Directory('$dir/etc').existsSync() ||
        !Directory('$dir/usr').existsSync();

    if (needsExtraction) {
      PandaLog.i('AlpineSetup', 'Installation / réparation du rootfs Alpine...');
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
        PandaLog.i('AlpineSetup', 'Rootfs Alpine extrait.');
      } catch (e) {
        PandaLog.e('AlpineSetup', 'Échec extraction rootfs Alpine: $e');
        return false;
      }
    }

    // Répertoires standards manquants dans l'archive.
    for (final sub in const [
      'root',
      'tmp',
      'etc',
      'dev',
      'proc',
      'sys',
      'var/tmp',
      'usr/bin',
      'usr/sbin',
      'usr/local/bin',
      'sbin',
      'bin',
    ]) {
      try {
        final d = Directory('$dir/$sub');
        if (!d.existsSync()) d.createSync(recursive: true);
      } catch (_) {}
    }

    // L'archive ZIP ne conserve pas les bits d'exécution.
    await _chmodExec('$dir/bin', recursive: true);
    await _chmodExec('$dir/sbin', recursive: true);
    await _chmodExec('$dir/usr', recursive: true);
    await _chmodExec('$dir/lib', recursive: true);

    await ensureBusyboxApplets();
    await ensureAlpineRuntimeFiles();

    final ok = isRootfsComplete();
    if (!ok) {
      PandaLog.e('AlpineSetup',
          'Rootfs Alpine encore incomplet après provisioning ($dir).');
    }
    return ok;
  }

  /// Applets busybox de secours si `busybox --list-full` n'est pas disponible.
  static const List<String> _fallbackApplets = [
    'bin/sh', 'bin/ash', 'bin/ls', 'bin/cat', 'bin/cp', 'bin/mv', 'bin/rm',
    'bin/mkdir', 'bin/rmdir', 'bin/ln', 'bin/chmod', 'bin/chown', 'bin/echo',
    'bin/pwd', 'bin/sleep', 'bin/date', 'bin/ps', 'bin/kill', 'bin/grep',
    'bin/sed', 'bin/dd', 'bin/df', 'bin/du', 'bin/tar', 'bin/gzip',
    'bin/gunzip', 'bin/hostname', 'bin/more', 'bin/sync', 'bin/touch',
    'bin/uname', 'bin/printenv', 'bin/mktemp', 'bin/su', 'bin/login',
    'usr/bin/env', 'usr/bin/awk', 'usr/bin/find', 'usr/bin/xargs',
    'usr/bin/head', 'usr/bin/tail', 'usr/bin/sort', 'usr/bin/uniq',
    'usr/bin/wc', 'usr/bin/cut', 'usr/bin/tr', 'usr/bin/vi', 'usr/bin/which',
    'usr/bin/whoami', 'usr/bin/id', 'usr/bin/basename', 'usr/bin/dirname',
    'usr/bin/tee', 'usr/bin/seq', 'usr/bin/clear', 'usr/bin/expr',
    'usr/bin/nohup', 'usr/bin/top', 'usr/bin/unzip', 'usr/bin/wget',
    'usr/bin/md5sum', 'usr/bin/sha256sum', 'usr/bin/realpath',
    'usr/bin/readlink', 'usr/bin/stat', 'usr/bin/strings', 'usr/bin/tty',
    'usr/bin/uptime', 'usr/bin/yes', 'usr/bin/less', 'usr/bin/diff',
    'usr/bin/patch', 'usr/bin/killall', 'usr/bin/time', 'usr/bin/nslookup',
    'usr/bin/hexdump', 'usr/bin/install', 'usr/bin/xxd',
    'sbin/sysctl', 'sbin/route', 'sbin/arp', 'sbin/ifconfig',
  ];

  /// Recrée les applets busybox (`/bin/sh`, `/usr/bin/env`, …).
  ///
  /// `assets/runtimes/alpine-proot.zip` ne contient aucun symlink (le format
  /// ZIP utilisé les a aplatis) : sans cette étape `/bin/sh` n'existe pas et
  /// la session PRoot se termine immédiatement.
  static Future<void> ensureBusyboxApplets({bool force = false}) async {
    final dir = alpineDir;
    final busybox = File('$dir/bin/busybox');
    if (!busybox.existsSync()) {
      PandaLog.e('AlpineSetup', 'bin/busybox absent — rootfs invalide.');
      return;
    }
    await _chmodExec(busybox.path);

    final shExists = FileSystemEntity.typeSync('$dir/bin/sh',
            followLinks: false) !=
        FileSystemEntityType.notFound;
    final envExists = FileSystemEntity.typeSync('$dir/usr/bin/env',
            followLinks: false) !=
        FileSystemEntityType.notFound;
    if (shExists && envExists && !force) return;

    // Bootstrap minimal : /bin/sh doit exister pour tout le reste.
    _linkApplet(dir, 'bin/sh');

    var applets = <String>[];
    try {
      applets = await _listBusyboxApplets(dir);
    } catch (e) {
      PandaLog.w('AlpineSetup', 'busybox --list-full indisponible: $e');
    }
    if (applets.isEmpty) {
      applets = _fallbackApplets;
      PandaLog.w('AlpineSetup', 'Utilisation de la liste d\'applets de secours.');
    }

    var created = 0;
    for (final applet in applets) {
      if (_linkApplet(dir, applet)) created++;
    }
    PandaLog.i('AlpineSetup', 'Applets busybox provisionnés: $created');
  }

  /// Interroge busybox (via PRoot) pour la liste exacte de ses applets.
  static Future<List<String>> _listBusyboxApplets(String dir) async {
    final prootBin = await locateProotBinary(dir);
    if (prootBin == null) return const [];
    final env = await prootLinkEnvironment();
    final result = await Process.run(
      prootBin,
      [
        '-0',
        '--link2symlink',
        '--kill-on-exit',
        '--rootfs=$dir',
        '-b', '/dev',
        '-b', '/proc',
        '-w', '/',
        '/bin/busybox',
        '--list-full',
      ],
      environment: env,
    ).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      PandaLog.w('AlpineSetup',
          'busybox --list-full exit=${result.exitCode}: ${result.stderr}');
      return const [];
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('/') && l.contains('/'))
        .toList();
  }

  /// Crée `<dir>/<appletPath>` en symlink relatif vers bin/busybox.
  static bool _linkApplet(String dir, String appletPath) {
    try {
      if (appletPath == 'bin/busybox') return false;
      final target = '$dir/$appletPath';
      if (FileSystemEntity.typeSync(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return false;
      }
      final parent = Directory(target).parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);
      final depth = appletPath.split('/').length - 1;
      final relative = '${'../' * depth}bin/busybox';
      Link(target).createSync(relative);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// (Ré)écrit les fichiers de configuration essentiels du rootfs.
  /// Idempotent, exécuté à chaque lancement.
  static Future<void> ensureAlpineRuntimeFiles() async {
    final dir = alpineDir;
    if (!Directory(dir).existsSync()) return;

    try {
      // 1. etc/resolv.conf
      final resolv = File('$dir/etc/resolv.conf');
      resolv.parent.createSync(recursive: true);
      String dnsServers =
          'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 1.0.0.1\n';
      try {
        final dns1 =
            Process.runSync('getprop', ['net.dns1']).stdout.toString().trim();
        final dns2 =
            Process.runSync('getprop', ['net.dns2']).stdout.toString().trim();
        if (dns1.isNotEmpty && dns1 != 'null') {
          dnsServers = 'nameserver $dns1\n';
          if (dns2.isNotEmpty && dns2 != 'null') {
            dnsServers += 'nameserver $dns2\n';
          }
          dnsServers += 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n';
        }
      } catch (_) {}
      resolv.writeAsStringSync(dnsServers, flush: true);

      // 2. etc/hosts
      final hosts = File('$dir/etc/hosts');
      if (!hosts.existsSync() || hosts.lengthSync() == 0) {
        hosts.writeAsStringSync(
          '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n',
          flush: true,
        );
      }

      // 3. etc/passwd / etc/group / etc/shells
      final passwd = File('$dir/etc/passwd');
      if (!passwd.existsSync() || passwd.lengthSync() == 0) {
        passwd.writeAsStringSync(
          'root:x:0:0:root:/root:/bin/sh\n'
          'nobody:x:65534:65534:nobody:/:/sbin/nologin\n',
          flush: true,
        );
      }
      final group = File('$dir/etc/group');
      if (!group.existsSync() || group.lengthSync() == 0) {
        group.writeAsStringSync('root:x:0:root\nnobody:x:65534:\n', flush: true);
      }
      final shells = File('$dir/etc/shells');
      if (!shells.existsSync() || shells.lengthSync() == 0) {
        shells.writeAsStringSync('/bin/sh\n/bin/ash\n/bin/bash\n', flush: true);
      }

      // 4. etc/apk/repositories (apk add fonctionnel)
      final repos = File('$dir/etc/apk/repositories');
      if (!repos.existsSync() || repos.lengthSync() == 0) {
        repos.parent.createSync(recursive: true);
        repos.writeAsStringSync(
          'https://dl-cdn.alpinelinux.org/alpine/latest-stable/main\n'
          'https://dl-cdn.alpinelinux.org/alpine/latest-stable/community\n',
          flush: true,
        );
      }

      // 5. root/.profile & root/.bashrc
      final rootDir = Directory('$dir/root');
      if (!rootDir.existsSync()) rootDir.createSync(recursive: true);

      const gitBranchFn = r"""# LD_LIBRARY_PATH d'Android ne doit pas fuiter dans l'invité
unset LD_LIBRARY_PATH
# Git branch helper
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

      final fullProfile =
          '${gitBranchFn.trimRight()}\n${richPS1.trimRight()}\n${aliases.join("\n")}\n';

      File('$dir/root/.profile').writeAsStringSync(fullProfile, flush: true);
      File('$dir/root/.bashrc').writeAsStringSync(fullProfile, flush: true);
    } catch (e) {
      PandaLog.w('AlpineSetup', 'Erreur écriture fichiers runtime Alpine: $e');
    }
  }
}
