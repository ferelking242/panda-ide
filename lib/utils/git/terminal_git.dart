import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants.dart';
import '../debian_setup.dart';
import '../rootfs_manager.dart';

/// Runs Git from the active terminal environment.
///
/// Android Git is installed by `panda update` inside the terminal rootfs and
/// must be started through PRoot. There is deliberately no bundled-binary or
/// Android-host fallback here.
class TerminalGit {
  static Future<Process> start(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final directory = workingDirectory ?? appDir;
    final extraEnvironment = <String, String>{
      'GIT_TERMINAL_PROMPT': '0',
      'HOME': homeDir,
      ...?environment,
    };

    if (!Platform.isAndroid) {
      return Process.start(
        'git',
        arguments,
        workingDirectory: directory,
        environment: {
          ...Platform.environment,
          ...extraEnvironment,
        },
      );
    }

    final rootfs = await RootfsManager.getActiveRootfsPath();
    await DebianSetup.ensureRuntimeFilesForRootfs(rootfs);
    final proot = await DebianSetup.locateProotBinary(rootfs);
    if (proot == null) {
      throw StateError(
        'Git is unavailable in the terminal. '
        'Open the terminal and run `panda update` first.',
      );
    }

    final extraBinds = <String>[
      if (Directory(appDir).existsSync()) '$appDir:$appDir',
      if (Directory(directory).existsSync()) '$directory:$directory',
    ];
    final prootArgs = await DebianSetup.prootArguments(
      rootfsPath: rootfs,
      extraBinds: extraBinds,
    );
    final guestEnvironment = await DebianSetup.prootSessionEnvironment(
      rootfsPath: rootfs,
      extra: extraEnvironment,
    );
    final guestWorkingDirectory =
        Directory(directory).existsSync() ? directory : '/root';

    return Process.start(
      proot,
      [...prootArgs, '-w', guestWorkingDirectory, 'git', ...arguments],
      workingDirectory: appDir,
      environment: guestEnvironment,
    );
  }

  static Future<ProcessResult> run(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Encoding stdoutEncoding = utf8,
    Encoding stderrEncoding = utf8,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final process = await start(
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final stdoutFuture =
        process.stdout.fold<List<int>>([], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    final stderrFuture =
        process.stderr.fold<List<int>>([], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });

    try {
      final values = await Future.wait<dynamic>([
        process.exitCode,
        stdoutFuture,
        stderrFuture,
      ]).timeout(timeout, onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException(
          'Git command timed out after ${timeout.inSeconds}s',
        );
      });
      return ProcessResult(
        process.pid,
        values[0] as int,
        stdoutEncoding.decode(values[1] as List<int>),
        stderrEncoding.decode(values[2] as List<int>),
      );
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }
}