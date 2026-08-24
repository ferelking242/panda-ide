import 'dart:async';
import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUILoadingState — 3 variantes de chargement agent :
///   - shimmer  : texte lumineux en balayage
///   - progress : barre de progression indéterminée
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
      BeUILoadingVariant.progress => _ProgressLine(color: color),
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

// ── Progress Bar (indeterminate) ──────────────────────────────────────────

class _ProgressLine extends StatefulWidget {
  final Color color;
  const _ProgressLine({required this.color});

  @override
  State<_ProgressLine> createState() => _ProgressLineState();
}

class _ProgressLineState extends State<_ProgressLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: BeUIDurations.slow,
    )..repeat();
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
        return Container(
          height: 3,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment(_ctrl.value * 2 - 1, 0),
            widthFactor: 0.4,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.color.withValues(alpha: 0),
                    widget.color,
                    widget.color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
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
