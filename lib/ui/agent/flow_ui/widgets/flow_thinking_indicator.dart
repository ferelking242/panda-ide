import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/flow_theme.dart';
import 'flow_shimmer_text.dart';

/// The six MIT-licensed orb motions adapted from
/// https://github.com/iamEtornam/thinking-orbs.
///
/// The package is intentionally inlined here so Panda has no runtime package
/// dependency for a small status indicator.
enum FlowOrbState {
  /// Particles run on tilted orbits.
  working,

  /// A scan meridian sweeps a dotted globe.
  searching,

  /// Bands scramble in quarter turns, then click back solved.
  solving,

  /// A waveform rolls through latitude rings.
  listening,

  /// An undulating multi-band sash.
  composing,

  /// A dotted outline morphs circle → triangle → square.
  shaping,
}

/// Compact animated status orb used by the agent message stream.
///
/// The orb is drawn locally with Flutter's canvas primitives. The upstream
/// implementation is MIT licensed:
///
/// Copyright (c) 2026 Bright Sunu
/// This is a Flutter port of "thinking-orbs" by Jakub Antalik.
///
/// MIT License
///
/// Permission is hereby granted, free of charge, to any person obtaining a
/// copy of this software and associated documentation files (the "Software"),
/// to deal in the Software without restriction, including without limitation
/// the rights to use, copy, modify, merge, publish, distribute, sublicense,
/// and/or sell copies of the Software, and to permit persons to whom the
/// Software is furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
/// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
/// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
/// DEALINGS IN THE SOFTWARE.
class FlowThinkingIndicator extends StatefulWidget {
  const FlowThinkingIndicator({
    super.key,
    this.label,
    this.active = true,
    this.color,
    this.size = 14,
    this.duration = const Duration(milliseconds: 2400),
    this.semanticLabel,
    this.orbState = FlowOrbState.working,
    this.orbSpeed = 1,
  });

  final String? label;
  final bool active;
  final Color? color;
  final double size;
  final Duration duration;
  final String? semanticLabel;
  final FlowOrbState orbState;
  final double orbSpeed;

  @override
  State<FlowThinkingIndicator> createState() => _FlowThinkingIndicatorState();
}

class _FlowThinkingIndicatorState extends State<FlowThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _syncAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(FlowThinkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active && !_reducedMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.flowColors.primary;
    final frame = CustomPaint(
      painter: _FlowOrbPainter(
        animation: _controller,
        state: widget.orbState,
        color: color,
        reducedMotion: _reducedMotion,
        speed: widget.orbSpeed,
      ),
      size: Size.square(widget.size),
    );
    final orb = Semantics(
      label: widget.semanticLabel,
      child: ExcludeSemantics(child: frame),
    );
    final label = widget.label;
    if (label == null) return orb;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        orb,
        const SizedBox(width: 4),
        FlowShimmerText(
          text: label,
          enabled: widget.active && !_reducedMotion,
          style: const TextStyle(height: 1.3),
        ),
      ],
    );
  }
}

class _FlowOrbPainter extends CustomPainter {
  _FlowOrbPainter({
    required this.animation,
    required this.state,
    required this.color,
    required this.reducedMotion,
    required this.speed,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final FlowOrbState state;
  final Color color;
  final bool reducedMotion;
  final double speed;

  double get _time =>
      (reducedMotion ? 0.6 : animation.value) * speed * math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    if (size.width != size.height) {
      canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    }
    final paint = Paint()..isAntiAlias = true;
    switch (state) {
      case FlowOrbState.working:
        _working(canvas, side, paint);
      case FlowOrbState.searching:
        _searching(canvas, side, paint);
      case FlowOrbState.solving:
        _solving(canvas, side, paint);
      case FlowOrbState.listening:
        _listening(canvas, side, paint);
      case FlowOrbState.composing:
        _composing(canvas, side, paint);
      case FlowOrbState.shaping:
        _shaping(canvas, side, paint);
    }
  }

  void _dot(Canvas canvas, Offset point, double radius, double opacity, Paint p) {
    p.color = color.withValues(
      alpha: (color.a * opacity).clamp(0.05, 1.0).toDouble(),
    );
    canvas.drawCircle(point, math.max(0.45, radius), p);
  }

  Offset _rotate(Offset point, double angle, Offset center) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    final x = point.dx - center.dx;
    final y = point.dy - center.dy;
    return Offset(
      center.dx + x * c - y * s,
      center.dy + x * s + y * c,
    );
  }

  void _working(Canvas canvas, double side, Paint p) {
    final center = Offset.square(side / 2);
    final radius = side * 0.33;
    for (var orbit = 0; orbit < 3; orbit++) {
      final tilt = 0.34 + orbit * 0.36;
      final phase = _time * (0.75 + orbit * 0.12) + orbit * 2.1;
      for (var i = 0; i < 12; i++) {
        final a = i / 12 * math.pi * 2 + phase;
        final point = Offset(
          center.dx + math.cos(a) * radius,
          center.dy + math.sin(a) * radius * tilt,
        );
        _dot(canvas, _rotate(point, orbit * 0.9, center), side * 0.035,
            0.25 + 0.65 * ((i + orbit) % 4) / 3, p);
      }
    }
    _dot(canvas, center, side * 0.07, 0.9, p);
  }

