/// ADB Setup Page — guides the user through wireless ADB / Shizuku setup
/// so that `flutter run` works on the same device without a computer.
///
/// Strategy (auto-detected, best available wins):
///   1. Shizuku   — if Shizuku app is installed + running → use binder IPC
///   2. Wireless ADB — Android 11+ wireless debugging → pair once, persist
///
/// After setup the terminal already has `adb` in PATH (platform-tools runtime)
/// so `flutter run` just works.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shizuku_service.dart';

library;




class AdbSetupPage extends StatefulWidget {
  const AdbSetupPage({super.key});

  @override
  State<AdbSetupPage> createState() => _AdbSetupPageState();
}

class _AdbSetupPageState extends State<AdbSetupPage> {
  _AdbMethod? _detectedMethod;
  bool _checking = true;
  bool _shizukuAvailable = false;
  bool _shizukuPermission = false;
  StreamSubscription? _shizukuSub;

  @override
  void initState() {
    super.initState();
    _detect();
    _shizukuSub = ShizukuService.instance.availabilityStream.listen((avail) {
      if (mounted) setState(() => _shizukuAvailable = avail);
    });
  }

  @override
  void dispose() {
    _shizukuSub?.cancel();
    super.dispose();
  }

  Future<void> _detect() async {
    final avail = await ShizukuService.instance.isAvailable();
    final perm  = avail
        ? await ShizukuService.instance.hasPermission()
        : false;
    if (!mounted) return;
    setState(() {
      _shizukuAvailable = avail;
      _shizukuPermission = perm;
      _detectedMethod = avail ? _AdbMethod.shizuku : _AdbMethod.wireless;
      _checking = false;
    });
  }

