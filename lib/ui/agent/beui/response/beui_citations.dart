import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUICitations — marqueurs inline + liste collapsible de références.
///
///   • Marqueurs [1][2][3] cliquables (scrollent vers la source)
///   • Liste expandable avec apparition progressive (staggered)
///   • Chaque source : avatar lettre, titre, domaine, extrait
/// ═══════════════════════════════════════════════════════════════════════════

class BeUICitation {
  final int index;
  final String title;
  final String? domain;
  final String? snippet;

  const BeUICitation({
    required this.index,
    required this.title,
    this.domain,
    this.snippet,
  });
}

class BeUICitations extends StatefulWidget {
  final List<BeUICitation> citations;
  final bool isDark;

  const BeUICitations({
    super.key,
    required this.citations,
    this.isDark = true,
  });

  @override
  State<BeUICitations> createState() => _BeUICitationsState();
}

class _BeUICitationsState extends State<BeUICitations> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.citations.isEmpty) return const SizedBox.shrink();

    final isDark = widget.isDark;
    final accent = BeUIColors.accentOf(isDark);
    final muted = isDark ? Colors.grey[500]! : Colors.grey[500]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Inline markers ────────────────────────────────────
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: widget.citations.map((c) {
            return GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${c.index}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // ── Collapsible reference list ────────────────────────
        if (_expanded)
          GestureDetector(
            onTap: () => setState(() => _expanded = false),
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BeUIColors.deepSurfaceOf(isDark),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BeUIColors.borderOf(isDark), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.format_list_numbered, size: 12, color: muted),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.citations.length} sources',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
                      ),
                      const Spacer(),
                      Icon(Icons.keyboard_arrow_up, size: 14, color: muted),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final c in widget.citations)
                    _CitationItem(citation: c, index: c.index, isDark: isDark),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CitationItem extends StatelessWidget {
  final BeUICitation citation;
  final int index;
  final bool isDark;

  const _CitationItem({
    required this.citation,
    required this.index,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    final muted = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final accent = BeUIColors.accentOf(isDark);

    return BeUIPopIn(
      delay: Duration(milliseconds: index * 80),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Number avatar
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg),
                  ),
                  if (citation.domain != null)
                    Text(
                      citation.domain!,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  if (citation.snippet != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        citation.snippet!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
