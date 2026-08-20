import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
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

  /// Lightweight background init — does NOT gate navigation.
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

  /// Called the instant the splash animation finishes — navigate NOW.
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

    // Android → SetupScreen with progress bar + live logs
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SetupScreen(),
        transitionsBuilder: (_, __, ___, child) =>
            FadeTransition(opacity: __, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PandaSplashScreen(onComplete: _onAnimationComplete);
  }
}
