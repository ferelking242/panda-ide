import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// beUI Theme — tokens partagés de la bibliothèque beUI pour Panda IDE.
///
/// Toutes les animations beUI utilisent les mêmes courbes et durées pour
/// une cohérence de mouvement sur toute l'interface agent :
///   • apparition  : easeOutCubic (déceleration naturelle)
///   • disparition : easeIn (acceleration douce)
///   • morphing    : easeInOutCubic
/// ═══════════════════════════════════════════════════════════════════════════

class BeUIColors {
  BeUIColors._();

  // ── Surfaces ──────────────────────────────────────────────────────────────
  static const bgDark = Color(0xFF1A1B1F);
  static const bgLight = Color(0xFFF5F5F7);
  static const surfaceDark = Color(0xFF121316);
  static const surfaceLight = Color(0xFFFAFAFA);
  static const borderDark = Color(0xFF3A3A3A);
  static const borderLight = Color(0xFFDDDDDD);

  // ── Accents ───────────────────────────────────────────────────────────────
  static const accent = Color(0xFF6366F1);
  static const accentSoft = Color(0xFF8B5CF6);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF38BDF8);

  /// Accent adapté au thème.
  static Color accentOf(bool isDark) =>
      isDark ? accentSoft : accent;

  /// Couleur de bordure adaptée au thème.
  static Color borderOf(bool isDark) =>
      isDark ? borderDark : borderLight;

  /// Couleur de surface adaptée au thème.
  static Color surfaceOf(bool isDark) => isDark ? bgDark : bgLight;

  /// Couleur de surface profonde adaptée au thème.
  static Color deepSurfaceOf(bool isDark) =>
      isDark ? surfaceDark : surfaceLight;
}

class BeUIDurations {
  BeUIDurations._();

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 600);
  static const reveal = Duration(milliseconds: 450);
  static const pulse = Duration(milliseconds: 1200);
  static const rotate = Duration(milliseconds: 2400);
  static const shimmer = Duration(milliseconds: 1800);
  static const phraseCycle = Duration(milliseconds: 2600);
}

class BeUICurves {
  BeUICurves._();

  static const inCurve = Curves.easeIn;
  static const outCurve = Curves.easeOutCubic;
  static const morph = Curves.easeInOutCubic;
  static const spring = Curves.easeOutBack;
  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIPulsingSquare — le carré animé signature de beUI (style Replit).
///
/// Petit carré arrondi qui pulse (scale 1.0 → 1.18) avec une légère rotation
/// et une respiration d'opacité. C'est l'icône "l'agent travaille" de toute
/// la bibliothèque : ticker, loading states, approvals en attente.
///
/// Taille par défaut : 14px (discret, aligné sur une ligne de texte).
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIPulsingSquare extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const BeUIPulsingSquare({
    super.key,
    this.size = 14,
    required this.color,
    this.duration = BeUIDurations.pulse,
  });

  @override
  State<BeUIPulsingSquare> createState() => _BeUIPulsingSquareState();
}

class _BeUIPulsingSquareState extends State<BeUIPulsingSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
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
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Transform.rotate(
          angle: 0.0,
          child: Transform.scale(
            scale: 1.0 + 0.18 * t,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.75 + 0.25 * t),
                borderRadius: BorderRadius.circular(widget.size * 0.28),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.35 * t),
                    blurRadius: 6 * t + 2,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIRotatingSquare — variante rotation continue (loader compact).
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIRotatingSquare extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const BeUIRotatingSquare({
    super.key,
    this.size = 14,
    required this.color,
    this.duration = BeUIDurations.rotate,
  });

  @override
  State<BeUIRotatingSquare> createState() => _BeUIRotatingSquareState();
}

class _BeUIRotatingSquareState extends State<BeUIRotatingSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          border: Border.all(color: widget.color.withValues(alpha: 0.25), width: widget.size * 0.14),
          borderRadius: BorderRadius.circular(widget.size * 0.28),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.topCenter,
          widthFactor: 1.0,
          heightFactor: 0.45,
          child: Container(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(widget.size * 0.2),
            ),
          ),
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIShimmer — wrapper de texte/surface avec balayage lumineux.
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIShimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;

  const BeUIShimmer({
    super.key,
    required this.child,
    required this.baseColor,
    Color? highlightColor,
    this.duration = BeUIDurations.shimmer,
  }) : highlightColor = highlightColor ?? const Color(0x55FFFFFF);

  @override
  State<BeUIShimmer> createState() => _BeUIShimmerState();
}

class _BeUIShimmerState extends State<BeUIShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
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
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = (bounds.width * 2) * (_ctrl.value * 2 - 0.5);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlidingGradientTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double dx;
  const _SlidingGradientTransform(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIPopIn — apparition scale+fade à l'insertion (nouvelles cartes/lignes).
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIPopIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  const BeUIPopIn({
    super.key,
    required this.child,
    this.duration = BeUIDurations.reveal,
    this.delay = Duration.zero,
  });

  @override
  State<BeUIPopIn> createState() => _BeUIPopInState();
}

class _BeUIPopInState extends State<BeUIPopIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: BeUICurves.outCurve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}
