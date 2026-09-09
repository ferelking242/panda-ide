import 'package:flutter/material.dart';

import '../events/event_ui_bridge.dart';

/// Displays verification status in the agent UI.
///
/// Shows a compact bar with verification progress and results.
class VerificationViewer extends StatelessWidget {
  final AgentUiState uiState;
  final bool isDark;

  const VerificationViewer({
    super.key,
    required this.uiState,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: uiState,
      builder: (context, _) {
        final v = uiState.verification;
        if (v == null) return const SizedBox.shrink();

        final fg = isDark ? Colors.grey[300]! : Colors.grey[700]!;
        final bg = isDark ? const Color(0xff1a1a2e) : const Color(0xfff0f0f5);

        final (icon, color, label) = switch (v.status) {
          'running' => (Icons.sync, Colors.blue, 'Vérification…'),
          'passed' => (Icons.check_circle, Colors.green, 'Vérification OK'),
          'failed' => (Icons.error, Colors.red, '${v.errors.length} erreur(s)'),
          _ => (Icons.help_outline, Colors.grey, 'Vérification'),
        };

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(fontSize: 11, color: fg)),
                  if (v.status == 'running') ...[
                    const Spacer(),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
              if (v.files.isNotEmpty && v.status == 'running') ...[
                const SizedBox(height: 4),
                Text(
                  '${v.files.length} fichier(s) vérifié(s)',
                  style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6)),
                ),
              ],
              if (v.errors.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final err in v.errors.take(3))
                  Text(
                    '• $err',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
