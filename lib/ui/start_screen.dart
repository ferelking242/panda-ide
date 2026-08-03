import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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

const List<String> javaTools = [
  'jar', 'jarsigner', 'java', 'javac', 'javadoc', 'javap', 'jcmd',
  'jconsole', 'jdb', 'jdeprscan', 'jdeps', 'jfr', 'jhsdb', 'jinfo',
  'jlink', 'jmap', 'jmod', 'jpackage', 'jps', 'jrunscript', 'jstack',
  'jstat', 'jstatd', 'jwebserver', 'keytool', 'rmiregistry', 'serialver'
];

const List<String> goToolBinaries = [
  'asm', 'cgo', 'compile', 'cover', 'fix', 'link', 'preprofile', 'vet',
];

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _animationDone = false;
  bool _initDone = false;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _safeInitialize();
  }

  Future<void> _safeInitialize() async {
    try {
      await _initializeApp();
    } catch (e, stack) {
      PandaLog.e('StartScreen', 'Startup failed: $e', error: e);
      debugPrint("Startup error: $e\n$stack");
      if (!mounted) return;
      setState(() => _initError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text("Startup failed: $e",
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
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
    if (kIsWeb) {
      _pushSelectType();
      return;
    }
    // Check if permission screen has been shown before
    final prefs = await SharedPreferences.getInstance();
    final permShown = prefs.getBool('permissions_shown') ?? false;
    if (!mounted) return;
    if (permShown) {
      _pushSelectType();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PermissionScreen()),
      );
    }
  }

  void _pushSelectType() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (context, animation, _) => const SelectType(),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  Future<void> _initializeApp() async {
    PandaLog.i('StartScreen', 'Initialization started');

    if (kIsWeb) {
      await ensureCopilotEnabledPrefInitialized();
      await ensureCopilotSignedPrefInitialized();
      return;
    }

    // ── Create Panda IDE public folder structure ───────────────────────────
    for (final path in [pandaRootDir, projectDir, templateDir, filesDir, pandaLogsDir]) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          PandaLog.w('StartScreen', 'Could not create $path: $e');
        }
      }
    }

    // ── Init file logging ─────────────────────────────────────────────────
    await PandaLog.initFileLogging();

    await NativeChannel.getExternalMediaDir();
    final downdir = Directory(downloadsDir);
    final gitCore = "$binDir/git-core";

    for (final path in [binDir, libDir, gitCore, homeDir]) {
      final dir = Directory(path);
      if (!dir.existsSync()) await dir.create(recursive: true);
    }

    // Clean up leftover zip files
    if (await downdir.exists()) {
      for (final file in downdir.listSync()) {
        if (file is File && file.path.endsWith('.zip')) {
          await file.delete();
        }
      }
    }

    await setupFilesDir();
    await setupProjectDir();
    await setupTempDir();
    await ensureCopilotEnabledPrefInitialized();
    await ensureCopilotSignedPrefInitialized();
    if (mounted) await context.read<PackageCatalogCubit>().syncOnStartup();

    final String sharedPath = await NativeChannel.getLibraryPath();
    PandaLog.i('StartScreen', 'sharedPath=$sharedPath');

    Map<String, dynamic> loader(String name,
        {String? loaderBin, Map<String, String>? env}) => {
      'src': '$sharedPath/${loaderBin ?? "libloader.so"}',
      'dst': '$binDir/$name',
      'env': env,
    };

    final loaderTools = [
      'clang', 'clang++', 'clangloader', 'node', 'python', 'python3',
      'npm', 'npx', 'pip', 'pip3', 'tsc', 'kotlinc', 'git', 'ruby', 'lua',
    ];

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
      {'src': '$sharedPath/libless.so',       'dst': '$binDir/less',  'env': <String,String>{'LD_LIBRARY_PATH': libDir}},
      {'src': '$sharedPath/libless.so',       'dst': '$binDir/pager', 'env': <String,String>{'LD_LIBRARY_PATH': libDir}},
      ...loaderTools.map((t) => loader(t, env: {'ROXUM_SHARED_PATH': sharedPath})),
      ...javaTools.map((t) => loader(t, env: {'ROXUM_SHARED_PATH': sharedPath})),
      {'src': '$binDir/clang',  'dst': '$binDir/aarch64-linux-android-clang'},
      {'src': '$binDir/clang++','dst': '$binDir/aarch64-linux-android-clang++'},
    ];

    PandaLog.i('StartScreen', 'Creating ${symlinks.length} symlinks');
    for (final link in symlinks) {
      final dst = link['dst'] as String;
      final src = link['src'] as String;
      final linkFile = Link(dst);
      bool needsCreation = true;
      if (linkFile.existsSync()) {
        try {
          if (linkFile.targetSync() == src) needsCreation = false;
        } catch (_) {}
      }
      if (needsCreation) {
        await Process.run(
          "ln", ["-sf", src, dst],
          environment: link['env'] as Map<String, String>?,
        );
      }
    }

    await _refreshRustGoRuntimeSymlinks(sharedPath);
    await _refreshDartRuntimeSymlinks(sharedPath);

    if (!File('$certDir/cacert.pem').existsSync()) {
      Directory(certDir).createSync(recursive: true);
      final certBytes = await rootBundle.load('assets/certificates/cacert.pem');
      File('$certDir/cacert.pem').writeAsBytesSync(certBytes.buffer.asUint8List());
    }

    await Process.run(
      "$binDir/git",
      ["config", "--global", "--add", "safe.directory", "*"],
      environment: gitEnvs(sharedPath),
    );

    PandaLog.i('StartScreen', 'Initialization complete');
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
        for (final tool in goToolBinaries) {
          await _ensureSymlink(
            linkPath: '${goToolDir.path}/$tool',
            targetPath: '$sharedPath/lib$tool.so',
          );
        }
      }
    }
  }

  Future<void> _ensureSymlink({
    required String linkPath,
    required String targetPath,
  }) async {
    try {
      final existingType = await FileSystemEntity.type(linkPath, followLinks: false);
      if (existingType == FileSystemEntityType.file)           await File(linkPath).delete();
      else if (existingType == FileSystemEntityType.link)      await Link(linkPath).delete();
      else if (existingType == FileSystemEntityType.directory) await Directory(linkPath).delete(recursive: true);
      await Link(linkPath).create(targetPath, recursive: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PandaSplashScreen(onComplete: _onAnimationComplete);
  }
}
