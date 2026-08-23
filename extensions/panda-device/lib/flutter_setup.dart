/// FlutterSetup — vérifie / installe / lance le SDK Flutter dans le rootfs.
///
/// Méthode validée sur le terrain (réseau instable proot) :
///   1. Tarball curl avec reprise (`curl -C - --retry`) → pas de RPC git
///   2. Greffe d'un vrai .git sur l'arborescence (flutter tool l'exige)
///   3. Premier `flutter --version` → télécharge le Dart SDK arm64
///   4. Fallback manuel : dart-sdk-linux-arm64.zip depuis GCS si échec
library panda_device.flutter_setup;

import 'dart:async';
import 'dart:io';

import 'package:panda_sdk/panda_sdk.dart';

class FlutterSetup {
  final TerminalAPI _terminal;
  final NetworkAPI _network;
  final FileSystemAPI _fs;
  final PandaLogger _log;
  final void Function(int? progress, String message)? onProgress;

  /// Chemin du SDK dans le rootfs.
  String installPath = '/opt/flutter';

  Process? _runProcess;

  FlutterSetup({
    required TerminalAPI terminal,
    required NetworkAPI network,
    required FileSystemAPI fs,
    required PandaLogger logger,
    this.onProgress,
  })  : _terminal = terminal,
        _network = network,
        _fs = fs,
        _log = logger;

  // ── État ───────────────────────────────────────────────────────────

  Future<bool> isInstalled() async {
    final r = await _sh('test -x $installPath/bin/flutter && echo OK');
    return r.trim() == 'OK';
  }

  Future<String> version() async =>
      (await _sh('$installPath/bin/flutter --version 2>/dev/null | head -1'))
          .trim();

  Future<void> cancelInstall() async {
    _runProcess?.kill();
    _runProcess = null;
  }

  // ── Installation (avec progression) ────────────────────────────────

  Future<bool> install({String channel = 'stable'}) async {
    void step(double p, String m) =>
        onProgress?.call((p * 100).round(), m);

    try {
      // Étape 1/5 — téléchargement du tarball (reprise auto sur coupure)
      step(0.05, 'Téléchargement Flutter ($channel)…');
      await _sh(
        'mkdir -p ${_dirOf(installPath)} && cd ${_dirOf(installPath)} && '
        'rm -rf flutter flutter-$channel flutter-${channel}-* fl.tar.gz && '
        'curl -L --retry 10 --retry-all-errors -C - '
        '--connect-timeout 30 -o fl.tar.gz '
        'https://github.com/flutter/flutter/archive/refs/heads/$channel.tar.gz',
        stream: true,
      );
      if (!await _fileExists('${_dirOf(installPath)}/fl.tar.gz')) {
        _log.error('Tarball non téléchargé');
        return false;
      }
      step(0.35, 'Extraction…');

      // Étape 2/5 — extraction
      await _sh(
        'cd ${_dirOf(installPath)} && '
        'tar xzf fl.tar.gz && mv flutter-$channel flutter && rm fl.tar.gz',
      );

      // Étape 3/5 — greffe git (le flutter tool exige un vrai clone)
      step(0.45, 'Préparation du dépôt git…');
      var ok = false;
      for (var attempt = 1; attempt <= 3 && !ok; attempt++) {
        await _sh(
          'cd $installPath && '
          'git init -q -b $channel 2>/dev/null; '
          'git remote add origin https://github.com/flutter/flutter.git 2>/dev/null || true; '
          'git fetch --depth 1 -q origin $channel && '
          'git reset --hard -q FETCH_HEAD && echo GRAFTED',
          stream: true,
        );
        ok = (await _sh(
                'cd $installPath && test -d .git && echo YES')).trim() ==
            'YES';
        if (!ok) _log.warning('Greffe git échouée (essai $attempt), retry…');
      }
      if (!ok) return false;

      // Étape 4/5 — premier lancement (Dart SDK arm64 ~250 Mo)
      step(0.55, 'Téléchargement du Dart SDK arm64 (~250 Mo)…');
      await _sh(
        'export PATH=$installPath/bin:\$PATH && flutter config --no-analytics >/dev/null 2>&1; '
        'flutter --version',
        stream: true,
      );

      // Vérifie ; sinon fallback manuel dart-sdk.zip
      if (!await isInstalled()) {
        step(0.70, 'Fallback : Dart SDK direct…');
        await _manualDartSdk();
      }

      // Étape 5/5 — précaches pour build
      if (await isInstalled()) {
        step(0.85, 'Precache des artefacts…');
        await _sh(
          'export PATH=$installPath/bin:\$PATH && flutter precache --android',
          stream: true,
        );
        // PATH persistant
        await _sh(
          "grep -q '$installPath/bin' ~/.profile 2>/dev/null || "
          "echo 'export PATH=$installPath/bin:\$PATH' >> ~/.profile",
        );
        step(1.0, 'Flutter prêt 🐼');
        return true;
      }
      return false;
    } catch (e) {
      _log.error('Installation Flutter échouée', e);
      return false;
    }
  }

  /// Fallback : télécharge directement le dart-sdk arm64 officiel.
  Future<void> _manualDartSdk() async {
    final engine =
        (await _sh('cat $installPath/bin/internal/engine.version')).trim();
    await _sh(
      'ENGINE="$engine" && mkdir -p $installPath/bin/cache && '
      'cd $installPath/bin/cache && '
      'curl -L --retry 10 --retry-all-errors -C - -o dart-sdk.zip '
      '"https://storage.googleapis.com/flutter_infra_release/flutter/'
      '\$ENGINE/dart-sdk-linux-arm64.zip" && '
      'rm -rf dart-sdk && unzip -q dart-sdk.zip && '
      'touch engine-dart-sdk.stamp dart-sdk.stamp',
      stream: true,
    );
  }

  // ── Run ────────────────────────────────────────────────────────────

  /// `flutter run` sur l'appareil. Hot reload via sendText('r').
  Future<Terminal?> runOnDevice({String? serial}) async {
    final sel = serial != null ? '-s $serial' : '';
    final term = await _terminal.createTerminal(name: 'Flutter Run');
    await term.sendText(
      'export PATH=$installPath/bin:\$PATH && '
      'flutter run $sel --debug',
    );
    return term;
  }

  // ── Helpers shell ──────────────────────────────────────────────────

  Future<String> _sh(String cmd, {bool stream = false}) async {
    final r = await Process.run('sh', ['-c', cmd],
        stdoutEncoding: const _Lenient(), stderrEncoding: const _Lenient());
    final out = '${r.stdout}${r.stderr}'.trim();
    if (out.isNotEmpty) _log.debug(out);
    return out;
  }

  Future<bool> _fileExists(String p) => _fs.exists(p);

  static String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }
}

class _Lenient extends Converter<List<int>, String> {
  const _Lenient();

  @override
  String convert(List<int> input, [int start = 0, int? end]) =>
      utf8.decode(input, allowMalformed: true);
}
