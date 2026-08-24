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

// Git operations — clone, commit, push, pull, branch, etc.
// Extracted from functions.dart

/// Ensures private roots and only probes shared storage for import/export.
Future<bool> configureStorageRoots() async {
  // Resolve the actual app data directory from path_provider.
  // On most Android devices this returns <actual_app_data>/app_flutter,
  // so we go one level up to get the true app root.
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    // docsDir.path is typically /data/data/<pkg>/app_flutter or
    // /storage/emulated/0/Android/data/<pkg>/files/app_flutter
    // Go up to the app root.
    final parent = docsDir.parent;
    final basePath = parent.path;
    print('[StorageRoots] path_provider docs: ${docsDir.path}');
    print('[StorageRoots] resolved basePath: $basePath');
    resolveAppDir(basePath);
  } catch (e) {
    print('[StorageRoots] path_provider failed, using default appDir: $e');
  }
  usePrivateStorageRoots();
  for (final root in [
    Directory(pandaRootDir),
    Directory(projectDir),
    Directory(templateDir),
    Directory(filesDir),
    Directory(pandaLogsDir),
  ]) {
    await root.create(recursive: true);
  }
  final publicRoot = Directory(publicPandaRootDir);
  try {
    if (!await publicRoot.exists()) return false;
    final probe = File(path.join(publicRoot.path, '.panda_write_probe'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

Future<Directory> setupProjectDir() async {
  for (final candidate in [Directory(projectDir)]) {
    try {
      await candidate.create(recursive: true);
      return candidate;
    } on FileSystemException {
      continue;
    }
  }
  throw FileSystemException(
    'Unable to create Panda IDE projects directory',
    projectDir,
  );
}

Future<Directory> setupTempDir() async {
  final target = Directory(tempDir);
  if (!target.existsSync()) {
    await target.create(recursive: true);
  }
  return target;
}

Future<Directory> setupFilesDir() async {
  // On web, dart:io paths like /data/data/... don't exist.
  // Use path_provider which returns an IDBFS-backed virtual path on web.
  if (kIsWeb) {
    final appDir = await getApplicationDocumentsDirectory();
    final webFilesDir = Directory('${appDir.path}/panda_files');
    if (!webFilesDir.existsSync()) {
      await webFilesDir.create(recursive: true);
    }
    return webFilesDir;
  }

  // The active root is always private. Shared storage is never a startup
  // dependency and is only used by explicit import/export flows.
  final candidates = <Directory>[Directory(filesDir)];
  Directory? target;
  for (final candidate in candidates) {
    try {
      if (!candidate.existsSync()) {
        await candidate.create(recursive: true);
      }
      final probe = File(path.join(candidate.path, '.panda_write_probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      target = candidate;
      break;
    } on FileSystemException {
      continue;
    }
  }
  if (target == null) {
    throw FileSystemException(
      'Unable to create Panda IDE files directory',
      candidates.last.path,
    );
  }

  final ggufDir = Directory(path.join(target.path, 'gguf'));
  await ggufDir.create(recursive: true);
  final currentFiles = File(path.join(target.path, '.current_files.json'));

  try {
    if (!await currentFiles.exists()) {
      await currentFiles.writeAsString(jsonEncode({}), flush: true);
      return target;
    }

    final raw = await currentFiles.readAsString();
    if (raw.trim().isEmpty) {
      await currentFiles.writeAsString(jsonEncode({}), flush: true);
      return target;
    }

    final decoded = jsonDecode(raw);
    final data = decoded is Map ? decoded : const <dynamic, dynamic>{};
    final cleaned = <String, String>{};
    for (final entry in data.entries) {
      final relativePath = entry.key.toString();
      if (await File(path.join(target.path, relativePath)).exists()) {
        cleaned[relativePath] = entry.value.toString();
      }
    }
    await currentFiles.writeAsString(jsonEncode(cleaned), flush: true);
  } catch (_) {
    await currentFiles.writeAsString(jsonEncode({}), flush: true);
  }

  return target;
}

Future<Directory> setupTemplateDir() async {
  for (final candidate in [Directory(templateDir)]) {
    try {
      await candidate.create(recursive: true);
      return candidate;
    } on FileSystemException {
      continue;
    }
  }
  throw FileSystemException(
    'Unable to create Panda IDE templates directory',
    templateDir,
  );
}

Future<File> setTempFile(String extension) async {
  final dir = await setupTemplateDir();

  File target;
  if (extension == 'html') {
    target = File('${dir.path}/index.html');
  } else if (extension == 'css') {
    target = File('${dir.path}/style.css');
  } else if (extension == 'js') {
    target = File('${dir.path}/script.js');
  } else {
    target = File('${dir.path}/tempCode.$extension');
  }

  if (!target.existsSync() || target.readAsStringSync().isEmpty) {
    await target.create(recursive: true);
    await target.writeAsString(
      languages.firstWhere(
        (lang) => lang.extension.contains(path.extension(target.path).replaceFirst(".", "")),
        orElse: () => languages[0],
      ).helloWorld,
    );
  }

  return target;
}

Map<String, String> gitEnvs(String sharedPath) => {
  'PATH': '$binDir:/bin:/usr/bin',
  'HOME': homeDir,
  'GIT_EXEC_PATH': '$binDir/git-core',
  'GIT_SSL_CAINFO': '$certDir/cacert.pem',
  'LD_LIBRARY_PATH': "$sharedPath:$libDir",
  'ROXUM_SHARED_PATH': sharedPath,
};

Future<void> cloneRepo(
  String location,
  String url,
  void Function(double progress) onProgress,
  {
  String? branch,
  int? depth,
  String? targetDirectory,
  bool recursive = false,
  }
) async {
  final sharedPath = await NativeChannel.getLibraryPath();

  final cloneArgs = <String>['clone', '--progress'];
  if (branch != null && branch.trim().isNotEmpty) {
    cloneArgs.addAll(['--branch', branch.trim()]);
  }
  if (depth != null && depth > 0) {
    cloneArgs.addAll(['--depth', '$depth']);
  }
  if (recursive) {
    cloneArgs.add('--recurse-submodules');
  }
  cloneArgs.add(url);
  if (targetDirectory != null && targetDirectory.trim().isNotEmpty) {
    cloneArgs.add(targetDirectory.trim());
  }

  final process = await Process.start(
    '$binDir/git',
    cloneArgs,
    workingDirectory: location,
    environment: gitEnvs(sharedPath),
  );

  final progressRegex = RegExp(
    r'(Receiving objects|Resolving deltas|Compressing objects):\s+(\d+)%',
  );

  process.stderr.listen((data) {
    final text = String.fromCharCodes(data);

    final match = progressRegex.firstMatch(text);
    if (match != null) {
      final percent = double.parse(match.group(2)!);
      onProgress(percent / 100);
    }
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception(
      'git clone failed with exit code $exitCode'
      '${branch != null && branch.trim().isNotEmpty ? ' for branch "${branch.trim()}"' : ''}',
    );
  }
}

Future<void> initRepo(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["init"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  await Process.run(
    "$binDir/git",
    ["config", "--local", "user.name", "Panda user"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  await Process.run(
    "$binDir/git",
    ["config", "--local", "user.email", "panda@local"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  await createGitignoreIfNeeded(workspacePath);
}

Future<void> createGitignoreIfNeeded(String workspacePath) async {
  final gitignoreFile = File('$workspacePath/.gitignore');
  final patterns = _getGitignorePatterns();

  if (await gitignoreFile.exists()) {
    final existingContent = await gitignoreFile.readAsString();
    final existingLines = existingContent
      .split('\n')
      .map((e) => e.trim())
      .toSet();

    final patternsToAdd = <String>[];
    for (final pattern in patterns) {
      final trimmedPattern = pattern.trim();
      if (trimmedPattern.isNotEmpty &&
          !trimmedPattern.startsWith('#') &&
          !existingLines.contains(trimmedPattern)) {
        patternsToAdd.add(pattern);
      }
    }

    if (patternsToAdd.isNotEmpty) {
      await gitignoreFile.writeAsString(
        '$existingContent\n\n# Auto-added by Panda\n${patternsToAdd.join('\n')}\n',
        mode: FileMode.append,
      );
    }
  } else {
    await gitignoreFile.writeAsString('${patterns.join('\n')}\n');
  }
}

List<String> _getGitignorePatterns() {
  return [
    '# Panda and Editor files',
    '.vscode/',
    '.idea/',
    '*.swp',
    '*.swo',
    '*~',
    '.DS_Store',
    '',
    '# Language Server Protocol (LSP) cache directories',
    '.ccls-cache/',
    'jdt.ls-java-project',
    '.clangd/',
    '.cache/',
    'compile_commands.json',
    '__pycache__/',
    '*.pyc',
    '.mypy_cache/',
    '.ruff_cache/',
    '.pytest_cache/',
    'pyrightconfig.json',
    '*.jdt.ls/',
    '.settings/',
    '',
    '# Dependencies',
    'node_modules/',
    '.pnpm-store/',
    '.npm/',
    '.yarn/',
    '.venv/',
    'venv/',
    'env/',
    'ENV/',
    '',
    '# Flutter / Dart',
    '.dart_tool/',
    '.packages',
    'pubspec.lock',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.metadata',
    '',
    '# Java / Android',
    'bin/',
    '.classpath',
    '.project',
    '.factorypath',
    '*.class',
    '.gradle/',
    'local.properties',
    '.externalNativeBuild/',
    '.cxx/',
    '',
    '# Node / TypeScript',
    'tsconfig.tsbuildinfo',
    '.eslintcache',
    '*.tsbuildinfo',
    '',
    '# Build outputs',
    'build/',
    'dist/',
    'out/',
    'target/',
    '*.o',
    '*.a',
    '*.so',
    '*.dylib',
    '*.dll',
    '*.exe',
    '*.app',
    '*.apk',
    '*.aab',
    '*.ipa',
    '*.so.*',
    '*.dylib.*',
    '',
    '# Logs and databases',
    '*.log',
    '*.sql',
    '*.sqlite',
    '*.db',
    '',
    '# Environment files',
    '.env',
    '.env.*',
    '',
    '# Temporary files',
    '*.tmp',
    '*.temp',
    '*.bak',
    '*.backup',
    '',
    '# Coverage reports',
    'coverage/',
    '.coverage',
    'htmlcov/',
    '',
    '# Package files',
    '*.tar.gz',
    '*.zip',
    '*.rar',
    '*.7z',
    '',
    '# OS files',
    '*.iml',
    'Thumbs.db',
    'Desktop.ini',
    '.Spotlight-V100',
    '.Trashes',
    '',
    '# Shell configuration',
    '.bashrc',
  ];
}

Future<ProcessResult> getRepoStatus(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["status", "--porcelain=v1", "-uall"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<void> stageChange(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["add", fileName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<void> stageAll(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["add", "--all"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<void> unstageChange(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final env = gitEnvs(sharedPath);

  final hasHead = await _hasInitialCommit(workspacePath, env);

  final args = hasHead
      ? ["restore", "--staged", fileName]
      : ["reset", fileName];

  await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: env,
  );
}

Future<void> unstageAll(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final env = gitEnvs(sharedPath);

  final hasHead = await _hasInitialCommit(workspacePath, env);

  final args = hasHead ? ["restore", "--staged", "."] : ["reset", "."];

  await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: env,
  );
}

Future<bool> _hasInitialCommit(
  String workspacePath,
  Map<String, String> env,
) async {
  final result = await Process.run(
    "$binDir/git",
    ["rev-parse", "--verify", "HEAD"],
    workingDirectory: workspacePath,
    environment: env,
  );

  return result.exitCode == 0;
}

Future<ProcessResult> gitCommit(
  String workspacePath,
  String message, {
  bool all = false,
  bool amend = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['commit'];
  if (amend) args.add('--amend');
  if (all) args.add('-a');
  args.addAll(['-m', message]);

  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  return result;
}

Future<List<CommitNode>> getGraph(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["log", "--all", "--date=short", "--pretty=format:%H%x01%P%x01%an%x01%s%x01%ad"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  String? headHash;
  String? upstreamHash;

  final headResult = await Process.run(
    "$binDir/git",
    ["rev-parse", "HEAD"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (headResult.exitCode == 0) {
    headHash = (headResult.stdout as String).trim();
  }

  final upstreamResult = await Process.run(
    "$binDir/git",
    ["rev-parse", "--verify", "@{u}"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (upstreamResult.exitCode == 0) {
    upstreamHash = (upstreamResult.stdout as String).trim();
  }

  final List<CommitNode> commits = [];
  final lines = result.stdout.toString().split('\n');

  for (final line in lines) {
    if (line.trim().isEmpty) continue;

    final parts = line.split('\x01');
    if (parts.length >= 4) {
      final hash = parts[0];
      final parentHashes = parts[1].isEmpty ? <String>[] : parts[1].split(' ');
      final author = parts[2];
      final message = parts[3];
      final date = parts.length > 4 ? parts[4] : '';

      commits.add(
        CommitNode(
          hash: hash,
          parents: parentHashes,
          author: author,
          message: message,
          date: date,
          isHead: hash == headHash,
          isRemoteHead: upstreamHash != null && hash == upstreamHash,
        ),
      );
    }
  }

  return commits;
}

Future<void> gitRestoreFile(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["restore", fileName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

