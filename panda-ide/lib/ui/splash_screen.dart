import 'package:flutter/material.dart';

/// PandaSplashScreen — Netflix-style splash screen for Panda IDE.
///
/// Shows:
///  1. Black background
///  2. Panda logo scales up with a subtle bounce (0 → 1.05 → 1.0)
///  3. "Panda IDE" text fades in below the logo
///  4. A white sweep flash sweeps across the screen
///  5. Calls [onComplete] to navigate to the next screen
class PandaSplashScreen extends StatefulWidget {
  /// Called when the animation finishes — navigate to the next screen here.
  final VoidCallback onComplete;

  const PandaSplashScreen({super.key, required this.onComplete});

  @override
  State<PandaSplashScreen> createState() => _PandaSplashScreenState();
}

class _PandaSplashScreenState extends State<PandaSplashScreen>
    with TickerProviderStateMixin {
  // Logo scale animation
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  // Text fade animation
  late final AnimationController _textCtrl;
  late final Animation<double> _textAnim;

  // Sweep flash animation
  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweepAnim;

  // Glow pulse animation
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    // ── 1. Logo scale-in with bounce ─────────────────────────────────────────
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.08)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 70),
      TweenSequenceItem(
          tween: Tween(begin: 1.08, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 30),
    ]).animate(_scaleCtrl);

    // ── 2. Text fade-in ───────────────────────────────────────────────────────
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textAnim = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);

    // ── 3. Glow pulse ────────────────────────────────────────────────────────
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    // ── 4. Sweep flash ───────────────────────────────────────────────────────
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _sweepAnim = CurvedAnimation(parent: _sweepCtrl, curve: Curves.easeOut);

    // ── Sequence ──────────────────────────────────────────────────────────────
    _startSequence();
  }

  Future<void> _startSequence() async {
    // Step 1: scale the logo in
    await _scaleCtrl.forward();

    // Step 2: fade in text and start glow simultaneously
    await Future.wait([
      _textCtrl.forward(),
      _glowCtrl.forward(),
    ]);

    // Hold for a moment
    await Future.delayed(const Duration(milliseconds: 600));

    // Step 3: sweep flash
    await _sweepCtrl.forward();

    // Done — navigate
    widget.onComplete();
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _textCtrl.dispose();
    _sweepCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background gradient ──────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [
                  Color(0xff0d1a2d),
                  Colors.black,
                ],
              ),
            ),
          ),

          // ── Logo + text ──────────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with glow
                AnimatedBuilder(
                  animation: Listenable.merge([_scaleAnim, _glowAnim]),
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnim.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xff5090c8)
                                  .withOpacity(0.6 * _glowAnim.value),
                              blurRadius: 40 * _glowAnim.value,
                              spreadRadius: 8 * _glowAnim.value,
                            ),
                          ],
                        ),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: Color(0xff1a3a55),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'P',
                              style: TextStyle(
                                color: Color(0xff5090c8),
                                fontSize: 64,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // "Panda IDE" text
                FadeTransition(
                  opacity: _textAnim,
                  child: Column(
                    children: [
                      const Text(
                        'Panda IDE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Code anywhere.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Sweep flash overlay ───────────────────────────────────────────
          AnimatedBuilder(
            animation: _sweepAnim,
            builder: (context, _) {
              if (_sweepAnim.value == 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: Opacity(
                  opacity: (1 - _sweepAnim.value).clamp(0.0, 0.7),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1.0 + 2 * _sweepAnim.value,
                            -0.5 + _sweepAnim.value),
                        end: Alignment(
                            0.3 + 2 * _sweepAnim.value, 1.0),
                        colors: const [
                          Colors.transparent,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