  Future<void> _requestShizukuPermission() async {
    final granted = await ShizukuService.instance.requestPermission();
    if (!mounted) return;
    setState(() => _shizukuPermission = granted);
    if (granted) {
      _showSnack('✓ Shizuku permission granted. flutter run is ready!');
    } else {
      _showSnack('Permission denied. Open Shizuku app and try again.',
          isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    final appBarBg = theme.appBarTheme.backgroundColor ?? cs.surface;
    final appBarFg = theme.appBarTheme.foregroundColor ?? cs.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        title: Text('ADB Setup for flutter run', style: TextStyle(color: appBarFg)),
        elevation: 0,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Status banner ──────────────────────────────────────────
                _StatusBanner(
                  shizukuAvailable: _shizukuAvailable,
                  shizukuPermission: _shizukuPermission,
                ),
                const SizedBox(height: 24),

                // ── Method tabs ────────────────────────────────────────────
                if (_shizukuAvailable)
                  _ShizukuSection(
                    hasPermission: _shizukuPermission,
                    onRequest: _requestShizukuPermission,
                  )
                else ...[
                  _InfoCard(
                    icon: Icons.info_outline,
                    color: cs.primary,
                    title: 'Shizuku not detected',
                    body:
                        'Shizuku gives Panda IDE ADB-level shell access without '
                        'a PC. Install it from Play Store for the best experience, '
                        'or use Wireless ADB pairing below (Android 11+).',
                    action: 'Install Shizuku',
                    onAction: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'https://shizuku.rikka.app'));
                      _showSnack('Shizuku URL copied to clipboard');
                    },
                  ),
                  const SizedBox(height: 16),
                  _WirelessAdbSection(),
                ],

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // ── flutter run cheat-sheet ────────────────────────────────
                _CheatSheet(),
              ],
            ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final bool shizukuAvailable;
  final bool shizukuPermission;
  const _StatusBanner(
      {required this.shizukuAvailable, required this.shizukuPermission});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final ready = shizukuAvailable && shizukuPermission;
    final color = ready ? Colors.green : cs.primary;
    final icon  = ready ? Icons.check_circle_rounded : Icons.info_outline;
    final title = ready
        ? 'Ready — flutter run will work on this device'
        : 'Setup required to use flutter run on this device';
    final sub = ready
        ? 'Shizuku is active and Panda IDE has permission.'
        : 'Follow the steps below to enable on-device deployment.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color, fontSize: 14)),
                const SizedBox(height: 4),
                Text(sub,
                    style: TextStyle(fontSize: 12,
                        color: color.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shizuku section ───────────────────────────────────────────────────────────

class _ShizukuSection extends StatelessWidget {
  final bool hasPermission;
  final VoidCallback onRequest;
  const _ShizukuSection(
      {required this.hasPermission, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              Text('Shizuku detected',
                  style: TextStyle(fontSize: 12,
                      color: Colors.green, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        if (hasPermission)
          _InfoCard(
            icon: Icons.shield_rounded,
            color: Colors.green,
            title: 'Permission granted',
            body: 'Panda IDE can now install APKs and run ADB commands '
                'directly on this device. Use flutter run in the terminal.',
          )
        else
          _InfoCard(
            icon: Icons.lock_open_rounded,
            color: cs.primary,
            title: 'Grant Shizuku permission',
            body: 'Tap the button below to allow Panda IDE to use '
                'Shizuku\'s privileged binder service.',
            action: 'Grant Permission',
            onAction: onRequest,
          ),
      ],
    );
  }
}

// ── Wireless ADB section ──────────────────────────────────────────────────────

class _WirelessAdbSection extends StatefulWidget {
  const _WirelessAdbSection();

  @override
  State<_WirelessAdbSection> createState() => _WirelessAdbSectionState();
}

class _WirelessAdbSectionState extends State<_WirelessAdbSection> {
  final _ipCtrl   = TextEditingController();
  final _portCtrl = TextEditingController(text: '37655');
  final _codeCtrl = TextEditingController();

  bool _pairing   = false;
  String? _pairResult;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _doPair() async {
    final ip   = _ipCtrl.text.trim();
    final port = _portCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (ip.isEmpty || port.isEmpty || code.isEmpty) return;

    setState(() { _pairing = true; _pairResult = null; });

    try {
      final result = await Process.run(
        'adb', ['pair', '$ip:$port', code],
        runInShell: false,
      );
      final out = result.stdout.toString() + result.stderr.toString();
      setState(() {
        _pairResult = out.trim();
        _pairing = false;
      });
    } catch (e) {
      setState(() {
        _pairResult = 'adb not found. Install platform-tools runtime first.';
        _pairing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wireless ADB (Android 11+)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),

        // Steps
        _Step(n: 1, text:
            'Go to Settings → Developer Options → Wireless debugging → tap "Pair device with pairing code".'),
        _Step(n: 2, text:
            'Note the IP address, pairing port, and 6-digit code shown on screen.'),
        _Step(n: 3, text: 'Fill in the fields below and tap Pair.'),
        _Step(n: 4, text:
            'After pairing, in the terminal run:  adb connect <ip>:<port>  then  flutter devices'),
        const SizedBox(height: 16),

        // Fields
        _LabeledField(label: 'IP address',   controller: _ipCtrl,
            hint: '192.168.x.x'),
        const SizedBox(height: 8),
        _LabeledField(label: 'Pairing port', controller: _portCtrl,
            hint: '37655', keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        _LabeledField(label: 'Pairing code', controller: _codeCtrl,
            hint: '123456', keyboardType: TextInputType.number),
        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _pairing ? null : _doPair,
            icon: _pairing
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: Colors.white))
                : const Icon(Icons.link_rounded, size: 18),
            label: Text(_pairing ? 'Pairing…' : 'Pair Device'),
          ),
        ),

        if (_pairResult != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_pairResult!,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ],
    );
  }
}

// ── Flutter run cheat-sheet ───────────────────────────────────────────────────

class _CheatSheet extends StatelessWidget {
  const _CheatSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    const cmds = [
      ('flutter devices',               'List connected devices'),
      ('flutter run',                    'Run app on connected device'),
      ('flutter run --release',          'Run in release mode'),
      ('flutter build apk --release',    'Build release APK'),
      ('flutter pub get',                'Fetch dependencies'),
      ('flutter clean',                  'Clean build cache'),
      ('flutter analyze',                'Run static analysis'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('flutter run — Quick Reference',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...cmds.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(c.$1,
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(c.$2,
                    style: TextStyle(fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.7))),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: color)),
          ]),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.5)),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(action!),
              style: TextButton.styleFrom(foregroundColor: color),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: cs.primary, shape: BoxShape.circle),
            child: Center(
              child: Text('$n',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: cs.onPrimary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5))),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6))),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _AdbMethod { shizuku, wireless }
