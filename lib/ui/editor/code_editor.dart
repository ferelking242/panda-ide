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

// Code editor widget
// Extracted from widgets.dart

import '../../utils/constants.dart';

Directory? _findRepoRoot(File file) {
  try {
    Directory dir = file.parent;
    while (true) {
      if (Directory(path.join(dir.path, '.git')).existsSync()) return dir;
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
  } catch (_) {}
  return null;
}

void _refreshRepoStatusForFile(BuildContext context, File file) {
  try {
    final root = _findRepoRoot(file);
    if (root != null) {
      context.read<RepoStatusBloc>().add(LoadRepoStatus(root.path));
    }
  } catch (_) {}
}

class CodeEditor extends StatefulWidget {
  final File filePath;
  final CodeForgeController codeController;
  final UndoRedoController undoRedoController;
  final ScrollController hscrollController;
  final ScrollController vscrollController;
  final Language language;
  final FindController findController;
  final bool showFindPanel;
  final VoidCallback? onFindPanelClose;
  const CodeEditor({
    super.key,
    required this.codeController,
    required this.undoRedoController,
    required this.hscrollController,
    required this.vscrollController,
    required this.filePath,
    required this.language,
    required this.findController,
    this.showFindPanel = false,
    this.onFindPanelClose,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class CodeEditorState extends State<CodeEditor> with AutomaticKeepAliveClientMixin {
  double _initialFontSize = 10.0;
  double _currentScale = 1.0;
  Timer? _saveTimer, _statusRefreshTimer;
  Timer? _copilotDebounceTimer;
  StreamSubscription<CopilotState>? _copilotSubscription;
  String? _currentCopilotUuid;
  bool _isUpdatingGhostText = false;
  bool _awaitingManualCopilotCompletion = false;

  @override
  void initState() {
    super.initState();
    final controller = widget.codeController;
    final ext = path.extension(widget.filePath.path).toLowerCase();
    if ((ext == '.tsx' || ext == '.jsx') && controller.lspConfig == null) {
      try {
        controller.lspConfig = LspSocketConfig(
          workspacePath: widget.filePath.parent.path,
          languageId: ext.substring(1),
          serverUrl: 'ws://127.0.0.1:65535',
          disableError: true,
          disableWarning: true,
        );
      } catch (_) {}
    }
    try {
      if (controller.text.isEmpty && widget.filePath.existsSync()) {
        controller.openedFile = widget.filePath.path;
        controller.notifyListeners();
      }
    } catch (_) {
    }
    final generalState = context.read<GeneralBloc>().state;
    final configState = context.read<ConfigBloc>().state;
    
    _setupCopilotListener();
    
    controller.addListener(() {
      if (!mounted || _isUpdatingGhostText) return;

      final isManual = configState.codeForgeConfig['manualCompletion'] ?? false;
      if (!isManual && controller.lastTypedCharacter != "") {
        _requestCopilotCompletion();
      }
      
      if (generalState.generalSettings['autoSave'] ?? true) {
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 85), () {
          try {
            controller.saveFile();
          } catch (_) {}
          _statusRefreshTimer?.cancel();
          _statusRefreshTimer = Timer(const Duration(milliseconds: 400), () {
            if (mounted) {
              _refreshRepoStatusForFile(context, widget.filePath);
            }
          });
        });
      }
    });
  }

  void _setupCopilotListener() {
    final copilotBloc = context.read<CopilotBloc>();
    _copilotSubscription = copilotBloc.stream.listen((state) {
      if (!mounted) return;
      
      final completion = state.currentCompletion;
      if (_awaitingManualCopilotCompletion) {
        if (completion != null) {
          _awaitingManualCopilotCompletion = false;
        } else {
          _awaitingManualCopilotCompletion = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No completion available'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      if (completion != null && completion.uuid != _currentCopilotUuid) {
        _currentCopilotUuid = completion.uuid;
        _displayCopilotGhostText(completion);
      } else if (completion == null && _currentCopilotUuid != null) {
        _currentCopilotUuid = null;
        _isUpdatingGhostText = true;
        widget.codeController.clearGhostText();
        _isUpdatingGhostText = false;
      }
    });
  }

  void _displayCopilotGhostText(CopilotCompletionData completion) {
    final controller = widget.codeController;
    final cursor = controller.selection.start;
    final text = controller.text;
    final lines = text.substring(0, cursor).split('\n');
    final line = lines.length - 1;
    final column = lines.last.length;
    
    _isUpdatingGhostText = true;
    controller.setGhostText(GhostText(
      line: line,
      column: column,
      text: completion.displayText,
      style: TextStyle(
        color: Colors.grey.withValues(alpha: 0.6),
        fontStyle: FontStyle.italic,
      ),
      shouldPersist: false,
    ));
    _isUpdatingGhostText = false;
  }

  void _requestCopilotCompletion() {
    _copilotDebounceTimer?.cancel();
    
    final copilotBloc = context.read<CopilotBloc>();
    final state = copilotBloc.state;
    
    if (!state.isEnabled || state.status != CopilotStatus.signedIn) {
      return;
    }
    
    _copilotDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      
      _isUpdatingGhostText = true;
      widget.codeController.clearGhostText();
      _currentCopilotUuid = null;
      _isUpdatingGhostText = false;
      
      final controller = widget.codeController;
      final cursor = controller.selection.start;
      final text = controller.text;
      final lines = text.substring(0, cursor).split('\n');
      final line = lines.length - 1;
      final character = lines.last.length;
      
      copilotBloc.add(CopilotRequestCompletion(
        filePath: widget.filePath.path,
        content: text,
        line: line,
        character: character,
        languageId: widget.language.name.toLowerCase(),
      ));
    });
  }

  void requestCopilotCompletionManual() {
    final copilotBloc = context.read<CopilotBloc>();
    final state = copilotBloc.state;
    
    if (!state.isEnabled || state.status != CopilotStatus.signedIn) {
      return;
    }
    
    _isUpdatingGhostText = true;
    widget.codeController.clearGhostText();
    _currentCopilotUuid = null;
    _isUpdatingGhostText = false;
    
    final controller = widget.codeController;
    final cursor = controller.selection.start;
    final text = controller.text;
    final lines = text.substring(0, cursor).split('\n');
    final line = lines.length - 1;
    final character = lines.last.length;

    _awaitingManualCopilotCompletion = true;
    
    copilotBloc.add(CopilotRequestCompletion(
      filePath: widget.filePath.path,
      content: text,
      line: line,
      character: character,
      languageId: widget.language.name.toLowerCase(),
    ));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _statusRefreshTimer?.cancel();
    _copilotDebounceTimer?.cancel();
    _copilotSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final codeController = widget.codeController;
    return BlocBuilder<GeneralBloc, GeneralState>(
      builder: (context, generalState) {
        return BlocBuilder<ConfigBloc, ConfigState>(
          builder: (context, configState) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: (details) {
                if (details.pointerCount == 2) {
                  _initialFontSize = configState.fontSize;
                }
              },
              onScaleUpdate: (details) {
                if (details.pointerCount == 2) {
                  _currentScale = details.scale;
                  double newFontSize = _initialFontSize * _currentScale;
                  newFontSize = newFontSize.clamp(8.0, 48.0);
                  context.read<ConfigBloc>().add(
                    SetFontSize(fontSize: newFontSize),
                  );
                }
              },
              child: BlocBuilder<AIBloc, AIState>(
                builder: (context, aiState) {
                  final ext = path.extension(widget.filePath.path).toLowerCase();
                  final primaryMode = widget.language.language;

                  return CodeForge(
                    key: ValueKey('${widget.filePath.path}:${widget.language.name}'),
                    horizontalScrollController: null,
                    verticalScrollController: null,
                    lineWrap: (configState.codeForgeConfig['lineWrap'] ?? false) as bool,
                    enableFolding: (configState.codeForgeConfig['enableFolding'] ?? true) as bool,
                    language: primaryMode,
                    extraLanguages: (() {
                      if (ext == '.tsx' || ext == '.jsx') {
                        final Mode? xmlMode = langxml.language;
                        if (xmlMode != null) {
                          return <Mode>[xmlMode];
                        }
                      }
                      return const <Mode>[];
                    })(),
                    customCodeSnippets: widget.language.customCodeSnippet,
                    filePath: widget.filePath.path,
                    enableGuideLines: (configState.codeForgeConfig['indentLineStatus'] ?? true) as bool,
                    selectionStyle: CodeSelectionStyle(
                      selectionColor: Colors.blueAccent.withAlpha(80),
                      cursorBubbleColor: Colors.blue,
                    ),
                    matchHighlightStyle: const MatchHighlightStyle(
                      currentMatchStyle: TextStyle(backgroundColor: Color(0xFFFFA726)),
                      otherMatchStyle: TextStyle(backgroundColor: Color(0x55FFFF00)),
                    ),
                    editorTheme: getMergedHighlightThemes(configState.codeForgeConfig)[configState.codeForgeConfig['theme']],
                    textStyle: TextStyle(
                      fontFamily: configState.codeForgeConfig['fontFamily'],
                      fontSize: configState.fontSize,
                    ),
                    controller: codeController,
                    undoController: widget.undoRedoController,
                    findController: widget.findController,
                    finderBuilder: (context, findController) {
                      return FindPanelWidget(
                        controller: findController,
                        onClose: widget.onFindPanelClose,
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

const double _kFindPanelWidth = 380, _kFindPanelHeight = 36;
const double _kReplacePanelHeight = _kFindPanelHeight * 2;
const double _kFindIconSize = 18;
const double _kFindInputFontSize = 13, _kFindResultFontSize = 11;
