/// PandaDevicePanel — vue sidebar de l'extension Panda Device.
///
/// Rendu par l'hôte de vues de l'IDE quand la contribution
/// `views.sidebar` du manifest est activée.
library panda_device.views.device_panel;

import 'package:flutter/material.dart';

import '../extension.dart';

class PandaDevicePanel extends StatelessWidget {
  final PandaDeviceExtension extension;

  const PandaDevicePanel({super.key, required this.extension});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceState>(
      stream: extension.onState,
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
                // ── En-tête ──
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.smartphone, color: Colors.teal, size: 24),
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
                        Text('Dev sur ton propre téléphone',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Étapes façon Shizuku ──
                _StepTile(
                  n: 1,
                  title: 'Options développeur',
                  subtitle: 'Active le Débogage sans fil',
                  onTap: () => extension.pairFlow(),
                ),
                _StepTile(
                  n: 2,
                  title: 'Appairer',
                  subtitle: 'Port de la popup + code à 6 chiffres',
                  onTap: () => extension.pairFlow(),
                ),
                _StepTile(
                  n: 3,
                  title: 'Flutter SDK',
                  subtitle: state.message ?? 'Vérification…',
                  trailing: _ProgressOrCheck(progress: state.progress),
                ),

                const SizedBox(height: 20),

                // ── Actions principales ──
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run sur l\'appareil'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => extension.runOnDevice(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Assistant complet'),
                  onPressed: () => extension.runWizard(),
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
                    constraints: const BoxConstraints(maxHeight: 160),
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
}

// ═════════════════════════════════════════════════════════════

class _StepTile extends StatelessWidget {
  final int n;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _StepTile({
    required this.n,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: Colors.teal.withValues(alpha: 0.15),
          child: Text('$n',
              style: const TextStyle(fontSize: 12, color: Colors.teal)),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.7))),
        trailing: trailing ?? const Icon(Icons.chevron_right, size: 18),
      ),
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
          color: Colors.teal),
    );
  }
}
