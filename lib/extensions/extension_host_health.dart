import 'dart:io';
import '../utils/constants.dart';
import 'extension_host_manager.dart';
import 'extension_host_setup.dart';
import 'node_runtime.dart';

/// Health check for the extension host system.
/// Verifies that all components are in place for running extensions.
class ExtensionHostHealth {
  /// Run a full health check and return the results.
  static Future<ExtensionHostReport> check() async {
    final checks = <ExtensionHostCheck>[];

    // 1. Node.js binary
    final nodeStatus = await NodeRuntimeManager.instance.getStatus();
    checks.add(ExtensionHostCheck(
      name: 'Node.js Runtime',
      passed: nodeStatus.installed,
      message: nodeStatus.installed
          ? 'v${nodeStatus.version ?? "?"} at ${nodeStatus.path}'
          : 'Not installed — download from Settings → Runtimes',
      severity: nodeStatus.installed ? CheckSeverity.ok : CheckSeverity.error,
    ));

    // 2. host.js
    final hostJsExists = await File(ExtensionHostSetup.hostJsPath).existsSync();
    checks.add(ExtensionHostCheck(
      name: 'Extension Host (host.js)',
      passed: hostJsExists,
      message: hostJsExists
          ? ExtensionHostSetup.hostJsPath
          : 'Missing — run ExtensionHostSetup.init()',
      severity: hostJsExists ? CheckSeverity.ok : CheckSeverity.error,
    ));

    // 3. IPC bridge JS
    final ipcJsExists = await File('${ExtensionHostSetup.hostDir}/ipc.js').existsSync();
    checks.add(ExtensionHostCheck(
      name: 'IPC Bridge (ipc.js)',
      passed: ipcJsExists,
      message: ipcJsExists ? 'Ready' : 'Missing',
      severity: ipcJsExists ? CheckSeverity.ok : CheckSeverity.error,
    ));

    // 4. VSCode API shim
    final vscodeJsExists = await File('${ExtensionHostSetup.hostDir}/api/vscode.js').existsSync();
    checks.add(ExtensionHostCheck(
      name: 'VS Code API (vscode.js)',
      passed: vscodeJsExists,
      message: vscodeJsExists ? 'Ready' : 'Missing',
      severity: vscodeJsExists ? CheckSeverity.ok : CheckSeverity.warning,
    ));

    // 5. Extension host manager configured
    final managerConfigured = ExtensionHostManager.instance.isConfigured;
    checks.add(ExtensionHostCheck(
      name: 'Extension Host Manager',
      passed: managerConfigured,
      message: managerConfigured ? 'Configured' : 'Not configured',
      severity: managerConfigured ? CheckSeverity.ok : CheckSeverity.error,
    ));

    // 6. Active extensions
    final activeCount = ExtensionHostManager.instance.activeHosts.length;
    checks.add(ExtensionHostCheck(
      name: 'Active Extensions',
      passed: true,
      message: '$activeCount extension(s) running',
      severity: CheckSeverity.ok,
    ));

    // 7. Directory structure
    final extDirExists = await Directory(extensionDir).existsSync();
    checks.add(ExtensionHostCheck(
      name: 'Extensions Directory',
      passed: extDirExists,
      message: extDirExists ? extensionDir : 'Missing',
      severity: extDirExists ? CheckSeverity.ok : CheckSeverity.warning,
    ));

    final allPassed = checks.every((c) => c.severity != CheckSeverity.error);
    final warningCount = checks.where((c) => c.severity == CheckSeverity.warning).length;
    final errorCount = checks.where((c) => c.severity == CheckSeverity.error).length;

    return ExtensionHostReport(
      healthy: allPassed,
      checks: checks,
      summary: allPassed
          ? 'Extension host is ready (${checks.length} checks passed)'
          : '$errorCount error(s), $warningCount warning(s)',
    );
  }
}

enum CheckSeverity { ok, warning, error }

class ExtensionHostCheck {
  final String name;
  final bool passed;
  final String message;
  final CheckSeverity severity;

  const ExtensionHostCheck({
    required this.name,
    required this.passed,
    required this.message,
    required this.severity,
  });
}

class ExtensionHostReport {
  final bool healthy;
  final List<ExtensionHostCheck> checks;
  final String summary;

  const ExtensionHostReport({
    required this.healthy,
    required this.checks,
    required this.summary,
  });
}
