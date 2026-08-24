/// Initialisation du système Extension Host.
///
/// À appeler depuis main() avant runApp() (Android uniquement).
/// Responsabilités :
///   1. Extraire les assets JS sur le filesystem Android
///   2. Configurer ExtensionHostManager (chemins node + host.js)
///   3. Brancher TasksBridge.launchInTerminal sur le shell Android
///   4. Charger tous les contributes statiques (thèmes, snippets, grammars, icônes)
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/constants.dart';
import 'contributes/grammar_loader.dart';
import 'contributes/icon_theme_loader.dart';
import 'contributes/snippet_loader.dart';
import 'contributes/theme_loader.dart';
import 'extension_host_manager.dart';
import 'node_runtime.dart';
import 'tasks_bridge.dart';

/// Fichiers JS à extraire de assets/ vers le filesystem Android.
const _kExtensionHostAssets = [
  'assets/extension_host/host.js',
  'assets/extension_host/ipc.js',
  'assets/extension_host/api/types.js',
  'assets/extension_host/api/vscode.js',
  'assets/extension_host/api/webview.js',
  'assets/extension_host/api/scm.js',
  'assets/extension_host/api/tasks.js',
  'assets/extension_host/api/debug.js',
];

class ExtensionHostSetup {
  ExtensionHostSetup._();

  /// Chemin sur le filesystem vers le répertoire extension_host extrait.
  static String get hostDir => '$appDir/extension_host';

  /// Chemin vers host.js sur le filesystem.
  static String get hostJsPath => '$hostDir/host.js';

  /// Chemin vers le binaire node (installé via node_feature / runtimes).
  static String get nodeBinPath => '$binDir/node';

  // ── Point d'entrée principal ───────────────────────────────────────────

  /// Initialise le système Extension Host.
  ///
  /// [sharedPath] : résultat de NativeChannel.getLibraryPath().
  /// Doit être appelé depuis main() après WidgetsFlutterBinding.ensureInitialized(),
  /// uniquement sur Android (!kIsWeb).
  static Future<void> init({required String sharedPath}) async {
    // 1. Extraire les fichiers JS sur le filesystem.
    await _extractAssets();

    // 2. Initialize Node.js runtime.
    final nodeReady = await NodeRuntimeManager.instance.init();
    if (!nodeReady) {
      print('[ExtensionHostSetup] ⚠️ Node.js runtime not found. Extensions requiring Node.js will not work.');
      print('[ExtensionHostSetup] Download Node.js from Settings → Runtimes to enable extension support.');
    }

    // 3. Configurer le manager avec les chemins corrects.
    final effectiveNodePath = NodeRuntimeManager.instance.nodePath ?? nodeBinPath;
    ExtensionHostManager.instance.configure(
      nodeBinPath: effectiveNodePath,
      hostJsPath: hostJsPath,
    );

    // 3. Brancher TasksBridge sur le shell Android (libbash.so).
    _wireTerminal(sharedPath: sharedPath);

    // 4. Charger les contributes statiques en parallèle.
    await Future.wait([
      ThemeLoader.instance.loadAll(),
      SnippetLoader.instance.loadAll(),
      GrammarLoader.instance.loadAll(),
      IconThemeLoader.instance.loadAll(),
    ]);
  }

  // ── Extraction des assets JS ───────────────────────────────────────────

  /// Copie chaque fichier JS de assets/ vers $appDir/ si absent ou périmé.
  ///
  /// Mapping : 'assets/extension_host/foo.js' → '$appDir/extension_host/foo.js'
  static Future<void> _extractAssets() async {
    for (final assetPath in _kExtensionHostAssets) {
      // Enlever le préfixe 'assets/' pour obtenir le chemin relatif.
      final rel = assetPath.substring('assets/'.length); // 'extension_host/foo.js'
      final dest = File('$appDir/$rel');

      // Créer les répertoires parents si nécessaire.
      if (!dest.parent.existsSync()) {
        await dest.parent.create(recursive: true);
      }

      // Lire depuis le bundle Flutter et écrire sur disque.
      final data = await rootBundle.load(assetPath);
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
  }

  // ── Wiring terminal pour TasksBridge ──────────────────────────────────

  /// Branche TasksBridge.launchInTerminal sur le shell Android (libbash.so).
  ///
  /// Les extensions qui utilisent vscode.tasks.executeTask() verront leur
  /// commande lancée dans un sous-process bash Android.
  static void _wireTerminal({required String sharedPath}) {
    TasksBridge.instance.launchInTerminal =
        (String command, String? cwd, Map<String, String> env) async {
      await Process.start(
        '$sharedPath/libbash.so',
        ['-c', command],
        workingDirectory: cwd ?? homeDir,
        environment: {
          'PATH': '$binDir:$runtimesDir/node/bin:/bin:/usr/bin:/sbin:/usr/sbin',
          'HOME': homeDir,
          'PREFIX': appDir,
          'ROXUM_SHARED_PATH': sharedPath,
          'LD_LIBRARY_PATH': '$sharedPath:$libDir:$runtimesDir/clang',
          ...env,
        },
        mode: ProcessStartMode.detached,
      );
    };
  }
}
