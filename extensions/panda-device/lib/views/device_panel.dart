/// PandaDevicePanel — vue sidebar de l'extension Panda Device.
///
/// Rendu par l'hôte de vues de l'IDE quand la contribution
/// `views.sidebar` du manifest est activée.
library panda_device.views.device_panel;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../extension.dart';

class PandaDevicePanel extends StatefulWidget {
  final PandaDeviceExtension extension;

  const PandaDevicePanel({super.key, required this.extension});

  @override
  State<PandaDevicePanel> createState() => _PandaDevicePanelState();
}

class _PandaDevicePanelState extends State<PandaDevicePanel> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceState>(
      stream: widget.extension.onState,
      initialData: const DeviceState(message: 'Prêt'),
      builder: (context, snap) {
        final state = snap.data!;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.smartphone,
                        color: Colors.teal, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Panda Device',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text('v1.1.0 — Dev sur ton téléphone',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── État actuel ──
                if (state.message != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _statusColor(state).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _statusColor(state).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.circle, size: 8, color: _statusColor(state)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(state.message!,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),

                const SizedBox(height: 20),

                // ══ GUIDE D'APPAIRAGE ══
                _SectionHeader(title: 'APPairage WiFi Debugging'),
                const SizedBox(height: 8),

                // ── Étape 1 : Ouvrir les options développeur ──
                _StepCard(
                  n: 1,
                  title: 'Options développeur',
                  subtitle: 'Active le Débogage sans fil',
                  icon: Icons.settings,
                  onTap: () => widget.extension.openDeveloperSettings(),
                  child: const Text(
                    'Menu → À propos du téléphone → Numéro de build (7×)\n'
                    'Puis: Système → Options développeur',
                    style: TextStyle(fontSize: 11, height: 1.4),
                  ),
                ),

                // ── Étape 2 : Activer débogage sans fil ──
                _StepCard(
                  n: 2,
                  title: 'Débogage sans fil',
                  subtitle: 'Active le commutateur',
                  icon: Icons.wifi,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• Active "Débogage sans fil"\n'
                        '• Appuie sur "Associer l\'appareil avec un code"\n'
                        '• GARDE la popup ouverte !',
                        style: TextStyle(fontSize: 11, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      // ── Afficher les infos ──
                      if (_getWifiIp(state) != null)
                        _InfoRow(
                          label: 'IP WiFi',
                          value: _getWifiIp(state)!,
                          onCopy: () => _copyToClipboard(context, _getWifiIp(state)!),
                        ),
                      if (_getPairPort(state) != null)
                        _InfoRow(
                          label: 'Port appairage',
                          value: _getPairPort(state)!,
                          onCopy: () => _copyToClipboard(context, _getPairPort(state)!),
                        ),
                      if (_getDebugPort(state) != null)
                        _InfoRow(
                          label: 'Port débogage',
                          value: _getDebugPort(state)!,
                          onCopy: () => _copyToClipboard(context, _getDebugPort(state)!),
                        ),
                    ],
                  ),
                ),

                // ── Étape 3 : Saisir le code d'appairage ──
                _StepCard(
                  n: 3,
                  title: 'Code d\'appairage',
                  subtitle: 'Saisis le code à 6 chiffres',
                  icon: Icons.vpn_key,
                  accent: true,
                  onTap: () => widget.extension.enterPairingCode(),
                  child: const Text(
                    'Le code s\'affiche dans la popup "Associer"\n'
                    'sur ton téléphone. Saisis-le ici.',
                    style: TextStyle(fontSize: 11, height: 1.4),
                  ),
                ),

                // ── Étape 4 : Connecter ──
                _StepCard(
                  n: 4,
                  title: 'Connecter adb',
                  subtitle: 'Port de débogage principal',
                  icon: Icons.link,
                  onTap: () => widget.extension.enterDebugPort(),
                  child: const Text(
                    'Le port de débogage s\'affiche sur l\'écran\n'
                    '"Débogage sans fil" (pas la popup d\'appairage).',
                    style: TextStyle(fontSize: 11, height: 1.4),
                  ),
                ),

                const SizedBox(height: 20),

                // ══ FLUTTER ══
                _SectionHeader(title: 'Flutter SDK'),
                const SizedBox(height: 8),

                _StepCard(
                  n: 5,
                  title: 'Flutter SDK',
                  subtitle: state.flutterVersion ?? 'Vérification…',
                  icon: Icons.code,
                  trailing: _ProgressOrCheck(progress: state.progress),
                  onTap: () => widget.extension.ensureFlutter(),
                ),

                const SizedBox(height: 20),

                // ══ ACTIONS ══
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run sur l\'appareil'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => widget.extension.runOnDevice(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-vérifier le statut'),
                  onPressed: () => widget.extension.refreshStatus(),
                ),

                // ── Console ──
                if (state.logLine != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Text(state.logLine!,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(DeviceState state) {
    if (state.message?.contains('✓') == true) return Colors.green;
    if (state.message?.contains('✗') == true) return Colors.red;
    if (state.progress != null && state.progress! < 100) return Colors.orange;
    return Colors.teal;
  }

  String? _getWifiIp(DeviceState state) {
    // Extract from log lines
    for (final line in state.allLogs ?? []) {
      if (line.contains('IP WiFi:')) {
        return line.split('IP WiFi:').last.trim();
      }
    }
    return null;
  }

  String? _getPairPort(DeviceState state) {
    for (final line in state.allLogs ?? []) {
      if (line.contains('Port appairage:')) {
        return line.split('Port appairage:').last.trim();
      }
    }
    return null;
  }

  String? _getDebugPort(DeviceState state) {
    for (final line in state.allLogs ?? []) {
      if (line.contains('Port débogage:')) {
        return line.split('Port débogage:').last.trim();
      }
    }
    return null;
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copié: $text'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

// ══ Widgets ════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int n;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? child;
  final Widget? trailing;
  final bool accent;

  const _StepCard({
    required this.n,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.child,
    this.trailing,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: accent
              ? Colors.teal.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor.withValues(alpha: 0.3),
          width: accent ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent
                      ? Colors.teal.withValues(alpha: 0.2)
                      : Colors.teal.withValues(alpha: 0.1),
                  child: Icon(icon,
                      size: 14,
                      color: accent ? Colors.teal : Colors.teal.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  const Icon(Icons.chevron_right, size: 18),
              ]),
              if (child != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                    child: child!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _InfoRow({required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Text('$label: ',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.6))),
        Text(value,
            style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500)),
        if (onCopy != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onCopy,
            child: Icon(Icons.copy, size: 12, color: Colors.teal.withValues(alpha: 0.6)),
          ),
        ],
      ]),
    );
  }
}

class _ProgressOrCheck extends StatelessWidget {
  final int? progress;
  const _ProgressOrCheck({this.progress});

  @override
  Widget build(BuildContext context) {
    if (progress == null) return const SizedBox.shrink();
    if (progress! >= 100) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 18);
    }
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        value: progress! > 0 ? progress! / 100 : null,
        color: Colors.teal,
      ),
    );
  }
}
