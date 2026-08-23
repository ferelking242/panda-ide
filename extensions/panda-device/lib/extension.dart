/// Panda Device — Extension entry point.
///
/// Workflow façon Shizuku :
///   1. Ouvre les Options développeur Android (intent)
///   2. Guide l'appairage WiFi + notification d'aide pour le code
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
  String get version => '1.0.0';

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
    // État initial asynchrone (ne bloque pas l'activation)
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

    // Déjà connecté ? → passe direct à Flutter
    if (await _adb!.hasConnectedDevice()) {
      ctx.logger.info('Appareil déjà connecté');
      await ensureFlutter();
      return;
    }

    // Étape 1 — ouvrir les options développeur
    final goSettings = await ctx.window.showConfirmation(
      'Panda va ouvrir les Options développeur.\n\n'
      'Active « Débogage sans fil », puis tape « Associer l\'appareil '
      'avec un code » — garde la popup ouverte.',
      title: 'Panda Device — Appairage',
    );
    if (!goSettings) return;
    await _adb!.openDeveloperSettings();

    // Étape 2 — saisie guidée du port + code (comme Shizuku)
    final portStr = await ctx.window.showInputBox(const InputBoxOptions(
      prompt:
          'Port d\'APPAIRAGE affiché dans la popup\n(ex: 44851 — pas celui '
          'de l\'écran principal !)',
      title: 'Port d\'appairage',
      placeHolder: '44851',
    ));
    if (portStr == null || int.tryParse(portStr.trim()) == null) return;

    final code = await ctx.window.showInputBox(const InputBoxOptions(
      prompt: 'Code d\'appairage à 6 chiffres',
      title: 'Code WiFi Debugging',
      placeHolder: '041602',
    ));
    if (code == null) return;

    // Notification pendant que l'utilisateur regarde la popup
    unawaited(ctx.window.showInformation(
      'Saisis maintenant dans Panda Device — la popup doit rester ouverte.',
    ));

    // Étape 3 — appairer (loopback d'abord, puis IP WiFi en fallback)
    _state.add(DeviceState(message: 'Appairage en cours…'));
    final paired = await _adb!.pair(port: portStr.trim(), code: code.trim());
    if (!paired) {
      await ctx.window.showError(
        'Échec de l\'appairage.\n'
        'Vérifie port/code et relance (la popup expire en ~60 s).',
      );
      return;
    }

    // Étape 4 — connecter avec le port de l'écran principal
    final debugPort = await ctx.window.showInputBox(InputBoxOptions(
      prompt:
          'Port de DÉBOGAGE (écran principal Débogage sans fil)\n'
          'IP affichée : ${_adb!.wifiIp ?? 'voir écran'}',
      title: 'Connexion adb',
      defaultValue: _adb!.lastDebugPort,
    ));
    if (debugPort == null) return;

    _state.add(DeviceState(message: 'Connexion…'));
    final connected = await _adb!.connect(port: debugPort.trim());
    if (!connected) {
      await ctx.window.showError('adb connect a échoué — réessaie.');
      return;
    }

    await ctx.window.showInformation('📱 Appareil connecté !');
    await ensureFlutter();
  }

  /// Appairage seul.
  Future<void> pairFlow() async {
    await _adb!.openDeveloperSettings();
    await runWizard(); // même flux, isAvailable/connected déjà gérés
  }

  // ── Flutter SDK ────────────────────────────────────────────────────

  Future<void> ensureFlutter() async {
    _state.add(DeviceState(message: 'Vérification Flutter…'));
    if (await _flutter!.isInstalled()) {
      final v = await _flutter!.version();
      _state.add(DeviceState(message: 'Flutter $v ✓', progress: 100));
      await _ctx!.window.showInformation('Flutter $v est prêt 🐼');
      return;
    }

    _state.add(DeviceState(message: 'Installation de Flutter…', progress: 0));
    final ok = await _flutter!.install();
    if (ok) {
      final v = await _flutter!.version();
      _state.add(DeviceState(message: 'Flutter $v installé ✓', progress: 100));
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
    ));
  }

  Future<void> showStatus() async {
    await refreshStatus();
    await _ctx!.window.showInformation(
        _lastMessage ?? 'Panda Device — statut inconnu',
        actions: ['Réappairer', 'Installer Flutter']);
  }

  String? _lastMessage;
}

/// État diffusé à la vue sidebar.
class DeviceState {
  final String? message;
  final int? progress; // 0..100
  final String? logLine;

  const DeviceState({this.message, this.progress, this.logLine});
}
