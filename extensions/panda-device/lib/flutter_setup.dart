/// FlutterSetup — installe / lance le SDK Flutter DANS le rootfs via PROOT.
///
/// Méthode validée sur le terrain (réseau proot instable) :
///   1. Tarball curl avec reprise (`curl -C - --retry`)
///   2. Greffe d'un vrai .git (le flutter tool l'exige)
///   3. Premier `flutter --version` → Dart SDK arm64
///   4. Fallback dart-sdk-linux-arm64.zip GCS si échec
library panda_device.flutter_setup;

import 'package:panda_sdk/panda_sdk.dart';

import 'proot_runner.dart';

class FlutterSetup {
  final TerminalAPI _terminal;
  final NetworkAPI _network;
  final FileSystemAPI _fs;
  final PandaLogger _log;
  final void Function(int? progress, String message)? onProgress;

  String installPath = '/opt/flutter';

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
    final r = await ProotRunner.run('test -x $installPath/bin/flutter && echo OK');
    return r.output.trim() == 'OK';
  }

  Future<String> version() async {
    final r = await ProotRunner.run(
        '$installPath/bin/flutter --version 2>/dev/null | head -1');
    return r.output.trim();
  }

  // ── Installation ───────────────────────────────────────────────────

  Future<bool> install({String channel = 'stable'}) async {
    void step(double p, String m) => onProgress?.call((p * 100).round(), m);
    final dir = installPath.substring(0, installPath.lastIndexOf('/'));

    try {
      step(0.05, 'Téléchargement Flutter ($channel)…');
      await _sh(
        'mkdir -p $dir && cd $dir && '
        'rm -rf flutter flutter-$channel fl.tar.gz && '
        'curl -L --retry 10 --retry-all-errors -C - '
        '--connect-timeout 30 -o fl.tar.gz '
        'https://github.com/flutter/flutter/archive/refs/heads/$channel.tar.gz',
      );

      step(0.35, 'Extraction…');
      await _sh('cd $dir && tar xzf fl.tar.gz && '
          'mv flutter-$channel flutter && rm fl.tar.gz');

      step(0.45, 'Greffe git…');
      var ok = false;
      for (var i = 1; i <= 3 && !ok; i++) {
        await _sh(
          'cd $installPath && '
          'git init -q -b $channel 2>/dev/null; '
          'git remote add origin https://github.com/flutter/flutter.git 2>/dev/null || true; '
          'git fetch --depth 1 -q origin $channel && '
          'git reset --hard -q FETCH_HEAD && echo GRAFTED',
        );
        ok = (await _sh('cd $installPath && test -d .git && echo YES'))
                .trim() == 'YES';
        if (!ok) _log.warning('Greffe git échouée (essai $i)');
      }
      if (!ok) return false;

      step(0.55, 'Dart SDK arm64 (~250 Mo)…');
      await _sh(
        'export PATH=$installPath/bin:\$PATH && '
        'flutter config --no-analytics >/dev/null 2>&1; '
        'flutter --version',
        onLine: _log.debug,
      );

      if (!await isInstalled()) {
        step(0.70, 'Fallback Dart SDK direct…');
        await _manualDartSdk();
      }
      if (!await isInstalled()) return false;

      step(0.85, 'Precache android…');
      await _sh('export PATH=$installPath/bin:\$PATH && '
          'flutter precache --android', onLine: _log.debug);

      step(1.0, 'Flutter prêt 🐼');
      return true;
    } catch (e) {
      _log.error('Installation Flutter échouée', e);
      return false;
    }
  }

  Future<void> _manualDartSdk() async {
    await _sh(
      'ENGINE=\$(cat $installPath/bin/internal/engine.version) && '
      'mkdir -p $installPath/bin/cache && cd $installPath/bin/cache && '
      'curl -L --retry 10 --retry-all-errors -C - -o dart-sdk.zip '
      '"https://storage.googleapis.com/flutter_infra_release/flutter/'
      '\$ENGINE/dart-sdk-linux-arm64.zip" && '
      'rm -rf dart-sdk && unzip -qo dart-sdk.zip && '
      'touch engine-dart-sdk.stamp dart-sdk.stamp',
      onLine: _log.debug,
    );
  }

  // ── Run ────────────────────────────────────────────────────────────

  /// `flutter run` dans le terminal intégré (hot reload via sendText).
  Future<Terminal?> runOnDevice({String? serial}) async {
    final sel = serial != null ? '-s $serial' : '';
    final term = await _terminal.createTerminal(name: 'Flutter Run');
    await term.sendText(
      'export PATH=$installPath/bin:\$PATH && flutter run $sel --debug',
    );
    return term;
  }

  // ── Helper shell via proot ─────────────────────────────────────────

  Future<String> _sh(String cmd, {void Function(String line)? onLine}) async {
    final r = await ProotRunner.run(cmd, onLine: onLine ?? _log.debug);
    return r.output;
  }
}
