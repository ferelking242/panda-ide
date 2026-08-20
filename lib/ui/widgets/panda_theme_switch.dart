import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Transition de thème par propagation (circular reveal).
///
/// Le principe : juste avant d'appliquer le nouveau thème, on capture une
/// image de la frame courante. Cette image est ensuite peinte **au-dessus** de
/// l'arbre déjà repeint avec le nouveau thème, puis on y perce un cercle qui
/// grandit depuis le point d'origine (le bouton de bascule). Résultat : le
/// nouveau thème « se propage » depuis le bouton au lieu d'apparaître d'un coup.
///
/// Usage :
/// ```dart
/// MaterialApp(
///   builder: (context, child) => ThemeSwitchScope(child: child!),
/// );
///
/// ThemeSwitchScope.propagateFrom(
///   context: context,          // contexte du bouton (donne l'origine)
///   apply: () => bloc.add(...) // applique le nouveau thème
/// );
/// ```
class ThemeSwitchScope extends StatefulWidget {
  const ThemeSwitchScope({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 620),
    this.curve = Curves.easeInOutCubic,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;

  /// État actif le plus récent — permet un appel depuis n'importe quel
  /// contexte descendant sans passer par un InheritedWidget.
  static ThemeSwitchScopeState? _current;

  static ThemeSwitchScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ThemeSwitchScopeState>() ?? _current;

  /// Déclenche la propagation depuis le widget associé à [context]
  /// (typiquement le bouton de bascule du thème).
  static Future<void> propagateFrom({
    required BuildContext context,
    required VoidCallback apply,
  }) async {
    final scope = maybeOf(context);
    Offset? origin;
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      origin = ro.localToGlobal(ro.size.center(Offset.zero));
    }
    if (scope == null) {
      apply();
      return;
    }
    await scope.run(origin: origin, apply: apply);
  }

  @override
  State<ThemeSwitchScope> createState() => ThemeSwitchScopeState();
}

class ThemeSwitchScopeState extends State<ThemeSwitchScope>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  ui.Image? _snapshot;
  Size _snapshotSize = Size.zero;
  Offset _origin = Offset.zero;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    ThemeSwitchScope._current = this;
  }

  @override
  void dispose() {
    if (ThemeSwitchScope._current == this) ThemeSwitchScope._current = null;
    _ctrl.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  /// Capture la frame courante, applique [apply], puis anime la propagation.
  Future<void> run({Offset? origin, required VoidCallback apply}) async {
    if (_running) {
      apply();
      return;
    }
    _running = true;
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      ui.Image? image;
      if (boundary != null && boundary.hasSize && !boundary.debugNeedsPaint) {
        try {
          image = await boundary.toImage(pixelRatio: 1.0);
          _snapshotSize = boundary.size;
        } catch (_) {
          image = null;
        }
      }

      if (image == null || !mounted) {
        // Pas de capture possible (web/software renderer) → bascule simple.
        apply();
        return;
      }

      final Size size = _snapshotSize;
      _origin = origin ?? Offset(size.width - 24, size.height / 2);
      setState(() {
        _snapshot?.dispose();
        _snapshot = image;
      });

      // Laisse une frame au snapshot pour être peint avant de changer le thème,
      // sinon on verrait un flash du nouveau thème sur toute la surface.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      apply();

      await _ctrl.forward(from: 0.0);
      if (!mounted) return;
      setState(() {
        _snapshot?.dispose();
        _snapshot = null;
      });
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Stack(
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => CustomPaint(
                  painter: _RevealPainter(
                    image: snapshot,
                    imageSize: _snapshotSize,
                    origin: _origin,
                    progress: widget.curve.transform(_ctrl.value),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RevealPainter extends CustomPainter {
  _RevealPainter({
    required this.image,
    required this.imageSize,
    required this.origin,
    required this.progress,
  });

  final ui.Image image;
  final Size imageSize;
  final Offset origin;
  final double progress;

  static double _maxRadius(Size size, Offset o) {
    final double dx = o.dx > size.width / 2 ? o.dx : size.width - o.dx;
    final double dy = o.dy > size.height / 2 ? o.dy : size.height - o.dy;
    return Offset(dx, dy).distance + 8;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = _maxRadius(size, origin) * progress;

    // Ancienne frame, trouée par un cercle qui grandit → propagation.
    final Path hole = Path()
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
    final Path outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      hole,
    );

    canvas.save();
    canvas.clipPath(outside);
    final Rect dst = Offset.zero & size;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();

    // Liseré doux sur le front d'onde : rend la propagation lisible.
    if (progress > 0.001 && progress < 0.999) {
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.14 * (1 - progress))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.progress != progress ||
      old.image != image ||
      old.origin != origin;
}
