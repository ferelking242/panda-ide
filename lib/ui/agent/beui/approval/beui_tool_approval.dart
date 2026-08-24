import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIToolApproval — carte d'approbation d'outil (human-in-the-loop).
///
///   • Affiche les détails de l'outil (nom, arguments)
///   • Bordure pulsante pendant l'attente
///   • 3 actions : Deny (ghost red) · Allow once · Always allow
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIToolApproval extends StatefulWidget {
  final String toolName;
  final Map<String, dynamic> args;
  final VoidCallback onAllow;
  final VoidCallback onAlways;
  final VoidCallback onDeny;
  final bool isDark;

  const BeUIToolApproval({
    super.key,
    required this.toolName,
    required this.args,
    required this.onAllow,
    required this.onAlways,
    required this.onDeny,
    this.isDark = true,
  });

  @override
  State<BeUIToolApproval> createState() => _BeUIToolApprovalState();
}

class _BeUIToolApprovalState extends State<BeUIToolApproval>
    with SingleTickerProviderStateMixin {
  late final AnimationController _borderCtrl;

  @override
  void initState() {
    super.initState();
    _borderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _borderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = BeUIColors.accentOf(widget.isDark);
    final fg = widget.isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted = widget.isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final border = BeUIColors.borderOf(widget.isDark);

    return AnimatedBuilder(
      animation: _borderCtrl,
      builder: (context, _) {
        final pulseAlpha = 0.15 + 0.15 * _borderCtrl.value;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BeUIColors.deepSurfaceOf(widget.isDark),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent.withValues(alpha: pulseAlpha),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────
              Row(
                children: [
                  BeUIPulsingSquare(size: 14, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Approbation requise',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Tool info ───────────────────────────────────
              Text(
                widget.toolName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),

              // ── Args ────────────────────────────────────────
              if (widget.args.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: BeUIColors.surfaceOf(widget.isDark),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in widget.args.entries)
                        _argRow(entry.key, entry.value?.toString() ?? '', fg, muted),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // ── Action buttons ──────────────────────────────
              Row(
                children: [
                  // Deny
                  Expanded(
                    child: _ApprovalButton(
                      label: 'Refuser',
                      icon: Icons.close,
                      color: BeUIColors.error,
                      filled: false,
                      onTap: widget.onDeny,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Always
                  Expanded(
                    child: _ApprovalButton(
                      label: 'Toujours',
                      icon: Icons.lock_open,
                      color: muted,
                      filled: false,
                      onTap: widget.onAlways,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Allow once
                  Expanded(
                    child: _ApprovalButton(
                      label: 'Autoriser',
                      icon: Icons.check,
                      color: accent,
                      filled: true,
                      onTap: widget.onAllow,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _argRow(String key, String value, Color fg, Color muted) {
    final display = value.length > 120 ? '${value.substring(0, 120)}…' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$key: ',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.7)),
          ),
          TextSpan(
            text: display,
            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withValues(alpha: 0.6)),
          ),
        ]),
      ),
    );
  }
}

class _ApprovalButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _ApprovalButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BeUIDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled ? color : color.withValues(alpha: 0.3),
            width: filled ? 0 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
