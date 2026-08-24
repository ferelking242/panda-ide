/// Panneau "Flutter Device" — wizard Shizuku-style pour piloter adb/Flutter
/// sur le même téléphone depuis l'environnement Alpine.
///
/// UX Shizuku (pas de saisie manuelle) :
///   1. Vérifie les packages (adb, git, curl) → installe si manquants
///   2. Demande les permissions (notifications, listener, batterie)
///   3. Ouvre le débogage sans fil automatiquement
///   4. Détecte le code de pairing via notification → appairage automatique
///   5. Connexion auto via mDNS → pas de saisie de port
///   6. Run Flutter sur l'appareil
///
/// Aucun terminal intégré : la sortie des commandes va dans l'onglet terminal
/// de l'IDE.
library;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../services/flutter_device_service.dart';
import '../services/ide_tab_opener.dart';
import '../services/wireless_pairing_service.dart';
import '../utils/themes.dart';





class FlutterDevicePanel extends StatefulWidget {
  const FlutterDevicePanel({super.key});

  @override
  State<FlutterDevicePanel> createState() => _FlutterDevicePanelState();
}

class _FlutterDevicePanelState extends State<FlutterDevicePanel> {
  final _service = FlutterDeviceService.instance;
  final _pairing = WirelessPairingService.instance;

  int _step = 0; // 0=packages, 1=permissions, 2=pairing, 3=connect, 4=run
  bool _busy = false;
  String _status = '';
  String? _error;

  // Package states
  bool _adbInstalled = false;
  bool _gitInstalled = false;
  bool _curlInstalled = false;
  bool _checkingPackages = true;

  // Permission states
  bool _notifEnabled = false;
  bool _listenerEnabled = false;
  bool _batteryOptDisabled = false;

  // Pairing state
  bool _pairingDetected = false;
  PairingData? _pairingData;
  bool _pairingInProgress = false;

