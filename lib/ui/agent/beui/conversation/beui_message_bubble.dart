import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIMessageBubble — surface de conversation avec ton visuel adapté.
///
///   • Utilisateur : aligné à droite, fond accent doux
///   • Assistant   : aligné à gauche, fond surface profonde
///   • Système     : centré, fond léger, bordure pointillée
///   • Contenu long : expandable avec "Voir plus"
///   • Liens cliquables
/// ═══════════════════════════════════════════════════════════════════════════

enum BeUIBubbleTone { user, assistant, system }

class BeUIMessageBubble extends StatefulWidget {
  final BeUIBubbleTone tone;
  final String text;
  final bool isStreaming;
  final bool animateIn;
  final bool expandable;
  final int maxLines;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final ValueChanged<String>? onLinkTap;
  final Widget? child;

  const BeUIMessageBubble({
    super.key,
    required this.tone,
    required this.text,
    this.isStreaming = false,
    this.animateIn = true,
    this.expandable = true,
    this.maxLines = 12,
    this.onRetry,
    this.onCopy,
    this.onLinkTap,
    this.child,
  });

  @override
  State<BeUIMessageBubble> createState() => _BeUIMessageBubbleState();
}

class _BeUIMessageBubbleState extends State<BeUIMessageBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = widget.tone == BeUIBubbleTone.user;
    final isSystem = widget.tone == BeUIBubbleTone.system;

    final bgColor = _bgColor(isDark);
    final borderColor = _borderColor(isDark);

    final needsTruncation =
        widget.expandable && !_expanded && widget.text.length > 300;

    Widget content = Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: isSystem
            ? Border.all(color: borderColor, width: 0.8)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Text ──────────────────────────────────────────
          if (widget.text.isNotEmpty)
            _buildText(context, needsTruncation),

          // ── Child (rich content like markdown, code, etc.) ─
          if (widget.child != null) widget.child!,

          // ── Streaming caret ───────────────────────────────
          if (widget.isStreaming)
            _BlinkingCaret(color: BeUIColors.accentOf(isDark)),

          // ── Expand toggle ─────────────────────────────────
          if (needsTruncation)
            GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Voir plus',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BeUIColors.accentOf(isDark),
                  ),
                ),
              ),
            ),

          // ── Action row ────────────────────────────────────
          if (!widget.isStreaming && (widget.onRetry != null || widget.onCopy != null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onCopy != null)
                    _ActionChip(
                      icon: Icons.copy,
                      label: 'Copier',
                      onTap: widget.onCopy!,
                      isDark: isDark,
                    ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(width: 6),
                    _ActionChip(
                      icon: Icons.refresh,
                      label: 'Réessayer',
                      onTap: widget.onRetry!,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    if (widget.animateIn) {
      content = BeUIPopIn(child: content);
    }

    return content;
  }

  Widget _buildText(BuildContext context, bool needsTruncation) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final displayText = needsTruncation
        ? widget.text.substring(0, 300)
        : widget.text;

    return SelectableText.rich(
      TextSpan(text: displayText, style: TextStyle(fontSize: 13.5, color: fg, height: 1.5)),
      onTap: () {},
    );
  }

  Color _bgColor(bool isDark) {
    return switch (widget.tone) {
      BeUIBubbleTone.user => BeUIColors.accentOf(isDark).withValues(alpha: 0.1),
      BeUIBubbleTone.assistant => BeUIColors.deepSurfaceOf(isDark),
      BeUIBubbleTone.system => BeUIColors.surfaceOf(isDark).withValues(alpha: 0.5),
    };
  }

  Color _borderColor(bool isDark) {
    return switch (widget.tone) {
      BeUIBubbleTone.system => BeUIColors.borderOf(isDark),
      _ => Colors.transparent,
    };
  }
}

// ── Blinking caret ────────────────────────────────────────────────────────

class _BlinkingCaret extends StatefulWidget {
  final Color color;
  const _BlinkingCaret({required this.color});

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
      child: Text(
        '▌',
        style: TextStyle(fontSize: 13, color: widget.color.withValues(alpha: 0.8)),
      ),
    );
  }
}

// ── Action chip (copy, retry) ─────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BeUIColors.deepSurfaceOf(isDark),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: fg)),
          ],
        ),
      ),
    );
  }
}
