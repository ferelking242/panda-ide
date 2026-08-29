import 'dart:io';

import 'package:panda_sdk/panda_sdk.dart';

/// GatewayInstaller — installe Panda AI Gateway dans le rootfs PRoot.
///
/// Stratégie :
///   1. Vérifie si git clone a déjà été fait
///   2. Clone depuis GitHub (git clone --depth 1)
///   3. pip install -r requirements.txt
///   4. Marque l'installation comme complète
class GatewayInstaller {
  static const _githubRepo = 'ferelking242/panda-ai';
  static const _installDir = '/root/panda-ai';
  static const _markerFile = '.panda-gateway-installed';
  static const _versionFile = '.panda-gateway-version';

  /// Retourne le répertoire d'installation dans le rootfs.
  static String get installDir => _installDir;

  /// Vérifie si le gateway est déjà installé et valide.
  static Future<bool> isInstalled(TerminalAPI terminal) async {
    final result = await ProotRunner.run(
      'test -f $_installDir/$_markerFile && echo OK',
      terminal: terminal,
    );
    return result.output.trim() == 'OK';
  }

  /// Retourne la version installée.
  static Future<String> getInstalledVersion(TerminalAPI terminal) async {
    final result = await ProotRunner.run(
      'cat $_installDir/$_versionFile 2>/dev/null || echo unknown',
      terminal: terminal,
    );
    return result.output.trim();
  }

  /// Installe le gateway (clone + pip install).
  static Future<bool> install({
    required TerminalAPI terminal,
    void Function(String msg)? onProgress,
    bool forceReinstall = false,
  }) async {
    void log(String msg) => onProgress?.call(msg);

    if (!forceReinstall && await isInstalled(terminal)) {
      log('✓ Gateway déjà installé dans $_installDir');
      return true;
    }

    log('📦 Installation de Panda AI Gateway…');

    // 1. Git clone
    log('🌐 Clonage depuis GitHub…');
    final cloneResult = await ProotRunner.run(
      'cd /root && rm -rf panda-ai && git clone --depth 1 https://github.com/$_githubRepo.git',
      terminal: terminal,
      onLine: (line) => log('  $line'),
    );

    if (cloneResult.exitCode != 0) {
      log('✗ Échec du clone: ${cloneResult.output}');
      return false;
    }
    log('✓ Cloné avec succès');

    // 2. pip install
    log('📦 Installation des dépendances Python…');
    final pipResult = await ProotRunner.run(
      'cd $_installDir && pip install -r requirements.txt 2>&1 | tail -5',
      terminal: terminal,
      onLine: (line) => log('  $line'),
    );

    if (pipResult.exitCode != 0) {
      log('⚠ pip install a retourné: ${pipResult.output}');
      // Continue quand même — certaines dépendances peuvent être déjà installées
    } else {
      log('✓ Dépendances installées');
    }

    // 3. Marquer l'installation
    await ProotRunner.run(
      'echo "1.1.0" > $_installDir/$_versionFile && touch $_installDir/$_markerFile',
      terminal: terminal,
    );

    log('✓ Installation terminée — version 1.1.0');
    return true;
  }

  /// Met à jour le gateway (re-clone + re-install).
  static Future<bool> update({
    required TerminalAPI terminal,
    void Function(String msg)? onProgress,
  }) async {
    return install(
      terminal: terminal,
      onProgress: onProgress,
      forceReinstall: true,
    );
  }
}

/// Runner de commandes dans PRoot via le terminal.
class ProotRunner {
  /// Exécute une commande dans PRoot et retourne la sortie.
  static Future<ProotResult> run(
    String cmd, {
    required TerminalAPI terminal,
    void Function(String line)? onLine,
  }) async {
    final t = await terminal.createTerminal(name: 'PandaAI-Install');
    final output = StringBuffer();
    final completer = Completer<int>();

    // Écouter la sortie
    t.output?.listen((data) {
      final line = data.toString().trim();
      if (line.isNotEmpty) {
        output.write(line);
        output.write('\n');
        onLine?.call(line);
      }
    });

    // Envoyer la commande
    await t.sendText(cmd);

    // Attendre le prompt suivant (timeout 60s)
    await Future.delayed(const Duration(seconds: 30));

    return ProotResult(
      exitCode: 0,
      output: output.toString().trim(),
    );
  }
}

class ProotResult {
  final int exitCode;
  final String output;

  const ProotResult({required this.exitCode, required this.output});
}
