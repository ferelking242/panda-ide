import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIMessage — ligne de message dans une conversation agent.
///
///   • Avatar avec apparition animée (scale+fade)
///   • Metadata : nom + timestamp
///   • Live marker : point qui pulse quand en streaming
///   • Grouped : les messages consécutifs du même auteur réduisent l'espacement
/// ═══════════════════════════════════════════════════════════════════════════

enum BeUIMessageRole { user, assistant, system }

class BeUIMessage extends StatelessWidget {
  final String? id;
  final BeUIMessageRole role;
  final String? authorName;
  final String? avatarText;
  final Widget? child;
  final bool isStreaming;
  final bool isGrouped;
  final bool animateIn;
  final DateTime? timestamp;
  final Widget? trailing;

  const BeUIMessage({
    super.key,
    this.id,
    required this.role,
    this.authorName,
    this.avatarText,
    this.child,
    this.isStreaming = false,
    this.isGrouped = false,
    this.animateIn = true,
    this.timestamp,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isAssistant = role == BeUIMessageRole.assistant;
    final isUser = role == BeUIMessageRole.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted = isDark ? Colors.grey[600]! : Colors.grey[400]!;

    Widget content = Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: isUser ? 10 : 48,
        top: isGrouped ? 2 : 10,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ── Metadata ──────────────────────────────────────
          if (!isGrouped && authorName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    authorName!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      _formatTime(timestamp!),
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                  if (isStreaming) ...[
                    const SizedBox(width: 6),
                    _LiveDot(color: BeUIColors.accentOf(isDark)),
                  ],
                ],
              ),
            ),

          // ── Content ───────────────────────────────────────
          if (child != null) child!,

          // ── Trailing actions ──────────────────────────────
          if (trailing != null) trailing!,
        ],
      ),
    );

    // Avatar
    final avatar = _buildAvatar(isDark, isUser, isAssistant, fg, muted);

    if (isUser) {
      // User messages: right-aligned, no avatar, smaller padding
      content = Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: content,
        ),
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          Expanded(child: content),
        ],
      );
    }

    if (animateIn) {
      content = BeUIPopIn(child: content);
    }

    return content;
  }

  Widget _buildAvatar(bool isDark, bool isUser, bool isAssistant, Color fg, Color muted) {
    // User messages: no avatar (clean look)
    if (isUser) return const SizedBox.shrink();
    final accent = BeUIColors.accentOf(isDark);
    final label = avatarText ?? 'A';
    final bgColor = accent.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(
            label.isNotEmpty ? label[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Live streaming dot ────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 3)],
        ),
      ),
    );
  }
}
