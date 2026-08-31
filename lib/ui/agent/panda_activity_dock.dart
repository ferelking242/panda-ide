import 'package:flutter/material.dart';
import 'flow_ui/widgets/flow_thinking_indicator.dart';
import 'flow_ui/widgets/flow_shimmer_text.dart';
import 'agent_models.dart';

/// Activity dock that displays the agent's current activity timeline.
///
/// Layout:
/// ```
/// ┌──────────────────────────────────────┐
/// │  🐼 thinking · Analyse de la demande │  ← active (top, animated)
/// ├──────────────────────────────────────┤
/// │  🐼 Cloning dépôt           ✓ done  │  ← completed (scrollable history)
/// │  🐼 execute cmd · git clone  ✓ done  │
/// │  🐼 working · Installation   ✓ done  │
/// └──────────────────────────────────────┘
/// [FlowComposer]                              ← input at bottom
/// ```
///
/// The active activity stays fixed above the composer.
/// Completed activities stack above it.
/// New activities slide in from the bottom; old ones slide up.
class PandaActivityDock extends StatelessWidget {
  final AgentActivityController controller;
  final bool isDark;

  const PandaActivityDock({
    super.key,
    required this.controller,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final active = controller.activeActivity;
    final history = controller.history;

    // Don't show anything if there's nothing to show
    if (active == null && history.isEmpty) {
      return const SizedBox.shrink();
    }

    final bg = isDark ? const Color(0xff1a1a1e) : const Color(0xfff8f8fa);
    final fg = isDark ? const Color(0xffe0e0e0) : const Color(0xff222222);
    final muted = isDark ? const Color(0xff8a8a8a) : const Color(0xff777777);
    final borderColor = isDark
        ? const Color(0xff2a2a2e)
        : const Color(0xffe8e8ec);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Completed activities (history) — compact list
          if (history.isNotEmpty)
            ...history.map((event) => _CompletedActivityRow(
                  event: event,
                  isDark: isDark,
                  fg: fg,
                  muted: muted,
                )),

          // Active activity — animated, fixed at bottom
          if (active != null)
            _ActiveActivityRow(
              event: active,
              isDark: isDark,
              fg: fg,
              muted: muted,
            ),
        ],
      ),
    );
  }
}

// ── Active Activity Row ──────────────────────────────────────────────────────

class _ActiveActivityRow extends StatelessWidget {
  final AgentActivityEvent event;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _ActiveActivityRow({
    required this.event,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark
        ? const Color(0xff6a8aff)
        : const Color(0xff3366cc);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // 🐼 emoji
          const Text('🐼', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),

          // Thinking indicator or shimmer text based on type
          if (event.type == AgentActivityType.thinking)
            FlowThinkingIndicator(
              active: true,
              color: accentColor,
              size: 14,
            )
          else if (event.type == AgentActivityType.tool ||
              event.type == AgentActivityType.status)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: accentColor,
              ),
            )
          else
            const SizedBox(width: 14),

          const SizedBox(width: 8),

          // Label with shimmer for running states
          Expanded(
            child: event.status == AgentActivityStatus.running
                ? FlowShimmerText(
                    text: event.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  )
                : Text(
                    event.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),

          // Status indicator
          if (event.status == AgentActivityStatus.running)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: accentColor,
              ),
            )
          else if (event.status == AgentActivityStatus.error)
            Icon(Icons.error_outline, size: 14, color: Colors.redAccent)
          else if (event.status == AgentActivityStatus.completed)
            Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
        ],
      ),
    );
  }
}

// ── Completed Activity Row ───────────────────────────────────────────────────

class _CompletedActivityRow extends StatelessWidget {
  final AgentActivityEvent event;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _CompletedActivityRow({
    required this.event,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark
        ? const Color(0xff6a8aff)
        : const Color(0xff3366cc);

    IconData statusIcon;
    Color statusColor;

    switch (event.status) {
      case AgentActivityStatus.completed:
        statusIcon = Icons.check_circle_outline;
        statusColor = Colors.green;
        break;
      case AgentActivityStatus.error:
        statusIcon = Icons.error_outline;
        statusColor = Colors.redAccent;
        break;
      case AgentActivityStatus.running:
        statusIcon = Icons.hourglass_top;
        statusColor = accentColor;
        break;
      case AgentActivityStatus.pending:
        statusIcon = Icons.radio_button_unchecked;
        statusColor = muted;
        break;
    }

    return InkWell(
      onTap: event.toolResult != null
          ? () => controller.toggleExpand(event.id)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            const Text('🐼', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 8),

            // Tool icon
            if (event.toolName != null)
              agentToolIconWidget(event.toolName!, 12, muted)
            else
              Icon(
                event.type == AgentActivityType.thinking
                    ? Icons.psychology_outlined
                    : Icons.play_circle_outline,
                size: 12,
                color: muted,
              ),
            const SizedBox(width: 6),

            // Label
            Expanded(
              child: Text(
                event.label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Duration
            if (event.duration != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  _formatDuration(event.duration!),
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),

            // Status icon
            Icon(statusIcon, size: 12, color: statusColor),

            // Expand indicator
            if (event.toolResult != null)
              Icon(
                event.isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 14,
                color: muted,
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m${d.inSeconds % 60}s';
  }
}
