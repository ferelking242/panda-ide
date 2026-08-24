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

// Editor area container
// Extracted from widgets.dart

class EditorArea extends StatefulWidget {
  final ActiveEditor editor;
  final AppTheme appTheme;
  final String workspacePath;
  final TabController? tabController;
  const EditorArea({
    super.key,
    required this.editor,
    required this.appTheme,
    required this.workspacePath,
    this.tabController,
  });

  @override
  State<EditorArea> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorArea> with AutomaticKeepAliveClientMixin {
  late final ActiveEditor editor;
  late final AppTheme appTheme;
  late final CodeForgeController controller;
  late final UndoRedoController undoRedoController;
  late Language language;
  late final File file;
  late final String ext;
  final GlobalKey<_CodeEditorState> _editorKey = GlobalKey();
  final cursor = ValueNotifier<({int line, int col})>((line: 0, col: 0));
  final isGeneratingCompletion = ValueNotifier<bool>(false);
  PendingEditFile? _pendingEdits;
  bool _isApplyingPendingAction = false;
  Timer? _pendingRefreshTimer;

  String _lspLanguageIdForPath(Language lang, String filePath) {
    return lspLanguageIdForFile(language: lang, filePath: filePath);
  }

  ({int line, int col}) _lineAndColumnAtCursor(CodeForgeController targetController) {
    final offset = targetController.selection.extentOffset.clamp(0, targetController.length);
    final line = targetController.getLineAtOffset(offset);
    final lineStartOffset = targetController.findLineStart(offset);
    final col = offset - lineStartOffset;
    return (line: line, col: col);
  }

  double _languageDropdownWidth(BuildContext context) {
    const fontSize = 11.0;
    final style = TextStyle(
      color: appTheme.selectScreenCardTextColor,
      fontSize: fontSize,
    );
    final painter = TextPainter(
      text: TextSpan(text: language.name, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

    const chromeWidth = 28.0;
    const horizontalPadding = 10.0;
    return painter.width + chromeWidth + horizontalPadding;
  }

  Future<void> _overrideLanguage(Language selectedLanguage) async {
    if (selectedLanguage.name == language.name) return;

    final activeEditorBloc = context.read<ActiveEditorBloc>();
    final codeForgeConfig = context.read<ConfigBloc>().state.codeForgeConfig;

    LspConfig? nextLspConfig;
    if (codeForgeConfig['enableLSP'] == true) {
      nextLspConfig = await activeEditorBloc.getOrStartSharedLspConfig(
        languageId: _lspLanguageIdForPath(selectedLanguage, file.path),
        ext: lspServerExtForFilePath(file.path),
        executable: selectedLanguage.lspExecutable,
        args: selectedLanguage.args ?? const [],
      );
    }

    if (!mounted) return;

    final currentEditors = List<ActiveEditor>.from(activeEditorBloc.state.activeEditors);
    final currentPath = File(file.path).absolute.path;
    final index = currentEditors.indexWhere(
      (item) => File(item.file.path).absolute.path == currentPath,
    );

    if (index >= 0) {
      final existing = currentEditors[index];
      currentEditors[index] = ActiveEditor(
        file: existing.file,
        controller: existing.controller,
        languageDetails: selectedLanguage,
        undoRedoController: existing.undoRedoController,
        hscroll: existing.hscroll,
        vscroll: existing.vscroll,
        isActive: existing.isActive,
        findController: existing.findController,
        customTitle: existing.customTitle,
      );
      activeEditorBloc.add(ActiveEditorEvent(currentEditors));
    }

    setState(() {
      language = selectedLanguage;
      controller.lspConfig = nextLspConfig;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.focusNode?.requestFocus();
    });
  }

  @override
  void initState() {
    editor = widget.editor;
    appTheme = widget.appTheme;
    controller = editor.controller;
    undoRedoController = editor.undoRedoController;
    language = editor.languageDetails;
    file = editor.file;
    ext = path.extension(file.path);
    _reloadPendingEdits();
    _pendingRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _reloadPendingEdits(silent: true),
    );

    controller.addListener((){
      if(!mounted || !context.mounted || !controller.selection.isValid) return;
      cursor.value = _lineAndColumnAtCursor(controller);
    });
    super.initState();
  }

  @override
  void didUpdateWidget(covariant EditorArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor.file.path != widget.editor.file.path) {
      _reloadPendingEdits();
    }
  }

  Future<void> _reloadPendingEdits({bool silent = false}) async {
    final pending = await PendingEditFile.getForFile(File(file.path).absolute.path);
    if (!mounted) return;
    if (silent && _pendingEdits?.editHunks.length == pending?.editHunks.length) {
      return;
    }
    setState(() {
      _pendingEdits = pending;
    });
  }

  Future<void> _keepHunk(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepPendingEditHunk(file.path, hunk.id);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
    }
  }

