import 'dart:async';
import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUILoadingState — 3 variantes de chargement agent :
///   - shimmer  : texte lumineux en balayage
///   - progress : carré animé qui pulse (style VS Code)
///   - cycling  : phrases tournantes avec fade
/// ═══════════════════════════════════════════════════════════════════════════

enum BeUILoadingVariant { shimmer, progress, cycling }

class BeUILoadingState extends StatelessWidget {
  final String label;
  final BeUILoadingVariant variant;
  final Color color;
  final List<String>? cyclingPhrases;

  const BeUILoadingState({
    super.key,
    required this.label,
    this.variant = BeUILoadingVariant.shimmer,
    required this.color,
    this.cyclingPhrases,
  });

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      BeUILoadingVariant.shimmer => _ShimmerLabel(label: label, color: color),
      BeUILoadingVariant.progress => _AnimatedSquare(label: label, color: color),
      BeUILoadingVariant.cycling => _CyclingPhrases(
          phrases: cyclingPhrases ?? [label],
          color: color,
        ),
    };
  }
}

// ── Shimmer Label ─────────────────────────────────────────────────────────

class _ShimmerLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _ShimmerLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return BeUIShimmer(
      baseColor: color.withValues(alpha: 0.4),
      highlightColor: color.withValues(alpha: 0.8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

// ── Animated Square (VS Code style pulsing square) ────────────────────────

class _AnimatedSquare extends StatefulWidget {
  final String label;
  final Color color;
  const _AnimatedSquare({required this.label, required this.color});

  @override
  State<_AnimatedSquare> createState() => _AnimatedSquareState();
}

class _AnimatedSquareState extends State<_AnimatedSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final size = 8.0 + _ctrl.value * 2;
        final opacity = 0.5 + _ctrl.value * 0.5;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing square
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            // White label text
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Cycling Phrases ───────────────────────────────────────────────────────

class _CyclingPhrases extends StatefulWidget {
  final List<String> phrases;
  final Color color;
  const _CyclingPhrases({required this.phrases, required this.color});

  @override
  State<_CyclingPhrases> createState() => _CyclingPhrasesState();
}

class _CyclingPhrasesState extends State<_CyclingPhrases> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(BeUIDurations.phraseCycle, (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.phrases.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: BeUIDurations.medium,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Text(
        widget.phrases[_index],
        key: ValueKey(_index),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: widget.color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
