/// ProotRunner — exécute des commandes DANS le rootfs Alpine (pattern ApkService).
///
/// Les binaires adb/flutter vivent dans le rootfs : un appel Process.run
/// direct depuis le process Android ne les trouve pas. Tout passe par proot.
///
/// NOTE compilation : ce fichier est compilé dans l'arbre lib/ de l'app
/// (lib/extensions/dev.panda.device/) → l'import relatif vers utils/ est
/// valide dans ce contexte.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/alpine_setup.dart';
import '../../../utils/panda_log.dart';

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
    if (!AlpineSetup.isRootfsComplete()) {
      return const ProcResult(-1, "Alpine Linux n'est pas encore configuré");
    }
    final prootBin = await AlpineSetup.locateProotBinary(AlpineSetup.alpineDir);
    if (prootBin == null) return const ProcResult(-1, 'PRoot introuvable');

    final prootArgs = <String>[
      '-0',
      '--link2symlink',
      '--kill-on-exit',
      '--rootfs=${AlpineSetup.alpineDir}',
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      '-w', '/root',
      '/bin/sh',
      '-c',
      shellCmd,
    ];

    final env = await AlpineSetup.prootSessionEnvironment();
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