  void _searching(Canvas canvas, double side, Paint p) {
    final center = Offset.square(side / 2);
    final radius = side * 0.36;
    final yaw = _time * 0.45;
    for (var lat = -4; lat <= 4; lat++) {
      final latitude = lat / 5 * math.pi / 2;
      final ringRadius = radius * math.cos(latitude);
      final y = center.dy - math.sin(latitude) * radius;
      for (var i = 0; i < 18; i++) {
        final a = i / 18 * math.pi * 2 + yaw;
        final depth = (math.sin(a) + 1) / 2;
        _dot(
          canvas,
          Offset(center.dx + math.cos(a) * ringRadius, y),
          side * (0.018 + depth * 0.023),
          0.18 + depth * 0.72,
          p,
        );
      }
    }
    final scan = (yaw % (math.pi * 2));
    for (var i = 0; i < 15; i++) {
      final latitude = -math.pi / 2 + (i + 0.5) / 15 * math.pi;
      _dot(
        canvas,
        Offset(
          center.dx + math.cos(scan) * radius * math.cos(latitude),
          center.dy - math.sin(latitude) * radius,
        ),
        side * 0.045,
        0.95,
        p,
      );
    }
  }

  void _solving(Canvas canvas, double side, Paint p) {
    final center = Offset.square(side / 2);
    final phase = (_time / (math.pi * 2) * 3) % 1;
    final quarter = phase < 0.58 ? phase / 0.58 : 1;
    final turn = (math.pi / 2) * _ease(quarter);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        final x = (col - 1.5) * side * 0.15;
        final y = (row - 1.5) * side * 0.15;
        final point = _rotate(
          Offset(center.dx + x, center.dy + y),
          turn * ((row + col) % 2 == 0 ? 1 : -1),
          center,
        );
        final active = ((row + col) % 4) / 4 < quarter;
        _dot(canvas, point, side * 0.045, active ? 0.95 : 0.38, p);
      }
    }
  }

  void _listening(Canvas canvas, double side, Paint p) {
    final center = Offset.square(side / 2);
    for (var ring = 0; ring < 5; ring++) {
      final radius = side * (0.13 + ring * 0.065);
      for (var i = 0; i < 18; i++) {
        final a = i / 18 * math.pi * 2;
        final wave = math.sin(a * 3 - _time * 1.5 + ring) * side * 0.025;
        _dot(
          canvas,
          Offset(
            center.dx + math.cos(a) * (radius + wave),
            center.dy + math.sin(a) * (radius + wave),
          ),
          side * 0.025,
          0.25 + 0.12 * ring,
          p,
        );
      }
    }
  }

  void _composing(Canvas canvas, double side, Paint p) {
    final center = Offset.square(side / 2);
    for (var lane = 0; lane < 5; lane++) {
      for (var i = 0; i < 18; i++) {
        final x = side * 0.12 + i / 17 * side * 0.76;
        final y = side * 0.24 +
            lane * side * 0.13 +
            math.sin(i * 0.55 - _time * 1.4 + lane * 0.8) * side * 0.06;
        _dot(
          canvas,
          _rotate(Offset(x, y), -0.18, center),
          side * 0.026,
          0.28 + 0.12 * lane,
          p,
        );
      }
    }
  }

  void _shaping(Canvas canvas, double side, Paint p) {
    final center = Offset.square(side / 2);
    final cycle = (_time / (math.pi * 2) * 0.75) % 3;
    final from = cycle.floor();
    final amount = _ease(cycle - from);
    for (var i = 0; i < 28; i++) {
      final f = i / 28;
      final a = _shape(from, f);
      final b = _shape((from + 1) % 3, f);
      final point = Offset(
        center.dx + (a.dx + (b.dx - a.dx) * amount) * side,
        center.dy + (a.dy + (b.dy - a.dy) * amount) * side,
      );
      _dot(canvas, point, side * 0.026, 0.72, p);
    }
  }

  Offset _shape(int shape, double f) {
    if (shape == 0) {
      final a = -math.pi / 2 + f * math.pi * 2;
      return Offset(math.cos(a) * 0.27, math.sin(a) * 0.27);
    }
    final vertices = shape == 1
        ? const [
            Offset(0, -0.30),
            Offset(0.28, 0.20),
            Offset(-0.28, 0.20),
          ]
        : const [
            Offset(-0.25, -0.25),
            Offset(0.25, -0.25),
            Offset(0.25, 0.25),
            Offset(-0.25, 0.25),
          ];
    final scaled = f * vertices.length;
    final index = math.min(vertices.length - 1, scaled.floor());
    final local = scaled - index;
    final from = vertices[index];
    final to = vertices[(index + 1) % vertices.length];
    return Offset(
      from.dx + (to.dx - from.dx) * local,
      from.dy + (to.dy - from.dy) * local,
    );
  }

  double _ease(double value) => value * value * (3 - 2 * value);

  @override
  bool shouldRepaint(_FlowOrbPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.speed != speed;
}