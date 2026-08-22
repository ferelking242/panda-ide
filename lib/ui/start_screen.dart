import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/home.dart';
import '../ui/permission_screen.dart';
import '../ui/splash_screen.dart';
import 'setup_screen.dart';

/// Splash → PermissionScreen (first time) → SetupScreen → Home.
/// No background init. No heavy work. Just navigation.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _navigated = false;

  /// Called the instant the splash animation finishes.
  void _onAnimationComplete() {
    if (!mounted || _navigated) return;
    _navigated = true;

    // Web / non-Android : l'IDE complet tourne directement (terminal proot
    // masqué par des gardes kIsWeb dans home.dart) — pas d'écrans natifs.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SelectType(),
          transitionsBuilder: (_, __, ___, child) =>
              FadeTransition(opacity: __, child: child),
        ),
      );
      return;
    }

    // Android: check if permissions were already shown
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final permShown = prefs.getBool('permissions_shown') ?? false;

      if (!permShown) {
        // First time: PermissionScreen → SetupScreen → Home
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PermissionScreen(),
            transitionsBuilder: (_, __, ___, child) =>
                FadeTransition(opacity: __, child: child),
          ),
        );
      } else {
        // Permissions done: straight to SetupScreen → Home
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SetupScreen(),
            transitionsBuilder: (_, __, ___, child) =>
                FadeTransition(opacity: __, child: child),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PandaSplashScreen(onComplete: _onAnimationComplete);
  }
}
