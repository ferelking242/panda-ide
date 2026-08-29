/// Panda Device — Extension entry point.
///
/// Workflow façon Shizuku :
///   1. Ouvre les Options développeur Android (intent)
///   2. Guide l'appairage WiFi + saisie manuelle du code
///   3. `adb pair` + `adb connect` automatiques
///   4. Vérifie / installe Flutter SDK avec progression
///   5. ▶ Run : flutter run sur l'appareil
library panda_device;

import 'dart:async';

import 'package:panda_sdk/panda_sdk.dart';

import 'adb_service.dart';
import 'flutter_setup.dart';

class PandaDeviceExtension extends PandaExtension {
  @override
  String get id => 'dev.panda.device';

  @override
  String get name => 'Panda Device';

  @override
  String get version => '1.1.0';

  AdbService? _adb;
  FlutterSetup? _flutter;
  ExtensionContext? _ctx;

  /// Flux d'état consommé par la vue sidebar (device_panel).
  final StreamController<DeviceState> _state =
      StreamController<DeviceState>.broadcast();
  Stream<DeviceState> get onState => _state.stream;

  @override
  Future<void> onActivate(ExtensionContext context) async {
    _ctx = context;
    _adb = AdbService(
      terminal: context.terminal,
      storage: context.storage,
      logger: context.logger,
      onLog: (line) => _state.add(DeviceState(logLine: line)),
    );
    _flutter = FlutterSetup(
      terminal: context.terminal,
      network: context.network,
      fs: context.fs,
      logger: context.logger,
      onProgress: (p, msg) =>
          _state.add(DeviceState(progress: p, message: msg)),
    );

    context.commands.register('$id.open', (_) => runWizard());
    context.commands.register('$id.pair', (_) => pairFlow());
    context.commands.register('$id.checkFlutter', (_) => ensureFlutter());
    context.commands.register('$id.run', (_) => runOnDevice());
    context.commands.register('$id.status', (_) => showStatus());

    context.logger.info('Panda Device activé');
    unawaited(refreshStatus());
  }

  @override
  Future<void> onDeactivate() async {
    await _state.close();
    await _flutter?.cancelInstall();
  }

  // ── Wizard complet (bouton principal) ─────────────────────────────

  Future<void> runWizard() async {
    final ctx = _ctx!;
    if (!await _adb!.isAvailable()) {
      await ctx.window.showWarning(
        'adb introuvable dans le terminal.\n'
        'Installe-le avec : apk add android-tools',
      );
      return;
    }

    if (await _adb!.hasConnectedDevice()) {
      ctx.logger.info('Appareil déjà connecté');
      await ensureFlutter();
      return;
    }

    // Étape 1 — ouvrir les options développeur
    final goSettings = await ctx.window.showConfirmation(
      'Étape 1: Active le Débogage sans fil\n\n'
      'Panda va ouvrir les Options développeur.\n'
      'Active "Débogage sans fil" puis appuie sur\n'
      '"Associer l\'appareil avec un code d\'association".',
      title: 'Panda Device — Appairage',
    );
    if (!goSettings) return;
    await _adb!.openDeveloperSettings();
  }

  // ── Ouvrir les options développeur ────────────────────────────────

  Future<void> openDeveloperSettings() async {
    await _adb!.openDeveloperSettings();
    _state.add(DeviceState(
      message: 'Options développeur ouvertes — active Débogage sans fil',
    ));
  }

  // ── Saisie du code d'appairage ────────────────────────────────────

  Future<void> enterPairingCode() async {
    final ctx = _ctx!;

    if (!await _adb!.isAvailable()) {
      await ctx.window.showWarning('adb introuvable — installez-le d\'abord');
      return;
    }

    // Demander le port d'appairage
    final portStr = await ctx.window.showInputBox(const InputBoxOptions(
      prompt: 'Port d\'APPAIRAGE affiché dans la popup\n'
          '(ex: 44851 — pas le port de l\'écran principal !)',
      title: 'Port d\'appairage',
      placeHolder: '44851',
    ));
    if (portStr == null || int.tryParse(portStr.trim()) == null) return;

    // Demander le code à 6 chiffres
    final code = await ctx.window.showInputBox(const InputBoxOptions(
      prompt: 'Code d\'appairage à 6 chiffres\n'
          '(affiché dans la popup "Associer l\'appareil")',
      title: 'Code WiFi Debugging',
      placeHolder: '041602',
    ));
    if (code == null || code.trim().isEmpty) return;

    // Appairer
    _state.add(DeviceState(
      message: 'Appairage en cours (port ${portStr.trim()})…',
      allLogs: ['Port appairage: ${portStr.trim()}'],
    ));

    final paired = await _adb!.pair(
      port: portStr.trim(),
      code: code.trim(),
    );

    if (!paired) {
      await ctx.window.showError(
        'Échec de l\'appairage.\n'
        'Vérifie:\n'
        '• Le port est bien celui de la popup (pas l\'écran principal)\n'
        '• Le code fait bien 6 chiffres\n'
        '• La popup est encore ouverte (expire en ~60s)',
      );
      return;
    }

    _state.add(DeviceState(
      message: 'Appairé ! Maintenant connecte le port de débogage.',
    ));

    await ctx.window.showInformation(
      '✅ Appairage réussi !\n\n'
      'Maintenant, note le PORT de DÉBOGAGE affiché\n'
      'sur l\'écran principal "Débogage sans fil"\n'
      '(pas la popup d\'appairage).',
    );
  }

