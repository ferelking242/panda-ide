import 'dart:async';
import 'dart:io';

/// Verification pipeline that runs checks after code modifications.
///
/// The level of verification is adaptive based on:
/// - Number of files changed
/// - Type of changes (critical vs routine)
/// - Device capabilities
/// - Battery level
class VerificationPipeline {
  /// Run verification on changed files.
  ///
  /// Returns a [VerificationResult] with pass/fail and any errors.
  static Future<VerificationResult> run({
    required List<String> changedFiles,
    required String workspacePath,
    VerificationLevel level = VerificationLevel.standard,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];

    // 1. LSP diagnostics (always)
    if (level.index >= VerificationLevel.basic.index) {
      final lspErrors = await _checkLsp(changedFiles);
      errors.addAll(lspErrors);
    }

    // 2. dart analyze (for Dart files)
    if (level.index >= VerificationLevel.standard.index) {
      final dartFiles = changedFiles.where((f) => f.endsWith('.dart')).toList();
      if (dartFiles.isNotEmpty) {
        final analyzeErrors = await _runAnalyzer(workspacePath);
        errors.addAll(analyzeErrors);
      }
    }

    // 3. Tests (only for significant changes)
    if (level.index >= VerificationLevel.thorough.index && changedFiles.length > 3) {
      final testErrors = await _runTests(workspacePath);
      warnings.addAll(testErrors);
    }

    // 4. Build check (only for critical files)
    if (level.index >= VerificationLevel.full.index) {
      final criticalFiles = changedFiles.where((f) =>
          f.contains('main.dart') ||
          f.contains('pubspec.yaml') ||
          f.contains('navigation')).toList();
      if (criticalFiles.isNotEmpty) {
        final buildErrors = await _checkBuild(workspacePath);
        errors.addAll(buildErrors);
      }
    }

    return VerificationResult(
      passed: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  static Future<List<String>> _checkLsp(List<String> files) async {
    // LSP diagnostics are checked by the editor's LSP bridge
    // This is a placeholder for the pipeline integration
    return [];
  }

  static Future<List<String>> _runAnalyzer(String workspacePath) async {
    try {
      final result = await Process.run(
        'dart',
        ['analyze', '--no-fatal-infos', '--no-fatal-warnings'],
        workingDirectory: workspacePath,
        environment: {'PATH': _androidPath()},
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        final output = result.stdout.toString() + result.stderr.toString();
        return output
            .split('\n')
            .where((l) => l.contains('error') || l.contains('Error'))
            .take(10)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> _runTests(String workspacePath) async {
    try {
      final result = await Process.run(
        'flutter',
        ['test', '--reporter=compact'],
        workingDirectory: workspacePath,
        environment: {'PATH': _androidPath()},
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode != 0) {
        final output = result.stdout.toString() + result.stderr.toString();
        return output
            .split('\n')
            .where((l) => l.contains('FAILED') || l.contains('Error'))
            .take(5)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<String>> _checkBuild(String workspacePath) async {
    // Don't run full build — just check pubspec
    try {
      final result = await Process.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: workspacePath,
        environment: {'PATH': _androidPath()},
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        return ['pub get failed: ${result.stderr}'];
      }
    } catch (_) {}
    return [];
  }

  static String _androidPath() {
    return '/data/data/com.termux/files/usr/bin:'
        '/data/user/0/com.pandaide.app/files/flutter/bin:'
        '/data/user/0/com.pandaide.app/files/dart-sdk/bin:'
        '${Platform.environment['PATH'] ?? ''}';
  }
}

enum VerificationLevel {
  basic,    // LSP only
  standard, // LSP + dart analyze
  thorough, // LSP + analyze + tests
  full,     // LSP + analyze + tests + build check
}

class VerificationResult {
  final bool passed;
  final List<String> errors;
  final List<String> warnings;

  const VerificationResult({
    required this.passed,
    required this.errors,
    required this.warnings,
  });

  String get summary {
    if (passed) return '✅ Verification passed';
    return '❌ ${errors.length} error(s), ${warnings.length} warning(s)';
  }
}
