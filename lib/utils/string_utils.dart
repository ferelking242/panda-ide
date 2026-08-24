import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:code_forge/code_forge.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:panda/utils/themes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../terminal/terminal.dart';
import '../utils/constants.dart';
import '../utils/languages.dart';

// String extensions for Panda IDE
// Extracted from functions.dart

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

Future<Map<String, dynamic>> sendRequest({
  required String url,
  required String method,
  Map<String, String>? headers,
  Object? body,
}) async {
  final uri = Uri.parse(url);
  http.Response response;

  try {
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: body);
        break;
      case 'PUT':
        response = await http.put(uri, headers: headers, body: body);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    return {
      'statusCode': response.statusCode,
      'headers': response.headers,
      'body': response.body,
    };
  } catch (e) {
    return {'error': e.toString()};
  }
}

void runCode(BuildContext context, String command, String rootDir) {
  try {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, scondaryAnimation) => SetupTerminal(projectDir: rootDir, args: ["-c", command]),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SizeTransition(sizeFactor: animation, child: child);
        },
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Execution failed: ${e.toString()}")),
    );
    debugPrint(e.toString());
  }
}

void runCodeInTermux(BuildContext context, String command, String rootDir, int? id) {
  try {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, scondaryAnimation) => SetupTerminal(
          projectDir: rootDir,
          termuxId: id,
          commandToExecuteInSSH: command,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SizeTransition(sizeFactor: animation, child: child);
        },
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Execution failed: ${e.toString()}")),
    );
    debugPrint(e.toString());
  }
}

String _resolveLspServerPath(String serverPath) {
  final normalized = serverPath
      .replaceAll('\$extensionDir', extensionDir)
      .replaceAll('\${extensionDir}', extensionDir);
  if (path.isAbsolute(normalized)) return normalized;
  return path.join(extensionDir, normalized);
}

String lspLanguageIdForExtension({
  required String ext,
  required String fallbackLanguageName,
}) {
  final normalizedExt = ext.toLowerCase().replaceFirst('.', '');

  switch (normalizedExt) {
    case 'c':
      return 'c';
    case 'cc':
    case 'cpp':
    case 'cxx':
    case 'c++':
    case 'h':
    case 'hh':
    case 'hpp':
    case 'hxx':
    case 'h++':
      return 'cpp';
    case 'js':
    case 'mjs':
    case 'cjs':
      return 'javascript';
    case 'jsx':
      return 'jsx';
    case 'ts':
      return 'typescript';
    case 'tsx':
      return 'tsx';
    case 'py':
    case 'pyi':
      return 'python';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'shellscript';
    default:
      break;
  }

  return fallbackLanguageName.trim().toLowerCase();
}

String lspLanguageIdForFile({
  required Language language,
  required String filePath,
}) {
  final ext = path.extension(filePath);
  return lspLanguageIdForExtension(
    ext: ext,
    fallbackLanguageName: language.name,
  );
}

String lspServerExtForExtension({required String ext}) {
  final normalizedExt = ext.toLowerCase().replaceFirst('.', '');
  switch (normalizedExt) {
    case 'jsx':
      return 'js';
    case 'tsx':
      return 'ts';
    default:
      return normalizedExt;
  }
}

String lspServerExtForFilePath(String filePath) {
  return lspServerExtForExtension(ext: path.extension(filePath));
}

bool isLspServerAvailable({
  required String ext,
  required String? executable,
  required List<String> args,
}) {
  if (executable == null || executable.isEmpty) return false;
  final executableExists = File(executable).existsSync();
  if (!executableExists) return false;
  final normalizedExt = ext.toLowerCase();

  if (normalizedExt == 'dart') {
    return File('$runtimesDir/dart/bin/dartaotruntime').existsSync() &&
      File('$runtimesDir/dart/bin/snapshots/analysis_server_aot.dart.snapshot')
        .existsSync();
  }

  if (normalizedExt == 'js' || normalizedExt == 'ts') {
    return File(
      '$runtimesDir/node/lib/node_modules/typescript-language-server/lib/cli.mjs',
    ).existsSync();
  }

  if (normalizedExt == 'c' ||
      normalizedExt == 'cpp' ||
      normalizedExt == 'cc' ||
      normalizedExt == 'c++') {
    return true;
  }

  String? serverFile;

  if (['py', 'sh', 'bash', 'zsh'].contains(normalizedExt)) {
    final matched = extensions.where(
      (item) => item.fileExtension.contains(normalizedExt),
    );
    if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
      serverFile = matched.first.serverFile.first;
    }
  } else if (normalizedExt == 'html') {
    final matched = extensions.where(
      (item) => item.fileExtension.any((ex) => ex == 'html'),
    );
    if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
      serverFile = matched.first.serverFile[0];
    }
  } else if (normalizedExt == 'css') {
    final matched = extensions.where(
      (item) => item.fileExtension.any((ex) => ex == 'css'),
    );
    if (matched.isNotEmpty && matched.first.serverFile.length > 1) {
      serverFile = matched.first.serverFile[1];
    }
  } else if (normalizedExt == 'json') {
    final matched = extensions.where(
      (item) => item.fileExtension.any((ex) => ex == 'json'),
    );
    if (matched.isNotEmpty && matched.first.serverFile.length > 2) {
      serverFile = matched.first.serverFile[2];
    }
  }

  if (serverFile != null && serverFile.isNotEmpty) {
    final resolved = _resolveLspServerPath(serverFile);
    return File(resolved).existsSync();
  }

  return true;
}