  Future<void> _rejectHunk(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectPendingEditHunk(file.path, hunk.id);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
      if (!result.success && result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
    }
  }

  Future<void> _keepAll() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepAllPendingEdits(file.path);
    await _reloadPendingEdits();
    if (mounted) setState(() => _isApplyingPendingAction = false);
  }

  Future<void> _rejectAll() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectAllPendingEdits(file.path);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
      if (!result.success && result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
    }
  }

  Future<void> _applyPendingAgenticDiffForFile(
    CodeForgeController targetController,
    String filePath,
  ) async {
    try {
      final canonicalPath = File(filePath).absolute.path;
      final pending = await PendingEditFile.getForFile(canonicalPath);
      if (!mounted) return;
      if (pending == null || pending.editHunks.isEmpty) return;
      pending.applyDecorations(targetController);
    } catch (_) {}
  }

  ButtonStyle _pendingActionStyle({bool destructive = false}) {
    final accent = destructive
        ? const Color(0xFFC62828)
        : (appTheme.isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32));
    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.75)),
      backgroundColor: accent.withValues(alpha: appTheme.isDark ? 0.12 : 0.08),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }

  Widget? _buildPendingDiffPanel() {
    final pending = _pendingEdits;
    if (pending == null || pending.editHunks.isEmpty) {
      return null;
    }
    final counts = _pendingDiffCounts(pending);

    return Positioned(
      right: 10,
      bottom: 10,
      child: Container(
        width: 310,
        constraints: const BoxConstraints(maxHeight: 250),
        decoration: BoxDecoration(
          color: appTheme.isDark ? const Color(0xff1f1f1f) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.compare_arrows, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Pending Diff',
                    style: TextStyle(
                      color: appTheme.selectScreenCardTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+${counts.added}',
                    style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-${counts.removed}',
                    style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pending.editHunks.length,
                  itemBuilder: (context, index) {
                    final hunk = pending.editHunks[index];
                    final displayRange = _resolveDisplayLineRange(pending, hunk);
                    final lineLabel = hunk.type == 'removed'
                      ? 'After L${displayRange.start + 1}'
                      : 'L${displayRange.start + 1}-${displayRange.end + 1}';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: appTheme.isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$lineLabel ${hunk.type}',
                              style: TextStyle(
                                color: appTheme.selectScreenCardTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            style: _pendingActionStyle(),
                            onPressed: _isApplyingPendingAction ? null : () => _keepHunk(hunk),
                            child: const Text('Keep'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            style: _pendingActionStyle(destructive: true),
                            onPressed: _isApplyingPendingAction ? null : () => _rejectHunk(hunk),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: _pendingActionStyle(),
                    onPressed: _isApplyingPendingAction ? null : _keepAll,
                    child: const Text('Keep all'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: _pendingActionStyle(destructive: true),
                    onPressed: _isApplyingPendingAction ? null : _rejectAll,
                    child: const Text('Reject all'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestExternalModelCompletion() async {
    final aiState = context.read<AIBloc>().state;
    final completionModel = aiState.completionModel;
    if (completionModel == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected completion model is not configured correctly.')),
      );
      return;
    }

    final text = controller.text;
    final cursorOffset = controller.selection.start.clamp(0, text.length);
    final cursorLine = controller.getLineAtOffset(cursorOffset);
    final lineStartOffset = controller.findLineStart(cursorOffset);
    final beforeCursor = text.substring(0, cursorOffset);
    final cursorColumn = cursorOffset - lineStartOffset;

    final prompt = '''Language: ${language.name}\nFile: ${file.path}\nCode:\n$beforeCursor<|CURSOR|>${text.substring(cursorOffset)}''';

    try {
      if (completionModel is LocalLlama) {
        final llamaBloc = context.read<LocalLlamaBloc>();
        if (llamaBloc.state.loadedModelPath != completionModel.modelPath ||
            !llamaBloc.state.isReady) {
          llamaBloc.add(LocalLlamaLoadModel(completionModel));
          await llamaBloc.stream.firstWhere(
            (s) => s.status == LocalLlamaStatus.ready || s.status == LocalLlamaStatus.error,
          );
          if (llamaBloc.state.status == LocalLlamaStatus.error) {
            throw Exception('Failed to load model: ${llamaBloc.state.error}');
          }
        }
        final llamaController = llamaBloc.controller;
        if (llamaController == null) throw Exception('Llama controller is null');

        final buffer = StringBuffer();
        isGeneratingCompletion.value = true;
        await for (final token in llamaController.generate(
          prompt: "${Models.instruction}\n\n$prompt",
          maxTokens: completionModel.maxTokens,
          temperature: completionModel.temperature,
          topP: completionModel.topP,
          topK: completionModel.topK,
          repeatPenalty: completionModel.repeatPenalty,
          frequencyPenalty: completionModel.frequencyPenalty,
          presencePenalty: completionModel.presencePenalty,
          repeatLastN: completionModel.repeatLastN,
          seed: completionModel.seed,
          mirostat: completionModel.mirostat,
          mirostatTau: completionModel.mirostatTau,
          mirostatEta: completionModel.mirostatEta,
        )) {
          buffer.write(token);
          controller.setGhostText(GhostText(
            line: cursorLine,
            column: cursorColumn,
            text: buffer.toString(),
            style: TextStyle(
            color: Colors.grey.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ));
        }
        isGeneratingCompletion.value = false;
        return;
      }

      isGeneratingCompletion.value = true;
      final suggestion = await completionModel.completionResponse(prompt);
      isGeneratingCompletion.value = false;

      if (!mounted) return;
      if (suggestion.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No completion available for this position.')),
        );
        return;
      }

      controller.clearGhostText();
      controller.setGhostText(
        GhostText(
          line: cursorLine,
          column: cursorColumn,
          text: suggestion,
          style: TextStyle(
            color: Colors.grey.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completion request failed: $e'), duration: const Duration(seconds: 3)),
      );
    } finally {
      isGeneratingCompletion.value = false;
    }
  }

  @override
  void dispose() {
    _pendingRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sctrl = ScrollController();
    super.build(context);
    final codeForgeConfig = context.watch<ConfigBloc>().state.codeForgeConfig;
    final activeEditorBloc = context.watch<ActiveEditorBloc>();
    final lspLanguageId = _lspLanguageIdForPath(language, file.path);
    final lspCacheKey = ActiveEditorBloc.buildLspCacheKey(
      workspacePath: widget.workspacePath,
      languageId: lspLanguageId,
    );
    final lspExt = language.extension.isNotEmpty
        ? language.extension[0]
        : path.extension(file.path).replaceFirst('.', '');
    final isLspServerInstalled = isLspServerAvailable(
      ext: lspExt,
      executable: language.lspExecutable,
      args: language.args ?? const [],
    );
    final workspaceLspConfig = activeEditorBloc.sharedLspConfigs[lspCacheKey];
    final isWorkspaceLspRunning =
        workspaceLspConfig != null && workspaceLspConfig == controller.lspConfig;
    final lspEnabled = (codeForgeConfig['enableLSP'] ?? false) == true;
    final lspFeatureToggle = Map<String, dynamic>.from(
      codeForgeConfig['LSPFeatureToggle'] ?? {},
    );
    final disabledLspFeatures = List<String>.from(
      lspFeatureToggle[language.name.toLowerCase()] ?? const [],
    );
    bool isLspFeatureEnabled(String feature) {
      if (!lspEnabled || !isLspServerInstalled || !isWorkspaceLspRunning) {
        return false;
      }
      return !disabledLspFeatures.contains(feature);
    }

    final codeActionEnabled = isLspFeatureEnabled('codeAction');
    final inlayHintEnabled = isLspFeatureEnabled('inlayHint');
    final goToDefinitionEnabled = isLspFeatureEnabled('goToDefinition');
    final signatureHelpEnabled = isLspFeatureEnabled('signatureHelp');

    final pageContent = Column(
      children: [
        Expanded(
          child: Builder(
            builder: (context) {
              final pendingPanel = _buildPendingDiffPanel();
              return Stack(
                children: [
                  CodeEditor(
                    key: _editorKey,
                    language: language,
                    undoRedoController: undoRedoController,
                    codeController: controller,
                    filePath: editor.file,
                    findController: editor.findController!,
                    hscrollController: editor.hscroll,
                    vscrollController: editor.vscroll,
                  ),
                  if (pendingPanel != null) pendingPanel,
                ],
              );
            },
          ),
        ),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: appTheme.isDark
                ? const Color.fromARGB(255, 25, 25, 25)
                : const Color.fromARGB(255, 236, 236, 236),
            border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ValueListenableBuilder(
                valueListenable: cursor,
                builder: (ctx, lineColValue, child) {
                  return Text(
                    'Ln ${lineColValue.line + 1}, Col ${lineColValue.col + 1}',
                    style: TextStyle(
                      color: appTheme.selectScreenCardTextColor,
                      fontSize: 11,
                    ),
                  );
                }
              ),
              const SizedBox(width: 20),
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: SizedBox(
                  width: _languageDropdownWidth(context),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Language>(
                      dropdownColor: appTheme.editorPageDrawerBg,
                      isDense: true,
                      isExpanded: true,
                      value: language,
                      iconSize: 16,
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor,
                        fontSize: 11,
                      ),
                      items: languages.map((lang) {
                        return DropdownMenuItem<Language>(
                          value: lang,
                          child: Row(
                            spacing: 3,
                            children: [
                              SizedBox(
                                height:14,
                                width: 14,
                                child: lang.icon
                              ),
                              Text(
                                lang.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _overrideLanguage(value);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ValueListenableBuilder(
            valueListenable: isGeneratingCompletion,
            builder:(context, aiValue, _) => aiValue ? Padding(
              padding: const EdgeInsets.only(right: 7, bottom: 7),
              child: Container(
                height: 50,
                width: 300,
                decoration: BoxDecoration(
                  color: appTheme.selectScreenDrawerBg,
                  borderRadius: BorderRadius.circular(10)
                ),
                child: Column(
                  children: [
                    Expanded(
                      flex: 15,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Row(
                          spacing: 8,
                          children: [
                            Icon(
                              Icons.info_outlined,
                              color: Colors.blue
                            ),
                            Expanded(
                              child: Text(
                                "Generating...",
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor
                                )
                              )
                            ),
                          ]
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: LinearProgressIndicator(
                          borderRadius: BorderRadius.circular(5)
                        ),
                      )
                    )
                  ]
                )
              ),
            ) : SizedBox.shrink(),
          ),
        ),
        RawScrollbar(
          controller: sctrl,
          scrollbarOrientation: ScrollbarOrientation.top,
          thumbColor: appTheme.selectScreenCardTextColor.withAlpha(50),
          interactive: false,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: SingleChildScrollView(
            controller: sctrl,
            padding: EdgeInsets.zero,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 78,
                  color: appTheme.isDark
                    ? const Color.fromARGB(255, 32, 32, 32)
                    : const Color.fromARGB(255, 219, 218, 218),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            height: 37,
                            width: 50,
                            child: Tooltip(
                              message: "tab",
                              child: IconButton(
                                highlightColor: Colors.lightBlue.withAlpha(160),
                                style: ButtonStyle(
                                  shape: WidgetStateProperty.all(
                                    const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(10)),
                                    ),
                                  ),
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  final ghostText = controller.ghostText;
                                  if(ghostText != null){
                                    controller.insertText(ghostText.text, ghostText.line, ghostText.column);
                                    controller.clearGhostText();
                                  } else {
                                    controller.indent();
                                  }
                                },
                                icon: SvgPicture.asset(
                                  "assets/icons/tab.svg",
                                  height: 25,
                                  width: 25,
                                  colorFilter: ColorFilter.mode(
                                    appTheme.isDark
                                      ? const Color.fromARGB(255, 194, 194, 194)
                                      : const Color.fromARGB(255, 40, 40, 40),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: "undo",
                            child: AnimatedBuilder(
                              animation: undoRedoController,
                              builder: (context, _) {
                                return bottomTool(
                                  appTheme.isDark,
                                  Icons.undo,
                                  undoRedoController.undo,
                                  null,
                                  undoRedoController.canUndo,
                                );
                              },
                            ),
                          ),
                          Tooltip(
                            message: "redo",
                            child: AnimatedBuilder(
                              animation: undoRedoController,
                              builder: (context, _) {
                                return bottomTool(
                                  appTheme.isDark,
                                  Icons.redo,
                                  undoRedoController.redo,
                                  null,
                                  undoRedoController.canRedo,
                                );
                              },
                            ),
                          ),
                          Tooltip(
                            message: "upward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_upward,
                              controller.pressUpArrowKey,
                            ),
                          ),
                          Tooltip(
                            message: "request ai completion",
                            child: SizedBox(
                              height: 37,
                              width: 50,
                              child: IconButton(
                                highlightColor: Colors.lightBlue.withAlpha(160),
                                style: ButtonStyle(
                                  shape: WidgetStateProperty.all(
                                    const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(10)),
                                    ),
                                  ),
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final String? codeModel = context.read<AIBloc>().state.modelSelected['code'];
                                  if (codeModel != null && codeModel.isNotEmpty && context.read<AIBloc>().state.isEnabled) {
                                    if(codeModel == "copilot"){
                                      _editorKey.currentState?.requestCopilotCompletionManual();
                                    } else {
                                      await _requestExternalModelCompletion();
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          "No completion model found. Configure one in the settings",
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                icon: SvgPicture.asset(
                                  "assets/icons/ai.svg",
                                  height: 25,
                                  width: 25,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Tooltip(
                            message: "zoom in",
                            child: bottomTool(appTheme.isDark, Icons.zoom_in, () {
                              double currentFontSize = context.read<ConfigBloc>().state.fontSize;
                              context.read<ConfigBloc>().add(SetFontSize(fontSize: currentFontSize * 1.15));
                            }),
                          ),
                          Tooltip(
                            message: "zoom out",
                            child: bottomTool(appTheme.isDark, Icons.zoom_out, () {
                              double currentFontSize = context.read<ConfigBloc>().state.fontSize;
                              context.read<ConfigBloc>().add(SetFontSize(fontSize: currentFontSize * 0.9));
                            }),
                          ),
                          Tooltip(
                            message: "backward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_back,
                              controller.pressLetfArrowKey,
                            ),
                          ),
                          Tooltip(
                            message: "downward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_downward,
                              controller.pressDownArrowKey,
                            ),
                          ),
                          Tooltip(
                            message: "forward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_forward,
                              controller.pressRightArrowKey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 78,
                  color: appTheme.isDark
                    ? const Color.fromARGB(255, 32, 32, 32)
                    : const Color.fromARGB(255, 219, 218, 218),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Tooltip(
                            message: "code actions",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.lightbulb,
                              (){
                                controller.getCodeAction();
                              },
                              null,
                              codeActionEnabled,
                            ),
                          ),
                          Tooltip(
                            message: "inlay hints",
                            child: SizedBox(
                              height: 37,
                              width: 50,
                              child: InkWell(
                                onTap: inlayHintEnabled
                                  ? (){
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: appTheme.cardTheme.color,
                                      content: Padding(
                                        padding: const EdgeInsets.only(left: 10),
                                        child: Row(
                                          spacing: 7, 
                                          children: [
                                            Icon(Icons.info_outline_rounded, color: Colors.blueAccent),
                                            Text("Hold down to see inlay hints")
                                          ]
                                        ),
                                      )
                                    )
                                  );
                                } : null,
                                onLongPress: inlayHintEnabled ? controller.showInlayHints : null,
                                onLongPressUp: inlayHintEnabled ? controller.hideInlayHints : null,
                                child: Icon(
                                  Icons.highlight_outlined,
                                  color: inlayHintEnabled
                                    ? (!appTheme.isDark
                                        ? const Color.fromARGB(255, 40, 40, 40)
                                        : const Color.fromARGB(255, 194, 194, 194))
                                    : (appTheme.isDark ? Colors.grey.shade700 : Colors.grey.shade500),
                                )
                              ),
                            ),
                          ),
                          
                          Tooltip(
                            message: "go to defenition",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.devices_fold_outlined,
                              () async{
                                if(controller.lspConfig == null || controller.openedFile == null) return;
                                final cursorOffset = controller.selection.extentOffset.clamp(0, controller.length);
                                final line = controller.getLineAtOffset(cursorOffset);
                                final lineText = controller.getLineText(line);
                                final lineStartOffset = controller.findLineStart(cursorOffset);
                                final character = (cursorOffset - lineStartOffset).clamp(0, lineText.length);

                                Map<String, dynamic> def = {};
                                try {
                                  def = await controller.lspConfig!.getDefinition(
                                    controller.openedFile!,
                                    line,
                                    character,
                                  );
                                } catch (_) {
                                  def = {};
                                }
                            
                                final String? defFile = def["uri"];
                                if (defFile != null){
                                  if(!context.mounted) return;
                                  final defPath = File(Uri.parse(defFile).toFilePath()).absolute.path;
                                  if(defPath == controller.openedFile){
                                    final int? line = def["range"]?["start"]?["line"];
                                    if(line != null){
                                      controller.scrollToLine(line);
                                    }
                                  } else {
                                    final int? line = def["range"]?["start"]?["line"];
                                    final activeEditorBloc = context.read<ActiveEditorBloc>();
                                    final currentState = List<ActiveEditor>.from(
                                      activeEditorBloc.state.activeEditors,
                                    );
                            
                                    final existingIndex = currentState.indexWhere(
                                      (item) => File(item.file.path).absolute.path == defPath,
                                    );
                            
                                    if (existingIndex >= 0) {
                                      for (var i = 0; i < currentState.length; i++) {
                                        currentState[i].isActive = i == existingIndex;
                                      }
                                      activeEditorBloc.add(ActiveEditorEvent(currentState));
                            
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        final tabController = widget.tabController;
                                        if (tabController != null && existingIndex < tabController.length) {
                                          tabController.animateTo(existingIndex);
                                        }
                                        if (line != null) {
                                          currentState[existingIndex].controller.scrollToLine(line);
                                        }
                                      });
                                    } else {
                                      final targetFile = File(defPath);
                                      if (!targetFile.existsSync()) return;
                            
                                      for (final item in currentState) {
                                        item.isActive = false;
                                      }
                            
                                      final lang = languages.firstWhere(
                                        (language) => language.extension.contains(
                                          path.extension(targetFile.path).replaceFirst(".", ""),
                                        ),
                                        orElse: () => languages[0],
                                      );
                            
                                      final config = context.read<ConfigBloc>().state.codeForgeConfig;
                                      LspConfig? lspConfig;
                                      if (config['enableLSP']) {
                                        lspConfig = await activeEditorBloc.getOrStartSharedLspConfig(
                                          languageId: _lspLanguageIdForPath(lang, targetFile.path),
                                          ext: lspServerExtForFilePath(targetFile.path),
                                          executable: lang.lspExecutable,
                                          args: lang.args ?? [],
                                        );
                                      }
                            
                                      final newController = CodeForgeController(lspConfig: lspConfig);
                                      await _applyPendingAgenticDiffForFile(newController, targetFile.path);
                                      final newEditor = ActiveEditor(
                                        file: targetFile,
                                        controller: newController,
                                        languageDetails: lang,
                                        undoRedoController: UndoRedoController(),
                                        hscroll: ScrollController(),
                                        vscroll: ScrollController(),
                                        isActive: true,
                                        findController: FindController(newController),
                                      );
                            
                                      currentState.add(newEditor);
                                      activeEditorBloc.add(ActiveEditorEvent(currentState));
                            
                                      final newIndex = currentState.length - 1;
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        final tabController = widget.tabController;
                                        if (tabController != null && newIndex < tabController.length) {
                                          tabController.animateTo(newIndex);
                                        }
                                        if (line != null) {
                                          Future.delayed(const Duration(milliseconds: 100), () {
                                            if (!mounted) return;
                                            newEditor.controller.scrollToLine(line);
                                          });
                                        }
                                      });
                                    }
                                  }
                                }
                              },
                              null,
                              goToDefinitionEnabled,
                            ),
                          ),
                          Tooltip(
                            message: "home key",
                            child: bottomTool(
                              appTheme.isDark,
                              "Home",
                              controller.pressHomeKey
                            ),
                          ),
                          Tooltip(
                            message: "end key",
                            child: bottomTool(
                              appTheme.isDark,
                              "End",
                              controller.pressEndKey
                            ),
                          )
                        ],
                      ),
                      Row(
                        children: [
                          Tooltip(
                            message: "move line up",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.keyboard_double_arrow_up_outlined,
                              controller.moveLineUp
                            ),
                          ),

                          Tooltip(
                            message: "move line down",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.keyboard_double_arrow_down_outlined,
                              controller.moveLineDown
                            ),
                          ),

                          Tooltip(
                            message: "duplicate selection",
                            child: bottomTool(
                              appTheme.isDark,
                              "Dup",
                              controller.duplicateLine
                            ),
                          ),

                          Tooltip(
                            message: "signature help",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.signpost,
                              () => controller.callSignatureHelp(),
                              null,
                              signatureHelpEnabled,
                            ),
                          ),

                          Tooltip(
                            message: "highlight current line",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.format_paint,
                              (){
                                final line = controller.getLineAtOffset(controller.selection.extentOffset);
                            
                                if(controller.lineDecorations.any((l) => l.id == line.toString())){
                                  final decoratedId = controller.lineDecorations.singleWhere((l) => l.id == line.toString()).id;
                                  controller.removeLineDecoration(decoratedId);
                                  controller.removeGutterDecoration(decoratedId);
                                  return;
                                }
                            
                                controller.addLineDecoration(
                                  LineDecoration(
                                    id: line.toString(),
                                    startLine: line,
                                    endLine: controller.getLineAtOffset(controller.selection.extentOffset),
                                    type: LineDecorationType.background,
                                    color: Colors.blue.withAlpha(95)
                                  )
                                );
                            
                                controller.addGutterDecoration(
                                  GutterDecoration(
                                    id: line.toString(),
                                    startLine: line,
                                    endLine: controller.getLineAtOffset(controller.selection.extentOffset),
                                    type: GutterDecorationType.dot,
                                    color: Colors.blue
                                  )
                                );
                              }
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
    return pageContent;
  }

  @override
  bool get wantKeepAlive => true;
}

class DirectoryTreeViewerCustom extends StatefulWidget {
