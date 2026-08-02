import 'package:flutter/material.dart';

/// Panda IDE surface — card decorations inspired by Scolaris dashboard.
/// Provides themed, adaptive card styles used throughout the app.
class PandaSurface {
  PandaSurface._();

  // ── Themed card (adapts to dark / light) ────────────────────────────────
  /// Standard card that respects the current theme.
  static BoxDecoration themedCard(
    BuildContext context, {
    double radius = 12,
    Color? borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? cs.outline.withOpacity(.20),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: cs.shadow.withOpacity(.05),
          blurRadius: 12,
          offset: const Offset(0, 3),
          spreadRadius: -2,
        ),
      ],
    );
  }

  // ── Welcome / Start item card ────────────────────────────────────────────
  static BoxDecoration welcomeItem(
    bool isDark, {
    bool hovered = false,
  }) {
    return BoxDecoration(
      color: hovered
          ? (isDark
              ? const Color(0xff2a2d2e)
              : const Color(0xffe8e8e8))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
    );
  }

  // ── Accent card (colored) ────────────────────────────────────────────────
  static BoxDecoration accentCard(
    BuildContext context, {
    required Color color,
    double radius = 12,
  }) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color.lerp(cs.surfaceContainer, color, 0.10)!,
          Color.lerp(cs.surfaceContainer, color, 0.22)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withOpacity(0.40), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.15),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: -2,
        ),
      ],
    );
  }

  // ── Stats chip ───────────────────────────────────────────────────────────
  static BoxDecoration statChip(bool isDark) {
    return BoxDecoration(
      color: isDark ? const Color(0xff252526) : const Color(0xfff3f3f3),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isDark
            ? const Color(0xff3c3c3c)
            : const Color(0xffe0e0e0),
        width: 1,
      ),
    );
  }

  // ── Recent item row ──────────────────────────────────────────────────────
  static BoxDecoration recentRow(bool isDark, {bool hovered = false}) {
    return BoxDecoration(
      color: hovered
          ? (isDark ? const Color(0xff2a2d2e) : const Color(0xffe8eaed))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
    );
  }
}
