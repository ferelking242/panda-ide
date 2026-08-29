import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIMessageBubble — surface de conversation avec ton visuel adapté.
///
///   • Utilisateur : aligné à droite, fond accent doux
///   • Assistant   : aligné à gauche, fond surface profonde
///   • Système     : centré, fond léger, bordure pointillée
///   • Contenu long : expandable avec "Voir plus"
///   • Liens cliquables
///   • Swipe gauche → menu actions (Copier, Réessayer, Sélectionner)
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
  final bool enableSwipeActions;

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
    this.enableSwipeActions = true,
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
        borderRadius: BorderRadius.circular(14),
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

    // Wrap with swipe gesture for actions (only assistant messages)
    if (widget.enableSwipeActions && !isUser && !widget.isStreaming) {
      content = _SwipeActionWrapper(
        onCopy: widget.onCopy,
        onRetry: widget.onRetry,
        child: content,
      );
    }

    return content;
  }

  Widget _buildText(BuildContext context, bool needsTruncation) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final displayText = needsTruncation
        ? widget.text.substring(0, 300)
        : widget.text;

    return SelectableText.rich(
      TextSpan(
        text: displayText,
        style: TextStyle(
          fontFamily: 'Google Sans',
          fontSize: 13.5,
          color: fg,
          height: 1.55,
          letterSpacing: 0.1,
        ),
      ),
      onTap: () {},
    );
  }

  Color _bgColor(bool isDark) {
    return switch (widget.tone) {
      BeUIBubbleTone.user => isDark ? const Color(0xFF2A2B30) : const Color(0xFFE8EAF0),
      BeUIBubbleTone.assistant => Colors.transparent,
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

// ── Swipe action wrapper ──────────────────────────────────────────────────
class _SwipeActionWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;

  const _SwipeActionWrapper({
    required this.child,
    this.onCopy,
    this.onRetry,
  });

  @override
  State<_SwipeActionWrapper> createState() => _SwipeActionWrapperState();
}

class _SwipeActionWrapperState extends State<_SwipeActionWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  static const _actionPanelWidth = 160.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _openActions() {
    _animCtrl.forward();
  }

  void _closeActions() {
    _animCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = BeUIColors.accentOf(isDark);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Action panel behind the message ─────────────────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _actionPanelWidth,
              child: FadeTransition(
                opacity: _animCtrl,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.onCopy != null)
                      _SwipeActionBtn(
                        icon: Icons.copy_rounded,
                        label: 'Copier',
                        color: accent,
                        onTap: () {
                          _closeActions();
                          widget.onCopy?.call();
                        },
                      ),
                    if (widget.onRetry != null)
                      _SwipeActionBtn(
                        icon: Icons.refresh_rounded,
                        label: 'Réessayer',
                        color: const Color(0xFFEF5350),
                        onTap: () {
                          _closeActions();
                          widget.onRetry?.call();
                        },
                      ),
                  ],
                ),
              ),
            ),

            // ── Message content with swipe ─────────────────────
            AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-_animCtrl.value * _actionPanelWidth, 0),
                  child: child,
                );
              },
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  final dx = details.primaryDelta ?? 0;
                  if (dx < -5) {
                    // Swipe left → open actions if not already open
                    if (!_animCtrl.isAnimating && _animCtrl.value == 0) {
                      _openActions();
                    }
                  } else if (dx > 5 && _animCtrl.value > 0) {
                    // Swipe right → close
                    _closeActions();
                  }
                },
                onHorizontalDragEnd: (details) {
                  // Snap: if partially open, finish opening; otherwise close
                  if (_animCtrl.value > 0 && _animCtrl.value < 0.5) {
                    _closeActions();
                  } else if (_animCtrl.value >= 0.5) {
                    _openActions();
                  }
                },
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SwipeActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SwipeActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
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
