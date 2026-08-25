import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/home.dart';
import '../ui/permission_screen.dart';
import '../ui/splash_screen.dart';

/// Splash → PermissionScreen (first time) → Home.
/// Setup now runs inline on the splash screen.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _navigated = false;

  void _onSetupComplete() {
    if (!mounted || _navigated) return;
    _navigated = true;

    // Web / non-Android: straight to home
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, __, ___, child) =>
              FadeTransition(opacity: __, child: child),
        ),
      );
      return;
    }

    // Android: check if permissions were shown
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final permShown = prefs.getBool('permissions_shown') ?? false;

      if (!permShown) {
        // First time: PermissionScreen → Home (setup already done on splash)
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PermissionScreen(),
            transitionsBuilder: (_, __, ___, child) =>
                FadeTransition(opacity: __, child: child),
          ),
        );
      } else {
        // Already set up: straight to Home
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, __, ___, child) =>
                FadeTransition(opacity: __, child: child),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PandaSplashScreen(onComplete: _onSetupComplete);
  }
}
