import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../extensions/debug_bridge.dart';

/// Service to launch debug sessions for different runtimes.
/// Connects to debug adapters (debugpy, node --inspect) running inside PRoot.
///
/// Usage: Pass a `sendToPty` callback from the terminal widget.
class DebugLauncher {
  DebugLauncher._();
  static final DebugLauncher instance = DebugLauncher._();

  /// Callback to send commands to the active PRoot terminal PTY.
  /// Set this from the terminal widget on init.
  void Function(String command)? sendToPty;

  /// Start a Node.js debug session for a JS/TS file.
  /// Launches `node --inspect-brk=0.0.0.0:9229 <file>` in PRoot,
  /// then connects the DebugBridge to localhost:9229.
  Future<String?> launchNodeDebug(String filePath) async {
    try {
      // Start debug adapter in the terminal via native channel
      final bridge = DebugBridge.instance;
      final sessionId = await bridge.startDebugging(
        extensionId: 'panda-debug',
        config: {
          'name': 'Node.js: $filePath',
          'type': 'node',
          'request': 'launch',
          'program': filePath,
          'stopOnEntry': false,
          'console': 'integratedTerminal',
          'address': '0.0.0.0',
          'port': 9229,
        },
      );

      if (sessionId == null) return null;

      // Launch the debug adapter in PRoot via terminal
      _launchInTerminal(
        'node --inspect-brk=0.0.0.0:9229 "$filePath"',
      );

      // Wait a moment for the adapter to start, then connect
      await Future.delayed(const Duration(seconds: 2));

      try {
        await bridge.connectSession(sessionId, '127.0.0.1', 9229);
      } catch (e) {
        debugPrint('[DebugLauncher] Connect failed (adapter may not be running): $e');
        // Session still exists — user can connect manually later
      }

      return sessionId;
    } catch (e) {
      debugPrint('[DebugLauncher] Node launch error: $e');
      return null;
    }
  }

  /// Start a Python debug session for a .py file.
  /// Launches `python -m debugpy --listen 0.0.0.0:5678 --wait-for-client <file>`
  /// in PRoot, then connects the DebugBridge to localhost:5678.
  Future<String?> launchPythonDebug(String filePath) async {
    try {
      final bridge = DebugBridge.instance;
      final sessionId = await bridge.startDebugging(
        extensionId: 'panda-debug',
        config: {
          'name': 'Python: $filePath',
          'type': 'python',
          'request': 'launch',
          'program': filePath,
          'debugAdapter': 'server',
          'address': '0.0.0.0',
          'port': 5678,
        },
      );

      if (sessionId == null) return null;

      _launchInTerminal(
        'python -m debugpy --listen 0.0.0.0:5678 --wait-for-client "$filePath"',
      );

      await Future.delayed(const Duration(seconds: 2));

      try {
        await bridge.connectSession(sessionId, '127.0.0.1', 5678);
      } catch (e) {
        debugPrint('[DebugLauncher] Python connect failed: $e');
      }

      return sessionId;
    } catch (e) {
      debugPrint('[DebugLauncher] Python launch error: $e');
      return null;
    }
  }

  /// Start a Go debug session using Delve.
  Future<String?> launchGoDebug(String filePath) async {
    try {
      final bridge = DebugBridge.instance;
      final sessionId = await bridge.startDebugging(
        extensionId: 'panda-debug',
        config: {
          'name': 'Go: $filePath',
          'type': 'go',
          'request': 'launch',
          'program': filePath,
          'port': 2345,
        },
      );

      if (sessionId == null) return null;

      _launchInTerminal(
        'dlv debug "$filePath" --headless --listen=:2345 --api-version=2',
      );

      await Future.delayed(const Duration(seconds: 3));

      try {
        await bridge.connectSession(sessionId, '127.0.0.1', 2345);
      } catch (e) {
        debugPrint('[DebugLauncher] Go connect failed: $e');
      }

      return sessionId;
    } catch (e) {
      debugPrint('[DebugLauncher] Go launch error: $e');
      return null;
    }
  }

  /// Launch a command in the PRoot terminal.
  void _launchInTerminal(String command) {
    try {
      sendToPty?.call('$command\n');
    } catch (e) {
      debugPrint('[DebugLauncher] Terminal command error: $e');
    }
  }

  /// Auto-detect file type and launch appropriate debugger.
  Future<String?> launchForFile(String filePath) async {
    if (filePath.endsWith('.js') || filePath.endsWith('.ts') ||
        filePath.endsWith('.mjs') || filePath.endsWith('.cjs')) {
      return launchNodeDebug(filePath);
    } else if (filePath.endsWith('.py')) {
      return launchPythonDebug(filePath);
    } else if (filePath.endsWith('.go')) {
      return launchGoDebug(filePath);
    } else {
      debugPrint('[DebugLauncher] No debug adapter for: $filePath');
      return null;
    }
  }
}
