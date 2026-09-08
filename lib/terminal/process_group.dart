import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';

/// Process lifecycle helpers for local PTY sessions.
///
/// flutter_pty creates a new session with the child as the process-group
/// leader, but its public kill() method only targets that leader. A shell can
/// have Git, Flutter and other descendants still running, so Android gets a
/// best-effort process-group kill before the normal PTY fallback.
class TerminalProcessGroup {
  TerminalProcessGroup._();

  static const MethodChannel _channel = MethodChannel('com.panda.ide');

  static int _signalNumber(ProcessSignal signal) {
    if (signal == ProcessSignal.sigint) return 2;
    if (signal == ProcessSignal.sigkill) return 9;
    if (signal == ProcessSignal.sigterm) return 15;
    if (signal == ProcessSignal.sigquit) return 3;
    if (signal == ProcessSignal.sighup) return 1;
    return 15;
  }

  static Future<bool> killPtyGroup(
    Pty pty, [
    ProcessSignal signal = ProcessSignal.sigterm,
  ]) async {
    final pid = pty.pid;
    if (pid <= 0) return false;

    if (Platform.isAndroid) {
      try {
        final killed = await _channel.invokeMethod<bool>(
          'killProcessGroup',
          <String, Object>{'pid': pid, 'signal': _signalNumber(signal)},
        );
        if (killed == true) return true;
      } catch (_) {
        // Fall through to flutter_pty's portable PID-only implementation.
      }
    }

    try {
      return pty.kill(signal);
    } catch (_) {
      return false;
    }
  }
}
