import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/alpine_setup.dart';
import '../utils/constants.dart';
import '../utils/panda_log.dart';
import 'home.dart';
import 'permission_screen.dart';
import '../terminal/panda_bridge.dart';

/// A step in the setup process.
class _SetupStep {
  final String label;
  final String description;
  bool completed;
  bool active;
  bool failed;
  String? error;

  _SetupStep({
    required this.label,
    required this.description,
    this.completed = false,
    this.active = false,
    this.failed = false,
    this.error,
  });
}

/// SetupScreen — First-time setup screen for Panda IDE.
///
/// Shows real-time progress of Alpine rootfs extraction and environment
/// initialization, with a live log view for debugging.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {
  final List<_SetupStep> _steps = [];
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _setupComplete = false;
  bool _setupError = false;
  String _currentStepLabel = '';
  int _currentStepIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initSteps();
    _startSetup();
  }

  void _initSteps() {
    _steps.addAll([
      _SetupStep(label: 'Storage', description: 'Creating directories'),
      _SetupStep(label: 'Certificates', description: 'Installing CA certificates'),
      _SetupStep(label: 'Alpine Linux', description: 'Extracting rootfs (first install only)'),
      _SetupStep(label: 'Runtime', description: 'Configuring runtime environment'),
      _SetupStep(label: 'Tools', description: 'Injecting Panda tools'),
      _SetupStep(label: 'Services', description: 'Starting Panda services'),
    ]);
  }

  void _addLog(String message) {
    final ts = DateTime.now().toString().substring(11, 19);
    setState(() => _logs.add('[$ts] $message'));
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setStepState(int index, {bool active = false, bool completed = false, bool failed = false, String? error}) {
    if (index < 0 || index >= _steps.length) return;
    setState(() {
      _steps[index].active = active;
      _steps[index].completed = completed;
      _steps[index].failed = failed;
      _steps[index].error = error;
      if (active) _currentStepIndex = index;
    });
  }

  Future<void> _startSetup() async {
    final sw = Stopwatch()..start();
    _addLog('Panda IDE setup started');

    try {
      // Step 0: Create directories
      _setStepState(0, active: true);
      _addLog('Creating storage directories...');
      await _createDirectories();
      _setStepState(0, completed: true);
      _addLog('Directories created (${sw.elapsedMilliseconds}ms)');

      // Step 1: Install certificates
      _setStepState(1, active: true);
      _addLog('Installing CA certificates...');
      await _installCertificates();
      _setStepState(1, completed: true);
      _addLog('Certificates installed (${sw.elapsedMilliseconds}ms)');

      // Step 2: Alpine rootfs
      _setStepState(2, active: true);
      _addLog('Setting up Alpine Linux...');
      await _setupAlpine(sw);
      _setStepState(2, completed: true);
      _addLog('Alpine Linux ready (${sw.elapsedMilliseconds}ms)');

      // Step 3: Runtime files
      _setStepState(3, active: true);
      _addLog('Configuring runtime environment...');
      await _setupRuntime();
      _setStepState(3, completed: true);
      _addLog('Runtime configured (${sw.elapsedMilliseconds}ms)');

      // Step 4: Panda tools
      _setStepState(4, active: true);
      _addLog('Injecting Panda tools...');
      await _injectTools();
      _setStepState(4, completed: true);
      _addLog('Tools injected (${sw.elapsedMilliseconds}ms)');

      // Step 5: Services
      _setStepState(5, active: true);
      _addLog('Starting Panda services...');
      await _startServices();
      _setStepState(5, completed: true);
      _addLog('Services started (${sw.elapsedMilliseconds}ms)');

      _addLog('✅ Setup complete in ${sw.elapsedMilliseconds}ms');
      setState(() => _setupComplete = true);

      // Wait a moment then navigate
      await Future.delayed(const Duration(milliseconds: 800));
      _navigateToApp();
    } catch (e, stack) {
      _addLog('❌ Setup failed: $e');
      _addLog('Stack: $stack');
      PandaLog.e('SetupScreen', 'Setup failed: $e', error: e, stackTrace: stack);
      setState(() => _setupError = true);
      _setStepState(_currentStepIndex, failed: true, error: e.toString());
    }
  }

  Future<void> _createDirectories() async {
    for (final path in [binDir, libDir, homeDir, '$binDir/git-core', '$appDir/Templates', '$appDir/Logs']) {
      await Directory(path).create(recursive: true).catchError((_) {});
    }
    _addLog('Created: bin, lib, Home, git-core, Templates, Logs');
  }

  Future<void> _installCertificates() async {
    if (!File('$certDir/cacert.pem').existsSync()) {
      Directory(certDir).createSync(recursive: true);
      final certBytes = await rootBundle.load('assets/certificates/cacert.pem');
      File('$certDir/cacert.pem').writeAsBytesSync(certBytes.buffer.asUint8List());
      _addLog('CA certificates installed');
    } else {
      _addLog('CA certificates already present');
    }
  }

  Future<void> _setupAlpine(Stopwatch sw) async {
    final alpineDir = Directory('${runtimesDir}/alpine-linux');
    final marker = File('${alpineDir.path}/.panda-rootfs-version');

    if (AlpineSetup.isRootfsComplete() && marker.existsSync()) {
      _addLog('Alpine rootfs already extracted, skipping');
      return;
    }

    _addLog('Extracting alpine-rootfs.tar.gz...');
    _addLog('This may take a moment on first install...');

    // Use AlpineSetup with progress logging
    final result = await AlpineSetup.ensureAlpineRootfs(
      force: !marker.existsSync(),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _addLog('⚠️ Alpine extraction timed out after 60s');
        return false;
      },
    );

    if (!result) {
      _addLog('⚠️ Alpine extraction failed: ${AlpineSetup.lastError}');
      _addLog('The terminal may not work correctly without Alpine');
      // Don't throw — let setup continue, terminal will be degraded
    } else {
      _addLog('Alpine rootfs extracted and validated');
    }
  }

  Future<void> _setupRuntime() async {
    final sharedPath = await NativeChannel.getLibraryPath().timeout(
      const Duration(seconds: 5),
      onTimeout: () => '',
    );
    _addLog('Native lib path: ${sharedPath.isNotEmpty ? sharedPath : "(unavailable)"}');

    if (sharedPath.isNotEmpty) {
      // Create symlinks for critical binaries
      final criticalLinks = [
        (src: '$sharedPath/libbash.so', dst: '$binDir/bash'),
        (src: '$sharedPath/libbash.so', dst: '$binDir/sh'),
        (src: '$sharedPath/libccls.so', dst: '$binDir/ccls'),
      ];
      int created = 0;
      for (final link in criticalLinks) {
        final linkFile = Link(link.dst);
        if (!linkFile.existsSync() || (await linkFile.target() != link.src)) {
          try {
            await linkFile.create(link.src, recursive: true);
            created++;
          } catch (_) {}
        }
      }
      _addLog('Created $created critical symlinks');
    }
  }

  Future<void> _injectTools() async {
    final alpineDir = '${runtimesDir}/alpine-linux';
    if (!Directory(alpineDir).existsSync()) {
      _addLog('Alpine not available, skipping tool injection');
      return;
    }

    final localBinDir = Directory('$alpineDir/usr/local/bin');
    if (!localBinDir.existsSync()) localBinDir.createSync(recursive: true);

    // Phase 1: Panda CLI
    final pandaCli = File('${localBinDir.path}/panda');
    pandaCli.writeAsStringSync('#!/bin/sh\necho "\$@" | nc 127.0.0.1 ${PandaBridge.port}\n');
    Process.runSync('chmod', ['+x', pandaCli.path]);
    _addLog('Panda CLI bridge installed');

    // Phase 2: Native shims
    final nativeBinaries = ['node', 'npm', 'npx', 'git', 'python', 'python3', 'pip', 'pip3', 'clang', 'clang++'];
    int shimsInstalled = 0;
    for (final bin in nativeBinaries) {
      final shim = File('${localBinDir.path}/$bin');
      final native = File('$binDir/$bin');
      if (native.existsSync() && !shim.existsSync()) {
        shim.writeAsStringSync('#!/bin/sh\nexec $binDir/$bin "\$@"\n');
        Process.runSync('chmod', ['+x', shim.path]);
        shimsInstalled++;
      }
    }
    _addLog('Native shims: $shimsInstalled installed');
  }

  Future<void> _startServices() async {
    // Start PandaBridge
    _addLog('Starting PandaBridge on port ${PandaBridge.port}');
    PandaBridge.start().timeout(
      const Duration(seconds: 10),
      onTimeout: () => _addLog('⚠️ PandaBridge start timed out'),
    ).catchError((e) => _addLog('⚠️ PandaBridge error: $e'));
  }

  void _navigateToApp() {
    if (!mounted) return;
    // Check permissions then proceed to main app
    SharedPreferences.getInstance().then((prefs) {
      final permShown = prefs.getBool('permissions_shown') ?? false;
      if (!mounted) return;
      if (permShown) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, _) => const SelectType(),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, _) => const PermissionScreen(),
            transitionsBuilder: (context, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a0a0a),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildStepsList()),
            _buildLogView(),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Row(
        children: [
          // Panda logo
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) {
              return Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff1a3a55),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff5090c8)
                          .withValues(alpha: 0.3 * _pulseAnim.value),
                      blurRadius: 12 * _pulseAnim.value,
                      spreadRadius: 2 * _pulseAnim.value,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'P',
                    style: TextStyle(
                      color: Color(0xff5090c8),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Setting Up Panda IDE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _setupComplete
                      ? 'Ready to go!'
                      : _setupError
                          ? 'Setup encountered an error'
                          : 'Preparing your development environment',
                  style: TextStyle(
                    color: _setupError
                        ? const Color(0xffcf6679)
                        : _setupComplete
                            ? const Color(0xff5090c8)
                            : Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (_setupComplete)
            const Icon(Icons.check_circle, color: Color(0xff5090c8), size: 32),
          if (_setupError)
            const Icon(Icons.error_outline, color: Color(0xffcf6679), size: 32),
        ],
      ),
    );
  }

  Widget _buildStepsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _steps.length,
      itemBuilder: (context, index) {
        final step = _steps[index];
        return _buildStepTile(step, index);
      },
    );
  }

  Widget _buildStepTile(_SetupStep step, int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: step.active
            ? const Color(0xff1a2a3a).withValues(alpha: 0.8)
            : step.completed
                ? const Color(0xff0d1a2d).withValues(alpha: 0.4)
                : step.failed
                    ? const Color(0xff2d1520).withValues(alpha: 0.6)
                    : const Color(0xff1a1a1a),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: step.active
              ? const Color(0xff5090c8).withValues(alpha: 0.4)
              : step.completed
                  ? const Color(0xff5090c8).withValues(alpha: 0.2)
                  : step.failed
                      ? const Color(0xffcf6679).withValues(alpha: 0.3)
                      : const Color(0xff2a2a2a),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildStepIcon(step),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    color: step.completed
                        ? const Color(0xff5090c8)
                        : step.failed
                            ? const Color(0xffcf6679)
                            : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.error ?? step.description,
                  style: TextStyle(
                    color: step.failed
                        ? const Color(0xffcf6679).withValues(alpha: 0.8)
                        : Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (step.active)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0xff5090c8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIcon(_SetupStep step) {
    if (step.completed) {
      return const Icon(Icons.check_circle, color: Color(0xff5090c8), size: 20);
    }
    if (step.failed) {
      return const Icon(Icons.error, color: Color(0xffcf6679), size: 20);
    }
    if (step.active) {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, __) => Icon(
          Icons.settings,
          color: Color.lerp(
            const Color(0xff5090c8),
            const Color(0xff7aabdd),
            _pulseAnim.value,
          ),
          size: 20,
        ),
      );
    }
    return const Icon(Icons.circle_outlined, color: Color(0xff3a3a3a), size: 20);
  }

  Widget _buildLogView() {
    return Expanded(
      flex: 2,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        decoration: BoxDecoration(
          color: const Color(0xff0d0d0d),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xff2a2a2a)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Log header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xff1a1a1a),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Color(0xff5090c8), size: 14),
                  const SizedBox(width: 6),
                  const Text(
                    'Setup Logs',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_logs.length} lines',
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
                ],
              ),
            ),
            // Log content
            Expanded(
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.all(10),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final line = _logs[index];
                  final isError = line.contains('❌') || line.contains('error');
                  final isWarning = line.contains('⚠️');
                  final isSuccess = line.contains('✅');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'hack',
                        fontSize: 11,
                        height: 1.5,
                        color: isError
                            ? const Color(0xffcf6679)
                            : isWarning
                                ? const Color(0xffffb74d)
                                : isSuccess
                                    ? const Color(0xff81c784)
                                    : const Color(0xff888888),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          // Copy logs button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _logs.isEmpty
                  ? null
                  : () {
                      final logText = _logs.join('\n');
                      Clipboard.setData(ClipboardData(text: logText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copied to clipboard'),
                          backgroundColor: Color(0xff1a3a55),
                        ),
                      );
                    },
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('Copy Logs', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Color(0xff3a3a3a)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Save logs to file button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _logs.isEmpty
                  ? null
                  : () async {
                      try {
                        final logDir = Directory(pandaLogsDir);
                        if (!logDir.existsSync()) await logDir.create(recursive: true);
                        final logFile = File('${logDir.path}/setup-${DateTime.now().millisecondsSinceEpoch}.log');
                        await logFile.writeAsString(_logs.join('\n'));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Logs saved to ${logFile.path}'),
                              backgroundColor: const Color(0xff1a3a55),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save: $e'),
                              backgroundColor: const Color(0xff5c1826),
                            ),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.save_alt, size: 14),
              label: const Text('Save Logs', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Color(0xff3a3a3a)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
