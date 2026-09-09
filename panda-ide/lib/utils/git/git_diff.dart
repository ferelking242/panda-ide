import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:panda/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../extractors.dart';
import 'git_operations.dart';
import '../editors/editor_theme.dart';

// Git diff parsing and result model
// Extracted from functions.dart

class GitDiffResult {
  final String diffText;
  final List<(int startLine, int endLine)> addedRanges;
  final List<({int afterLine, String content})> removedRanges;

  GitDiffResult({
    required this.diffText,
    required this.addedRanges,
    required this.removedRanges,
  });
}

Future<GitDiffResult> getGitDiff(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["diff", "--function-context", fileName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  final diffTextOriginal = result.stdout as String;
  final addedRanges = <(int, int)>[];
  final removedRanges = <({int afterLine, String content})>[];

  final lines = diffTextOriginal.split('\n');
  final filteredLines = lines
    .where(
      (line) =>
        !line.startsWith('diff --git') &&
        !line.startsWith('index ') &&
        !line.startsWith('--- ') &&
        !line.startsWith('+++ '),
    )
    .toList();

  final visibleLines = <String>[];

  int? currentAddedStart;
  int? currentRemovedAfterLine;
  final removedContent = StringBuffer();

  void flushAdded(int endExclusive) {
    if (currentAddedStart == null) return;
    addedRanges.add((currentAddedStart!, endExclusive - 1));
    currentAddedStart = null;
  }

  void flushRemoved() {
    if (currentRemovedAfterLine == null) return;
    removedRanges.add((
      afterLine: currentRemovedAfterLine!,
      content: removedContent.toString(),
    ));
    currentRemovedAfterLine = null;
    removedContent.clear();
  }

  for (final line in filteredLines) {
    final isAdded = line.startsWith('+');
    final isRemoved = line.startsWith('-');

    if (isRemoved) {
      flushAdded(visibleLines.length);
      currentRemovedAfterLine ??= visibleLines.isEmpty
          ? 0
          : visibleLines.length - 1;
      if (removedContent.isNotEmpty) {
        removedContent.write('\n');
      }
      removedContent.write(line.length > 1 ? line.substring(1) : '');
      continue;
    }

    flushRemoved();

    if (isAdded) {
      currentAddedStart ??= visibleLines.length;
      visibleLines.add(line);
      continue;
    }

    flushAdded(visibleLines.length);
    visibleLines.add(line);
  }

  flushAdded(visibleLines.length);
  flushRemoved();

  final diffText = visibleLines.join('\n');

  return GitDiffResult(
    diffText: diffText,
    addedRanges: addedRanges,
    removedRanges: removedRanges,
  );
}

Future<ProcessResult> gitPush(
  String workspacePath, {
  String? remote,
  String? branch,
  bool setUpstream = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['push'];
  if (setUpstream) args.add('-u');
  if (remote != null) args.add(remote);
  if (branch != null) args.add(branch);
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result;
}

Future<ProcessResult> gitPull(
  String workspacePath, {
  String? remote,
  String? branch,
  bool rebase = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['pull'];
  if (rebase) args.add('--rebase');
  if (remote != null) args.add(remote);
  if (branch != null) args.add(branch);
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result;
}

Future<ProcessResult> gitFetch(
  String workspacePath, {
  String? remote,
  bool all = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['fetch'];
  if (all) args.add('--all');
  if (remote != null && !all) args.add(remote);
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result;
}

Future<ProcessResult> gitSync(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final pullResult = await Process.run(
    "$binDir/git",
    ["pull", "--rebase"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (pullResult.exitCode != 0) return pullResult;

  final pushResult = await Process.run(
    "$binDir/git",
    ["push"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return pushResult;
}

Future<List<String>> gitListBranches(
  String workspacePath, {
  bool remote = false,
  bool all = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['branch'];
  if (all) {
    args.add('-a');
  } else if (remote) {
    args.add('-r');
  }
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
      .split('\n')
      .map((b) => b.replaceFirst('*', '').trim())
      .where((b) => b.isNotEmpty)
      .toList();
}

Future<String?> gitCurrentBranch(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["branch", "--show-current"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return null;
  final branch = (result.stdout as String).trim();

  if (branch.isEmpty) {
    final descResult = await Process.run(
      "$binDir/git",
      ["describe", "--tags", "--exact-match", "HEAD"],
      workingDirectory: workspacePath,
      environment: gitEnvs(sharedPath),
    );
    if (descResult.exitCode == 0) {
      return (descResult.stdout as String).trim();
    }

    final refResult = await Process.run(
      "$binDir/git",
      ["rev-parse", "--short", "HEAD"],
      workingDirectory: workspacePath,
      environment: gitEnvs(sharedPath),
    );
    if (refResult.exitCode == 0) {
      return (refResult.stdout as String).trim();
    }
    return "HEAD";
  }

  return branch;
}

Future<ProcessResult> gitCreateBranch(
  String workspacePath,
  String branchName, {
  String? fromRef,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['checkout', '-b', branchName];
  if (fromRef != null) args.add(fromRef);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitCheckoutBranch(
  String workspacePath,
  String branchName,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["checkout", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitRenameBranch(
  String workspacePath,
  String oldName,
  String newName,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["branch", "-m", oldName, newName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteBranch(
  String workspacePath,
  String branchName, {
  bool force = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["branch", force ? "-D" : "-d", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteRemoteBranch(
  String workspacePath,
  String branchName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", remote, "--delete", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitMergeBranch(
  String workspacePath,
  String branchName, {
  bool noFf = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['merge'];
  if (noFf) args.add('--no-ff');
  args.add(branchName);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitRebaseBranch(
  String workspacePath,
  String branchName,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["rebase", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitPublishBranch(
  String workspacePath,
  String branchName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", "-u", remote, branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<List<Map<String, String>>> gitListStashes(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["stash", "list", "--format=%gd%x01%s"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  final lines = (result.stdout as String)
      .split('\n')
      .where((l) => l.isNotEmpty);
  return lines.map((line) {
    final parts = line.split('\x01');
    return {
      'ref': parts.isNotEmpty ? parts[0] : '',
      'message': parts.length > 1 ? parts[1] : '',
    };
  }).toList();
}


Future<List<String>> gitListTags(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["tag", "-l"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
    .split('\n')
    .where((t) => t.isNotEmpty)
    .toList();
}

Future<ProcessResult> gitCreateTag(
  String workspacePath,
  String tagName, {
  String? message,
  String? ref,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['tag'];
  if (message != null && message.isNotEmpty) {
    args.addAll(['-a', tagName, '-m', message]);
  } else {
    args.add(tagName);
  }
  if (ref != null) args.add(ref);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteTag(String workspacePath, String tagName) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["tag", "-d", tagName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteRemoteTag(
  String workspacePath,
  String tagName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", remote, "--delete", "refs/tags/$tagName"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitPushTag(
  String workspacePath,
  String tagName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", remote, tagName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<List<String>> gitListRemotes(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["remote"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
      .split('\n')
      .where((r) => r.isNotEmpty)
      .toList();
}

Future<String?> gitGetRemoteUrl(
  String workspacePath, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["remote", "get-url", remote],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trim();
}

Future<ProcessResult> gitAddRemote(
  String workspacePath,
  String name,
  String url,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["remote", "add", name, url],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<bool> hasRemote(String workspacePath) async {
  final remotes = await gitListRemotes(workspacePath);
  return remotes.isNotEmpty;
}

Future<int> getUnpushedCommitCount(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["rev-list", "--count", "@{u}..HEAD"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return 0;
  return int.tryParse((result.stdout as String).trim()) ?? 0;
}

Future<int> getUnpulledCommitCount(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await gitFetch(workspacePath);
  final result = await Process.run(
    "$binDir/git",
    ["rev-list", "--count", "HEAD..@{u}"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return 0;
  return int.tryParse((result.stdout as String).trim()) ?? 0;
}

Future<bool> hasUpstream(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result.exitCode == 0;
}

Future<String> gitHubSignIn() async {
  final secureStorage = const FlutterSecureStorage();
  const clientId     = "Ov23li7t3A7ZkHgtN7hl";
  const clientSecret = "1d4d1ec47b757082e0497938b593c352a7200db7";

  final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
    'client_id': clientId,
    'scope': 'repo read:user',
    'redirect_uri': 'panda://oauth',
  });

  try {
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: 'panda',
      options: const FlutterWebAuth2Options(),
    );

    final code = Uri.parse(result).queryParameters['code'];

    if (code == null || code.isEmpty) {
      return 'No authorization code received';
    }

    // Échange direct — pas de backend nécessaire sur mobile
    final response = await http
      .post(
        Uri.https('github.com', '/login/oauth/access_token'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'client_id': clientId,
          'client_secret': clientSecret,
          'code': code,
        }),
      )
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () => http.Response('Timeout', 408),
      );

    if (response.statusCode != 200) {
      return '${response.statusCode}: ${response.body}';
    }

    final data = jsonDecode(response.body);

    if (data['error'] != null) {
      return data['error_description'] ?? data['error'];
    }

    final accessToken = data['access_token'] as String?;

    if (accessToken == null || accessToken.isEmpty) {
      return 'No access token received';
    }

    await secureStorage.write(key: 'github_access_token', value: accessToken);

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      await _configureGitIdentity(jsonDecode(response.body));
      await _configureGitCredentialHelper();
      await _approveGithubCredentials(accessToken);
    } catch (e) {
      debugPrint('Failed to load user info: $e');
    }

    return "success";
  } catch (e) {
    final err = e.toString();
    if (err.contains('PlatformException(CANCELED') ||
        err.toLowerCase().contains('user canceled')) {
      return 'Sign in was canceled';
    }
    return e.toString();
  }
}

String resolveGitEmail(Map<String, dynamic> user) {
  final email = user['email'];
  final login = user['login'];
  if (email != null && email.toString().isNotEmpty) {
    return email;
  }
  return '$login@users.noreply.github.com';
}

Future<void> _configureGitIdentity(Map<String, dynamic> user) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final name = user['name'] ?? user['login'];
  final email = resolveGitEmail(user);

  await Process.run("$binDir/git", [
    "config",
    "--global",
    "user.name",
    name,
  ], environment: gitEnvs(sharedPath));

  await Process.run("$binDir/git", [
    "config",
    "--global",
    "user.email",
    email,
  ], environment: gitEnvs(sharedPath));
}

Future<void> _configureGitCredentialHelper() async {
  final sharedPath = await NativeChannel.getLibraryPath();

  await Process.run("$binDir/git", [
    "config",
    "--global",
    "credential.helper",
    "store",
  ], environment: gitEnvs(sharedPath));
}

Future<void> _approveGithubCredentials(String token) async {
  final sharedPath = await NativeChannel.getLibraryPath();

  final process = await Process.start("$binDir/git", [
    "credential-store",
    "store",
  ], environment: gitEnvs(sharedPath));

  process.stdin.write(
    "protocol=https\n"
    "host=github.com\n"
    "username=oauth2\n"
    "password=$token\n\n",
  );

  await process.stdin.close();
  await process.exitCode;
}

Future<void> clearGitCredentials() async {
  final sharedPath = await NativeChannel.getLibraryPath();

  await Process.run(
    "$binDir/git",
    ["credential", "reject"],
    environment: gitEnvs(sharedPath),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  final home = Directory(homeDir);
  final credsFile = File('${home.path}/.git-credentials');
  if (credsFile.existsSync()) {
    credsFile.deleteSync();
  }
}

String extractRepoName(String url) {
  url = url.replaceFirst(RegExp(r'^(https?://|git@)'), '');
  final parts = url.split(RegExp(r'[:/]'));
  if (parts.isEmpty) return '';
  String repoName = parts.last;
  if (repoName.endsWith('.git')) {
    repoName = repoName.substring(0, repoName.length - 4);
  }

  return repoName;
}

Future<File?> pickFile() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: false,
    type: FileType.custom,
    withData: kIsWeb, // always fetch bytes on web since there's no file path
  );

  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.first;

  if (picked.path == null && picked.bytes == null) {
    return null;
  }

  final projectDir = await setupFilesDir();

  // On web we skip the identifier/metadata JSON since dart:io may not fully
  // support it; the file bytes path below is always taken instead.
  if (!kIsWeb) {
    final currentFiles = File('${projectDir.path}/.current_files.json');
    Map<String, String> fileMap = {};
    if (currentFiles.existsSync() && currentFiles.lengthSync() > 0) {
      fileMap = Map<String, String>.from(
        jsonDecode(currentFiles.readAsStringSync()),
      );
    }
    if (picked.identifier != null) {
      fileMap[picked.name] = picked.identifier!;
    }
    await currentFiles.writeAsString(jsonEncode(fileMap), flush: true);
  }

  final targetFile = File('${projectDir.path}/${picked.name}');

  if (picked.bytes != null) {
    await targetFile.writeAsBytes(picked.bytes!, flush: true);
  } else {
    final tempFile = File(picked.path!);
    await tempFile.copy(targetFile.path);
  }

  return targetFile;
}

Future<Directory?> pickDir() async {
  // SAF (Storage Access Framework) is Android-only; not available on web or desktop.
  if (kIsWeb) return null;
  const MethodChannel saf = MethodChannel('panda/saf');
  final String? treeUri = await saf.invokeMethod<String>('pickSafDir');

  if (treeUri == null) return null;

  final projectPath = await saf.invokeMethod<String>('cloneSafDir', {
    'uri': treeUri,
  });
  if (projectPath == null) return null;
  return Directory(projectPath);
}

Future<String?> selectDir({
  String? dialogeTitle,
  String? initialDirectory,
  String? fileName,
  Uint8List? bytes,
}) async {
  return await FilePicker.saveFile(
    dialogTitle: dialogeTitle,
    fileName: fileName,
    initialDirectory: initialDirectory,
    bytes: bytes,
  );
}

Future<File?> createFile(
  String filename,
  String dirPath,
  BuildContext context,
) async {
  final file = File("$dirPath/$filename");

  if (kIsWeb) {
    // On Flutter web, dart:io sync calls (existsSync, createSync) are
    // not supported. Use only async APIs and return the File object
    // regardless — the editor's own try/catch handles a missing/unreadable
    // file gracefully by starting with empty content.
    try {
      final dir = Directory(dirPath);
      await dir.create(recursive: true);
    } catch (_) { /* best-effort: virtual FS may not need explicit mkdir */ }
    try {
      await file.create(recursive: true);
    } catch (_) { /* best-effort: return File path even if creation fails */ }
    return file;
  }

  // ── Native (Android / desktop) path ──────────────────────────────────────
  final fileDir = Directory(dirPath);
  if (!fileDir.existsSync()) {
    await fileDir.create(recursive: true);
  }
  if (!file.existsSync()) {
    try {
      await file.create(recursive: true);
      return file;
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(e.toString()),
            title: const Text(
              "Failed to open file",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w300),
            ),
            backgroundColor: const Color(0xff2b2b2b),
            icon: const Icon(Icons.error_outline),
            iconColor: Colors.red[600],
          ),
        );
      }
      return null;
    }
  }
  return file;
}

Future<HttpServer?> startServer() async {
  try {
    final server = await HttpServer.bind('127.0.0.1', 49258);
    return server;
  } catch (e) {
    return null;
  }
}

Future<String> getRecent() async {
  final prefs = await SharedPreferences.getInstance();
  final recent = prefs.getString('recent');
  return recent ?? '[]';
}

const String copilotEnabledPrefKey = 'isCopilotEnabled';
const String copilotSignedPrefKey = 'isSignedCopilot';

Future<bool> ensureCopilotEnabledPrefInitialized() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotEnabledPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotEnabledPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<bool> ensureCopilotSignedPrefInitialized() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotSignedPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotSignedPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<bool> isCopilotSignedPref() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotSignedPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotSignedPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<void> setCopilotSignedPref(bool isSignedIn) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(copilotSignedPrefKey, isSignedIn);
}

Future<bool> isCopilotEnabledPref() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotEnabledPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotEnabledPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<void> setCopilotEnabledPref(bool isEnabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(copilotEnabledPrefKey, isEnabled);
}

Future<String> getAppTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final savedAppTheme = prefs.getString("savedAppTheme");
  return savedAppTheme ?? "dark";
}

Future<String> getCodeForgeConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final defaultConfig = {
    "indentLineStatus": true,
    "lineWrap": false,
    "enableFolding": true,
    "theme": "vs2015",
    "terminalTheme": "classic-green",
    "fontFamily": "jetBrainsMono",
    "terminalFontSize": 14.0,
    "isAIEnabled": true,
    "manualCompletion": true,
    "autoSave": true,
    "enableLSP": true,
    "LSPFeatureToggle": {},
    "customEditorThemes": {},
  };
  final configString = prefs.getString('codeForgeConfig');
  if (configString == null) {
    return jsonEncode(defaultConfig);
  }
  try {
    final Map<String, dynamic> storedConfig = jsonDecode(configString);
    final mergedConfig = Map<String, dynamic>.from(defaultConfig)
      ..addAll(storedConfig);
    return jsonEncode(mergedConfig);
  } catch (e) {
    return jsonEncode(defaultConfig);
  }
}

Map<String, CustomEditorTheme> getCustomEditorThemes(Map<String, dynamic> codeForgeConfig) {
  final rawThemes = codeForgeConfig['customEditorThemes'];
  if (rawThemes is! Map) {
    return {};
  }

  final themes = <String, CustomEditorTheme>{};
  rawThemes.forEach((key, value) {
    if (key == null || value == null) {
      return;
    }

    final themeName = key.toString();
    if (value is Map<String, dynamic>) {
      themes[themeName] = CustomEditorTheme.fromJson(value);
    } else if (value is Map) {
      themes[themeName] = CustomEditorTheme.fromJson(
        Map<String, dynamic>.from(value),
      );
    }
  });

  return themes;
}

Map<String, Map<String, TextStyle>> getMergedHighlightThemes(Map<String, dynamic> codeForgeConfig) {
  final mergedThemes = Map<String, Map<String, TextStyle>>.from(highlightThemes);
  getCustomEditorThemes(codeForgeConfig).forEach((themeName, theme) {
    mergedThemes[themeName] = theme.toMap();
  });
  return mergedThemes;
}

Future<String> getAiConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final defaultConfig = {};
  final configString = prefs.getString('aiConfig');
  if (configString == null) {
    return jsonEncode(defaultConfig);
  }
  try {
    final Map<String, dynamic> storedConfig = jsonDecode(configString);
    final mergedConfig = Map<String, dynamic>.from(defaultConfig)
      ..addAll(storedConfig);
    return jsonEncode(mergedConfig);
  } catch (e) {
    return jsonEncode(defaultConfig);
  }
}

Future<String> getModelSelected() async {
  final prefs = await SharedPreferences.getInstance();
  final defaultConfig = {"code": "", "chat": ""};
  final configString = prefs.getString('modelSelected');
  if (configString == null) {
    return jsonEncode(defaultConfig);
  }
  try {
    final Map<String, dynamic> storedConfig = jsonDecode(configString);
    final mergedConfig = Map<String, dynamic>.from(defaultConfig)
      ..addAll(storedConfig);
    return jsonEncode(mergedConfig);
  } catch (e) {
    return jsonEncode(defaultConfig);
  }
}