  // Connection state
  bool _connected = false;
  String _connectPort = '';
  List<AdbDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _bootstrap();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _pairing.stopPolling();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Étape 0 : Vérifier les packages
    await _checkPackages();
  }

  // ── Étape 0 : Vérification des packages ──────────────────────────────────

  Future<void> _checkPackages() async {
    setState(() { _checkingPackages = true; _busy = true; _status = 'Vérification des packages…'; });
    try {
      final results = await Future.wait([
        _service.checkPackage('adb'),
        _service.checkPackage('git'),
        _service.checkPackage('curl'),
      ]);
      _adbInstalled = results[0];
      _gitInstalled = results[1];
      _curlInstalled = results[2];
    } catch (_) {}
    setState(() { _checkingPackages = false; _busy = false; });

    // Installer les manquants automatiquement
    final missing = <String>[];
    if (!_adbInstalled) missing.add('android-tools');
    if (!_gitInstalled) missing.add('git');
    if (!_curlInstalled) missing.add('curl');

    if (missing.isNotEmpty) {
      setState(() { _busy = true; _status = 'Installation de ${missing.join(", ")}…'; });
      await _service.installPackages(missing, onLine: (line) {
        if (mounted) setState(() => _status = line);
      });
      setState(() { _busy = false; _status = ''; });
      // Re-vérifier
      _adbInstalled = await _service.checkPackage('adb');
      _gitInstalled = await _service.checkPackage('git');
      _curlInstalled = await _service.checkPackage('curl');
    }

    setState(() => _step = 1);
    _checkPermissions();
  }

  // ── Étape 1 : Permissions ────────────────────────────────────────────────

  Future<void> _checkPermissions() async {
    _notifEnabled = await _service.isPostNotificationsGranted();
    _listenerEnabled = await _pairing.isNotificationListenerEnabled();
    _batteryOptDisabled = await _pairing.isIgnoringBatteryOptimization();

    setState(() {});

    if (_notifEnabled && _listenerEnabled && _batteryOptDisabled) {
      setState(() => _step = 2);
      _startPairing();
    }
  }

  Future<void> _requestNotifPermission() async {
    await _service.requestPostNotificationsPermission();
    // Petit délai pour laisser le system dialog
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _requestListenerPermission() async {
    await _pairing.openNotificationListenerSettings();
  }

  Future<void> _requestBatteryOpt() async {
    await _pairing.requestIgnoreBatteryOptimization();
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  // ── Étape 2 : Appairage automatique ──────────────────────────────────────

  Future<void> _startPairing() async {
    setState(() { _pairingInProgress = true; _status = 'En attente du code d\'appairage…'; });

    // Écouter les notifications de pairing
    _pairing.onDetected.listen((data) {
      if (!mounted) return;
      setState(() {
        _pairingData = data;
        _pairingDetected = true;
        _status = 'Code détecté ! Appairage en cours…';
      });
      _doPairing(data);
    });

    // Polling en backup
    _pairing.startPolling();

    // Ouvrir le débogage sans fil pour guider l'utilisateur
    await _pairing.openWirelessDebugging();
  }

  Future<void> _doPairing(PairingData data) async {
    if (!data.isComplete) return;
    setState(() { _busy = true; _status = 'Appairage en cours… adb pair ${data.ip}:${data.port}'; });

    final ok = await _service.pair(data.port, data.code, onLine: (line) {
      if (mounted) setState(() => _status = line);
    });

    _pairing.stopPolling();

    if (ok) {
      setState(() { _busy = false; _status = 'Appairage réussi ✓'; _step = 3; });
      await _autoConnect();
    } else {
      setState(() { _busy = false; _error = 'Appairage échoué — réessaie'; _pairingInProgress = false; });
    }
  }

  // ── Étape 3 : Connexion auto via mDNS ────────────────────────────────────

  Future<void> _autoConnect() async {
    setState(() { _busy = true; _status = 'Découverte du port de débogage (mDNS)…'; });

    // Essayer mDNS d'abord
    final mDNSPort = await _service.discoverDebugPort();
    if (mDNSPort != null) {
      setState(() { _connectPort = mDNSPort; _status = 'Port détecté : $mDNSPort — connexion…'; });
      final ok = await _service.connect(mDNSPort, onLine: (line) {
        if (mounted) setState(() => _status = line);
      });
      if (ok) {
        await _refreshDevices();
        setState(() { _busy = false; _connected = true; _step = 4; _status = 'Connecté ✓'; });
        return;
      }
    }

    // Fallback : afficher champ de saisie de port
    setState(() { _busy = false; _status = ''; _step = 3; });
  }

  Future<void> _manualConnect() async {
    if (_connectPort.isEmpty) return;
    setState(() { _busy = true; _status = 'Connexion à 127.0.0.1:$_connectPort…'; });
    final ok = await _service.connect(_connectPort, onLine: (line) {
      if (mounted) setState(() => _status = line);
    });
    if (ok) {
      await _refreshDevices();
      setState(() { _busy = false; _connected = true; _step = 4; _status = 'Connecté ✓'; });
    } else {
      setState(() { _busy = false; _error = 'Connexion échouée — vérifie le port'; });
    }
  }

  Future<void> _refreshDevices() async {
    final devices = await _service.refreshDevices();
    setState(() { _devices = devices; });
  }

  // ── Étape 4 : Run Flutter ────────────────────────────────────────────────

  Future<void> _runFlutter() async {
    String? dev;
    for (final d in _devices) {
      if (d.online) { dev = d.serial; break; }
    }
    if (dev == null) {
      setState(() { _error = 'Aucun appareil connecté'; });
      return;
    }
    setState(() { _busy = true; _status = 'flutter run sur $dev…'; });
    await _service.startRun(deviceId: dev, onLine: (line) {
      // Output → onglet terminal de l'IDE (pas de console intégrée)
    });
    setState(() { _busy = false; _status = "Flutter en cours d'execution"; });
    // Ouvrir l'onglet terminal pour voir la sortie
    IdeTabOpener.instance.openTerminal();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppThemeBloc, AppThemeState>(
      builder: (context, themeState) {
        final appTheme = themeState.appTheme;
        final isDark = appTheme.isDark;
        final bg = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
        final fg = isDark ? Colors.grey[200]! : Colors.grey[900]!;
        final muted = isDark ? Colors.grey[500]! : Colors.grey[600]!;
        final card = isDark ? const Color(0xff252526) : Colors.white;
        final border = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
        final accent = const Color(0xFF007ACC);

        return Container(
          color: bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                child: Row(children: [
                  Icon(Icons.smartphone, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('Flutter Device', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                  const Spacer(),
                  if (_busy)
                    const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ),

              // ── Steps ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Progress indicator
                      _buildStepIndicator(fg, muted, accent, border),
                      const SizedBox(height: 16),

                      // Error banner
                      if (_error != null) ...[
                        _errorBanner(_error!, fg),
                        const SizedBox(height: 12),
                      ],

                      // ── Step 0 : Packages ──
                      if (_step == 0 || _checkingPackages)
                        _buildPackagesStep(fg, muted, card, border, accent),

                      // ── Step 1 : Permissions ──
                      if (_step == 1)
                        _buildPermissionsStep(fg, muted, card, border, accent),

                      // ── Step 2 : Pairing (auto) ──
                      if (_step == 2)
                        _buildPairingStep(fg, muted, card, border, accent),

                      // ── Step 3 : Connect ──
                      if (_step == 3)
                        _buildConnectStep(fg, muted, card, border, accent),

                      // ── Step 4 : Run ──
                      if (_step >= 4)
                        _buildRunStep(fg, muted, card, border, accent),

                      // Status
                      if (_status.isNotEmpty && !_busy) ...[
                        const SizedBox(height: 12),
                        _statusBar(_status, muted),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── UI Builders ──────────────────────────────────────────────────────────

  Widget _buildStepIndicator(Color fg, Color muted, Color accent, Color border) {
    final steps = ['Packages', 'Permissions', 'Appairage', 'Connexion', 'Run'];
    return Row(
      children: List.generate(steps.length, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Column(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? Colors.green : active ? accent : border,
              ),
              child: Center(child: done
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text('${i + 1}', style: TextStyle(fontSize: 12, color: done || active ? Colors.white : muted))),
            ),
            const SizedBox(height: 4),
            Text(steps[i], style: TextStyle(fontSize: 9, color: done ? Colors.green : active ? fg : muted),
                textAlign: TextAlign.center),
          ]),
        );
      }),
    );
  }

  Widget _buildPackagesStep(Color fg, Color muted, Color card, Color border, Color accent) {
    return _card(card, border, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('VÉRIFICATION DES PACKAGES', muted),
        _checkItem('adb (android-tools)', _adbInstalled, fg),
        _checkItem('git', _gitInstalled, fg),
        _checkItem('curl', _curlInstalled, fg),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    ));
  }

  Widget _buildPermissionsStep(Color fg, Color muted, Color card, Color border, Color accent) {
    return _card(card, border, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('PERMISSIONS REQUISES', muted),
        _permissionItem('Notifications', _notifEnabled, fg, () => _requestNotifPermission()),
        _permissionItem('Notification listener', _listenerEnabled, fg, () => _requestListenerPermission()),
        _permissionItem('Optimisation batterie', _batteryOptDisabled, fg, () => _requestBatteryOpt()),
        const SizedBox(height: 12),
        // Info box
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(
            'Le listener de notifications permet de détecter automatiquement '
            'le code d\'appairage sans que tu aies à le saisir manuellement. '
            'C\'est exactement comme Shizuku.',
            style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8)),
          ),
        ),
      ],
    ));
  }

  Widget _buildPairingStep(Color fg, Color muted, Color card, Color border, Color accent) {
    return Column(children: [
      _card(card, border, Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('APPAIRAGE AUTOMATIQUE', muted),
          if (_pairingDetected && _pairingData != null) ...[
            _checkItem('Code détecté : ${_pairingData!.code}', true, fg),
            _checkItem('Port : ${_pairingData!.port}', _pairingData!.port.isNotEmpty, fg),
          ] else ...[
            Text(
              '1. Va dans Options développeur → Débogage sans fil\n'
              '2. Appuie sur "Associer l\'appareil avec un code d\'association"\n'
              '3. Le code sera capturé automatiquement — ne le saisis pas',
              style: TextStyle(fontSize: 11, color: fg),
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
          ],
          const SizedBox(height: 10),
          // Guidance text (style Shizuku)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.amber[600]),
                  const SizedBox(width: 6),
                  Text('Guide de connexion', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber[700])),
                ]),
                const SizedBox(height: 6),
                Text(
                  '• Certaines parties (MIUI etc.) interdisent l\'accès réseau '
                  'quand l\'appli n\'est pas visible.\n'
                  '• Désactive l\'optimisation batterie pour Panda IDE.\n'
                  '• Appuie sur la partie GAUCHE de "Débogage sans fil" '
                  '(pas juste le commutateur à droite).\n'
                  '• La zone de texte à gauche est cliquable → ouvre la page dédiée.',
                  style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      )),
    ]);
  }

  Widget _buildConnectStep(Color fg, Color muted, Color card, Color border, Color accent) {
    return _card(card, border, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('CONNEXION', muted),
        if (_connected) ...[
          _checkItem('Connecté à 127.0.0.1:$_connectPort', true, fg),
          const SizedBox(height: 8),
          for (final d in _devices)
            _checkItem('${d.model.isNotEmpty ? d.model : d.serial} (${d.state})', d.online, fg),
        ] else ...[
          // Champ port (fallback si mDNS échoue)
          TextField(
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 13, color: fg),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Port débogage (si auto-detect échoue)',
              labelStyle: const TextStyle(fontSize: 11),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF007ACC))),
            ),
            onChanged: (v) => _connectPort = v.trim(),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            _button('Connecter', accent, _manualConnect),
            _button('Rafraîchir', fg, _refreshDevices),
            _button('mDNS auto', Colors.green[400]!, _autoConnect),
          ]),
        ],
      ],
    ));
  }

  Widget _buildRunStep(Color fg, Color muted, Color card, Color border, Color accent) {
    return _card(card, border, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('RUN — PREVIEW SUR CE TÉLÉPHONE', muted),
        if (_service.isRunning) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _button('r · Hot reload', Colors.amber[600]!, () => _service.sendRunKey('r')),
            _button('R · Restart', Colors.amber[700]!, () => _service.sendRunKey('R')),
            _button('■ Stop', Colors.red[400]!, _service.stopRun),
          ]),
          const SizedBox(height: 8),
          Text('La sortie s\'affiche dans l\'onglet Terminal de l\'IDE.',
              style: TextStyle(fontSize: 10, color: muted)),
        ] else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _button('▶ Run sur Android', Colors.green[500]!, _runFlutter),
            _button('▶ Preview Web', fg, () async {
              await _service.startRun(deviceId: 'web-server', onLine: (_) {});
              IdeTabOpener.instance.openTerminal();
            }),
          ]),
          const SizedBox(height: 8),
          Text('La sortie de flutter run s\'affiche dans l\'onglet Terminal.',
              style: TextStyle(fontSize: 10, color: muted)),
        ],
      ],
    ));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _checkItem(String label, bool ok, Color fg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 16,
            color: ok ? Colors.green[400] : Colors.red[400]),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: fg)),
      ]),
    );
  }

  Widget _permissionItem(String label, bool granted, Color fg, VoidCallback onRequest) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(granted ? Icons.check_circle : Icons.warning_amber, size: 16,
            color: granted ? Colors.green[400] : Colors.orange[400]),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: fg))),
        if (!granted)
          TextButton(
            onPressed: onRequest,
            child: Text('Autoriser', style: TextStyle(fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _errorBanner(String msg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 11, color: fg))),
        IconButton(
          icon: const Icon(Icons.close, size: 14),
          onPressed: () => setState(() => _error = null),
        ),
      ]),
    );
  }

  Widget _statusBar(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: color)),
    );
  }

  Widget _sectionTitle(String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: color)),
  );

  Widget _card(Color bg, Color border, Widget child) => Container(
    width: double.infinity,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
    padding: const EdgeInsets.all(12),
    child: child,
  );

  Widget _button(String label, Color accent, VoidCallback onTap) {
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
      ),
    );
  }
}
