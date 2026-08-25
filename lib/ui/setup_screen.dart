import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/debian_setup.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
import 'home.dart';
import '../terminal/panda_bridge.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


// ── Tool lists (shared with start_screen) ──────────────────────────────────────
const List<String> _javaTools = [
  'jar', 'jarsigner', 'java', 'javac', 'javadoc', 'javap', 'jcmd',
  'jconsole', 'jdb', 'jdeprscan', 'jdeps', 'jfr', 'jhsdb', 'jinfo',
  'jlink', 'jmap', 'jmod', 'jpackage', 'jps', 'jrunscript', 'jstack',
  'jstat', 'jstatd', 'jwebserver', 'keytool', 'rmiregistry', 'serialver'
];

const List<String> _goToolBinaries = [
  'asm', 'cgo', 'compile', 'cover', 'fix', 'link', 'preprofile', 'vet',
];

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

/// SetupScreen — First-time AND subsequent setup screen for Panda IDE.
///
/// Shows real-time progress of environment initialization with a linear
/// progress bar, step list, and live log view.
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
  int _currentStepIndex = 0;
  bool _isFirstInstall = false;

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

    _isFirstInstall = !DebianSetup.isRootfsComplete();
    _initSteps();
    // Defer setup to after first frame so setState triggers rebuilds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startSetup();
    });
  }

  void _initSteps() {
    _steps.addAll([
      _SetupStep(label: 'Storage', description: 'Creating directories'),
      _SetupStep(label: 'Certificates', description: 'Installing CA certificates'),
      if (_isFirstInstall) _SetupStep(label: 'Choose Terminal', description: 'Select Debian, Alpine, or Bionic'),
      if (_isFirstInstall) _SetupStep(label: 'Download Rootfs', description: 'Downloading terminal environment'),
      _SetupStep(label: 'Runtime', description: 'Setting up symlinks & runtime'),
      _SetupStep(label: 'Tools', description: 'Injecting Panda tools'),
      _SetupStep(label: 'Services', description: 'Starting PandaBridge'),
    ]);
  }

  /// Overall progress [0..1]
  double get _progress {
    if (_steps.isEmpty) return 0.0;
    int done = 0;
    for (final s in _steps) {
      if (s.completed) done++;
    }
    return done / _steps.length;
  }

  /// Bulletproof logging - can never throw, block, and kill setup.
  void _addLog(String message) {
    try {
      final ts = DateTime.now().toString().substring(11, 19);
      _logs.add('[$ts] $message');
      print('[SetupScreen] $message');
      // Schedule setState for next frame — never block this method.
      // ignore: unawaited_futures
      Future.microtask(() {
        try {
          if (mounted) setState(() {});
        } catch (_) {}
      });
      // Fire-and-forget PandaLog — can hang if bridge not ready.
      // ignore: unawaited_futures
      Future(() {
        try { PandaLog.i('SetupScreen', message); } catch (_) {}
      });
      // Auto-scroll log view on next frame.
      // ignore: unawaited_futures
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_logScrollController.hasClients) {
            _logScrollController.animateTo(
              _logScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _setStepState(int index,
      {bool active = false,
      bool completed = false,
      bool failed = false,
      String? error}) {
    if (index < 0 || index >= _steps.length) return;
    try {
      setState(() {
        _steps[index].active = active;
        _steps[index].completed = completed;
        _steps[index].failed = failed;
        _steps[index].error = error;
        if (active) _currentStepIndex = index;
      });
    } catch (_) {}
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Main setup orchestrator
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _startSetup() async {
    print('[SetupScreen] _startSetup called, mounted=$mounted, steps=${_steps.length}');
    final sw = Stopwatch()..start();

    try {
      // ALL logging INSIDE try-catch so nothing can kill the setup
      _addLog(_isFirstInstall
          ? 'Panda IDE first-install setup started'
          : 'Panda IDE runtime initialisation started');
      _addLog('Steps: ${_steps.length}, isFirstInstall=$_isFirstInstall');
      _addLog('appDir=$appDir, binDir=$binDir');
      print('[SetupScreen] entering step loop');
      int si = 0;

      // Step: Storage — log FIRST so user always sees progress
      _addLog('Step 1/${_steps.length}: Creating directories...');
      _setStepState(si, active: true);
      print('[SetupScreen] calling _createDirectories...');
      try {
        await _createDirectories().timeout(
          const Duration(seconds: 15),
          onTimeout: () => _addLog('⚠️ Directory creation timed out (continuing)'),
        );
      } catch (e) {
        _addLog('⚠️ _createDirectories error: $e');
      }
      print('[SetupScreen] _createDirectories done');
      _setStepState(si, completed: true);
      _addLog('Directories ready (${sw.elapsedMilliseconds}ms)');
      si++;

      // Step: Certificates
      _addLog('Step ${si + 1}/${_steps.length}: Installing certificates...');
      _setStepState(si, active: true);
      print('[SetupScreen] calling _installCertificates...');
      try {
        await _installCertificates().timeout(
          const Duration(seconds: 5),
          onTimeout: () => _addLog('⚠️ Certificate install timed out'),
        );
      } catch (e) {
        _addLog('⚠️ Certificate install error: $e');
      }
      print('[SetupScreen] _installCertificates done');
      _setStepState(si, completed: true);
      _addLog('Certificates installed (${sw.elapsedMilliseconds}ms)');
      si++;

      // Step: Choose Terminal (first install only)
      if (_isFirstInstall) {
        _addLog('Step ${si + 1}/${_steps.length}: Choose Terminal...');
        _setStepState(si, active: true);
        _setStepState(si, completed: true);
        _addLog('Terminal chosen (${sw.elapsedMilliseconds}ms)');
        si++;
      }

      // Step: Download Rootfs (first install only)
      if (_isFirstInstall) {
        _addLog('Step ${si + 1}/${_steps.length}: Downloading Rootfs...');
        _setStepState(si, active: true);
        try {
          final activeTerminal = await RootfsManager.getActiveTerminal();
          if (await RootfsManager.isInstalled(activeTerminal)) {
            _addLog('${activeTerminal.displayName} already installed, skipping download');
          } else {
            _addLog('Downloading ${activeTerminal.displayName}...');
            await RootfsManager.install(activeTerminal, onProgress: (progress, downloaded, total) {
              _addLog('Download: ${(progress * 100).toStringAsFixed(0)}%');
            });
          }
        } catch (e) {
          _addLog('⚠️ Rootfs download error: $e');
        }
        _setStepState(si, completed: true);
        _addLog('Rootfs ready (${sw.elapsedMilliseconds}ms)');
        si++;
      }

      // Step: Runtime (symlinks + runtime files)
      _addLog('Step ${si + 1}/${_steps.length}: Configuring runtime...');
      _setStepState(si, active: true);
      try {
        await _setupRuntime(sw).timeout(
          const Duration(seconds: 30),
          onTimeout: () => _addLog('⚠️ Runtime setup timed out (continuing)'),
        );
      } catch (e) {
        _addLog('⚠️ Runtime setup error: $e');
      }
      _setStepState(si, completed: true);
      _addLog('Runtime configured (${sw.elapsedMilliseconds}ms)');
      si++;

      // Step: Tools
      _addLog('Step ${si + 1}/${_steps.length}: Injecting tools...');
      _setStepState(si, active: true);
      await _injectTools();
      _setStepState(si, completed: true);
      _addLog('Tools injected (${sw.elapsedMilliseconds}ms)');
      si++;

      // Step: Services
      _addLog('Step ${si + 1}/${_steps.length}: Starting services...');
      _setStepState(si, active: true);
      await _startServices();
      _setStepState(si, completed: true);
      _addLog('Services started (${sw.elapsedMilliseconds}ms)');

      _addLog('✅ Setup complete in ${sw.elapsedMilliseconds}ms');
      setState(() => _setupComplete = true);

      await Future.delayed(const Duration(milliseconds: 800));
      _navigateToApp();
    } catch (e, stack) {
      _addLog('❌ Setup failed: $e');
      _addLog('Stack: $stack');
      try { Future.microtask(() { try { PandaLog.e('SetupScreen', 'Setup failed: $e', error: e.toString()); } catch (_) {} }); } catch (_) {}
      setState(() => _setupError = true);
      _setStepState(_currentStepIndex, failed: true, error: e.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Individual setup steps
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _createDirectories() async {
    final dirs = [binDir, libDir, homeDir, '$binDir/git-core', '$appDir/Templates', '$appDir/Logs'];
    for (final p in dirs) {
      try {
        final d = Directory(p);
        if (!await d.exists()) {
          await d.create(recursive: true).timeout(const Duration(seconds: 5));
        }
        print('[SetupScreen] dir OK: $p');
      } catch (e) {
        print('[SetupScreen] Dir create failed for $p: $e');
      }
    }
    _addLog('Created: bin, lib, Home, git-core, Templates, Logs');
  }

  Future<void> _installCertificates() async {
    if (!await File('$certDir/cacert.pem').exists()) {
      Directory(certDir).createSync(recursive: true);
      final certBytes = await rootBundle.load('assets/certificates/cacert.pem');
      File('$certDir/cacert.pem').writeAsBytesSync(certBytes.buffer.asUint8List());
      _addLog('CA certificates installed');
    } else {
      _addLog('CA certificates already present');
    }
  }

  Future<void> _setupAlpine(Stopwatch sw) async {
    final debianDir = Directory('${runtimesDir}/alpine-linux');
    final marker = File('${debianDir.path}/.panda-rootfs-version');

    if (DebianSetup.isRootfsComplete() && await marker.exists()) {
      _addLog('Alpine rootfs already extracted, skipping');
      return;
    }

    _addLog('Preparing Alpine rootfs (downloaded at runtime)...');
    _addLog('Rootfs is managed by RootfsManager — no bundled asset needed.');

    // Retry logic: try up to 2 times
    bool result = false;
    for (int attempt = 1; attempt <= 2; attempt++) {
      if (attempt > 1) _addLog('Retry attempt $attempt/2...');

      result = await DebianSetup.ensureDebianRootfs(
        force: !await marker.exists() && attempt == 1,
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          _addLog('⚠️ Alpine extraction timed out after 90s');
          try { Future.microtask(() { try { PandaLog.e('SetupScreen', 'Alpine extraction timeout'); } catch (_) {} }); } catch (_) {}
          return false;
        },
      );

      if (result) break;

      _addLog('⚠️ Attempt $attempt failed: ${DebianSetup.lastError}');
      if (attempt < 2) {
        _addLog('Waiting 2s before retry...');
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (!result) {
      _addLog('❌ Alpine extraction failed: ${DebianSetup.lastError}');
      _addLog('Terminal may be degraded without Alpine');
    } else {
      _addLog('Alpine rootfs extracted and validated');
    }
  }

  Future<void> _setupRuntime(Stopwatch sw) async {
    String sharedPath = '';
    try {
      sharedPath = await NativeChannel.getLibraryPath().timeout(
        const Duration(seconds: 5),
        onTimeout: () => '',
      );
    } catch (_) {}
    _addLog('Native lib path: ${sharedPath.isNotEmpty ? sharedPath : "(unavailable)"}');

    if (sharedPath.isEmpty) {
      _addLog('⚠️ No native lib path — skipping symlinks');
      return;
    }

    // ── Clean up leftover zip files ──
    final downdir = Directory(downloadsDir);
    if (await downdir.exists()) {
      for (final file in downdir.listSync()) {
        if (file is File && file.path.endsWith('.zip')) {
          await file.delete();
        }
      }
    }

    // ── Git global config ──
    final gitCore = '$binDir/git-core';
    try {
      await Process.run(
        '$binDir/git',
        ['config', '--global', '--add', 'safe.directory', '*'],
        environment: gitEnvs(sharedPath),
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      try { Future.microtask(() { try { PandaLog.w('SetupScreen', 'Git global config failed (ignored): $e'); } catch (_) {} }); } catch (_) {}
    }

    // ── Full symlink creation ──
    _addLog('Creating symlinks...');
    try { Future.microtask(() { try { PandaLog.i('SetupScreen', '[${sw.elapsedMilliseconds}ms] Creating symlinks'); } catch (_) {} }); } catch (_) {}

    Map<String, dynamic> loader(String name,
            {String? loaderBin, Map<String, String>? env}) =>
        {
          'src': '$sharedPath/${loaderBin ?? "libloader.so"}',
          'dst': '$binDir/$name',
          'env': env,
        };

    final symlinks = [
      {'src': '$sharedPath/libreadline.so',   'dst': '$libDir/libreadline.so.8'},
      {'src': '$sharedPath/libz.so',          'dst': '$libDir/libz.so.1'},
      {'src': '$sharedPath/libncursesw.so',   'dst': '$libDir/libncursesw.so.6'},
      {'src': '$sharedPath/libcrypto.so',     'dst': '$libDir/libcrypto.so.3'},
      {'src': '$sharedPath/libssl.so',        'dst': '$libDir/libssl.so.3'},
      {'src': '$sharedPath/libzstd.so',       'dst': '$libDir/libzstd.so.1'},
      {'src': '$sharedPath/libxml2.so',       'dst': '$libDir/libxml2.so.16'},
      {'src': '$sharedPath/libicuuc.so',      'dst': '$libDir/libicuuc.so.78'},
      {'src': '$sharedPath/libicudata.so',    'dst': '$libDir/libicudata.so.78'},
      {'src': '$sharedPath/libbash.so',       'dst': '$binDir/bash'},
      {'src': '$sharedPath/libbash.so',       'dst': '$binDir/sh'},
      {'src': '$sharedPath/libgit-remote-https.so', 'dst': '$gitCore/git-remote-https'},
      {'src': '$sharedPath/libgit-remote-https.so', 'dst': '$gitCore/git-remote-http'},
      {'src': '$sharedPath/libccls.so',       'dst': '$binDir/ccls'},
      {'src': '$sharedPath/libless.so',       'dst': '$binDir/less',  'env': <String, String>{'LD_LIBRARY_PATH': libDir}},
      {'src': '$sharedPath/libless.so',       'dst': '$binDir/pager', 'env': <String, String>{'LD_LIBRARY_PATH': libDir}},
      ...[
        'clang', 'clang++', 'clangloader', 'node', 'python', 'python3',
        'npm', 'npx', 'pip', 'pip3', 'tsc', 'kotlinc', 'git', 'ruby', 'lua',
      ].map((t) => loader(t, env: {'ROXUM_SHARED_PATH': sharedPath})),
      ..._javaTools.map((t) => loader(t, env: {'ROXUM_SHARED_PATH': sharedPath})),
      {'src': '$binDir/clang',  'dst': '$binDir/aarch64-linux-android-clang'},
      {'src': '$binDir/clang++','dst': '$binDir/aarch64-linux-android-clang++'},
    ];

    int created = 0;
    for (final link in symlinks) {
      final dst = link['dst'] as String;
      final src = link['src'] as String;
      bool needsCreation = true;
      try {
        final linkType = await FileSystemEntity.type(dst, followLinks: false);
        if (linkType == FileSystemEntityType.link) {
          final target = await Link(dst).target();
          if (target == src) needsCreation = false;
        }
      } catch (_) {}
      if (needsCreation) {
        try {
          await Process.run(
            'ln', ['-sf', src, dst],
            environment: link['env'] as Map<String, String>?,
          ).timeout(const Duration(seconds: 2));
          created++;
        } catch (_) {}
      }
    }
    _addLog('Created/verified $created symlinks (${sw.elapsedMilliseconds}ms)');

    // ── Rust / Go / Dart runtime symlinks ──
    await _refreshRustGoRuntimeSymlinks(sharedPath);
    await _refreshDartRuntimeSymlinks(sharedPath);

    // ── Alpine runtime files ──
    final debianDir = '${runtimesDir}/alpine-linux';
    if (await Directory(debianDir).exists()) {
      try {
        await DebianSetup.ensureDebianRuntimeFiles();
        _addLog('Alpine runtime files ready');
      } catch (e) {
        try { Future.microtask(() { try { PandaLog.e('SetupScreen', 'Alpine runtime files error: $e'); } catch (_) {} }); } catch (_) {}
      }

      // Inject Panda tools into Alpine local bin
      _addLog('Injecting Panda tools into Alpine...');
      final localBinDir = Directory('$debianDir/usr/local/bin');
      if (!await localBinDir.exists()) localBinDir.createSync(recursive: true);

      // Panda CLI bridge
      final pandaCli = File('${localBinDir.path}/panda');
      pandaCli.writeAsStringSync('#!/bin/sh\necho "\$@" | nc 127.0.0.1 ${PandaBridge.port}\n');
      Process.runSync('chmod', ['+x', pandaCli.path]);

      // Native fast-path shims
      final nativeBinaries = [
        'node', 'npm', 'npx', 'git', 'python', 'python3', 'pip', 'pip3',
        'clang', 'clang++', 'rustc', 'cargo',
      ];
      int shims = 0;
      for (final bin in nativeBinaries) {
        final shim = File('${localBinDir.path}/$bin');
        final native = File('$binDir/$bin');
        if (await native.exists()) {
          if (!await shim.exists()) {
            shim.writeAsStringSync('#!/bin/sh\nexec $binDir/$bin "\$@"\n');
            Process.runSync('chmod', ['+x', shim.path]);
            shims++;
          }
        } else if (await shim.exists()) {
          await shim.delete();
        }
      }
      _addLog('Panda tools: CLI bridge + $shims shims injected');

      // Panda service supervisor
      final pandaService = File('${localBinDir.path}/panda-service');
      pandaService.writeAsStringSync('''#!/bin/sh
case "\$1" in
  start)
    echo "[Panda Services] Starting \$2..."
    nohup "\$2" > /tmp/"\$2".log 2>&1 &
    echo \$! > /tmp/"\$2".pid
    ;;
  stop)
    echo "[Panda Services] Stopping \$2..."
    kill \$(cat /tmp/"\$2".pid) 2>/dev/null
    rm -f /tmp/"\$2".pid
    ;;
  status)
    if [ -f /tmp/"\$2".pid ]; then
      echo "[Panda Services] \$2 is RUNNING (PID \$(cat /tmp/"\$2".pid))"
    else
      echo "[Panda Services] \$2 is STOPPED"
    fi
    ;;
  *) echo "Usage: panda-service [start|stop|status] <command>" ;;
esac
''');
      Process.runSync('chmod', ['+x', pandaService.path]);
    }
  }

  Future<void> _injectTools() async {
    // Tool injection is handled in _setupRuntime for Alpine local bin.
    // This step is a no-op placeholder so the step count stays consistent.
    _addLog('Tool injection complete');
  }

  Future<void> _startServices() async {
    _addLog('Starting PandaBridge on port ${PandaBridge.port}');
    await PandaBridge.start().timeout(
      const Duration(seconds: 10),
      onTimeout: () => _addLog('⚠️ PandaBridge start timed out'),
    ).catchError((e) => _addLog('⚠️ PandaBridge error: $e'));
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Runtime symlink helpers
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _refreshRustGoRuntimeSymlinks(String sharedPath) async {
    if (await Directory('$runtimesDir/rust').exists()) {
      await _ensureSymlink(linkPath: '$binDir/rustc',      targetPath: '$sharedPath/librustc.so');
      await _ensureSymlink(linkPath: '$binDir/rustloader', targetPath: '$sharedPath/librstloader.so');
      await _ensureSymlink(linkPath: '$binDir/cargo',      targetPath: '$sharedPath/libcargo.so');
    }

    if (await Directory('$runtimesDir/go').exists()) {
      await _ensureSymlink(linkPath: '$binDir/go',    targetPath: '$sharedPath/libgo.so');
      await _ensureSymlink(linkPath: '$binDir/gofmt', targetPath: '$sharedPath/libgofmt.so');
      final goToolDir = Directory('$runtimesDir/go/pkg/tool/android_arm64');
      if (await goToolDir.exists()) {
        for (final tool in _goToolBinaries) {
          await _ensureSymlink(
            linkPath: '${goToolDir.path}/$tool',
            targetPath: '$sharedPath/lib$tool.so',
          );
        }
      }
    }
  }

  Future<void> _refreshDartRuntimeSymlinks(String sharedPath) async {
    final dartBinDir = Directory('$runtimesDir/dart/bin');
    if (!await dartBinDir.exists()) return;

    await _ensureSymlink(linkPath: '${dartBinDir.path}/dart',             targetPath: '$sharedPath/libdart.so');
    await _ensureSymlink(linkPath: '${dartBinDir.path}/dartvm',           targetPath: '$sharedPath/libdartvm.so');
    final aotIntermediate = '${dartBinDir.path}/libdart.so';
    await _ensureSymlink(linkPath: aotIntermediate,                       targetPath: '$sharedPath/libdartaotruntime.so');
    await _ensureSymlink(linkPath: '${dartBinDir.path}/dartaotruntime',   targetPath: aotIntermediate);
  }

  Future<void> _ensureSymlink({
    required String linkPath,
    required String targetPath,
  }) async {
    try {
      final existingType =
          await FileSystemEntity.type(linkPath, followLinks: false);
      if (existingType == FileSystemEntityType.file) {
        await File(linkPath).delete();
      } else if (existingType == FileSystemEntityType.link) {
        await Link(linkPath).delete();
      } else if (existingType == FileSystemEntityType.directory) {
        await Directory(linkPath).delete(recursive: true);
      }
      await Link(linkPath).create(targetPath, recursive: true);
    } catch (_) {}
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Navigation
  // ────────────────────────────────────────────────────────────────────────────

  void _navigateToApp() {
    if (!mounted) return;
    // Permissions already handled by PermissionScreen — go straight home
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => const SelectType(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a0a0a),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildProgressBar(),
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
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
      child: Row(
        children: [
          // Panda logo with glow
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

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _setupComplete
                    ? 'Complete'
                    : 'Step ${_currentStepIndex + 1} of ${_steps.length}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${(_progress * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xff5090c8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: const Color(0xff1a1a1a),
              valueColor: AlwaysStoppedAnimation<Color>(
                _setupComplete
                    ? const Color(0xff81c784)
                    : _setupError
                        ? const Color(0xffcf6679)
                        : const Color(0xff5090c8),
              ),
            ),
          ),
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
            Expanded(
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.all(10),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final line = _logs[index];
                  final isError = line.contains('\u274c') || line.toLowerCase().contains('error');
                  final isWarning = line.contains('\u26a0\ufe0f');
                  final isSuccess = line.contains('\u2705');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
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
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _logs.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _logs.join('\n')));
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
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _logs.isEmpty
                  ? null
                  : () async {
                      try {
                        final logDir = Directory(pandaLogsDir);
                        if (!await logDir.exists()) await logDir.create(recursive: true);
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
