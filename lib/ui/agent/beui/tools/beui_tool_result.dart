import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIToolResult — résultat d'exécution d'outil (terminal, output).
///
///   • Running  : header spinner + output scrollable borné (max 160px)
///   • Done     : collapse en ligne compacte "✓ title · N lignes" (tap → expand)
///   • Error    : accent rouge + exit code
/// ═══════════════════════════════════════════════════════════════════════════

class BeUIToolResult extends StatefulWidget {
  final String title;
  final String output;
  final bool isRunning;
  final int? exitCode;
  final String? duration;
  final bool isDark;

  const BeUIToolResult({
    super.key,
    required this.title,
    this.output = '',
    this.isRunning = false,
    this.exitCode,
    this.duration,
    this.isDark = true,
  });

  @override
  State<BeUIToolResult> createState() => _BeUIToolResultState();
}

class _BeUIToolResultState extends State<BeUIToolResult> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = BeUIColors.accentOf(isDark);
    final fg = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    final muted = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final lineCount = widget.output.split('\n').length;
    final isError = widget.exitCode != null && widget.exitCode! != 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? BeUIColors.error.withValues(alpha: 0.3) : BeUIColors.borderOf(isDark),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header (tap to toggle) ──────────────────────
          InkWell(
            onTap: (widget.output.isNotEmpty && !widget.isRunning)
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  // Status icon
                  if (widget.isRunning)
                    BeUIRotatingSquare(size: 12, color: accent)
                  else if (isError)
                    Icon(Icons.error_outline, size: 13, color: BeUIColors.error)
                  else
                    Icon(Icons.check_circle, size: 13, color: BeUIColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isRunning
                          ? widget.title
                          : '${widget.title} · $lineCount lignes'
                          '${widget.duration != null ? ' · ${widget.duration}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isError ? Colors.redAccent : fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  // Copy button (when done)
                  if (!widget.isRunning && widget.output.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        // TODO: copy to clipboard
                      },
                      child: Icon(Icons.copy, size: 12, color: muted),
                    ),
                  // Expand chevron
                  if (widget.output.isNotEmpty && !widget.isRunning) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: BeUIDurations.fast,
                      child: Icon(Icons.expand_more, size: 14, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Output body ──────────────────────────────────
          if (widget.isRunning && widget.output.isNotEmpty)
            _buildOutput(widget.output, maxH: 160),

          if (!widget.isRunning && _expanded && widget.output.isNotEmpty)
            _buildOutput(widget.output, maxH: 300),
        ],
      ),
    );
  }

  Widget _buildOutput(String text, {double maxH = 160}) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BeUIColors.surfaceOf(isDark),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: BeUIColors.accentOf(isDark).withValues(alpha: 0.65),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  bool get isDark => widget.isDark;
}
