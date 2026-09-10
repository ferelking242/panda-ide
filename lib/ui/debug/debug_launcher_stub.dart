import '../../terminal/terminal.dart';

class DebugLaunchResult {
  final bool started;
  final String command;
  final String? sessionId;
  final String? error;

  const DebugLaunchResult({
    required this.started,
    required this.command,
    this.sessionId,
    this.error,
  });
}

class DebugLauncher {
  DebugLauncher._();
  static final DebugLauncher instance = DebugLauncher._();

  Future<DebugLaunchResult> runTarget({
    String? filePath,
    required String workspaceDir,
  }) async {
    return const DebugLaunchResult(
      started: false,
      command: '',
      error: 'Run/Debug nécessite un terminal natif.',
    );
  }

  Future<bool> sendControl(String sequence) async =>
      TerminalSessionStore.instance.sendToActivePty(sequence);

  Future<void> stopCurrent() async {}
}