import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
import '../ui/splash_screen.dart';
import '../ui/permission_screen.dart';
import 'setup_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: logger + prefs only. Never blocks navigation.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _backgroundInit();
    }
  }

  Future<void> _backgroundInit() async {
    try {
      await NativeChannel.getExternalMediaDir().timeout(
            const Duration(seconds: 3),
            onTimeout: () => '',
          );
    } catch (_) {}
    try {
      for (final path in [binDir, libDir, homeDir]) {
        if (!Directory(path).existsSync()) {
          await Directory(path).create(recursive: true);
        }
      }
      await Directory(appDir).create(recursive: true);
      await setupFilesDir();
      await setupProjectDir();
      await setupTempDir();
      await PandaLog.initFileLogging();
      await ensureCopilotEnabledPrefInitialized();
      await ensureCopilotSignedPrefInitialized();
    } catch (e) {
      PandaLog.w('StartScreen', 'Background init partial failure: $e');
    }
  }

  /// Called the instant the splash animation finishes.
  void _onAnimationComplete() {
    if (!mounted || _navigated) return;
    _navigated = true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
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
        // First time: PermissionScreen → then SetupScreen handles everything
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PermissionScreen(),
            transitionsBuilder: (_, __, ___, child) =>
                FadeTransition(opacity: __, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      } else {
        // Permissions already done: straight to SetupScreen
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SetupScreen(),
            transitionsBuilder: (_, __, ___, child) =>
                FadeTransition(opacity: __, child: child),
            transitionDuration: const Duration(milliseconds: 400),
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
