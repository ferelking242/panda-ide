import 'package:flutter/material.dart';
import '../extension.dart';

/// Dashboard panel for Panda AI extension — sidebar view.
class DashboardPanel extends StatelessWidget {
  final PandaAiExtension extension;

  const DashboardPanel({super.key, required this.extension});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AiState>(
      stream: extension.onState,
      initialData: const AiState(message: 'Prêt'),
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
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.smart_toy_rounded,
                        color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Panda AI',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text('Gateway + Dashboard',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Status ──
                _StatusTile(
                  icon: Icons.circle,
                  iconColor: _statusColor(state.status),
                  title: state.message ?? 'En attente…',
                ),

                const SizedBox(height: 16),

                // ── Actions ──
                _ActionTile(
                  icon: Icons.download_rounded,
                  title: 'Installer le Gateway',
                  subtitle: 'Télécharge panda-ai depuis GitHub',
                  onTap: () => extension.installGateway(),
                ),
                _ActionTile(
                  icon: Icons.play_arrow_rounded,
                  title: 'Démarrer le serveur',
                  subtitle: 'Lance uvicorn sur le port 8000',
                  onTap: () => extension.startServer(),
                ),
                _ActionTile(
                  icon: Icons.stop_rounded,
                  title: 'Arrêter le serveur',
                  subtitle: 'Stoppe le processus Python',
                  onTap: () => extension.stopServer(),
                ),
                _ActionTile(
                  icon: Icons.open_in_browser_rounded,
                  title: 'Ouvrir le Dashboard',
                  subtitle: 'Accède au dashboard Next.js',
                  onTap: () => extension.openDashboard(),
                ),
                _ActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Statut',
                  subtitle: 'Vérifie Python, pip, et le gateway',
                  onTap: () => extension.showStatus(),
                ),

                const SizedBox(height: 16),

                // ── Logs ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    state.logLine ?? 'Aucun log',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(AiStatus? status) {
    switch (status) {
      case AiStatus.running:
        return Colors.green;
      case AiStatus.error:
        return Colors.red;
      case AiStatus.installing:
      case AiStatus.starting:
        return Colors.orange;
      case AiStatus.ready:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  const _StatusTile({
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 10, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        dense: true,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
