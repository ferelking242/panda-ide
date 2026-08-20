import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:panda/bloc/ui_bloc/ui_bloc.dart';
import 'package:panda/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/home.dart';
import '../ui/splash_screen.dart';
import '../ui/permission_screen.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
import 'setup_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _animationDone = false;
  bool _initDone = false;
  bool _initError = false;
  DateTime? _initStartTime;

  /// Maximum time we wait for initialization before forcing navigation.
  static const Duration _maxInitDuration = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _initStartTime = DateTime.now();
    _safeInitialize();
    // Safety fallback: force navigation even if init hangs.
    Future.delayed(_maxInitDuration, _forceNavigateIfStuck);
  }

  /// If we're still on the splash after [_maxInitDuration], force navigation
  /// so the user is never permanently stuck.
  void _forceNavigateIfStuck() {
    if (!mounted) return;
    if (!_initDone || !_animationDone) {
      PandaLog.w('StartScreen',
          'Safety fallback: forcing navigation after $_maxInitDuration');
      _animationDone = true;
      if (!_initDone) {
        setState(() => _initError = true);
      }
      setState(() => _initDone = true);
      _maybeNavigate();
    }
  }

  Future<void> _safeInitialize() async {
    PandaLog.i('StartScreen', '_safeInitialize started');
    try {
      // Minimal init: just directories and logger. All heavy work (symlinks,
      // Alpine, tools, services) is done inside SetupScreen with visible
      // progress so the user is never staring at a black splash.
      await _initializeApp().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          PandaLog.w('StartScreen', '_initializeApp() TIMEOUT after 10s');
        },
      );
    } catch (e, stack) {
      PandaLog.e('StartScreen', 'Startup failed: $e', error: e);
      debugPrint("Startup error: $e\n$stack");
      if (!mounted) return;
      setState(() => _initError = true);
      try {
        PandaNotifications.show(
          context: context,
          title: 'Startup Error',
          message: e.toString(),
          isError: true,
        );
      } catch (_) {}
    }
    final elapsed = _initStartTime != null
        ? DateTime.now().difference(_initStartTime!)
        : Duration.zero;
    PandaLog.i('StartScreen', '_safeInitialize done in ${elapsed.inMilliseconds}ms');
    if (mounted) setState(() => _initDone = true);
    _maybeNavigate();
  }

  void _onAnimationComplete() {
    _animationDone = true;
    _maybeNavigate();
  }

  void _maybeNavigate() {
    if (!_animationDone || !_initDone) return;
    if (!mounted) return;
    _navigate();
  }

  Future<void> _navigate() async {
    if (!mounted) return;

    // On web / non-Android go straight to the editor
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (context, animation, _) => const SelectType(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ));
      return;
    }

    // Android: always route through SetupScreen which handles everything
    // (first-install Alpine extraction AND subsequent symlinks / services)
    // with a visible progress bar and live logs.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => const SetupScreen(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  /// Minimal init — only things required before the first frame:
  /// external media dir, directories, logger, shared-prefs.
  /// All heavy lifting (symlinks, Alpine, tools, PandaBridge) is done
  /// inside SetupScreen where the user can see progress.
  Future<void> _initializeApp() async {
    PandaLog.i('StartScreen', 'Initialization started');
    final sw = Stopwatch()..start();

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await ensureCopilotEnabledPrefInitialized();
      await ensureCopilotSignedPrefInitialized();
      return;
    }

    try {
      await NativeChannel.getExternalMediaDir().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          PandaLog.w('StartScreen', 'getExternalMediaDir timed out after 5s');
          return '';
        },
      );
    } catch (e) {
      PandaLog.w('StartScreen', 'getExternalMediaDir failed: $e');
    }

    // Create basic directories required before SetupScreen
    for (final path in [binDir, libDir, '$binDir/git-core', homeDir]) {
      final dir = Directory(path);
      if (!dir.existsSync()) await dir.create(recursive: true);
    }

    await Directory(appDir).create(recursive: true);
    await setupFilesDir();
    await setupProjectDir();
    await setupTempDir();
    await Directory('$appDir/Templates').create(recursive: true);
    await Directory('$appDir/Logs').create(recursive: true);
    await PandaLog.initFileLogging();
    await ensureCopilotEnabledPrefInitialized();
    await ensureCopilotSignedPrefInitialized();

    PandaLog.i('StartScreen', '[${sw.elapsedMilliseconds}ms] Minimal init complete');
  }

  @override
  Widget build(BuildContext context) {
    return PandaSplashScreen(onComplete: _onAnimationComplete);
  }
}
