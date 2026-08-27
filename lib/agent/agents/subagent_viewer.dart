import 'package:flutter/material.dart';
import 'package:broken_icons/broken_icons.dart';

import '../events/event_ui_bridge.dart';

/// Displays active subagents in the agent UI.
///
/// Shows a compact card for each running/completed/failed subagent.
class SubagentViewer extends StatelessWidget {
  final AgentUiState uiState;
  final bool isDark;

  const SubagentViewer({
    super.key,
    required this.uiState,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: uiState,
      builder: (context, _) {
        final subs = uiState.activeSubagents;
        if (subs.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final sub in subs) _SubagentCard(sub: sub, isDark: isDark),
            ],
          ),
        );
      },
    );
  }
}

class _SubagentCard extends StatelessWidget {
  final SubagentInfo sub;
  final bool isDark;

  const _SubagentCard({required this.sub, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    final bg = isDark ? const Color(0xff1e1e2e) : const Color(0xfff5f5f5);

    final (icon, color) = switch (sub.status) {
      'running' => (Icons.autorenew, Colors.blue),
      'completed' => (Icons.check_circle, Colors.green),
      'failed' => (Icons.error_outline, Colors.red),
      _ => (Icons.help_outline, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${sub.type} — ${sub.status}',
              style: TextStyle(fontSize: 11, color: fg),
            ),
          ),
          if (sub.status == 'running')
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.blue,
              ),
            ),
        ],
      ),
    );
  }
}