Future<LspConfig?> startLspServer({
  required String ext,
  required String? executable,
  required List<String> args,
  required String workspacePath,
  required String langId,
  Map<String, String>? environment,
  LspClientCapabilities? capabilities,
}) async {
  if (executable == null) return null;
  try {
    final String sharedPath = await NativeChannel.getLibraryPath();
    final String runtimeDir = runtimesDir;
    final String normalizedExt = ext.toLowerCase();
    final String dartRuntimeDir = '$runtimeDir/dart';
    final String dartRuntimeExecutable = '$dartRuntimeDir/bin/dart';
    final String dartAotRuntimeExecutable = '$dartRuntimeDir/bin/dartaotruntime';
    final String dartAnalysisServerSnapshot = '$dartRuntimeDir/bin/snapshots/analysis_server_aot.dart.snapshot';
    final String resolvedExecutable = normalizedExt == 'dart'
      ? dartAotRuntimeExecutable
      : executable;
    List<String> resolveServerArgs(String ext, List<String> args) {
      final normalizedExt = ext.toLowerCase();

      if (['sh', 'bash', 'zsh'].contains(normalizedExt)) {
        final matched = extensions.where(
          (item) => item.fileExtension.contains(normalizedExt),
        );
        if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
          return [matched.first.serverFile.first, ...args];
        }
      }

      if (normalizedExt == 'html') {
        final matched = extensions.where(
          (item) => item.fileExtension.any((ex) => ex == 'html'),
        );
        if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
          return [matched.first.serverFile[0], ...args];
        }
      }

      if (normalizedExt == 'css') {
        final matched = extensions.where(
          (item) => item.fileExtension.any((ex) => ex == 'css'),
        );
        if (matched.isNotEmpty && matched.first.serverFile.length > 1) {
          return [matched.first.serverFile[1], ...args];
        }
      }

      if (normalizedExt == 'json') {
        final matched = extensions.where(
          (item) => item.fileExtension.any((ex) => ex == 'json'),
        );
        if (matched.isNotEmpty && matched.first.serverFile.length > 2) {
          return [matched.first.serverFile[2], ...args];
        }
      }

      return args;
    }

    final resolvedArgs = (() {
      if (normalizedExt == 'ts' || normalizedExt == 'js') {
        return [
          "$runtimeDir/node/lib/node_modules/typescript-language-server/lib/cli.mjs",
          ...args,
        ];
      } else if (normalizedExt == 'py' || normalizedExt == 'pyi') {
        return ["server"];
      } else if (normalizedExt == 'c' ||
          normalizedExt == 'cpp' ||
          normalizedExt == 'cc' ||
          normalizedExt == 'c++' ||
          normalizedExt == 'h' ||
          normalizedExt == 'hpp' ||
          normalizedExt == 'hh' ||
          normalizedExt == 'hxx') {
        return [
          '--init={"cache":{"directory":"$tempDir/.ccls-cache"}, "clang":{"extraArgs":["-isystem","$runtimeDir/clang/sysroot/usr/include/c++/v1","-isystem","$runtimeDir/clang/sysroot/usr/include","-isystem","$runtimeDir/clang/lib/clang/21/include"],"resourceDir":"$runtimeDir/clang/lib/clang/21"}}',
        ];
      } else if (normalizedExt == 'dart') {
        return [
          dartAnalysisServerSnapshot,
          "--protocol=lsp",
          "--dart-sdk=$dartRuntimeDir",
        ];
      }
      return resolveServerArgs(ext, args);
    })();

    final resolvedEnvironment = {
      ...environment ?? {},
      'PATH': '$binDir:$runtimeDir/dart/bin:/bin:/usr/bin:${Platform.environment['PATH'] ?? ''}',
      'ROXUM_SHARED_PATH': sharedPath,
      'LD_LIBRARY_PATH': '${normalizedExt == 'dart' ? '$sharedPath:$libDir' : '$libDir:$runtimeDir/clang:$runtimeDir/node/lib:$sharedPath'}:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      if (normalizedExt == 'dart') 'DART_ROOT': dartRuntimeDir,
      'JAVA_HOME': '$runtimeDir/java-21-openjdk',
    };

    if (normalizedExt == 'dart') {
      try {
        final config = await LspStdioConfig.start(
          executable: resolvedExecutable,
          capabilities: capabilities ?? const LspClientCapabilities(),
          args: resolvedArgs,
          environment: resolvedEnvironment,
          workspacePath: workspacePath,
          languageId: langId.toLowerCase(),
        );
        debugPrint('Dart LSP started with AOT runtime executable: $resolvedExecutable');
        return config;
      } catch (primaryError) {
        debugPrint(
          'Primary Dart LSP startup failed with $resolvedExecutable: $primaryError',
        );
        final fallbackExecutable = dartRuntimeExecutable;
        final fallbackConfig = await LspStdioConfig.start(
          executable: fallbackExecutable,
          capabilities: capabilities ?? const LspClientCapabilities(),
          args: [
            'language-server',
            '--protocol=lsp',
            '--sdk=$dartRuntimeDir',
          ],
          environment: resolvedEnvironment,
          workspacePath: workspacePath,
          languageId: langId.toLowerCase(),
        );
        debugPrint('Dart LSP started with fallback executable: $fallbackExecutable');
        return fallbackConfig;
      }
    }

    final config = await LspStdioConfig.start(
      executable: resolvedExecutable,
      capabilities: capabilities ?? const LspClientCapabilities(),
      args: resolvedArgs,
      environment: resolvedEnvironment,
      workspacePath: workspacePath,
      languageId: langId.toLowerCase(),
    );
    return config;
  } catch (e) {
    debugPrint('LSP Initialization failed: $e');
  }
  return null;
}

