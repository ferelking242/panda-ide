import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIFileDiff — affichage de diffs avec apparition progressive.
///
///   • Rows progressives pendant le streaming
///   • Lignes vertes (added) / rouges (removed) / grises (context)
///   • Compteur +N/-M animé
///   • Collapse automatique à la complétion
/// ═══════════════════════════════════════════════════════════════════════════

enum BeUIDiffLineType { added, removed, context }

class BeUIDiffLine {
  final BeUIDiffLineType type;
  final int? oldLine;
  final int? newLine;
  final String text;

  const BeUIDiffLine({
    required this.type,
    this.oldLine,
    this.newLine,
    required this.text,
  });
}

class BeUIFileDiff extends StatefulWidget {
  final String? fileName;
  final List<BeUIDiffLine> lines;
  final bool isStreaming;
  final bool isDone;
  final int revealedCount;
  final bool isDark;

  const BeUIFileDiff({
    super.key,
    this.fileName,
    required this.lines,
    this.isStreaming = false,
    this.isDone = false,
    this.revealedCount = 9999,
    this.isDark = true,
  });

  @override
  State<BeUIFileDiff> createState() => _BeUIFileDiffState();
}

class _BeUIFileDiffState extends State<BeUIFileDiff> {
  bool _collapsed = false;

  int get _added => widget.lines.where((l) => l.type == BeUIDiffLineType.added).length;
  int get _removed => widget.lines.where((l) => l.type == BeUIDiffLineType.removed).length;

  @override
  void initState() {
    super.initState();
    if (widget.isDone) _collapsed = true;
  }

  @override
  void didUpdateWidget(covariant BeUIFileDiff old) {
    super.didUpdateWidget(old);
    if (widget.isDone && !old.isDone) {
      setState(() => _collapsed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = BeUIColors.accentOf(widget.isDark);
    final fg = widget.isDark ? Colors.grey[300]! : Colors.grey[700]!;
    final muted = widget.isDark ? Colors.grey[500]! : Colors.grey[500]!;

    final visible = widget.lines.take(widget.revealedCount).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(widget.isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BeUIColors.borderOf(widget.isDark), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────
          InkWell(
            onTap: widget.lines.isNotEmpty ? () => setState(() => _collapsed = !_collapsed) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows, size: 13, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName ?? 'diff',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
                    ),
                  ),
                  // Live counters
                  if (_added > 0)
                    Text('+$_added', style: TextStyle(fontSize: 11, color: BeUIColors.success, fontFamily: 'monospace')),
                  if (_added > 0 && _removed > 0) const SizedBox(width: 4),
                  if (_removed > 0)
                    Text('-$_removed', style: TextStyle(fontSize: 11, color: BeUIColors.error, fontFamily: 'monospace')),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _collapsed ? 0.5 : 0,
                    duration: BeUIDurations.fast,
                    child: Icon(Icons.keyboard_arrow_down, size: 14, color: muted),
                  ),
                ],
              ),
            ),
          ),

          // ── Lines ────────────────────────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildLines(visible, fg, muted),
            crossFadeState: _collapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: BeUIDurations.medium,
          ),
        ],
      ),
    );
  }

  Widget _buildLines(List<BeUIDiffLine> lines, Color fg, Color muted) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: _collapsed ? 0 : 300,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              _DiffLineRow(line: line, fg: fg, muted: muted, isDark: widget.isDark),
          ],
        ),
      ),
    );
  }

  bool get isDark => widget.isDark;
}

class _DiffLineRow extends StatelessWidget {
  final BeUIDiffLine line;
  final Color fg;
  final Color muted;
  final bool isDark;

  const _DiffLineRow({
    required this.line,
    required this.fg,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = switch (line.type) {
      BeUIDiffLineType.added => BeUIColors.success.withValues(alpha: 0.08),
      BeUIDiffLineType.removed => BeUIColors.error.withValues(alpha: 0.08),
      _ => Colors.transparent,
    };

    final prefix = switch (line.type) {
      BeUIDiffLineType.added => '+',
      BeUIDiffLineType.removed => '-',
      _ => ' ',
    };

    final prefixColor = switch (line.type) {
      BeUIDiffLineType.added => BeUIColors.success,
      BeUIDiffLineType.removed => BeUIColors.error,
      _ => muted,
    };

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers
          SizedBox(
            width: 60,
            child: Text(
              '${line.oldLine ?? ''} ${line.newLine ?? ''}',
              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: muted.withValues(alpha: 0.5)),
            ),
          ),
          // Prefix (+/-/ )
          SizedBox(
            width: 14,
            child: Text(prefix, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: prefixColor)),
          ),
          // Text
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