  // ── Saisie du port de débogage ────────────────────────────────────

  Future<void> enterDebugPort() async {
    final ctx = _ctx!;

    if (!await _adb!.isAvailable()) {
      await ctx.window.showWarning('adb introuvable');
      return;
    }

    final debugPort = await ctx.window.showInputBox(InputBoxOptions(
      prompt: 'Port de DÉBOGAGE\n'
          '(affiché sur l\'écran "Débogage sans fil")\n'
          'IP: ${_adb!.wifiIp ?? "voir écran"}',
      title: 'Connexion adb',
      defaultValue: _adb!.lastDebugPort,
      placeHolder: '5555',
    ));
    if (debugPort == null || debugPort.trim().isEmpty) return;

    _state.add(DeviceState(
      message: 'Connexion sur port ${debugPort.trim()}…',
    ));

    final connected = await _adb!.connect(port: debugPort.trim());
    if (!connected) {
      await ctx.window.showError(
        'adb connect a échoué.\n'
        'Vérifie:\n'
        '• Le port est bien celui de l\'écran principal\n'
        '• Le téléphone est sur le même WiFi\n'
        '• Le débogage sans fil est actif',
      );
      return;
    }

    _state.add(DeviceState(
      message: '📱 Appareil connecté !',
    ));
    await ctx.window.showInformation('📱 Appareil connecté !');
    await ensureFlutter();
  }

  /// Appairage seul.
  Future<void> pairFlow() async {
    await _adb!.openDeveloperSettings();
    await runWizard();
  }

  // ── Flutter SDK ────────────────────────────────────────────────────

  Future<void> ensureFlutter() async {
    _state.add(DeviceState(message: 'Vérification Flutter…'));
    if (await _flutter!.isInstalled()) {
      final v = await _flutter!.version();
      _state.add(DeviceState(
        message: 'Flutter $v ✓',
        progress: 100,
        flutterVersion: v,
      ));
      await _ctx!.window.showInformation('Flutter $v est prêt 🐼');
      return;
    }

    _state.add(DeviceState(message: 'Installation de Flutter…', progress: 0));
    final ok = await _flutter!.install();
    if (ok) {
      final v = await _flutter!.version();
      _state.add(DeviceState(
        message: 'Flutter $v installé ✓',
        progress: 100,
        flutterVersion: v,
      ));
      await _ctx!.window.showInformation('Flutter $v installé avec succès 🎉');
    } else {
      _state.add(DeviceState(message: 'Installation échouée — réessaie'));
      await _ctx!.window
          .showError('Installation Flutter échouée (réseau ?). Réessaie.');
    }
  }

  // ── Run ────────────────────────────────────────────────────────────

  Future<void> runOnDevice() async {
    if (!await _adb!.hasConnectedDevice()) {
      await _ctx!.window
          .showWarning('Aucun appareil — lance d\'abord l\'appairage.');
      return;
    }
    if (!await _flutter!.isInstalled()) {
      await ensureFlutter();
    }
    await _flutter!.runOnDevice(serial: await _adb!.firstDeviceSerial());
  }

  // ── Status ─────────────────────────────────────────────────────────

  Future<void> refreshStatus() async {
    final adbOk = await _adb?.isAvailable() ?? false;
    final device = adbOk ? await _adb?.hasConnectedDevice() : false;
    var flutter = '?';
    if (_flutter != null && await _flutter!.isInstalled()) {
      flutter = await _flutter!.version();
    }
    _state.add(DeviceState(
      message: 'adb:${adbOk ? '✓' : '✗'} · device:'
          '${device == true ? '✓' : '✗'} · flutter:$flutter',
      flutterVersion: flutter != '?' ? flutter : null,
    ));
  }

  Future<void> showStatus() async {
    await refreshStatus();
    await _ctx!.window.showInformation(
      _lastMessage ?? 'Panda Device — statut inconnu',
      actions: ['Réappairer', 'Installer Flutter'],
    );
  }

  String? _lastMessage;
}

/// État diffusé à la vue sidebar.
class DeviceState {
  final String? message;
  final int? progress; // 0..100
  final String? logLine;
  final String? flutterVersion;
  final List<String>? allLogs;

  const DeviceState({
    this.message,
    this.progress,
    this.logLine,
    this.flutterVersion,
    this.allLogs,
  });
}
