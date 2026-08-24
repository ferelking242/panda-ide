import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_json/flutter_json.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import '../../utils/llama_wrapper.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:path/path.dart' as path;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:panda/utils/agentic_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bloc/repo_bloc/repo_bloc.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../terminal/terminal.dart';
import '../../utils/ai.dart';
import '../../utils/copilot_chat.dart';
import '../../utils/functions.dart';
import '../../utils/languages.dart';
import '../../utils/themes.dart';
import '../../utils/constants.dart';

// Git source control panel
// Extracted from widgets.dart

import '../components/git_graph.dart';

String _extractGitFilename(String gitStatusLine) {
  String fileName = gitStatusLine.substring(2).trim();
  if (fileName.startsWith('"') && fileName.endsWith('"')) {
    fileName = fileName.substring(1, fileName.length - 1);
  }
  return fileName;
}

class SourceControl extends StatefulWidget {
  final AppTheme appTheme;
  final String workSpace;
  final bool isRepoThere;
  final Function(String fileName, String workspacePath, ActiveEditorBloc bloc)? onOpenDiffView;
  final ActiveEditorBloc? activeEditorsBloc;
  const SourceControl({
    super.key,
    required this.appTheme,
    required this.workSpace,
    required this.isRepoThere,
    this.onOpenDiffView,
    this.activeEditorsBloc,
  });

  @override
  State<SourceControl> createState() => _SourceControlState();
}

class _SourceControlState extends State<SourceControl> {
  bool _isARepo = false;
  late final TextEditingController _commitController;
  late final StreamSubscription<GitCommitState> _commitSub;
  bool _stagedExpanded = true;
  bool _unstagedExpanded = true;
  bool _commitGraphExpanded = true;
  late final ScrollController _commitGraphScrollController;
  final ScrollController _stagedScrollController = ScrollController();
  final ScrollController _unstagedScrollController = ScrollController();
  StreamSubscription<FileSystemEvent>? _gitWatcher;
  DateTime? _lastGitRefresh;
  bool _isGeneratingCommitMessage = false;
  bool _requestedCopilotCommitModels = false;

  static const int _maxCommitDiffChars = 16000;
  static const int _maxUntrackedPreviewChars = 1200;

