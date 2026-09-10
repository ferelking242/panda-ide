import 'dart:async';
import 'dart:io';
import '../utils/constants.dart';
import '../utils/debian_setup.dart';

/// Manages the Node.js runtime binary for the extension host.
///
/// Android never executes a Linux guest binary directly. Node is installed by
/// `panda update` inside the terminal rootfs and is launched through the same
/// PRoot environment as the interactive terminal.
class NodeRuntimeManager {
  static final NodeRuntimeManager instance = NodeRuntimeManager._();
  NodeRuntimeManager._();

  bool _installed = false;
  bool get isInstalled => _installed;

  String? _nodePath;
  String? get nodePath => _nodePath;
  bool _usesGuestRootfs = false;
  bool get usesGuestRootfs => _usesGuestRootfs;

  /// Version of the installed node binary.
  String? _version;
  String? get version => _version;

  // ── Initialization ──────────────────────────────────────────────────────

  /// Initialize the Node.js runtime from the terminal environment.
  Future<bool> init() async {
    _installed = false;
    _nodePath = null;
    _version = null;
    _usesGuestRootfs = false;

    if (Platform.isAndroid) {
      final rootfs = DebianSetup.debianDir;
      for (final guestPath in const ['/usr/bin/node', '/usr/local/bin/node']) {
        if (!File('$rootfs$guestPath').existsSync()) continue;
        _nodePath = guestPath;
        _usesGuestRootfs = true;
        _version = await _getVersion();
        if (_version != null) {
          _installed = true;
          return true;
        }
      }
      _nodePath = null;
      _usesGuestRootfs = false;
      return false;
    }

    for (final candidate in const ['node', '/usr/local/bin/node', '/usr/bin/node']) {
      try {
        final result = await Process.run(candidate, ['--version'])
            .timeout(const Duration(seconds: 10));
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          _nodePath = candidate;
          _version = result.stdout.toString().trim();
          _installed = true;
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Starts Node in the terminal rootfs on Android, or directly on desktop.
  Future<Process> startNode({
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final node = _nodePath;
    if (node == null) {
      throw StateError('Node.js is not installed in the terminal. Run `panda update` first.');
    }

    if (!_usesGuestRootfs) {
      return Process.start(
        node,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }

    final rootfs = DebianSetup.debianDir;
    final proot = await DebianSetup.locateProotBinary(rootfs);
    if (proot == null) {
      throw StateError('PRoot is unavailable; restart the terminal and run `panda doctor`.');
    }

    final prootArgs = await DebianSetup.prootArguments(
      rootfsPath: rootfs,
      extraBinds: [
        if (Directory(appDir).existsSync()) '$appDir:$appDir',
        if (Directory(runtimesDir).existsSync()) '$runtimesDir:$runtimesDir',
        if (Directory(workingDirectory).existsSync())
          '$workingDirectory:$workingDirectory',
      ],
    );
    final guestEnvironment = await DebianSetup.prootSessionEnvironment(
      rootfsPath: rootfs,
      extra: {
        ...environment,
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      },
    );

    return Process.start(
      proot,
      [
        ...prootArgs,
        '-w',
        workingDirectory.startsWith('/') ? workingDirectory : '/root',
        node,
        ...arguments,
      ],
      workingDirectory: appDir,
      environment: guestEnvironment,
    );
  }

  // ── Installation status ───────────────────────────────────────────────

  /// Get detailed installation status.
  Future<NodeRuntimeStatus> getStatus() async {
    final installed = _installed || File('$binDir/node').existsSync();
    final version = installed ? await _getVersion() : null;
    final size = installed ? await _getBinarySize() : 0;

    return NodeRuntimeStatus(
      installed: installed,
      path: _nodePath,
      version: version,
      sizeBytes: size,
      required: true, // Required for extensions
    );
  }

  /// Get the download URL for the current platform.
  static String getDownloadUrl() {
    // Node.js official builds for Android (arm64)
    return 'https://nodejs.org/dist/v20.11.1/node-v20.11.1-android-arm64.tar.gz';
  }

  // ── Private helpers ──────────────────────────────────────────────────

  Future<String?> _getVersion() async {
    if (_nodePath == null) return null;
    try {
      if (_usesGuestRootfs) {
        final rootfs = DebianSetup.debianDir;
        final proot = await DebianSetup.locateProotBinary(rootfs);
        if (proot == null) return null;
        final prootArgs = await DebianSetup.prootArguments(
          rootfsPath: rootfs,
          extraBinds: [
            if (Directory(appDir).existsSync()) '$appDir:$appDir',
          ],
        );
        final env = await DebianSetup.prootSessionEnvironment(
          rootfsPath: rootfs,
          extra: const {
            'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
          },
        );
        final result = await Process.run(
          proot,
          [...prootArgs, '-w', '/root', _nodePath!, '--version'],
          workingDirectory: appDir,
          environment: env,
        ).timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) return result.stdout.toString().trim();
        return null;
      }

      final nodeDirectory = Directory(_nodePath!).parent.path;
      final runtimeLibraryDirectory = Directory(nodeDirectory).parent.path;
      final environment = <String, String>{
        ...Platform.environment,
        'PATH': '$nodeDirectory:${Platform.environment['PATH'] ?? ''}',
        'LD_LIBRARY_PATH':
            '$runtimeLibraryDirectory:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
        'HOME': Platform.environment['HOME'] ?? appDir,
        'TMPDIR': Platform.environment['TMPDIR'] ?? tempDir,
      };
      final result = await Process.run(
        _nodePath!,
        ['--version'],
        environment: environment,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      print('[NodeRuntime] --version failed (${result.exitCode}): ${result.stderr}');
    } catch (error) {
      print('[NodeRuntime] Unable to execute $_nodePath: $error');
    }
    return null;
  }

  Future<int> _getBinarySize() async {
    if (_nodePath == null) return 0;
    try {
      final file = File(
        _usesGuestRootfs
            ? '${DebianSetup.debianDir}$_nodePath'
            : _nodePath!,
      );
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Dispose resources.
  void dispose() {
    _installed = false;
    _nodePath = null;
    _version = null;
    _usesGuestRootfs = false;
  }
}

/// Status of the Node.js runtime installation.
class NodeRuntimeStatus {
  final bool installed;
  final String? path;
  final String? version;
  final int sizeBytes;
  final bool required;

  const NodeRuntimeStatus({
    required this.installed,
    this.path,
    this.version,
    this.sizeBytes = 0,
    required this.required,
  });

  String get sizeText {
    if (sizeBytes == 0) return 'Not installed';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
