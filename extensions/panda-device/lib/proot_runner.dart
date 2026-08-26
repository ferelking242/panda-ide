/// ProotRunner — exécute des commandes DANS le rootfs Linux.
///
/// Supporte Ubuntu, Debian et Alpine via RootfsManager.
/// Le rootfs actif est déterminé par la préférence utilisateur.
///
/// NOTE compilation : ce fichier est compilé dans l'arbre lib/ de l'app
/// (lib/extensions/dev.panda.device/) → l'import relatif vers utils/ est
/// valide dans ce contexte.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/debian_setup.dart';
import '../../../utils/panda_log.dart';
import '../../../utils/rootfs_manager.dart';

class ProcResult {
  final int exitCode;
  final String output;
  const ProcResult(this.exitCode, this.output);
  bool get ok => exitCode == 0;
}

class ProotRunner {
  /// Exécute une commande shell dans le rootfs. Retourne stdout+stderr.
  static Future<ProcResult> run(
    String shellCmd, {
    void Function(String line)? onLine,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    // 1. Get active terminal type from RootfsManager
    final activeType = await RootfsManager.getActiveTerminal();

    // 2. Check if rootfs is installed via RootfsManager
    if (!await RootfsManager.isInstalled(activeType)) {
      PandaLog.e('ProotRunner',
          'Rootfs not installed for ${activeType.id}');
      return const ProcResult(-1, "Linux n'est pas encore configuré");
    }

    // 3. Get rootfs directory from RootfsManager
    final rootfsDir = await RootfsManager.rootfsDir(activeType);

    // 4. Find proot binary (still uses DebianSetup for native lib path)
    final prootBin = await DebianSetup.locateProotBinary(rootfsDir.path);
    if (prootBin == null) {
      PandaLog.e('ProotRunner', 'PRoot binary not found');
      return const ProcResult(-1, 'PRoot introuvable');
    }

    // 5. Determine the shell to use
    // Ubuntu/Debian use /usr/bin/bash (real file, no symlink chain)
    // Alpine uses /bin/sh (native, no usrmerge)
    final String shell;
    switch (activeType) {
      case TerminalType.ubuntu:
      case TerminalType.debian:
        // Prefer /usr/bin/bash (real file) over /bin/sh (symlink chain)
        shell = File('${rootfsDir.path}/usr/bin/bash').existsSync()
            ? '/usr/bin/bash'
            : '/bin/sh';
        break;
      case TerminalType.alpine:
        shell = '/bin/sh';
        break;
      case TerminalType.bionic:
        shell = '/system/bin/sh';
        break;
    }

    PandaLog.i('ProotRunner',
        'Running in ${activeType.id} rootfs at ${rootfsDir.path} with $shell');

    final prootArgs = <String>[
      '-0',
      '--link2symlink',
      '--kill-on-exit',
      '--rootfs=${rootfsDir.path}',
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      '-w', '/root',
      shell,
      '-c',
      shellCmd,
    ];

    final env = await DebianSetup.prootSessionEnvironment();
    final lines = <String>[];
    try {
      final process = await Process.start(prootBin, prootArgs).timeout(timeout);
      final sub1 = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) {
        lines.add(l);
        onLine?.call(l);
      });
      final sub2 = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) {
        lines.add(l);
        onLine?.call(l);
      });
      final code = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        return -1;
      });
      await sub1.asFuture<void>().catchError((_) {});
      await sub2.asFuture<void>().catchError((_) {});
      return ProcResult(code, lines.join('\n'));
    } catch (e) {
      PandaLog.e('ProotRunner', '$shellCmd failed: $e');
      return ProcResult(-1, e.toString());
    }
  }
}
