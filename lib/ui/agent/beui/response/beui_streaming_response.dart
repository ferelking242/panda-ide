import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIStreamingResponse — surface de réponse stable pendant le streaming.
///
///   • Texte affiché au fil du stream (pas de re-layout)
///   • Caret clignotant pendant streaming
///   • Actions de complétion (copier, réessayer) apparaissent en fade
///   • Sources expandables (optionnel)
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIStreamingResponse extends StatelessWidget {
  final String text;
  final bool isStreaming;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final List<BeUISource>? sources;
  final bool isDark;

  const BeUIStreamingResponse({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.onCopy,
    this.onRetry,
    this.sources,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Streaming text ────────────────────────────────────
        if (text.isNotEmpty)
          SelectableText(
            text,
            style: TextStyle(fontSize: 13.5, color: fg, height: 1.6),
          ),

        // ── Blinking caret ────────────────────────────────────
        if (isStreaming && text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: _BlinkingCaret(color: BeUIColors.accentOf(isDark)),
          ),

        // ── Completion actions ────────────────────────────────
        AnimatedOpacity(
          opacity: isStreaming ? 0.0 : 1.0,
          duration: BeUIDurations.medium,
          child: AnimatedSlide(
            offset: isStreaming ? const Offset(0, 0.3) : Offset.zero,
            duration: BeUIDurations.medium,
            curve: BeUICurves.outCurve,
            child: (onCopy != null || onRetry != null)
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onCopy != null)
                          _CompletionButton(
                            icon: Icons.copy,
                            label: 'Copier',
                            onTap: onCopy!,
                            isDark: isDark,
                          ),
                        if (onRetry != null) ...[
                          const SizedBox(width: 6),
                          _CompletionButton(
                            icon: Icons.refresh,
                            label: 'Réessayer',
                            onTap: onRetry!,
                            isDark: isDark,
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),

        // ── Sources summary ───────────────────────────────────
        if (sources != null && sources!.isNotEmpty)
          _SourcesSummary(sources: sources!, isDark: isDark),
      ],
    );
  }
}

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
      child: Text('▌', style: TextStyle(fontSize: 13, color: widget.color)),
    );
  }
}

class _CompletionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _CompletionButton({
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

// ── Sources ───────────────────────────────────────────────────────────────

class BeUISource {
  final String title;
  final String? domain;
  final String? url;

  const BeUISource({required this.title, this.domain, this.url});
}

class _SourcesSummary extends StatefulWidget {
  final List<BeUISource> sources;
  final bool isDark;

  const _SourcesSummary({required this.sources, required this.isDark});

  @override
  State<_SourcesSummary> createState() => _SourcesSummaryState();
}

class _SourcesSummaryState extends State<_SourcesSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final muted = widget.isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final accent = BeUIColors.accentOf(widget.isDark);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: BeUIColors.deepSurfaceOf(widget.isDark),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 12, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${widget.sources.length} source${widget.sources.length > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: BeUIDurations.fast,
                  child: Icon(Icons.expand_more, size: 14, color: muted),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              for (final src in widget.sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          child: Text(
                            (src.domain ?? src.title[0]).substring(0, 1).toUpperCase(),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          src.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: fg),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Color get fg => widget.isDark ? Colors.grey[400]! : Colors.grey[600]!;
}
