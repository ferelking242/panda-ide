import 'dart:io';

import '../utils/constants.dart';
import '../utils/debian_setup.dart';

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

  bool get isAvailable => _available;
  String? get version => _version;

  Future<bool> init() async {
    _available = false;
    _version = null;

    try {
      final result = Platform.isAndroid
          ? await _runInTerminal(['--version'])
          : await Process.run('node', ['--version'])
              .timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return false;

      final version = result.stdout.toString().trim();
      if (version.isEmpty) return false;
      _version = version;
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
    final command = await prepareNodeCommand(
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
    if (!_available && !await init()) {
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

    final rootfs = DebianSetup.debianDir;
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
        'node',
        ...arguments,
      ],
      hostWorkingDirectory: hostWorkingDirectory ?? appDir,
      environment: guestEnvironment,
    );
  }

  Future<ProcessResult> _runInTerminal(List<String> arguments) async {
    final rootfs = DebianSetup.debianDir;
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