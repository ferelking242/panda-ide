import 'package:flutter/material.dart';
import '../extension.dart';

/// Dashboard panel for Panda AI extension — sidebar view.
/// Shows server status, actions, and log output.
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
                        Text('v1.1.0 — Gateway + Dashboard',
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
                  subtitle: 'Clone panda-ai + pip install',
                  onTap: () => extension.installGateway(),
                ),
                _ActionTile(
                  icon: Icons.play_arrow_rounded,
                  title: 'Démarrer le serveur',
                  subtitle: 'Lance uvicorn sur :8000',
                  onTap: () => extension.startServer(),
                ),
                _ActionTile(
                  icon: Icons.stop_rounded,
                  title: 'Arrêter le serveur',
                  subtitle: 'Stoppe le processus',
                  onTap: () => extension.stopServer(),
                ),
                _ActionTile(
                  icon: Icons.open_in_browser_rounded,
                  title: 'Ouvrir le Dashboard',
                  subtitle: 'Dashboard Next.js sur :8000',
                  onTap: () => extension.openDashboard(),
                ),
                _ActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Statut',
                  subtitle: 'Vérifie Python, pip, gateway',
                  onTap: () => extension.showStatus(),
                ),

                const SizedBox(height: 16),

                // ── Logs ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
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

                const SizedBox(height: 16),

                // ── Info ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comment ça marche',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '1. Installe Python + git dans le terminal\n'
                        '2. Cliquez "Installer" pour cloner panda-ai\n'
                        '3. Configurez .env avec votre clé API\n'
                        '4. Cliquez "Démarrer" pour lancer le serveur\n'
                        '5. Le dashboard est accessible sur :8000',
                        style: TextStyle(fontSize: 11, height: 1.4),
                      ),
                    ],
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
