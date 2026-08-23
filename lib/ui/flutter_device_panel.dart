/// Panneau "Flutter Device" — piloter le déploiement Flutter sur le même
/// téléphone depuis l'environnement Alpine de Panda.
///
/// Workflow :
///   1. Activer "Débogage sans fil" (Options développeur) sur Android
///   2. Appairer une fois   : adb pair 127.0.0.1:<port appairage> <code>
///   3. Connecter à chaque session : adb connect 127.0.0.1:<port debug>
///   4. flutter run -d <serial>  → vraie app + hot reload sur le téléphone
///   Fallback preview : -d web-server ouvert dans le navigateur intégré.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/ui_bloc/ui_bloc.dart';
import '../services/flutter_device_service.dart';
import '../utils/themes.dart';

class FlutterDevicePanel extends StatefulWidget {
  const FlutterDevicePanel({super.key});

  @override
  State<FlutterDevicePanel> createState() => _FlutterDevicePanelState();
}

class _FlutterDevicePanelState extends State<FlutterDevicePanel> {
  final _service = FlutterDeviceService.instance;
  final _pairPort = TextEditingController();
  final _pairCode = TextEditingController();
  final _connectPort = TextEditingController();
  final _logController = ScrollController();

  bool _busy = false;
  final List<String> _logLines = [];

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
    _pairPort.dispose();
    _pairCode.dispose();
    _connectPort.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _run('Préparation adb…', () => _service.ensureAdb());
    await _refreshDevices();
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() {
      _logLines.add(line);
      if (_logLines.length > 400) _logLines.removeRange(0, _logLines.length - 400);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logController.hasClients) {
        _logController.jumpTo(_logController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _run(String label, Future<bool> Function() action) async {
    setState(() => _busy = true);
    _log('\$ $label');
    final ok = await action();
    _log(ok ? '✓ terminé' : '✗ échec');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refreshDevices() =>
      _run('adb devices', () => _service.refreshDevices().then((_) => true));

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

        return Container(
          color: bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration:
                    BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                child: Row(children: [
                  Icon(Icons.smartphone, size: 16, color: const Color(0xFF007ACC)),
                  const SizedBox(width: 8),
                  Text('Flutter Device',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                  const Spacer(),
                  if (_busy)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Devices détectés ──
                      _sectionTitle('APPAREILS', muted),
                      _card(card, border, child: Column(
                        children: [
                          if (_service.devices.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text('Aucun appareil — connecte-toi ci-dessous.',
                                  style: TextStyle(fontSize: 12, color: muted)),
                            )
                          else
                            for (final d in _service.devices)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  d.online ? Icons.check_circle : Icons.error_outline,
                                  size: 18,
                                  color: d.online ? Colors.green[400] : Colors.orange[400],
                                ),
                                title: Text(d.model.isEmpty ? d.serial : d.model,
                                    style: TextStyle(fontSize: 13, color: fg)),
                                subtitle: Text('${d.serial} • ${d.state}',
                                    style: TextStyle(fontSize: 11, color: muted)),
                              ),
                        ],
                      )),
                      const SizedBox(height: 12),

                      // ── Appairage (une fois) ──
                      _sectionTitle('APPAIRAGE — DÉBOGAGE SANS FIL (1re FOIS)', muted),
                      _card(card, border, child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(children: [
                          _row('Port appairage', 'ex: 41573', _pairPort, isDark, border, fg),
                          const SizedBox(height: 8),
                          _row('Code', '6 chiffres', _pairCode, isDark, border, fg),
                          const SizedBox(height: 10),
                          _button('Appairer 127.0.0.1', fg, () async {
                            await _service.pair(
                                _pairPort.text.trim(), _pairCode.text.trim(),
                                onLine: _log);
                            await _refreshDevices();
                          }),
                        ]),
                      )),
                      const SizedBox(height: 12),

                      // ── Connexion (à chaque session) ──
                      _sectionTitle('CONNEXION (À CHAQUE SESSION)', muted),
                      _card(card, border, child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(children: [
                          _row('Port débogage', 'ex: 39211', _connectPort, isDark, border, fg),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _button('Connecter', fg, () async {
                              await _service.connect(_connectPort.text.trim(),
                                  onLine: _log);
                            }),
                            _button('Rafraîchir', fg, _refreshDevices),
                            _button('flutter doctor', fg, () => _run(
                                'flutter doctor',
                                () => _service.flutterDoctor().then((out) {
                                      for (final l in out.split('\n')) _log(l);
                                      return true;
                                    }))),
                          ]),
                        ]),
                      )),
                      const SizedBox(height: 12),

                      // ── Run ──
                      _sectionTitle('RUN — PREVIEW SUR CE TÉLÉPHONE', muted),
                      _card(card, border, child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          if (!_service.isRunning) ...[
                            _button('▶ Run sur Android', Colors.green[500]!, () async {
                              String? dev;
                              for (final d in _service.devices) {
                                if (d.online) {
                                  dev = d.serial;
                                  break;
                                }
                              }
                              if (dev == null) {
                                _log('✗ aucun appareil connecté');
                                return;
                              }
                              await _service.startRun(deviceId: dev, onLine: _log);
                            }),
                            _button('▶ Preview Web (navigateur)', fg, () async {
                              await _service.startRun(
                                  deviceId: 'web-server', onLine: _log);
                              _log('→ http://127.0.0.1:8090 (navigateur intégré)');
                            }),
                          ] else ...[
                            _button('r · Hot reload', Colors.amber[600]!,
                                () => _service.sendRunKey('r')),
                            _button('R · Restart', Colors.amber[700]!,
                                () => _service.sendRunKey('R')),
                            _button('■ Stop', Colors.red[400]!,
                                _service.stopRun),
                          ],
                        ]),
                      )),

                      const SizedBox(height: 12),
                      _sectionTitle('SORTIE', muted),
                    ],
                  ),
                ),
              ),

              // ── Log stream (fixé en bas) ──
              Expanded(
                flex: 0,
                child: Container(
                  height: 170,
                  color: isDark ? const Color(0xff111111) : const Color(0xfff0f0f0),
                  child: ListView.builder(
                    controller: _logController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logLines.length,
                    itemBuilder: (_, i) => Text(_logLines[i],
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: muted)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: color)),
      );

  Widget _card(Color bg, Color border, {required Widget child}) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: child,
      );

  Widget _row(String label, String hint, TextEditingController controller,
      bool isDark, Color border, Color fg) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: 13, color: fg),
      decoration: InputDecoration(
        isDense: true,
        labelText: '$label ($hint)',
        labelStyle: TextStyle(fontSize: 11),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border)),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF007ACC))),
      ),
    );
  }

  Widget _button(String label, Color accent, VoidCallback onTap) {
    return InkWell(
      onTap: _busy && !label.startsWith('■') ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
      ),
    );
  }
}