  @override
  void initState() {
    _commitController = TextEditingController(
      text: context.read<GitCommitBloc>().state.commitMessage,
    );

    _commitSub = context.read<GitCommitBloc>().stream.listen((s) {
      final newText = s.commitMessage;
      if (newText != _commitController.text) {
        _commitController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    });

    _commitGraphScrollController = ScrollController();

    if (widget.isRepoThere) {
      final currentState = context.read<RepoStatusBloc>().state;
      if (currentState is RepoStatusInitial) {
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      }
      _setupGitWatcher();
    }
    super.initState();
  }

  void _setupGitWatcher() {
    _gitWatcher?.cancel();
    final gitDir = Directory(path.join(widget.workSpace, '.git'));
    if (gitDir.existsSync()) {
      _gitWatcher = gitDir.watch(recursive: true).listen((event) {
        if (mounted) {
          final now = DateTime.now();
          if (_lastGitRefresh == null ||
              now.difference(_lastGitRefresh!).inSeconds >= 2) {
            _lastGitRefresh = now;
            context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
          }
        }
      });
    }
  }

  void _requestCopilotModelsIfNeeded(
    bool githubSignedIn,
    bool copilotSignedIn,
    CopilotChatState chatState,
  ) {
    final copilotAvailable = githubSignedIn || copilotSignedIn;
    if (!copilotAvailable) {
      _requestedCopilotCommitModels = false;
      return;
    }

    if (_requestedCopilotCommitModels ||
        chatState.isFetchingModels ||
        chatState.hasFetchedModels) {
      return;
    }

    _requestedCopilotCommitModels = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CopilotChatBloc>().add(CopilotChatFetchModels(forceRefresh: true));
    });
  }

  Future<ProcessResult> _runGitCommand(List<String> args) async {
    final sharedPath = await NativeChannel.getLibraryPath();
    return Process.run(
      '$binDir/git',
      args,
      workingDirectory: widget.workSpace,
      environment: gitEnvs(sharedPath),
    );
  }

  Future<List<String>> _loadRecentCommitSubjects() async {
    final result = await _runGitCommand(['log', '-n', '8', '--pretty=format:%s']);
    if (result.exitCode != 0) {
      return const [];
    }

    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String> _loadCommitDiffContext({required bool stagedOnly}) async {
    final diffArgs = stagedOnly
        ? ['diff', '--cached', '--no-color', '--no-ext-diff', '--patch', '--unified=3', '--']
        : ['diff', '--no-color', '--no-ext-diff', '--patch', '--unified=3', '--'];

    final trackedDiffResult = await _runGitCommand(diffArgs);
    final buffer = StringBuffer();
    if (trackedDiffResult.exitCode == 0) {
      final trackedDiff = trackedDiffResult.stdout.toString().trimRight();
      if (trackedDiff.isNotEmpty) {
        buffer.writeln(trackedDiff);
      }
    }

    if (!stagedOnly) {
      final untrackedFilesResult = await _runGitCommand([
        'ls-files',
        '--others',
        '--exclude-standard',
      ]);

      final untrackedFiles = untrackedFilesResult.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(6)
          .toList();

      if (untrackedFiles.isNotEmpty) {
        buffer.writeln('\n# Untracked file previews');
      }

      for (final relativePath in untrackedFiles) {
        final file = File(path.join(widget.workSpace, relativePath));
        if (!file.existsSync()) continue;

        try {
          final bytes = await file.readAsBytes();
          if (bytes.contains(0)) continue;

          final decoded = utf8.decode(bytes, allowMalformed: true).trimRight();
          if (decoded.isEmpty) continue;

          final preview = _truncateText(decoded, _maxUntrackedPreviewChars);
          buffer.writeln('\n## $relativePath');
          for (final line in preview.split('\n')) {
            buffer.writeln('+$line');
          }
        } catch (_) {
          continue;
        }
      }
    }

    return _truncateText(buffer.toString().trim(), _maxCommitDiffChars);
  }

  String _truncateText(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n\n[truncated]';
  }

  String _buildCommitGenerationPrompt({
    required String diffText,
    required List<String> recentCommits,
    required bool stagedOnly,
  }) {
    final styleHints = recentCommits.isEmpty
        ? '- No recent commits found.'
        : recentCommits.map((msg) => '- $msg').join('\n');

    final source = stagedOnly
        ? 'staged changes only'
        : 'working tree changes (including untracked file previews)';

    return '''
You are generating a git commit message.

Rules:
- Return exactly one commit subject line.
- Use imperative mood.
- Maximum 72 characters.
- Do not use markdown, bullet points, quotes, or code fences.
- Do not include issue numbers unless they appear explicitly in the changes.

Changes source: $source

Recent commit style examples (style reference only):
$styleHints

Changes:
$diffText
''';
  }

  String _normalizeGeneratedCommitMessage(String raw) {
    var text = raw.trim();
    final fenced = RegExp(r'```(?:\w+)?\s*([\s\S]*?)\s*```').firstMatch(text);
    if (fenced != null) {
      text = fenced.group(1)!.trim();
    }

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';

    var message = lines.first;
    message = message.replaceFirst(RegExp(r'^[-*]\s+'), '');
    message = message.replaceFirst(
      RegExp(r'^(commit message|message)\s*:\s*', caseSensitive: false),
      '',
    );

    if ((message.startsWith('"') && message.endsWith('"')) ||
        (message.startsWith('\'') && message.endsWith('\''))) {
      message = message.substring(1, message.length - 1).trim();
    }

    if (message.length > 72) {
      final chunk = message.substring(0, 72);
      final lastSpace = chunk.lastIndexOf(' ');
      if (lastSpace >= 50) {
        message = chunk.substring(0, lastSpace).trimRight();
      } else {
        message = chunk.trimRight();
      }
    }

    return message;
  }

  List<Models> _collectExternalCommitModels(AIState aiState) {
    if (!aiState.isEnabled) return const [];

    final models = <Models>[];
    final seen = <String>{};

    void addModel(Models? model) {
      if (model == null) return;
      final key = '${model.runtimeType}|${model.url}|${model.model ?? ''}';
      if (seen.add(key)) {
        models.add(model);
      }
    }

    addModel(aiState.chatModel);
    addModel(aiState.completionModel);
    return models;
  }

  bool _canGenerateCommitMessage({
    required AIState aiState,
    required bool githubSignedIn,
    required bool copilotSignedIn,
    required CopilotChatState chatState,
  }) {
    if (!aiState.isEnabled) return false;

    final hasCopilotModels = (githubSignedIn || copilotSignedIn) && chatState.models.isNotEmpty;
    final hasExternalModels = _collectExternalCommitModels(aiState).isNotEmpty;
    return hasCopilotModels || hasExternalModels;
  }

  Future<String?> _tryGenerateWithCopilotModels(
    CopilotChatState chatState,
    String prompt,
  ) async {
    final chatClient = context.read<CopilotChatBloc>().chatClient;
    if (chatClient == null) return null;

    final modelIds = chatState.models
        .map((model) => model['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    for (final modelId in modelIds) {
      try {
        final response = await chatClient.chatWithModel(
          model: modelId,
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          chatMode: ChatMode.ask,
        );

        final normalized = _normalizeGeneratedCommitMessage(response);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<String?> _tryGenerateWithExternalModels(
    List<Models> models,
    String prompt,
  ) async {
    for (final model in models) {
      try {
        final response = await model.completionResponse(prompt);
        final normalized = _normalizeGeneratedCommitMessage(response);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<void> _generateCommitMessage({
    required BuildContext context,
    required AIState aiState,
    required CopilotChatState chatState,
    required bool githubSignedIn,
    required bool copilotSignedIn,
  }) async {
    if (_isGeneratingCommitMessage) return;

    final repoState = context.read<RepoStatusBloc>().state;
    if (repoState is! RepoStatusLoaded) {
      _showErrorSnackBar(context, 'Repository status is still loading');
      return;
    }

    if (repoState.staged.isEmpty && repoState.unstaged.isEmpty) {
      _showErrorSnackBar(context, 'No changes available to generate a commit message');
      return;
    }

    setState(() => _isGeneratingCommitMessage = true);

    try {
      final stagedOnly = repoState.staged.isNotEmpty;
      final diffText = await _loadCommitDiffContext(stagedOnly: stagedOnly);
      if (diffText.isEmpty && context.mounted) {
        _showErrorSnackBar(context, 'Could not gather changes for commit message generation');
        return;
      }

      final recentCommits = await _loadRecentCommitSubjects();
      final prompt = _buildCommitGenerationPrompt(
        diffText: diffText,
        recentCommits: recentCommits,
        stagedOnly: stagedOnly,
      );

      String? generated;

      if (aiState.isEnabled && (githubSignedIn || copilotSignedIn) && chatState.models.isNotEmpty) {
        generated = await _tryGenerateWithCopilotModels(chatState, prompt);
      }

      if ((generated == null || generated.isEmpty) && aiState.isEnabled) {
        final externalModels = _collectExternalCommitModels(aiState);
        generated = await _tryGenerateWithExternalModels(externalModels, prompt);
      }

      if (!context.mounted) return;

      if (generated == null || generated.isEmpty) {
        _showErrorSnackBar(context, 'No working AI model could generate a commit message');
        return;
      }

      context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: generated));
      _showSuccessSnackBar(context, 'Commit message generated');
    } catch (_) {
      if (!mounted) return;
      _showErrorSnackBar(context, 'Failed to generate commit message');
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCommitMessage = false);
      }
    }
  }

  @override
  void dispose() {
    _gitWatcher?.cancel();
    _commitSub.cancel();
    _commitController.dispose();
    _commitGraphScrollController.dispose();
    _stagedScrollController.dispose();
    _unstagedScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SourceControl oldWidget) {
    if (oldWidget.workSpace != widget.workSpace) {
      try {
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        if (widget.isRepoThere) {
          context.read<RepoStatusBloc>().add(LoadCommitGraph(widget.workSpace));
          _setupGitWatcher();
        }
      } catch (_) {}
    }
    super.didUpdateWidget(oldWidget);
  }

  Widget _buildCollapsibleChangesList({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    required Widget actionButton,
    required ScrollController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 12,
              bottom: 4,
              right: 4,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$itemCount',
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
                actionButton,
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: isExpanded
              ? ConstrainedBox(
                  key: ValueKey('$title-expanded'),
                  constraints: BoxConstraints(
                    maxHeight: itemCount > 5 ? 250 : itemCount * 50.0,
                  ),
                  child: Scrollbar(
                    controller: controller,
                    thumbVisibility: itemCount > 5,
                    child: ListView.builder(
                      controller: controller,
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: itemCount,
                      itemBuilder: itemBuilder,
                    ),
                  ),
                )
              : SizedBox.shrink(key: ValueKey('$title-collapsed')),
        ),
      ],
    );
  }

  Widget _buildCollapsibleCommitGraph() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _commitGraphExpanded = !_commitGraphExpanded),
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 12,
              bottom: 8,
              right: 4,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _commitGraphExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  "Commit History",
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    fontSize: 14,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: _commitGraphExpanded
              ? ConstrainedBox(
                  key: const ValueKey('commit-graph-expanded'),
                  constraints: const BoxConstraints(maxHeight: 600),
                  child: BlocBuilder<RepoStatusBloc, RepoStatusState>(
                    builder: (context, state) {
                      if (state is RepoStatusLoaded && state.commits != null) {
                        if (state.commits!.isEmpty) {
                          return Center(
                            child: Text(
                              'No commits found',
                              style: TextStyle(
                                color:
                                    widget.appTheme.selectScreenCardTextColor,
                              ),
                            ),
                          );
                        }
                        final commits = state.commits!;
                        return Scrollbar(
                          controller: _commitGraphScrollController,
                          thumbVisibility: commits.length > 10,
                          child: SingleChildScrollView(
                            controller: _commitGraphScrollController,
                            child: GitCommitGraph(
                              commits: commits,
                              appTheme: widget.appTheme,
                            ),
                          ),
                        );
                      } else if (state is RepoStatusLoading) {
                        return const Center(child: CircularProgressIndicator());
                      } else {
                        return Center(
                          child: Text(
                            'Loading commits...',
                            style: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                )
              : SizedBox.shrink(key: const ValueKey('commit-graph-collapsed')),
        ),
      ],
    );
  }

  

  Future<void> _performPush(BuildContext context) async {
    _showLoadingDialog(context, 'Pushing...');
    try {
      final result = await gitPush(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (result.exitCode == 0) {
          _showSuccessSnackBar(context, 'Push successful');
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        } else {
          _showErrorSnackBar(context, 'Push failed: ${result.stderr}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Push failed: $e');
      }
    }
  }

  Future<void> _performPull(BuildContext context) async {
    _showLoadingDialog(context, 'Pulling...');
    try {
      final result = await gitPull(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (result.exitCode == 0) {
          _showSuccessSnackBar(context, 'Pull successful');
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
          context.read<RepoStatusBloc>().add(LoadCommitGraph(widget.workSpace));
        } else {
          final out = '${result.stdout}'.trim();
          final err = '${result.stderr}'.trim();
          final conflictDetected = out.contains('CONFLICT') || err.contains('CONFLICT');

          if (conflictDetected) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Merge conflict detected'),
                content: SingleChildScrollView(
                  child: Text(
                    'Merge conflicts were found during pull.\n\n${err.isNotEmpty ? 'Error:\n$err\n\n' : ''}${out.isNotEmpty ? 'Output:\n$out' : ''}',
                    style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                      context.read<RepoStatusBloc>().add(LoadCommitGraph(widget.workSpace));
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            _showErrorSnackBar(context, 'Pull failed: ${result.stderr}');
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Pull failed: $e');
      }
    }
  }

  Future<void> _performCommitAndPush(
    BuildContext context,
    String message,
  ) async {
    _showLoadingDialog(context, 'Committing and pushing...');
    try {
      final commitResult = await gitCommit(
        widget.workSpace,
        message,
        all: true,
      );
      if (commitResult.exitCode != 0) {
        if (context.mounted) {
          Navigator.of(context).pop();
          _showErrorSnackBar(context, 'Commit failed: ${commitResult.stderr}');
        }
        return;
      }

      final pushResult = await gitPush(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (pushResult.exitCode == 0) {
          _showSuccessSnackBar(context, 'Commit and push successful');
          context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: ''));
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        } else {
          _showErrorSnackBar(context, 'Push failed: ${pushResult.stderr}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Failed: $e');
      }
    }
  }

  Future<void> _performCommitAndSync(
    BuildContext context,
    String message,
  ) async {
    _showLoadingDialog(context, 'Committing and syncing...');
    try {
      final commitResult = await gitCommit(
        widget.workSpace,
        message,
        all: true,
      );
      if (commitResult.exitCode != 0) {
        if (context.mounted) {
          Navigator.of(context).pop();
          _showErrorSnackBar(context, 'Commit failed: ${commitResult.stderr}');
        }
        return;
      }

      final syncResult = await gitSync(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (syncResult.exitCode == 0) {
          _showSuccessSnackBar(context, 'Commit and sync successful');
          context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: ''));
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        } else {
          _showErrorSnackBar(context, 'Sync failed: ${syncResult.stderr}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Failed: $e');
      }
    }
  }

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(
              message,
              style: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  

  void _showCreateBranchDialog(BuildContext context) {
    final repoBloc = context.read<RepoStatusBloc>();
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.appTheme.isDark
                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                  : [
                      const Color.fromARGB(255, 250, 250, 250),
                      const Color.fromARGB(255, 240, 240, 240)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Create Branch',
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Branch name',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (controller.text.trim().isEmpty) return;
                      Navigator.pop(dialogContext);
                      final result = await gitCreateBranch(
                        widget.workSpace,
                        controller.text.trim(),
                      );
                      if (dialogContext.mounted) {
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(
                            dialogContext,
                            'Branch created and checked out',
                          );
                          repoBloc.add(
                            LoadRepoStatus(widget.workSpace),
                          );
                        } else {
                          _showErrorSnackBar(
                            dialogContext,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateBranchFromDialog(
    BuildContext context,
    List<String> branches,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    final controller = TextEditingController();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.call_split,
                        color: Colors.cyan,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Create Branch From',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Source Branch',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    hintText: 'New branch name',
                    hintStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (controller.text.trim().isEmpty || selectedBranch == null) {
                          return;
                        }
                        Navigator.pop(dialogContext);
                        final result = await gitCreateBranch(
                          widget.workSpace,
                          controller.text.trim(),
                          fromRef: selectedBranch,
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(
                              dialogContext,
                              'Branch created from $selectedBranch',
                            );
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMergeBranchDialog(
    BuildContext context,
    List<String> branches,
    String? currentBranch,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.merge_type,
                        color: Colors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Merge Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Current branch: ${currentBranch ?? "unknown"}',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Branch to merge',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .where((b) => b != currentBranch)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Merging...');
                        final result = await gitMergeBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(
                              dialogContext,
                              'Merged $selectedBranch',
                            );
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Merge failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Merge'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRebaseBranchDialog(
    BuildContext context,
    List<String> branches,
    String? currentBranch,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.swap_calls,
                        color: Colors.deepOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Rebase onto Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Current branch: ${currentBranch ?? "unknown"}',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Rebase onto',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .where((b) => b != currentBranch)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Rebasing...');
                        final result = await gitRebaseBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(
                              dialogContext,
                              'Rebased onto $selectedBranch',
                            );
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Rebase failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Rebase'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRenameBranchDialog(BuildContext context, List<String> branches) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        color: Colors.amber,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Rename Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Branch to rename',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() => selectedBranch = val);
                    controller.text = val ?? '';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    hintText: 'New name',
                    hintStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null || controller.text.trim().isEmpty) return;
                        Navigator.pop(dialogContext);
                        final result = await gitRenameBranch(
                          widget.workSpace,
                          selectedBranch!,
                          controller.text.trim(),
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Branch renamed');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Rename'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteBranchDialog(
    BuildContext context,
    List<String> branches,
    String? currentBranch,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Branch to delete',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .where((b) => b != currentBranch)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        final result = await gitDeleteBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Branch deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteRemoteBranchDialog(
    BuildContext context,
    List<String> remoteBranches,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cloud_off_outlined,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Remote Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                    ? const Color(0xff2b2b2b)
                    : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Remote branch to delete',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: remoteBranches.map((b) {
                    final display = b.replaceFirst('origin/', '');
                    return DropdownMenuItem(
                      value: display,
                      child: Text(b),
                    );
                  }).toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Deleting remote branch...');
                        final result = await gitDeleteRemoteBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Remote branch deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPublishBranchDialog(
    BuildContext context,
    String? currentBranch,
  ) async {
    if (currentBranch == null) return;
    _showLoadingDialog(context, 'Publishing branch...');
    final result = await gitPublishBranch(widget.workSpace, currentBranch);
    if (context.mounted) {
      Navigator.pop(context);
      if (result.exitCode == 0) {
        _showSuccessSnackBar(context, 'Branch published to origin');
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      } else {
        _showErrorSnackBar(context, 'Failed: ${result.stderr}');
      }
    }
  }

  

  void _showStashDialog(
    BuildContext context, {
    bool includeUntracked = false,
    bool stagedOnly = false,
  }) {
    final repoBloc = context.read<RepoStatusBloc>();
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.appTheme.isDark
                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                  : [
                      const Color.fromARGB(255, 250, 250, 250),
                      const Color.fromARGB(255, 240, 240, 240)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.save_outlined,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      stagedOnly
                          ? 'Stash Staged'
                          : (includeUntracked
                              ? 'Stash (Include Untracked)'
                              : 'Stash'),
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: controller,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Stash message (optional)',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      final result = await gitStash(
                        widget.workSpace,
                        message: controller.text.trim().isEmpty
                            ? null
                            : controller.text.trim(),
                        includeUntracked: includeUntracked,
                        stagedOnly: stagedOnly,
                      );
                      if (dialogContext.mounted) {
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(dialogContext, 'Changes stashed');
                          repoBloc.add(
                            LoadRepoStatus(widget.workSpace),
                          );
                        } else {
                          _showErrorSnackBar(
                            dialogContext,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Stash'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showApplyStashDialog(
    BuildContext context,
    List<Map<String, String>> stashes, {
    bool pop = false,
  }) {
    if (stashes.isEmpty) {
      _showErrorSnackBar(context, 'No stashes available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedStash;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : Colors.white,
          title: Text(
            pop ? 'Pop Stash' : 'Apply Stash',
            style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
          ),
          content: DropdownButtonFormField<String>(
            initialValue: selectedStash,
            dropdownColor: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : Colors.white,
            decoration: InputDecoration(
              labelText: 'Select stash',
              labelStyle: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
              ),
            ),
            items: stashes
                .map(
                  (s) => DropdownMenuItem(
                    value: s['ref'],
                    child: Text(
                      '${s['ref']}: ${s['message']}',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) => setDialogState(() => selectedStash = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedStash == null) return;
                Navigator.pop(dialogContext);
                final result = pop
                    ? await gitStashPop(
                        widget.workSpace,
                        stashRef: selectedStash,
                      )
                    : await gitStashApply(
                        widget.workSpace,
                        stashRef: selectedStash,
                      );
                if (dialogContext.mounted) {
                  if (result.exitCode == 0) {
                    _showSuccessSnackBar(
                      dialogContext,
                      pop ? 'Stash popped' : 'Stash applied',
                    );
                    repoBloc.add(
                      LoadRepoStatus(widget.workSpace),
                    );
                  } else {
                    _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                  }
                }
              },
              child: Text(pop ? 'Pop' : 'Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDropStashDialog(
    BuildContext context,
    List<Map<String, String>> stashes,
  ) {
    if (stashes.isEmpty) {
      _showErrorSnackBar(context, 'No stashes available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedStash;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : Colors.white,
          title: Text(
            'Drop Stash',
            style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
          ),
          content: DropdownButtonFormField<String>(
            initialValue: selectedStash,
            dropdownColor: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : Colors.white,
            decoration: InputDecoration(
              labelText: 'Select stash to drop',
              labelStyle: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
              ),
            ),
            items: stashes
                .map(
                  (s) => DropdownMenuItem(
                    value: s['ref'],
                    child: Text(
                      '${s['ref']}: ${s['message']}',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) => setDialogState(() => selectedStash = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedStash == null) return;
                Navigator.pop(dialogContext);
                final result = await gitStashDrop(
                  widget.workSpace,
                  stashRef: selectedStash,
                );
                if (dialogContext.mounted) {
                  if (result.exitCode == 0) {
                    _showSuccessSnackBar(dialogContext, 'Stash dropped');
                    repoBloc.add(
                      LoadRepoStatus(widget.workSpace),
                    );
                  } else {
                    _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                  }
                }
              },
              child: const Text('Drop', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDropAllStashesDialog(BuildContext context) {
    final repoBloc = context.read<RepoStatusBloc>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.appTheme.isDark
          ? const Color(0xff2b2b2b)
          : Colors.white,
        title: Text(
          'Drop All Stashes',
          style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
        ),
        content: Text(
          'Are you sure you want to drop all stashes? This cannot be undone.',
          style: TextStyle(
            color: widget.appTheme.selectScreenCardTextColor.withAlpha(200),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final result = await gitStashClear(widget.workSpace);
              if (dialogContext.mounted) {
                if (result.exitCode == 0) {
                  _showSuccessSnackBar(dialogContext, 'All stashes dropped');
                  repoBloc.add(
                    LoadRepoStatus(widget.workSpace),
                  );
                } else {
                  _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                }
              }
            },
            child: const Text('Drop All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showViewStashDialog(
    BuildContext context,
    List<Map<String, String>> stashes,
  ) {
    if (stashes.isEmpty) {
      _showErrorSnackBar(context, 'No stashes available');
      return;
    }
    String? selectedStash;
    String? stashContent;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
          title: Text(
            'View Stash',
            style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
          ),
          content: SizedBox(
            width: 400,
            height: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedStash,
                  dropdownColor: widget.appTheme.isDark
                    ? const Color(0xff2b2b2b)
                    : Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Select stash',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withAlpha(150),
                    ),
                  ),
                  items: stashes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['ref'],
                          child: Text(
                            '${s['ref']}: ${s['message']}',
                            style: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) async {
                    setDialogState(() => selectedStash = val);
                    if (val != null) {
                      final content = await gitStashShow(widget.workSpace, val);
                      setDialogState(() => stashContent = content);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.appTheme.isDark
                          ? Colors.black26
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        stashContent ?? 'Select a stash to view',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: widget.appTheme.selectScreenCardTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  

  void _showCreateTagDialog(BuildContext context) {
    final repoBloc = context.read<RepoStatusBloc>();
    final nameController = TextEditingController();
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.appTheme.isDark
                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                  : [
                      const Color.fromARGB(255, 250, 250, 250),
                      const Color.fromARGB(255, 240, 240, 240)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.label_outline,
                      color: Colors.purple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Create Tag',
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: nameController,
                autofocus: true,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Tag name (e.g., v1.0.0)',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Message (optional, creates annotated tag)',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      Navigator.pop(dialogContext);
                      final result = await gitCreateTag(
                        widget.workSpace,
                        nameController.text.trim(),
                        message: messageController.text.trim().isEmpty
                            ? null
                            : messageController.text.trim(),
                      );
                      if (dialogContext.mounted) {
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(dialogContext, 'Tag created');
                          repoBloc.add(
                            LoadRepoStatus(widget.workSpace),
                          );
                        } else {
                          _showErrorSnackBar(
                            dialogContext,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteTagDialog(BuildContext context, List<String> tags) {
    if (tags.isEmpty) {
      _showErrorSnackBar(context, 'No tags available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedTag;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.label_off_outlined,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Tag',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedTag,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tag to delete',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: tags
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedTag = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedTag == null) return;
                        Navigator.pop(dialogContext);
                        final result = await gitDeleteTag(
                          widget.workSpace,
                          selectedTag!,
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Tag deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteRemoteTagDialog(BuildContext context, List<String> tags) {
    if (tags.isEmpty) {
      _showErrorSnackBar(context, 'No tags available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedTag;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cloud_off_outlined,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Remote Tag',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedTag,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tag to delete from remote',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: tags
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedTag = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedTag == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Deleting remote tag...');
                        final result = await gitDeleteRemoteTag(
                          widget.workSpace,
                          selectedTag!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Remote tag deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGitActionsRow(
    BuildContext context,
    RepoStatusState repoState,
    bool isSignedIn,
  ) {
    final loaded = repoState is RepoStatusLoaded ? repoState : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.5, right: 5.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (repoState is RepoStatusLoaded && repoState.currentBranch != null)
          Expanded(
            child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: PopupMenuButton<String>(
                  tooltip: 'Switch branch',
                  color: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  onSelected: (branch) async {
                    if (branch != repoState.currentBranch) {
                      _showLoadingDialog(context, 'Switching to $branch...');
                      final result = await gitCheckoutBranch(widget.workSpace, branch);
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(context, 'Switched to $branch');
                          context.read<RepoStatusBloc>().add(
                                LoadRepoStatus(widget.workSpace),
                              );
                          context.read<RepoStatusBloc>().add(
                                LoadCommitGraph(widget.workSpace),
                              );
                        } else {
                          _showErrorSnackBar(
                            context,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    ...repoState.branches.map(
                      (branch) => PopupMenuItem<String>(
                        value: branch,
                        child: Row(
                          children: [
                            branch == repoState.currentBranch
                              ? Icon(Icons.check, size: 14, color: Colors.green)
                              : FaIcon(
                                FontAwesomeIcons.codeBranch,
                                size: 14,
                                color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              branch,
                              style: TextStyle(
                                color: widget.appTheme.selectScreenCardTextColor,
                                fontWeight: branch == repoState.currentBranch
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (repoState.remoteBranches.isNotEmpty) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(
                          'Remote Branches',
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor.withAlpha(100),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ...repoState.remoteBranches
                          .where((rb) => !repoState.branches.contains(rb.replaceFirst('origin/', '')))
                          .map(
                            (branch) => PopupMenuItem<String>(
                              value: branch,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_outlined,
                                    size: 14,
                                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      branch,
                                      style: TextStyle(
                                        color: widget.appTheme.selectScreenCardTextColor,
                                      ),
                                      overflow: TextOverflow.ellipsis
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.codeBranch,
                        size: 15,
                        color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                      ),
                      const SizedBox(width: 3),
                      SizedBox(
                        width: 45,
                        child: Text(
                          repoState.currentBranch!,
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                      ),
                      if (repoState.unpushedCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(40),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '↑${repoState.unpushedCount}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ),
          Tooltip(
            message: 'Pull',
            child: IconButton(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              onPressed: () => _performPull(context),
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(200),
                    size: 17,
                  ),
                  if ((loaded?.unpulledCount ?? 0) > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'M ${loaded?.unpulledCount ?? 0}',
                        style: const TextStyle(
                          color: Colors.lightBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.appTheme.isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Push',
            child: IconButton(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              onPressed: loaded?.hasUpstream == true
                ? () => _performPush(context)
                : null,
              icon: Icon(
                Icons.arrow_upward,
                color: loaded?.hasUpstream == true
                  ? widget.appTheme.selectScreenCardTextColor.withAlpha(200)
                  : widget.appTheme.selectScreenCardTextColor.withAlpha(80),
                size: 17,
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.appTheme.isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz,color: widget.appTheme.selectScreenCardTextColor.withAlpha(200)),
            color: widget.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : Colors.white,
            onSelected: (value) =>
                _handleGitMenuAction(context, value, loaded, isSignedIn),
            itemBuilder: (context) => [
              _buildPopupMenuWithSubmenu('Branch', FontAwesomeIcons.codeBranch, [
                ('merge', 'Merge...'),
                ('rebase', 'Rebase Branch...'),
                ('divider', ''),
                ('create_branch', 'Create Branch...'),
                ('create_branch_from', 'Create Branch From...'),
                ('rename_branch', 'Rename Branch...'),
                ('divider', ''),
                ('delete_branch', 'Delete Branch...'),
                ('delete_remote_branch', 'Delete Remote Branch...'),
                ('publish_branch', 'Publish Branch'),
              ], loaded, isSignedIn),
              _buildPopupMenuWithSubmenu('Stash', Icons.archive, [
                ('stash', 'Stash'),
                ('stash_untracked', 'Stash (Include Untracked)'),
                ('stash_staged', 'Stash Staged'),
                ('divider', ''),
                ('apply_latest_stash', 'Apply Latest Stash'),
                ('apply_stash', 'Apply Stash...'),
                ('divider', ''),
                ('pop_latest_stash', 'Pop Latest Stash'),
                ('pop_stash', 'Pop Stash...'),
                ('divider', ''),
                ('drop_stash', 'Drop Stash...'),
                ('drop_all_stashes', 'Drop All Stashes'),
                ('view_stash', 'View Stash...'),
              ], loaded, isSignedIn),
              _buildPopupMenuWithSubmenu('Tags', Icons.local_offer, [
                ('create_tag', 'Create Tag...'),
                ('delete_tag', 'Delete Tag...'),
                ('delete_remote_tag', 'Delete Remote Tag...'),
              ], loaded, isSignedIn),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuEntry<String> _buildPopupMenuWithSubmenu(
    String title,
    dynamic icon,
    List<(String, String)> subItems,
    RepoStatusLoaded? loaded,
    bool isSignedIn,
  ) {
    return PopupMenuItem<String>(
      padding: EdgeInsets.zero,
      child: PopupMenuButton<String>(
        offset: const Offset(200, 0),
        color: widget.appTheme.isDark ? const Color(0xff2b2b2b) : Colors.white,
        onSelected: (value) {
          
          Navigator.pop(context);
          
          Future.microtask(() {
            if(mounted) {
              _handleGitMenuAction(context, value, loaded, isSignedIn);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              (() {
                if (icon is IconData) {
                  return Icon(
                    icon,
                    size: 18,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                  );
                }
                if (icon is Widget) {
                  return icon;
                }
                try {
                  return FaIcon(
                    icon,
                    size: 18,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                  );
                } catch (_) {
                  return Icon(
                    Icons.help_outline,
                    size: 18,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                  );
                }
              }()),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(120),
              ),
            ],
          ),
        ),
        itemBuilder: (context) => subItems.map((item) {
          if (item.$1 == 'divider') {
            return const PopupMenuDivider() as PopupMenuEntry<String>;
          }
          return PopupMenuItem<String>(
            value: item.$1,
            child: Text(
              item.$2,
              style: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _handleGitMenuAction(
    BuildContext context,
    String action,
    RepoStatusLoaded? loaded,
    bool isSignedIn,
  ) {
    switch (action) {
      case 'merge':
        _showMergeBranchDialog(
          context,
          loaded?.branches ?? [],
          loaded?.currentBranch,
        );
        break;
      case 'rebase':
        _showRebaseBranchDialog(
          context,
          loaded?.branches ?? [],
          loaded?.currentBranch,
        );
        break;
      case 'create_branch':
        _showCreateBranchDialog(context);
        break;
      case 'create_branch_from':
        _showCreateBranchFromDialog(context, loaded?.branches ?? []);
        break;
      case 'rename_branch':
        _showRenameBranchDialog(context, loaded?.branches ?? []);
        break;
      case 'delete_branch':
        _showDeleteBranchDialog(
          context,
          loaded?.branches ?? [],
          loaded?.currentBranch,
        );
        break;
      case 'delete_remote_branch':
        _showDeleteRemoteBranchDialog(context, loaded?.remoteBranches ?? []);
        break;
      case 'publish_branch':
        _showPublishBranchDialog(context, loaded?.currentBranch);
        break;
      case 'stash':
        _showStashDialog(context);
        break;
      case 'stash_untracked':
        _showStashDialog(context, includeUntracked: true);
        break;
      case 'stash_staged':
        _showStashDialog(context, stagedOnly: true);
        break;
      case 'apply_latest_stash':
        _applyLatestStash(context);
        break;
      case 'apply_stash':
        _showApplyStashDialog(context, loaded?.stashes ?? []);
        break;
      case 'pop_latest_stash':
        _popLatestStash(context);
        break;
      case 'pop_stash':
        _showApplyStashDialog(context, loaded?.stashes ?? [], pop: true);
        break;
      case 'drop_stash':
        _showDropStashDialog(context, loaded?.stashes ?? []);
        break;
      case 'drop_all_stashes':
        _showDropAllStashesDialog(context);
        break;
      case 'view_stash':
        _showViewStashDialog(context, loaded?.stashes ?? []);
        break;
      case 'create_tag':
        _showCreateTagDialog(context);
        break;
      case 'delete_tag':
        _showDeleteTagDialog(context, loaded?.tags ?? []);
        break;
      case 'delete_remote_tag':
        _showDeleteRemoteTagDialog(context, loaded?.tags ?? []);
        break;
    }
  }

  Future<void> _applyLatestStash(BuildContext context) async {
    final result = await gitStashApply(widget.workSpace);
    if (context.mounted) {
      if (result.exitCode == 0) {
        _showSuccessSnackBar(context, 'Latest stash applied');
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      } else {
        _showErrorSnackBar(context, 'Failed: ${result.stderr}');
      }
    }
  }

  Future<void> _popLatestStash(BuildContext context) async {
    final result = await gitStashPop(widget.workSpace);
    if (context.mounted) {
      if (result.exitCode == 0) {
        _showSuccessSnackBar(context, 'Latest stash popped');
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      } else {
        _showErrorSnackBar(context, 'Failed: ${result.stderr}');
      }
    }
  }

  Widget _buildCommitButton(
    BuildContext context,
    RepoStatusLoaded repoState,
    bool isSignedIn,
  ) {
    final stagedEmpty = repoState.staged.isEmpty;
    final unstagedEmpty = repoState.unstaged.isEmpty;
    final hasChanges = !stagedEmpty || !unstagedEmpty;
    final hasRemote = repoState.hasRemote;
    final hasUpstream = repoState.hasUpstream;
    final unpushedCount = repoState.unpushedCount;
    final unpulledCount = repoState.unpulledCount;

    final bool showPush = !hasChanges && unpushedCount > 0 && hasUpstream;
    final bool showPublish =
        !hasChanges && hasRemote && !hasUpstream && isSignedIn;

    final Widget incomingSection = unpulledCount > 0
        ? Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.appTheme.isDark
                ? Colors.blueGrey.withAlpha(40)
                : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.arrow_downward, size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  'Incoming changes: M $unpulledCount',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    Widget buttonSection;

    if (showPush) {
      buttonSection = SizedBox(
        width: 250,
        child: ElevatedButton.icon(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            backgroundColor: const WidgetStatePropertyAll(Color(0xff0e639c)),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          onPressed: () => _performPush(context),
          icon: const Icon(Icons.cloud_upload, size: 18),
          label: Text('Push ($unpushedCount)'),
        ),
      );
    } else if (showPublish) {
      buttonSection = SizedBox(
        width: 250,
        child: ElevatedButton.icon(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            backgroundColor: const WidgetStatePropertyAll(Color(0xff0e639c)),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          onPressed: () => _showPublishBranchDialog(context, repoState.currentBranch),
          icon: const Icon(Icons.cloud_upload, size: 18),
          label: const Text('Publish Branch'),
        ),
      );
    } else {
      buttonSection = SizedBox(
        width: 250,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ButtonStyle(
                  shape: const WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    hasChanges
                        ? const Color(0xff0e639c)
                        : const Color.fromARGB(255, 15, 61, 92),
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    hasChanges ? Colors.white : Colors.grey,
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                onPressed: hasChanges
                    ? () => _handleCommit(context, stagedEmpty, unstagedEmpty)
                    : null,
                child: const Text('\u2713 Commit'),
              ),
            ),
            Container(
              width: 50,
              height: 40,
              decoration: BoxDecoration(
                border: const BorderDirectional(
                  start: BorderSide(color: Colors.white, width: 0.5),
                ),
                color: hasChanges
                    ? const Color(0xff0e639c)
                    : const Color.fromARGB(255, 15, 61, 92),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: PopupMenuButton<String>(
                enabled: hasChanges,
                icon: FaIcon(
                  FontAwesomeIcons.caretDown,
                  color: hasChanges ? Colors.white : Colors.grey,
                  size: 14,
                ),
                color: widget.appTheme.cardTheme.color,
                onSelected: (value) {
                  final commitMessage = context.read<GitCommitBloc>().state.commitMessage;
                  if (commitMessage.isEmpty) {
                    _showCommitMessageError(context);
                    return;
                  }
                  if (value == 'commit_push') {
                    _performCommitAndPush(context, commitMessage);
                  } else if (value == 'commit_sync') {
                    _performCommitAndSync(context, commitMessage);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'commit_push',
                    child: Text(
                      'Commit and Push',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'commit_sync',
                    child: Text(
                      'Commit and Sync',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [incomingSection, buttonSection],
    );
  }

  void _handleCommit(
    BuildContext context,
    bool stagedEmpty,
    bool unstagedEmpty,
  ) async {
    final commitMessage = context.read<GitCommitBloc>().state.commitMessage;
    if (commitMessage.isEmpty) {
      _showCommitMessageError(context);
      return;
    }

    if (!stagedEmpty) {
      await gitCommit(widget.workSpace, commitMessage);
      if (context.mounted) {
        context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: ''));
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      }
    } else if (!unstagedEmpty) {
      final repoBloc = context.read<RepoStatusBloc>();
      final gitBloc = context.read<GitCommitBloc>();
      showDialog(
        context: context,
        builder: (context) => BlocProvider.value(
          value: repoBloc,
          child: BlocProvider.value(
            value: gitBloc,
            child: AlertDialog(
              title: Text(
                "Changes aren't staged",
                style: TextStyle(color: Colors.grey[400], fontSize: 20),
              ),
              backgroundColor: widget.appTheme.isDark
                  ? const Color(0xff2b2b2b)
                  : const Color.fromARGB(255, 240, 240, 240),
              icon: const Icon(Icons.warning_amber_outlined, size: 35),
              iconColor: Colors.amber,
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "Cancel",
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await gitCommit(widget.workSpace, commitMessage, all: true);
                    if (context.mounted) {
                      gitBloc.add(GitCommitEvent(commitMessage: ''));
                      repoBloc.add(LoadRepoStatus(widget.workSpace));
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text(
                    "Stage all and Commit",
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showCommitMessageError(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Commit message cannot be empty.",
          style: TextStyle(color: Colors.grey[400], fontSize: 20),
        ),
        backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : const Color.fromARGB(255, 240, 240, 240),
        icon: const Icon(Icons.info_outline, size: 35),
        iconColor: Colors.red,
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showInitializeRepoDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : const Color.fromARGB(255, 240, 240, 240),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xff0e639c).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.create_new_folder,
                      color: Color(0xff0e639c),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Initialize Repository",
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "This will create a new Git repository in the current folder. This action initializes Git tracking for version control.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor.withValues(
                    alpha: 0.8,
                  ),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _initializeRepository(widget.workSpace);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0e639c),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Initialize",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPublishToGithubDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : const Color.fromARGB(255, 240, 240, 240),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.github,
                      color: Colors.black87,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Publish to GitHub",
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "This will create a new repository on GitHub and push your local code. You'll need to authenticate with GitHub first.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor.withValues(
                    alpha: 0.8,
                  ),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Make sure you have GitHub CLI installed and authenticated.",
                        style: TextStyle(
                          color: Colors.amber[800],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _publishToGithub();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Publish",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeRepository(String workspacePath) async {
    try {
      await initRepo(workspacePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Repository initialized successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isARepo = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize repository: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _publishToGithub() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Publishing to GitHub... (Feature coming soon)'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish to GitHub: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTemp = widget.workSpace == templateDir;
    _isARepo = Directory(path.join(widget.workSpace, '.git')).existsSync();
    final List<Widget> noRepoFound = [
      Text(
        "The folder currently open\ndosen't hava a Git repository.\nYou can initialize a repository\nwhich will enable source control\nfeatures powered by Git.",
        textAlign: TextAlign.start,
        style: TextStyle(
          color: widget.appTheme.isDark
              ? Colors.grey[400]
              : widget.appTheme.selectScreenCardTextColor,
        ),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _showInitializeRepoDialog,
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
          ),
          backgroundColor: WidgetStatePropertyAll(Color(0xff0e639c)),
          foregroundColor: WidgetStatePropertyAll(Colors.white),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        child: const Text("Initialize Repository"),
      ),
      const SizedBox(height: 13.5),
      Text(
        "You can directly publish this\nfolder to a GitHub repository.\nOnce published, you'll have\naccess to source control featured\npowered by Git and GitHub",
        textAlign: TextAlign.start,
        style: TextStyle(
          color: widget.appTheme.isDark
              ? Colors.grey[400]
              : widget.appTheme.selectScreenCardTextColor,
        ),
      ),
      const SizedBox(height: 13.5),
      SizedBox(
        width: 200,
        child: ElevatedButton(
          onPressed: _showPublishToGithubDialog,
          style: const ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(5)),
              ),
            ),
            backgroundColor: WidgetStatePropertyAll(Color(0xff0e639c)),
            foregroundColor: WidgetStatePropertyAll(Colors.white),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          child: const Row(
            children: [
              FaIcon(FontAwesomeIcons.github, color: Colors.white),
              SizedBox(width: 8),
              Text("Publish to Github"),
            ],
          ),
        ),
      ),
    ];
    return !isTemp
      ? SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 25, left: 10),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    "SOURCE CONTROL",
                    style: TextStyle(
                      fontWeight: widget.appTheme.isDark
                          ? FontWeight.w300
                          : FontWeight.w500,
                      color: widget.appTheme.selectScreenCardTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 13.5),
                if (!_isARepo) ...noRepoFound,
                if (_isARepo) ...[
                  BlocBuilder<GithubAuthCubit, GithubAuthState>(
                    builder: (context, authState) {
                      final isSignedIn = authState.isSignedIn;
                      return BlocBuilder<RepoStatusBloc, RepoStatusState>(
                        builder: (context, repoState) {
                          return _buildGitActionsRow(context, repoState, isSignedIn);
                        },
                      );
                    },
                  ),
                  BlocBuilder<GitCommitBloc, GitCommitState>(
                    builder: (context, commitState) {
                      return SizedBox(
                        height: 50,
                        width: 250,
                        child: TextField(
                          controller: _commitController,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(color: Colors.grey),
                          cursorColor: Colors.grey,
                          onChanged: (val) {
                            context.read<GitCommitBloc>().add(
                              GitCommitEvent(commitMessage: val),
                            );
                          },
                          decoration: InputDecoration(
                            suffixIcon: BlocBuilder<AIBloc, AIState>(
                              builder: (context, aiState) {
                                return BlocBuilder<GithubAuthCubit, GithubAuthState>(
                                  builder: (context, authState) {
                                    return BlocBuilder<CopilotChatBloc, CopilotChatState>(
                                      builder: (context, chatState) {
                                        final copilotSignedIn = context.read<CopilotBloc>().state.isSignedIn;
                                        _requestCopilotModelsIfNeeded(authState.isSignedIn, copilotSignedIn, chatState);

                                        final canGenerate = !_isGeneratingCommitMessage &&
                                            _canGenerateCommitMessage(
                                              aiState: aiState,
                                              githubSignedIn: authState.isSignedIn,
                                              copilotSignedIn: copilotSignedIn,
                                              chatState: chatState,
                                            );

                                        final tooltip = _isGeneratingCommitMessage
                                            ? 'Generating commit message...'
                                            : (!aiState.isEnabled
                                                ? 'AI is disabled in settings'
                                                : canGenerate
                                                    ? 'Generate commit message'
                                                    : (chatState.isFetchingModels
                                                        ? 'Loading AI models...'
                                                        : 'No AI model available'));

                                        return Tooltip(
                                          message: tooltip,
                                          child: IconButton(
                                            onPressed: canGenerate
                                                ? () => _generateCommitMessage(
                                                      context: context,
                                                      aiState: aiState,
                                                      chatState: chatState,
                                                      githubSignedIn: authState.isSignedIn,
                                                      copilotSignedIn: copilotSignedIn,
                                                    )
                                                : null,
                                            icon: _isGeneratingCommitMessage
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : SvgPicture.asset(
                                                    'assets/icons/ai.svg',
                                                    height: 20,
                                                    width: 20,
                                                    colorFilter: ColorFilter.mode(
                                                      canGenerate
                                                          ? widget.appTheme.selectScreenCardTextColor
                                                              .withValues(alpha: 0.85)
                                                          : widget.appTheme.selectScreenCardTextColor
                                                              .withValues(alpha: 0.35),
                                                      BlendMode.srcIn,
                                                    ),
                                                  ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                            hintText: "Commit message",
                            hintStyle: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor
                                  .withAlpha(120),
                            ),
                            border: const OutlineInputBorder(),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xff0e639c),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  BlocBuilder<GithubAuthCubit, GithubAuthState>(
                    builder: (context, authState) {
                      final isSignedIn = authState.isSignedIn;
                      return BlocBuilder<RepoStatusBloc, RepoStatusState>(
                        builder: (_, repoState) {
                          return Column(
                            children: [
                              if (repoState is RepoStatusLoaded)
                                _buildCommitButton(context, repoState, isSignedIn),
                              if (repoState is RepoStatusLoading || repoState is RepoStatusInitial) ...[
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 20),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ] else if (repoState is RepoStatusError) ...[
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'Error: ${repoState.message}',
                                    style: TextStyle(
                                      color: widget.appTheme.selectScreenCardTextColor,
                                    ),
                                  ),
                                ),
                              ] else if (repoState is RepoStatusLoaded) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (repoState.staged.isNotEmpty)
                                      _buildCollapsibleChangesList(
                                        title: "Staged Changes",
                                        isExpanded: _stagedExpanded,
                                        onToggle: () => setState(() => _stagedExpanded =!_stagedExpanded),
                                        itemCount: repoState.staged.length,
                                        actionButton: Tooltip(
                                          message: "Unstage All Changes",
                                          child: IconButton(
                                            onPressed: () async {
                                              await unstageAll(
                                                widget.workSpace,
                                              );
                                              try {
                                                if (context.mounted) {
                                                  context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                }
                                              } catch (_) {}
                                            },
                                            icon: Text(
                                              "—",
                                              style: TextStyle(
                                                color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                                              ),
                                            ),
                                          ),
                                        ),
                                        controller: _stagedScrollController,
                                        itemBuilder: (_, index) {
                                          final fileName =
                                              _extractGitFilename(
                                                repoState.staged[index],
                                              );
                                          final (String, Color)
                                          repoIndicator =
                                              gitFileStatus[repoState.staged[index].substring(0, 2).trim()]!;
                                          return Padding(
                                            padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(8),
                                                onTap: () {},
                                                child: Container(
                                                  padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                  decoration: BoxDecoration(
                                                    color: widget.appTheme.isDark
                                                      ? Colors.white.withValues(alpha: 0.03)
                                                      : Colors.black.withValues(alpha: 0.03),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: repoIndicator.$2.withValues(alpha: 0.2),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 32,
                                                        height: 32,
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: (() {
                                                          try {
                                                            return languages.singleWhere((lang) => 
                                                              lang.extension.contains(
                                                                path.extension(path.basename(fileName),).replaceAll('.','',)
                                                              )).icon;
                                                          } catch (e) {
                                                            return Icon(
                                                              Icons .insert_drive_file,
                                                              size: 18,
                                                              color: repoIndicator.$2,
                                                            );
                                                          }
                                                        })(),
                                                      ),
                                                      const SizedBox(
                                                        width: 12,
                                                      ),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(path.basename(fileName),
                                                              style: TextStyle(
                                                                fontSize: 13.5,
                                                                fontWeight: FontWeight.w500,
                                                                color: repoIndicator.$2,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              fileName,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.5),
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 3,
                                                          ),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          repoIndicator.$1,
                                                          style: TextStyle(
                                                            color: repoIndicator.$2,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: 4,
                                                      ),
                                                      Tooltip(
                                                        message:"Unstage Changes",
                                                        child: InkWell(
                                                          borderRadius:BorderRadius.circular(4),
                                                          onTap: () async {
                                                            await unstageChange(fileName,widget.workSpace);
                                                            if (context.mounted) {
                                                              try {
                                                                context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                              } catch (_) {}
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(6),
                                                            child: Icon(
                                                              Icons.remove_circle_outline,
                                                              size: 18,
                                                              color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    if (repoState.unstaged.isNotEmpty)
                                      _buildCollapsibleChangesList(
                                        title: "Unstaged Changes",
                                        isExpanded: _unstagedExpanded,
                                        onToggle: () => setState(
                                          () => _unstagedExpanded =
                                              !_unstagedExpanded,
                                        ),
                                        itemCount: repoState.unstaged.length,
                                        actionButton: Tooltip(
                                          message: "Stage All Changes",
                                          child: IconButton(
                                            onPressed: () async {
                                              await stageAll(
                                                widget.workSpace,
                                              );
                                              if (context.mounted) {
                                                try {
                                                  context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                } catch (_) {}
                                              }
                                            },
                                            icon: Icon(
                                              Icons.add,
                                              color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                                            ),
                                          ),
                                        ),
                                        controller: _unstagedScrollController,
                                        itemBuilder: (_, index) {
                                          final fileName =_extractGitFilename(repoState.unstaged[index]);
                                          final (String, Color)
                                          repoIndicator = gitFileStatus[repoState.unstaged[index].substring(0, 2).trim()]!;
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 3),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:BorderRadius.circular(8),
                                                onTap: () {
                                                  final onOpenDiffView =
                                                      widget.onOpenDiffView;
                                                  final activeEditorsBloc =
                                                      widget.activeEditorsBloc;
                                                  if (onOpenDiffView != null &&
                                                      activeEditorsBloc != null) {
                                                    onOpenDiffView(
                                                      fileName,
                                                      widget.workSpace,
                                                      activeEditorsBloc,
                                                    );
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: widget.appTheme.isDark
                                                      ? Colors.white.withValues(alpha: 0.03)
                                                      : Colors.black.withValues(alpha: 0.03),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: repoIndicator.$2.withValues(alpha: 0.2),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 32,
                                                        height: 32,
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: (() {
                                                          try {
                                                            return languages.singleWhere((lang)
                                                              => lang.extension.contains(path.extension(
                                                                  path.basename(fileName)).replaceAll('.', ''),
                                                                  ),
                                                                ).icon;
                                                          } catch (e) {
                                                            return Icon(
                                                              Icons.insert_drive_file,
                                                              size: 18,
                                                              color: repoIndicator.$2,
                                                            );
                                                          }
                                                        })(),
                                                      ),
                                                      const SizedBox(width: 12,),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(path.basename(fileName),
                                                              style: TextStyle(
                                                                fontSize:13.5,
                                                                fontWeight: FontWeight.w500,
                                                                color: repoIndicator.$2,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(
                                                              fileName,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.5),
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          repoIndicator.$1,
                                                          style: TextStyle(
                                                            color: repoIndicator.$2,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Tooltip(
                                                        message: "Discard Change",
                                                        child: InkWell(
                                                          borderRadius: BorderRadius.circular(4),
                                                          onTap: () {
                                                            final repoBloc = context.read<RepoStatusBloc>();
                                                            showDialog(
                                                              context: context,
                                                              builder: (context) => BlocProvider.value(
                                                                value: repoBloc,
                                                                child: AlertDialog(
                                                                  title: Text(
                                                                    "Are you sure want to discard the changes?",
                                                                    style: TextStyle(
                                                                      color: Colors.grey[400],
                                                                      fontSize: 20,
                                                                    ),
                                                                  ),
                                                                  backgroundColor:widget.appTheme.isDark
                                                                      ? const Color(0xff2b2b2b)
                                                                      : const Color.fromARGB(255,240,240,240),
                                                                  icon: const Icon(Icons.info_outline, size: 35),
                                                                  iconColor: Colors.blue,
                                                                  actionsAlignment:MainAxisAlignment.center,
                                                                  actions: [
                                                                    TextButton(
                                                                      onPressed: () => Navigator.of(context,).pop(),
                                                                      child: const Text(
                                                                        "Cancel",
                                                                        style: TextStyle(
                                                                          color:Colors.red,
                                                                          fontSize:17,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width:25),
                                                                    TextButton(
                                                                      onPressed: () async {
                                                                        try {
                                                                          await gitRestoreFile(fileName, widget.workSpace);
                                                                          if (!context.mounted) return;

                                                                          final activeEditorBloc = widget.activeEditorsBloc;
                                                                          if (activeEditorBloc != null) {
                                                                            final activeEditors = activeEditorBloc.state.activeEditors;
                                                                            ActiveEditor? activeEditor;

                                                                            for (final editor in activeEditors) {
                                                                              if (editor.isActive) {
                                                                                activeEditor = editor;
                                                                                break;
                                                                              }
                                                                            }

                                                                            activeEditor ??= activeEditors.isNotEmpty ? activeEditors.first: null;
                                                                            activeEditor?.controller.refetchFile();
                                                                          }

                                                                          try {
                                                                            repoBloc.add(LoadRepoStatus(widget.workSpace));
                                                                          } catch (_) {}
                                                                        } catch (_) {
                                                                          if (context.mounted) {
                                                                            _showErrorSnackBar(
                                                                              context,
                                                                              'Failed to discard changes',
                                                                            );
                                                                          }
                                                                        } finally {
                                                                          if (context.mounted) {
                                                                            Navigator.of(context).pop();
                                                                          }
                                                                        }
                                                                      },
                                                                      child: const Text(
                                                                        "Yes",
                                                                        style: TextStyle(
                                                                          color: Colors.blue,
                                                                          fontSize: 17,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(6),
                                                            child: FaIcon(
                                                              FontAwesomeIcons.arrowRotateLeft,
                                                              size: 16,
                                                              color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.6),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: 4,
                                                      ),
                                                      Tooltip(
                                                        message: "Stage Changes",
                                                        child: InkWell(
                                                          borderRadius: BorderRadius.circular(4),
                                                          onTap: () async {
                                                            await stageChange(fileName, widget.workSpace);
                                                            if (context.mounted) {
                                                              try {
                                                                context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                              } catch (_) {}
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(6),
                                                            child: Icon(
                                                              Icons.add_circle_outline,
                                                              size: 18,
                                                              color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.6),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    Divider(thickness: 0.1,endIndent: 12,color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                                    ),
                                    _buildCollapsibleCommitGraph(),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        )
      : Center(
          child: Text(
            "Cannot initalize a git repository in the temp directory.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.appTheme.selectScreenCardTextColor,
            ),
          ),
        );
  }
}
