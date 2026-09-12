import 'package:flutter/material.dart';

import '../agent_runner.dart';

/// Compact live status for the current agent turn.
///
/// This is deliberately separate from the message thread: the thread stores
/// user and assistant content, while this widget only represents ephemeral
/// execution state.
class PandaAgentActivity extends StatelessWidget {
  const PandaAgentActivity({
    super.key,
    required this.phase,
    required this.label,
  });

  final AgentPhase phase;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isError = phase == AgentPhase.error;
    final indicatorColor = isError ? colors.error : colors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: indicatorColor.withValues(alpha: isError ? 0.35 : 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: indicatorColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: indicatorColor.withValues(alpha: 0.12),
              ),
            ),
            child: !isError
                ? SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: indicatorColor,
                    ),
                  )
                : Icon(
                    Icons.error_outline,
                    size: 15,
                    color: indicatorColor,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                label,
                key: ValueKey(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}