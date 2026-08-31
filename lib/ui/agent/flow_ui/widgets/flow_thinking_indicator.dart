import 'package:flutter/material.dart';
import 'package:thinking_orbs_flutter/thinking_orbs.dart';

import '../theme/flow_theme.dart';
import 'flow_shimmer_text.dart';

/// The thinking line shown while the assistant has not started responding:
/// a dotted thought-orb animation beside a shimmering, host-supplied label.
///
/// Uses the thinking-orbs-flutter library for hand-tuned animated orbs.
///
/// ```dart
/// FlowThinkingIndicator(label: 'Thinking…')
/// ```
///
/// [label] is the whole text — the package ships no strings — and null
/// renders the orb alone. [active] is the state switch: true animates the
/// orb; false pauses it.
///
/// [orbState] controls which animation variant to show:
/// - [OrbState.working] (default) — particles on tilted orbits
/// - [OrbState.searching] — a scan meridian sweeps a dotted globe
/// - [OrbState.solving] — bands scramble, then click back solved
/// - [OrbState.composing] — an undulating multi-band sash
///
/// Respects the platform reduced-motion setting by rendering static.
class FlowThinkingIndicator extends StatefulWidget {
  const FlowThinkingIndicator({
    super.key,
    this.label,
    this.active = true,
    this.color,
    this.size = 14,
    this.duration = const Duration(milliseconds: 2400),
    this.semanticLabel,
    this.orbState = OrbState.working,
    this.orbSize = OrbSize.small,
    this.orbTheme = OrbTheme.auto,
    this.orbSpeed = 1.0,
  });

  /// Host-localized text beside the glyph, e.g. 'Thinking…'.
  /// Null renders the glyph alone.
  final String? label;

  /// Whether the orb animates. False pauses the orb.
  final bool active;

  /// Glyph ink — ignored when using ThinkingOrb (orb uses its own theme).
  final Color? color;

  /// Edge of the square glyph.
  final double size;

  /// One full cycle duration — ignored when using ThinkingOrb.
  final Duration duration;

  /// Accessibility label for the glyph-only form (e.g. a localized
  /// "Thinking"). Ignored when [label] is set — the visible text already
  /// carries the meaning.
  final String? semanticLabel;

  /// Which orb animation variant to show.
  final OrbState orbState;

  /// Size preset for the orb.
  final OrbSize orbSize;

  /// Theme mode for the orb.
  final OrbTheme orbTheme;

  /// Animation speed multiplier.
  final double orbSpeed;

  @override
  State<FlowThinkingIndicator> createState() => _FlowThinkingIndicatorState();
}

class _FlowThinkingIndicatorState extends State<FlowThinkingIndicator> {
  /// The design's gap between the glyph and its label.
  static const double _labelGap = 4;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;

    Widget glyph = ThinkingOrb(
      state: widget.orbState,
      size: widget.orbSize,
      theme: widget.orbTheme,
      speed: widget.orbSpeed,
      paused: !widget.active,
      semanticsLabel: widget.semanticLabel,
    );

    if (label == null) {
      final semanticLabel = widget.semanticLabel;
      if (semanticLabel == null) return glyph;
      return Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(child: glyph),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: glyph),
        const SizedBox(width: _labelGap),
        FlowShimmerText(
          text: label,
          enabled: widget.active,
          style: const TextStyle(height: 1.3),
        ),
      ],
    );
  }
}


