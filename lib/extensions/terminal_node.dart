import 'dart:io';

import '../utils/constants.dart';
import '../utils/debian_setup.dart';
import '../utils/rootfs_manager.dart';

/// Starts Node.js from the active Panda terminal environment.
///
/// Node is not an application runtime. The terminal owns its installation
/// through `panda update`; this launcher only verifies and executes the
/// `node` command in that same environment.
class TerminalNodeLauncher {
  static final TerminalNodeLauncher instance = TerminalNodeLauncher._();
  TerminalNodeLauncher._();

  bool _available = false;
  String? _version;
  String? _rootfsPath;

  bool get isAvailable => _available;
  String? get version => _version;

  Future<bool> init() async {
    _available = false;
    _version = null;

    try {
      final rootfsPath =
          Platform.isAndroid ? await RootfsManager.getActiveRootfsPath() : null;
      final result = Platform.isAndroid
          ? await _runInTerminal(['--version'], rootfsPath: rootfsPath!)
          : await Process.run('node', ['--version'])
              .timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return false;

      final version = result.stdout.toString().trim();
      if (version.isEmpty) return false;
      _version = version;
      _rootfsPath = rootfsPath;
      _available = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<TerminalNodeStatus> getStatus() async {
    if (!_available) await init();
    return TerminalNodeStatus(
      available: _available,
      version: _version,
      path: _available ? 'terminal: node' : null,
    );
  }

  Future<Process> startNode({
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    return startCommand(
      executable: 'node',
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  /// Starts a command from the active Panda terminal environment.
  ///
  /// This is used for npm as well as node-based extension processes. Both
  /// commands must run through the same PRoot/rootfs boundary as the PTY.
  Future<Process> startCommand({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final command = await prepareCommand(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      hostWorkingDirectory: appDir,
    );
    return Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.hostWorkingDirectory,
      environment: command.environment,
    );
  }

  Future<TerminalNodeCommand> prepareNodeCommand({
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const {},
    String? hostWorkingDirectory,
  }) async {
    return prepareCommand(
      executable: 'node',
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      hostWorkingDirectory: hostWorkingDirectory,
    );
  }

  Future<TerminalNodeCommand> prepareCommand({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const {},
    String? hostWorkingDirectory,
  }) async {
    final activeRootfsPath =
        Platform.isAndroid ? await RootfsManager.getActiveRootfsPath() : null;
    if (!_available ||
        (Platform.isAndroid && _rootfsPath != activeRootfsPath)) {
      if (!await init()) {
        throw StateError(
          'Node.js is unavailable in the active terminal. '
          'Open the terminal and run `panda update` first.',
        );
      }
    }

    if (!_available) {
      throw StateError(
        'Node.js is unavailable in the terminal. '
        'Open the terminal and run `panda update` first.',
      );
    }

    if (!Platform.isAndroid) {
      return TerminalNodeCommand(
        executable: 'node',
        arguments: arguments,
        hostWorkingDirectory: hostWorkingDirectory ?? workingDirectory,
        environment: {
          ...Platform.environment,
          ...environment,
        },
      );
    }

    final rootfs = activeRootfsPath!;
    final proot = await DebianSetup.locateProotBinary(rootfs);
    if (proot == null) {
      throw StateError(
        'The terminal environment is not initialized. '
        'Open the terminal and run `panda update` first.',
      );
    }

    final binds = <String>[
      if (Directory(appDir).existsSync()) '$appDir:$appDir',
      if (Directory(workingDirectory).existsSync())
        '$workingDirectory:$workingDirectory',
    ];
    final prootArgs = await DebianSetup.prootArguments(
      rootfsPath: rootfs,
      extraBinds: binds,
    );
    final guestEnvironment = await DebianSetup.prootSessionEnvironment(
      rootfsPath: rootfs,
      extra: {
        ...environment,
        'PATH': environment['PATH'] ??
            '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      },
    );
    final guestWorkingDirectory =
        Directory(workingDirectory).existsSync() ? workingDirectory : '/root';

    return TerminalNodeCommand(
      executable: proot,
      arguments: [
        ...prootArgs,
        '-w',
        guestWorkingDirectory,
        executable,
        ...arguments,
      ],
      hostWorkingDirectory: hostWorkingDirectory ?? appDir,
      environment: guestEnvironment,
    );
  }

  Future<ProcessResult> _runInTerminal(
    List<String> arguments, {
    required String rootfsPath,
  }) async {
    final rootfs = rootfsPath;
    final proot = await DebianSetup.locateProotBinary(rootfs);
    if (proot == null) {
      throw StateError('PRoot is unavailable');
    }
    final prootArgs = await DebianSetup.prootArguments(rootfsPath: rootfs);
    final environment = await DebianSetup.prootSessionEnvironment(
      rootfsPath: rootfs,
    );
    return Process.run(
      proot,
      [...prootArgs, '-w', '/root', 'node', ...arguments],
      workingDirectory: appDir,
      environment: environment,
    ).timeout(const Duration(seconds: 10));
  }
}

class TerminalNodeCommand {
  final String executable;
  final List<String> arguments;
  final String hostWorkingDirectory;
  final Map<String, String> environment;

  const TerminalNodeCommand({
    required this.executable,
    required this.arguments,
    required this.hostWorkingDirectory,
    required this.environment,
  });
}

class TerminalNodeStatus {
  final bool available;
  final String? version;
  final String? path;

  const TerminalNodeStatus({
    required this.available,
    this.version,
    this.path,
  });
}