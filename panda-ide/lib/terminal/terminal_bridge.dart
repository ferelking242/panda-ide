import 'dart:async';

/// Singleton bridge between the visible PTY terminal and Panda Agent tools.
///
/// [_SetupTerminalState] attaches itself when it mounts and detaches on
/// dispose.  [AgenticTools.runShellCommand] then calls [runCommand] to execute
/// a command inside the *visible* terminal session and capture its output.
class TerminalBridge {
  TerminalBridge._();
  static final TerminalBridge instance = TerminalBridge._();

  TerminalBridgeDelegate? _delegate;

  /// True when a live local PTY session is connected.
  bool get isAvailable => _delegate != null;

  /// Called by [_SetupTerminalState] when mounted.
  void attach(TerminalBridgeDelegate delegate) => _delegate = delegate;

  /// Called by [_SetupTerminalState] on dispose.
  void detach() => _delegate = null;

  // ── Agent → terminal ───────────────────────────────────────────────────────

  /// Runs [command] inside the visible PTY session and returns
  /// stdout+stderr with ANSI codes stripped.
  Future<String> runCommand(
    String command, {
    Duration timeout = const Duration(seconds: 120),
  }) {
    final d = _delegate;
    if (d == null) throw StateError('No active terminal session');
    return d.executeCommandAndCapture(command, timeout: timeout);
  }

  /// Writes raw text to the active PTY without capturing output.
  void write(String text) => _delegate?.writeToPty(text);

  // ── Terminal → agent callbacks ─────────────────────────────────────────────

  /// Set by HomeState. Injects a pre-formatted message into Panda Agent.
  void Function(String message)? onSendToAgent;

  /// Set by HomeState. Called when the terminal's shell exits with code != 0.
  void Function(String recentOutput, int exitCode)? onCommandError;

  /// Set by HomeState. Called when the agent starts or stops running a
  /// terminal command so the UI can open the terminal panel.
  void Function(bool running, String? command)? onAgentCommandStateChanged;

  // ── Raw output stream ──────────────────────────────────────────────────────

  /// Broadcasts every raw PTY chunk. The agent panel subscribes to show a
  /// live "terminal active" indicator while the agent is working.
  final _outputCtrl = StreamController<String>.broadcast();
  Stream<String> get outputStream => _outputCtrl.stream;

  /// Called by [_SetupTerminalState] for every PTY output chunk.
  void notifyOutput(String chunk) {
    if (!_outputCtrl.isClosed) _outputCtrl.add(chunk);
  }
}

/// Interface implemented by [_SetupTerminalState].
abstract class TerminalBridgeDelegate {
  /// Runs [command] in the active PTY session and returns captured output.
  Future<String> executeCommandAndCapture(
    String command, {
    required Duration timeout,
  });

  /// Writes [text] directly to the active PTY.
  void writeToPty(String text);
}

/// Strips ANSI/VT-100 escape sequences from [input].
String stripAnsiCodes(String input) => input.replaceAll(
      RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])'),
      '',
    );
