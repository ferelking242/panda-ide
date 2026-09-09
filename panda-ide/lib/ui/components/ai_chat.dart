import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import '../../utils/llama_wrapper.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:path/path.dart' as path;
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:panda/utils/agentic_tools.dart';
import '../../bloc/repo_bloc/repo_bloc.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../terminal/terminal.dart';
import '../../utils/ai.dart';
import '../../utils/copilot_chat.dart';
import '../../utils/functions.dart';
import '../../utils/languages.dart';
import '../../utils/themes.dart';


// Helper functions extracted from monolithic widgets.dart

int _lineCount(String? text) {
  if (text == null || text.isEmpty) return 0;
  return text.split('\n').length;
}

({int added, int removed}) _pendingDiffCounts(PendingEditFile? pending) {
  if (pending == null) return (added: 0, removed: 0);
  var added = 0;
  var removed = 0;
  for (final hunk in pending.editHunks) {
    if (hunk.type == 'added') {
      added += _lineCount(hunk.addedText ?? hunk.newText);
      continue;
    }
    if (hunk.type == 'removed') {
      removed += _lineCount(hunk.removedText ?? hunk.oldText);
      continue;
    }
    added += _lineCount(hunk.addedText);
    removed += _lineCount(hunk.removedText);
  }
  return (added: added, removed: removed);
}

int _lineAtOffset(String text, int offset) {
  if (text.isEmpty) return 0;
  final safeOffset = offset.clamp(0, text.length);
  return '\n'.allMatches(text.substring(0, safeOffset)).length;
}

({int start, int end}) _resolveDisplayLineRange(
  PendingEditFile pending,
  EditHunk hunk,
) {
  final needle = hunk.oldText;
  if (needle.isNotEmpty) {
    final first = pending.oldText.indexOf(needle);
    if (first >= 0) {
      final second = pending.oldText.indexOf(needle, first + 1);
      if (second == -1) {
        final start = _lineAtOffset(pending.oldText, first);
        final endOffset = (first + needle.length - 1).clamp(first, pending.oldText.length);
        final end = _lineAtOffset(pending.oldText, endOffset);
        return (start: start, end: end);
      }
    }
  }
  return (start: hunk.sourceStartLine, end: hunk.sourceEndLine);
}

// AI chat interface
// Extracted from widgets.dart

class AIChat extends StatefulWidget {
  final String filePath, workspacePath;
  const AIChat({
    required this.filePath,
    required this.workspacePath, 
    super.key
  });

  @override
  State<AIChat> createState() => _AIChatState();
}

class _ModelOption {
  final String id, name;
  final String? provider;
  final String? rateLabel;
  final Widget icon;
  final bool isCopilot;
  _ModelOption({
    required this.id,
    required this.name,
    this.provider,
    this.rateLabel,
    required this.icon,
    this.isCopilot = false,
  });
}

class _AIChatState extends State<AIChat> with SingleTickerProviderStateMixin {
  static final RegExp _toolEditPattern = RegExp(r'^\[\[PANDA_EDIT:([^|\]]+)\|(\d+)\|(\d+)\]\]$');
  static final RegExp _toolTerminalPattern = RegExp(r'^\[\[PANDA_TERMINAL:([^\]]+)\]\]$');
  static final RegExp _toolStatusPattern = RegExp(r'^\[\[PANDA_STATUS:([^\]]+)\]\]$');
  static const String _thinkingStartMarker = '[[PANDA_THINK_START]]';
  static const String _thinkingEndMarker = '[[PANDA_THINK_END]]';

  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _statusPulseController;
  http.Client? _currentClient;
  bool _initialScrollDone = false;
  bool _requestedCopilotModelRefresh = false;
  PendingEditFile? _pendingEdits;
  Timer? _pendingRefreshTimer;
  bool _isApplyingPendingAction = false;
  bool _isPendingPollingActive = false;
  bool _copilotSignedInFromPrefs = false;
  StreamSubscription<CopilotState>? _copilotStateSubscription;
  List<AIConversation>? _pendingEditBaseConversations;
  List<AIConversation>? _pendingEditedConversations;
  String? _pendingEditOriginalText;

  @override
  void initState() {
    super.initState();
    _statusPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    final uiState = context.read<AIChatUIBloc>().state;
    _promptController.text = uiState.promptText;
    _promptController.addListener(_onPromptChanged);
    _scrollController.addListener(_onScrollChanged);
    _loadCopilotSignInPref();
    _copilotStateSubscription = context.read<CopilotBloc>().stream.listen((state) {
      final nextValue = state.isSignedIn;
      if (nextValue == _copilotSignedInFromPrefs || !mounted) {
        return;
      }
      setState(() {
        _copilotSignedInFromPrefs = nextValue;
      });
    });
    _reloadPendingEdits();
  }

  Future<void> _loadCopilotSignInPref() async {
    final isSignedIn = await isCopilotSignedPref();
    if (!mounted) {
      return;
    }
    if (_copilotSignedInFromPrefs == isSignedIn) {
      return;
    }
    setState(() {
      _copilotSignedInFromPrefs = isSignedIn;
    });
  }

  @override
  void didUpdateWidget(covariant AIChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _reloadPendingEdits();
    }
  }

  void _updatePendingPolling(bool isGenerating) {
    if (isGenerating && !_isPendingPollingActive) {
      _isPendingPollingActive = true;
      _pendingRefreshTimer?.cancel();
      _pendingRefreshTimer = Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => _reloadPendingEdits(silent: true),
      );
      return;
    }

    if (!isGenerating && _isPendingPollingActive) {
      _isPendingPollingActive = false;
      _pendingRefreshTimer?.cancel();
      _pendingRefreshTimer = null;
      _reloadPendingEdits(silent: true);
    }
  }

  Future<void> _reloadPendingEdits({bool silent = false}) async {
    if (widget.filePath.isEmpty) {
      if (!mounted) return;
      setState(() => _pendingEdits = null);
      return;
    }
    final pending = await PendingEditFile.getForFile(File(widget.filePath).absolute.path);
    if (!mounted) return;
    if (silent && _pendingEdits?.editHunks.length == pending?.editHunks.length) {
      return;
    }
    setState(() {
      _pendingEdits = pending;
    });
  }

  Future<void> _keepHunkFromDrawer(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepPendingEditHunk(widget.filePath, hunk.id);
    await _reloadPendingEdits();
    if (mounted) setState(() => _isApplyingPendingAction = false);
  }

  Future<void> _rejectHunkFromDrawer(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectPendingEditHunk(widget.filePath, hunk.id);
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

  Future<void> _keepAllFromDrawer() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepAllPendingEdits(widget.filePath);
    await _reloadPendingEdits();
    if (mounted) setState(() => _isApplyingPendingAction = false);
  }

  Future<void> _rejectAllFromDrawer() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectAllPendingEdits(widget.filePath);
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

  ButtonStyle _drawerPendingActionStyle(AppTheme appTheme, {bool destructive = false}) {
    final accent = destructive
      ? const Color(0xFFC62828)
      : (appTheme.isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32));
    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.75)),
      backgroundColor: accent.withValues(alpha: appTheme.isDark ? 0.12 : 0.08),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }

  Widget _buildPendingDiffDrawerPanel(AppTheme appTheme) {
    final pending = _pendingEdits;
    if (pending == null || pending.editHunks.isEmpty) {
      return const SizedBox.shrink();
    }
    final counts = _pendingDiffCounts(pending);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appTheme.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pending hunks: ${pending.editHunks.length}',
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.88),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text('+${counts.added}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('-${counts.removed}', style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 112,
            child: ListView.builder(
              itemCount: pending.editHunks.length,
              itemBuilder: (context, index) {
                final hunk = pending.editHunks[index];
                final displayRange = _resolveDisplayLineRange(pending, hunk);
                final lineLabel = hunk.type == 'removed'
                  ? 'After L${displayRange.start + 1}'
                  : 'L${displayRange.start + 1}-${displayRange.end + 1}';
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$lineLabel ${hunk.type}',
                        style: TextStyle(
                          color: appTheme.selectScreenCardTextColor,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    OutlinedButton(
                      style: _drawerPendingActionStyle(appTheme),
                      onPressed: _isApplyingPendingAction ? null : () => _keepHunkFromDrawer(hunk),
                      child: const Text('Keep'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: _drawerPendingActionStyle(appTheme, destructive: true),
                      onPressed: _isApplyingPendingAction ? null : () => _rejectHunkFromDrawer(hunk),
                      child: const Text('Reject'),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.bottomRight,
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  style: _drawerPendingActionStyle(appTheme),
                  onPressed: _isApplyingPendingAction ? null : _keepAllFromDrawer,
                  child: const Text('Keep all'),
                ),
                OutlinedButton(
                  style: _drawerPendingActionStyle(appTheme, destructive: true),
                  onPressed: _isApplyingPendingAction ? null : _rejectAllFromDrawer,
                  child: const Text('Reject all'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onPromptChanged() {
    final bloc = context.read<AIChatUIBloc>();
    final current = bloc.state;
    bloc.add(AIChatUIEvent(
      chatMode: current.chatMode,
      promptText: _promptController.text,
      selectedModelId: current.selectedModelId,
      scrollOffset: current.scrollOffset,
      isGenerating: current.isGenerating,
    ));
  }

  void _onScrollChanged() {
    if (_scrollController.hasClients) {
      _updateBlocState(scrollOffset: _scrollController.offset);
    }
  }

  void _updateBlocState({
    ChatMode? chatMode,
    String? promptText,
    String? selectedModelId,
    double? scrollOffset,
    bool? isGenerating,
  }) {
    if (!mounted) return;

    final bloc = context.read<AIChatUIBloc>();
    final current = bloc.state;
    bloc.add(AIChatUIEvent(
      chatMode: chatMode ?? current.chatMode,
      promptText: promptText ?? current.promptText,
      selectedModelId: selectedModelId ?? current.selectedModelId,
      scrollOffset: scrollOffset ?? current.scrollOffset,
      isGenerating: isGenerating ?? current.isGenerating,
    ));
  }

  bool get _hasPendingConversationEdit => _pendingEditBaseConversations != null;

  List<AIConversation> _cloneConversations(List<AIConversation> conversations) {
    return conversations.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
  }

  void _restorePendingConversationEdit() {
    if (!_hasPendingConversationEdit) return;
    setState(() {
      _pendingEditBaseConversations = null;
      _pendingEditedConversations = null;
      _pendingEditOriginalText = null;
    });
  }

  void _startPendingConversationEdit(int index, List<AIConversation> baseConversations) {
    if (index < 0 || index >= baseConversations.length) return;

    final originalText = baseConversations[index].userRequest;
    final trimmedConversations = _cloneConversations(
      baseConversations.take(index).toList(),
    );

    setState(() {
      _pendingEditBaseConversations = _cloneConversations(baseConversations);
      _pendingEditedConversations = trimmedConversations;
      _pendingEditOriginalText = originalText;
    });

    _promptController.text = originalText;
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
  }

  Future<void> _retryConversationFromIndex({
    required int index,
    required AIConversation conversation,
    required List<AIConversation> sourceConversations,
    required AIChatUIState aiChatUIState,
    required ChatSessionState sessionState,
    required CopilotChatState chatState,
    required Models? chatModel,
  }) async {
    if (aiChatUIState.isGenerating) return;

    final prompt = conversation.userRequest.trim();
    if (prompt.isEmpty) return;

    final retryConversations = _cloneConversations(
      sourceConversations.take(index).toList(),
    );

    if (_hasPendingConversationEdit) {
      _restorePendingConversationEdit();
    }

    _promptController.text = prompt;
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );

    final selectedModel = aiChatUIState.selectedModelId ?? '';
    Map<String, dynamic> selectedCopilotModel = <String, dynamic>{};
    for (final candidate in chatState.models) {
      if (candidate['id']?.toString() == selectedModel) {
        selectedCopilotModel = Map<String, dynamic>.from(candidate);
        break;
      }
    }

    if (selectedCopilotModel.isNotEmpty) {
      _sendCopilotChatPrompt(
        retryConversations,
        sessionState.currentSession?.id,
        selectedModel,
        widget.workspacePath,
      );
      return;
    }

    if (chatModel != null) {
      _sendPrompt(chatModel, retryConversations, sessionState.currentSession?.id);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat model not available'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _showUserBubbleActions({
    required int index,
    required AIConversation conversation,
    required List<AIConversation> baseConversations,
    required AIChatUIState aiChatUIState,
    required ChatSessionState sessionState,
    required CopilotChatState chatState,
    required Models? chatModel,
    required AppTheme appTheme,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: appTheme.isDark ? const Color(0xff1e1e2e) : Colors.white,
      builder: (sheetContext) {
        final textColor = appTheme.selectScreenCardTextColor;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.copy_outlined, color: textColor),
                title: Text('Copy', style: TextStyle(color: textColor)),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: textColor),
                title: Text('Edit', style: TextStyle(color: textColor)),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.refresh_outlined, color: textColor),
                title: Text('Try again', style: TextStyle(color: textColor)),
                onTap: () => Navigator.of(sheetContext).pop('retry'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: conversation.userRequest));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
      return;
    }

    if (action == 'edit') {
      _startPendingConversationEdit(index, baseConversations);
      return;
    }

    if (action == 'retry') {
      await _retryConversationFromIndex(
        index: index,
        conversation: conversation,
        sourceConversations: baseConversations,
        aiChatUIState: aiChatUIState,
        sessionState: sessionState,
        chatState: chatState,
        chatModel: chatModel,
      );
    }
  }

  String _userFacingChatErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('Connection closed')) {
      return 'Generation stopped by user';
    }
    return 'Request failed: $text';
  }

  void _logChatError(String source, Object error, StackTrace stackTrace) {
    debugPrint('[AIChat][$source] $error');
    debugPrint('[AIChat][$source][stack] $stackTrace');
  }

  void _stopGeneration() {
    if (!mounted) return;

    _currentClient?.close();
    _currentClient = null;

    context.read<CopilotChatBloc>().chatClient?.cancelCurrentRequest();
    context.read<LocalLlamaBloc>().add(LocalLlamaStopGeneration());

    _updateBlocState(isGenerating: false);
  }

  @override
  void dispose() {
    _statusPulseController.dispose();
    _copilotStateSubscription?.cancel();
    _promptController.removeListener(_onPromptChanged);
    _scrollController.removeListener(_onScrollChanged);
    _currentClient?.close();
    _pendingRefreshTimer?.cancel();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _formatCopilotRate(Map<String, dynamic> model) {
    final billing = model['billing'];
    if (billing is! Map<String, dynamic>) return null;
    final multiplier = billing['multiplier'];
    if (multiplier is! num) return null;

    if (multiplier == multiplier.toInt()) {
      return '${multiplier.toInt()}x';
    }

    final fixed = multiplier.toStringAsFixed(2);
    final compact = fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${compact}x';
  }

  Widget _buildModeSelector(Color textColor, bool isDark, ChatMode chatMode) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ChatMode>(
          value: chatMode,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: textColor.withAlpha(150), size: 18),
          dropdownColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
          style: TextStyle(color: textColor, fontSize: 13),
          items: [
            DropdownMenuItem(
              value: ChatMode.ask,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 14, color: textColor.withAlpha(180)),
                  const SizedBox(width: 6),
                  Text('Ask', style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: ChatMode.agent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined, size: 14, color: textColor.withAlpha(180)),
                  const SizedBox(width: 6),
                  Text('Agent', style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              _updateBlocState(chatMode: mode);
            }
          },
        ),
      ),
    );
  }

  Widget _buildModelSelector(
    BuildContext context, 
    AIState aiState, 
    CopilotChatState chatState, 
    Color textColor, 
    bool isDark,
    bool githubSignedIn,
    bool copilotSignedIn,
    String? selectedModelId,
  ) {
    final isCopilotAvailable = copilotSignedIn;
    final List<_ModelOption> models = [];
    
    if (isCopilotAvailable) {
      for (final model in chatState.models) {
        final id = model['id'] as String?;
        final name = model['name'] as String?;
        if (id == null || name == null) continue;
        final rateLabel = _formatCopilotRate(model);
        final detailParts = <String>[
          if (rateLabel != null && rateLabel.isNotEmpty) rateLabel,
        ];
        models.add(_ModelOption(
          id: id,
          name: name,
          provider: 'GitHub Copilot',
          rateLabel: detailParts.isEmpty ? null : detailParts.join(' | '),
          icon: SvgPicture.asset(
            'assets/icons/github-copilot-icon.svg',
            height: 14,
            width: 14,
            colorFilter: ColorFilter.mode(Colors.green, BlendMode.srcIn),
          ),
          isCopilot: true,
        ));
      }
    }
    
    for (final entry in aiState.config.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final config = entry.value as Map<String, dynamic>;
      final provider = (config['apiProvider'] ?? config['provider'] ?? '').toString();
      final isLocalLlama = provider == 'LocalLlama';
      final modelName = (isLocalLlama
          ? (config['modelName'] ?? config['model'] ?? entry.key)
          : (config['model'] ?? entry.key)).toString();

      Widget icon;
      if (isLocalLlama) {
        icon = BlocBuilder<LocalLlamaBloc, LocalLlamaState>(
          builder: (context, llamaState) {
            final isLoaded = llamaState.loadedModelPath == (config['modelPath'] ?? '').toString();
            return Icon(
              Icons.memory,
              size: 14,
              color: isLoaded ? Colors.teal : Colors.grey,
            );
          },
        );
      } else {
        icon = _getProviderIcon(provider, textColor);
      }

      models.add(_ModelOption(
        id: entry.key,
        name: modelName,
        provider: isLocalLlama ? 'On-device' : (provider != 'Unknown' ? provider : null),
        icon: icon,
        isCopilot: false,
      ));
    }

    final uniqueModels = <_ModelOption>[];
    final seenIds = <String>{};
    for (final model in models) {
      if (seenIds.add(model.id)) uniqueModels.add(model);
    }

    if (uniqueModels.isEmpty) return const SizedBox.shrink();
    
    final currentModelId = selectedModelId != null && models.any((m) => m.id == selectedModelId)
      ? selectedModelId
      : models.first.id;

    Map<String, dynamic>? currentProviderConfig;
    if (aiState.config.containsKey(currentModelId)) {
      final raw = aiState.config[currentModelId];
      if (raw is Map) currentProviderConfig = Map<String, dynamic>.from(raw);
    }

    final currentApiKeys = (currentProviderConfig?['apiKeys'] as List?)
        ?.whereType<Map>()
        .map((k) => Map<String, dynamic>.from(k))
        .where((k) => (k['key'] ?? k['apiKey'])?.toString().trim().isNotEmpty == true)
        .toList() ?? [];

    final activeKeyId = currentProviderConfig?['activeKeyId']?.toString();
    final activeKeyLabel = currentApiKeys.isNotEmpty
        ? (currentApiKeys.firstWhere((k) => k['id'] == activeKeyId, orElse: () => currentApiKeys.first)['label'] ?? 'Clé 1')
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentModelId,
                isDense: true,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor.withAlpha(180), size: 20),
                dropdownColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
                style: TextStyle(color: textColor, fontSize: 13),
                items: models.map((model) {
                  final isCurrent = model.id == currentModelId;
                  return DropdownMenuItem<String>(
                    value: model.id,
                    child: Row(
                      children: [
                        model.icon,
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            model.name,
                            style: TextStyle(
                              color: isCurrent ? const Color(0xFF4CAF50) : textColor,
                              fontSize: 13,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (model.provider != null && !model.isCopilot) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${model.provider})',
                            style: TextStyle(color: textColor.withAlpha(100), fontSize: 11),
                          ),
                        ],
                        if (model.rateLabel != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            model.rateLabel!,
                            style: TextStyle(
                              color: textColor.withAlpha(150),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_rounded, size: 16, color: Color(0xFF4CAF50)),
                        ],
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (modelId) {
                  if (modelId == null) return;
                  _updateBlocState(selectedModelId: modelId);
                  final currentModelSelected = Map<String, dynamic>.from(aiState.modelSelected);
                  currentModelSelected['chat'] = modelId;
                  context.read<AIBloc>().add(ModelSelectEvent(currentModelSelected));
                },
              ),
            ),
          ),
        ),
        if (currentApiKeys.length > 1) ...[
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: 'Changer de clé API',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            color: isDark ? const Color(0xff2d2d2d) : Colors.white,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.vpn_key_rounded, size: 12, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Text(
                    activeKeyLabel.toString(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4CAF50)),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF4CAF50)),
                ],
              ),
            ),
            itemBuilder: (ctx) {
              return currentApiKeys.map((kMap) {
                final kId = kMap['id']?.toString() ?? '';
                final kLabel = (kMap['label'] ?? 'Clé').toString();
                final isSelectedKey = kId == activeKeyId;
                return PopupMenuItem<String>(
                  value: kId,
                  height: 36,
                  child: Row(
                    children: [
                      Icon(
                        isSelectedKey ? Icons.vpn_key_rounded : Icons.vpn_key_outlined,
                        size: 14,
                        color: isSelectedKey ? const Color(0xFF4CAF50) : textColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          kLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelectedKey ? FontWeight.w600 : FontWeight.normal,
                            color: isSelectedKey ? const Color(0xFF4CAF50) : textColor,
                          ),
                        ),
                      ),
                      if (isSelectedKey)
                        const Icon(Icons.check_rounded, size: 14, color: Color(0xFF4CAF50)),
                    ],
                  ),
                );
              }).toList();
            },
            onSelected: (selectedKeyId) {
              final aiBloc = context.read<AIBloc>();
              final updatedConfig = Map<String, dynamic>.from(aiBloc.state.config);
              final cfg = updatedConfig[currentModelId] is Map
                  ? Map<String, dynamic>.from(updatedConfig[currentModelId] as Map)
                  : <String, dynamic>{};

              final List<Map<String, dynamic>> keys = (cfg['apiKeys'] as List?)
                  ?.whereType<Map>()
                  .map((k) => Map<String, dynamic>.from(k))
                  .toList() ?? [];

              final kIdx = keys.indexWhere((k) => k['id'] == selectedKeyId);

              cfg['activeKeyId'] = selectedKeyId;
              if (kIdx >= 0) {
                cfg['activeKeyIndex'] = kIdx;
                final keyVal = (keys[kIdx]['key'] ?? keys[kIdx]['apiKey'])?.toString() ?? '';
                if (keyVal.isNotEmpty) {
                  cfg['apiKey'] = keyVal;
                  cfg['key'] = keyVal;
                }
              }

              updatedConfig[currentModelId] = cfg;
              aiBloc.add(AIConfigEvent(updatedConfig));
            },
          ),
        ],
      ],
    );
  }

  Widget _getProviderIcon(String provider, Color textColor) {
    IconData iconData;
    Color color;
    
    switch (provider.toLowerCase()) {
      case 'openai':
        iconData = Icons.auto_awesome;
        color = Colors.green;
        break;
      case 'google':
      case 'gemini':
        iconData = Icons.auto_awesome;
        color = Colors.blue;
        break;
      case 'anthropic':
      case 'claude':
        iconData = Icons.psychology;
        color = Colors.orange;
        break;
      case 'openrouter':
        iconData = Icons.route;
        color = Colors.purple;
        break;
      default:
        iconData = Icons.smart_toy_outlined;
        color = textColor.withAlpha(150);
    }
    
    return Icon(iconData, size: 14, color: color);
  }

  String _decodeBase64(String encoded, {String fallback = ''}) {
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return fallback;
    }
  }

  String _stripToolUiMarkers(String input) {
    final lines = input.split('\n');
    final clean = <String>[];
    var insideThinkingBlock = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == _thinkingStartMarker) {
        insideThinkingBlock = true;
        continue;
      }
      if (trimmed == _thinkingEndMarker) {
        insideThinkingBlock = false;
        continue;
      }
      if (insideThinkingBlock) {
        continue;
      }
      if (_toolEditPattern.hasMatch(trimmed) ||
          _toolTerminalPattern.hasMatch(trimmed) ||
          _toolStatusPattern.hasMatch(trimmed)) {
        continue;
      }
      clean.add(line);
    }
    return clean.join('\n').trim();
  }

  Widget _buildToolStatusIndicator(String status, AppTheme appTheme) {
    final baseColor = appTheme.selectScreenCardTextColor.withAlpha(135);
    final glowColor = appTheme.selectScreenCardTextColor.withAlpha(230);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: AnimatedBuilder(
        animation: _statusPulseController,
        builder: (context, child) {
          final t = _statusPulseController.value;
          final center = -0.9 + (t * 2.8);

          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              return LinearGradient(
                colors: [baseColor, glowColor, baseColor],
                stops: const [0.2, 0.5, 0.8],
                begin: Alignment(center - 1.0, 0),
                end: Alignment(center + 1.0, 0),
              ).createShader(rect);
            },
            child: child,
          );
        },
        child: Text(
          status,
          style: TextStyle(
            color: baseColor,
            fontStyle: FontStyle.italic,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildToolEditSummary(String filePath, int added, int removed, AppTheme appTheme) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? Colors.white.withAlpha(15)
          : Colors.black.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              path.basename(filePath),
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+$added',
            style: const TextStyle(
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '-$removed',
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolTerminal(
    String command,
    AppTheme appTheme,
    int markerIndex, {
    String? stdout,
    String? stderr,
    String? exitCode,
  }) {
    final hasCapturedOutput =
      (stdout != null && stdout.isNotEmpty) ||
      (stderr != null && stderr.isNotEmpty) ||
      (exitCode != null && exitCode.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? Colors.white.withAlpha(10)
          : Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            command,
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor,
              fontFamily: 'monospace',
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          if (hasCapturedOutput)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: appTheme.isDark
                  ? Colors.black.withAlpha(80)
                  : Colors.white.withAlpha(180),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withAlpha(70)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  [
                    if (stdout != null && stdout.isNotEmpty) stdout,
                    if (stderr != null && stderr.isNotEmpty)
                      '[stderr]\n$stderr',
                    if (exitCode != null && exitCode.isNotEmpty)
                      '[Process exited: $exitCode]',
                  ].join('\n'),
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 170,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: EmbeddedTerminal(
                  key: ValueKey('tool-terminal-$markerIndex-$command'),
                  projectDir: widget.workspacePath,
                  args: ['-c', command],
                  showKeyboardMenu: false,
                  readOnly: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThinkingPanel(String thinkingText, AppTheme appTheme) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? Colors.white.withAlpha(8)
          : Colors.black.withAlpha(6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(70)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          dense: true,
          title: Text(
            'Thinking',
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor.withAlpha(180),
              fontStyle: FontStyle.italic,
              fontSize: 12.5,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                thinkingText.trim(),
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor.withAlpha(190),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantResponseContent(
    String response,
    MarkdownConfig config,
    AppTheme appTheme,
  ) {
    final lines = response.split('\n');
    final widgets = <Widget>[];
    final markdownBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    var markerIndex = 0;
    var insideThinkingBlock = false;

    void flushMarkdown() {
      final content = markdownBuffer.toString().trim();
      if (content.isNotEmpty) {
        widgets.add(
          MarkdownBlock(
            data: content,
            config: config,
          ),
        );
      }
      markdownBuffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed == _thinkingStartMarker) {
        flushMarkdown();
        insideThinkingBlock = true;
        thinkingBuffer.clear();
        continue;
      }

      if (trimmed == _thinkingEndMarker) {
        if (insideThinkingBlock) {
          final thinkingText = thinkingBuffer.toString().trim();
          if (thinkingText.isNotEmpty) {
            widgets.add(_buildThinkingPanel(thinkingText, appTheme));
          }
          thinkingBuffer.clear();
          insideThinkingBlock = false;
        }
        continue;
      }

      if (insideThinkingBlock) {
        thinkingBuffer.writeln(line);
        continue;
      }

      final editMatch = _toolEditPattern.firstMatch(trimmed);
      if (editMatch != null) {
        flushMarkdown();
        final filePath = _decodeBase64(editMatch.group(1)!, fallback: 'unknown');
        final added = int.tryParse(editMatch.group(2) ?? '0') ?? 0;
        final removed = int.tryParse(editMatch.group(3) ?? '0') ?? 0;
        widgets.add(_buildToolEditSummary(filePath, added, removed, appTheme));
        markerIndex++;
        continue;
      }

      final statusMatch = _toolStatusPattern.firstMatch(trimmed);
      if (statusMatch != null) {
        flushMarkdown();
        final status = statusMatch.group(1)?.trim() ?? '';
        if (status.isNotEmpty) {
          widgets.add(_buildToolStatusIndicator(status, appTheme));
        }
        continue;
      }

      final terminalMatch = _toolTerminalPattern.firstMatch(trimmed);
      if (terminalMatch != null) {
        flushMarkdown();
        final terminalPayload = _decodeBase64(terminalMatch.group(1)!, fallback: '');
        var command = terminalPayload;
        String? stdout;
        String? stderr;
        String? exitCode;

        try {
          final decoded = jsonDecode(terminalPayload);
          if (decoded is Map<String, dynamic>) {
            command = decoded['command']?.toString() ?? '';
            stdout = decoded['stdout']?.toString();
            stderr = decoded['stderr']?.toString();
            exitCode = decoded['exitCode']?.toString();
          }
        } catch (_) {}

        if (command.isNotEmpty) {
          widgets.add(
            _buildToolTerminal(
              command,
              appTheme,
              markerIndex,
              stdout: stdout,
              stderr: stderr,
              exitCode: exitCode,
            ),
          );
          markerIndex++;
        }
        continue;
      }

      markdownBuffer.writeln(line);
    }

    flushMarkdown();
    if (insideThinkingBlock) {
      final thinkingText = thinkingBuffer.toString().trim();
      if (thinkingText.isNotEmpty) {
        widgets.add(_buildThinkingPanel(thinkingText, appTheme));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Map<String, dynamic>> _buildChatHistory(List<AIConversation> conversations) {
    final List<Map<String, dynamic>> history = [];
    for (final conv in conversations) {
      history.add({"role": "user", "content": conv.userRequest});
      if (conv.modelResponse != null && conv.modelResponse!.isNotEmpty) {
        final response = _stripToolUiMarkers(conv.modelResponse!);
        if (response.isNotEmpty) {
          history.add({"role": "assistant", "content": response});
        }
      }
    }
    return history;
  }
  
  List<Map<String, dynamic>> _buildGeminiHistory(List<AIConversation> conversations) {
    final List<Map<String, dynamic>> history = [];
    for (final conv in conversations) {
      history.add({
        "role": "user",
        "parts": [{"text": conv.userRequest}]
      });
      if (conv.modelResponse != null && conv.modelResponse!.isNotEmpty) {
        final response = _stripToolUiMarkers(conv.modelResponse!);
        if (response.isEmpty) {
          continue;
        }
        history.add({
          "role": "model",
          "parts": [{"text": response}]
        });
      }
    }
    return history;
  }

  String _toolEditMarker(String filePath, int added, int removed) {
    final fileEncoded = base64Encode(utf8.encode(filePath));
    return '[[PANDA_EDIT:$fileEncoded|$added|$removed]]\n';
  }

  String _toolTerminalMarker(
    String command, {
    String? stdout,
    String? stderr,
    String? exitCode,
  }) {
    final payload = jsonEncode({
      'command': command,
      'stdout': stdout ?? '',
      'stderr': stderr ?? '',
      'exitCode': exitCode,
    });
    final encoded = base64Encode(utf8.encode(payload));
    return '[[PANDA_TERMINAL:$encoded]]\n';
  }

  String _toolStatusMarker(String status) {
    return '[[PANDA_STATUS:$status]]\n';
  }

  String _toolStatusForFunction(String functionName) {
    const analyzingTools = {
      'activeEditorFile',
      'currentlySelectedText',
      'getLspDiagnostics',
      'readFile',
      'listFiles',
      'readFilesBatch',
      'globSearchFiles',
      'searchInFiles',
      'grepInFiles',
      'getPendingEditsForFile',
      'getFileInfo',
      'gitStatus',
      'gitDiff',
      'gitLog',
      'searchInWeb',
      'openLinks',
    };

    const patchTools = {
      'writeFile',
      'deleteFile',
      'renamePath',
      'rename',
      'insertAtLine',
      'replaceAllInFile',
      'editFile',
    };

    if (analyzingTools.contains(functionName)) {
      return 'Analyzing';
    }
    if (patchTools.contains(functionName)) {
      return 'Generating patch';
    }
    return 'Processing';
  }

  String _shellCommandPreview(String command, List<String> args) {
    final parts = [command, ...args].map(_shellEscape).toList();
    return parts.join(' ');
  }

  String _shellEscape(String value) {
    if (value.isEmpty) return "''";
    final safePattern = RegExp(r'^[A-Za-z0-9_./:-]+$');
    if (safePattern.hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  Future<String> _executeExternalToolCall({
    required AgenticTools tools,
    required String functionName,
    required Map<String, dynamic> args,
    required void Function(String) pushPartial,
  }) async {
    try {
      switch (functionName) {
        case 'activeEditorFile':
          final res = await tools.activeEditorFile();
          return res.success
            ? (res.data ?? 'No active file')
            : (res.error ?? 'Error getting active file');
        case 'currentlySelectedText':
          final res = await tools.currentlySelectedText();
          return res.success
            ? 'Start Line: ${res.data?['startLine'] ?? 'Unknown'}, End Line: ${res.data?['endLine'] ?? 'Unknown'}, Text: ${res.data?['selectedText'] ?? ''}'
            : (res.error ?? 'Error getting selected text');
        case 'getLspDiagnostics':
          final res = await tools.getLspDiagnostics(args['filePath']);
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error getting LSP diagnostics');
        case 'readFile':
          final res = await tools.readFile(
            args['filePath'],
            args['startLine'],
            args['endLine'],
          );
          return res.success
            ? (res.data ?? 'No content')
            : (res.error ?? 'Error reading file');
        case 'writeFile':
          String? previousContent;
          final previousRead = await tools.readFile(args['filePath']);
          if (previousRead.success) {
            previousContent = previousRead.data;
          }
          final res = await tools.writeFile(
            args['filePath'],
            args['content'],
          );
          if (res.success) {
            final added = _lineCount(args['content']?.toString());
            final removed = _lineCount(previousContent);
            pushPartial(_toolStatusMarker('Generating patch (+$added/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                removed,
              ),
            );
          }
          return res.success
            ? 'File written successfully'
            : (res.error ?? 'Error writing file');
        case 'deleteFile':
          final previousRead = await tools.readFile(args['filePath']);
          final res = await tools.deleteFile(args['filePath']);
          if (res.success) {
            final removed = _lineCount(previousRead.data);
            pushPartial(_toolStatusMarker('Generating patch (+0/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                0,
                removed,
              ),
            );
          }
          return res.success
            ? 'File deleted successfully'
            : (res.error ?? 'Error deleting file');
        case 'renamePath':
          final res = await tools.renamePath(
            args['oldPath'],
            args['newPath'],
          );
          return res.success
            ? 'Path renamed successfully'
            : (res.error ?? 'Error renaming path');
        case 'rename':
          final res = await tools.rename(
            args['oldPath'],
            args['newPath'],
          );
          return res.success
            ? 'Path renamed successfully'
            : (res.error ?? 'Error renaming path');
        case 'insertAtLine':
          final res = await tools.insertAtLine(
            args['filePath'],
            args['line'],
            args['text'],
            position: args['position'] ?? 'before',
          );
          if (res.success) {
            final added = _lineCount(args['text']?.toString());
            pushPartial(_toolStatusMarker('Generating patch (+$added/-0)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                0,
              ),
            );
          }
          return res.success
            ? 'Text inserted successfully'
            : (res.error ?? 'Error inserting text');
        case 'replaceAllInFile':
          final res = await tools.replaceAllInFile(
            args['filePath'],
            args['oldText'],
            args['newText'],
            useRegex: args['useRegex'] ?? false,
            maxReplacements: args['maxReplacements'],
            caseSensitive: args['caseSensitive'] ?? true,
          );
          if (res.success) {
            final added = _lineCount(args['newText']?.toString());
            final removed = _lineCount(args['oldText']?.toString());
            pushPartial(_toolStatusMarker('Generating patch (+$added/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                removed,
              ),
            );
          }
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error replacing text');
        case 'listFiles':
          final res = await tools.listFiles(
            args['directoryPath'],
            pattern: args['pattern'],
            recursive: args['recursive'] ?? false,
          );
          return res.success
            ? (res.data?.join('\n') ?? 'No files')
            : (res.error ?? 'Error listing files');
        case 'readFilesBatch':
          final parsedFiles = (args['files'] as List?) ?? const [];
          final res = await tools.readFilesBatch(parsedFiles);
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error reading files batch');
        case 'globSearchFiles':
          final parsedExcludePatterns = (args['excludePatterns'] as List?)?.map((item) => item.toString()).toList();
          final res = await tools.globSearchFiles(
            args['pattern'],
            directoryPath: args['directoryPath'] ?? '.',
            excludePatterns: parsedExcludePatterns,
            recursive: args['recursive'] ?? true,
            maxResults: args['maxResults'],
          );
          return res.success
            ? (res.data?.join('\n') ?? 'No matches')
            : (res.error ?? 'Error searching files by glob');
        case 'searchInFiles':
          final res = await tools.searchInFiles(
            args['query'],
            filePattern: args['filePattern'],
            caseSensitive: args['caseSensitive'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            useRegex: args['useRegex'] ?? false,
          );
          return res.success
            ? (res.data?.map((s) => '${s.filePath}:${s.lineNumber}: ${s.lineContent}').join('\n') ?? 'No results')
            : (res.error ?? 'Error searching files');
        case 'grepInFiles':
          final res = await tools.grepInFiles(
            args['query'],
            filePattern: args['filePattern'],
            caseSensitive: args['caseSensitive'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            useRegex: args['useRegex'] ?? false,
            before: args['before'] ?? 2,
            after: args['after'] ?? 2,
            maxResults: args['maxResults'],
          );
          return res.success
            ? (res.data?.map((r) => r.toString()).join('\n') ?? 'No results')
            : (res.error ?? 'Error grepping files');
        case 'editFile':
          final res = await tools.editFile(
            args['filePath'],
            args['oldText'],
            args['newText'],
          );
          if (res.success) {
            final added = _lineCount(args['newText']?.toString());
            final removed = _lineCount(args['oldText']?.toString());
            pushPartial(_toolStatusMarker('Generating patch (+$added/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                removed,
              ),
            );
          }
          return res.success
            ? 'File edited successfully'
            : (res.error ?? 'Error editing file');
        case 'getPendingEditsForFile':
          final res = await tools.getPendingEditsForFile(args['filePath']);
          return res.success
            ? (res.data == null ? 'No pending edits' : jsonEncode(res.data!.toJson()))
            : (res.error ?? 'Error getting pending edits');
        case 'getFileInfo':
          final res = await tools.getFileInfo(args['filePath']);
          return res.success
            ? 'Path: ${res.data?.path ?? 'Unknown'}, Size: ${res.data?.size ?? 0}, Modified: ${res.data?.modified ?? 'Unknown'}, IsDirectory: ${res.data?.isDirectory ?? false}'
            : (res.error ?? 'Error getting file info');
        case 'openLinks':
          final res = await tools.openLinks(args['url']);
          return res.success
            ? (res.data?.toString() ?? 'No content')
            : (res.error ?? 'Error fetching web page');
        case 'searchInWeb':
          final res = await tools.searchInWeb(args['searchQuery']);
          return res.success
            ? (res.data?.map((w) => '${w.title}\n${w.url}\n${w.snippet}').join('\n---\n') ?? 'No results')
            : (res.error ?? 'Error searching web');
        case 'runShellCommand':
          final parsedArgs = (args['args'] as List?)?.map((item) => item.toString()).toList() ?? <String>[];
          final parsedEnvs = (args['envs'] as Map?)?.map((key, value) => MapEntry(key.toString(), value.toString())) ?? <String, String>{};
          final preview = _shellCommandPreview(
            args['command']?.toString() ?? '',
            parsedArgs,
          );
          final res = await tools.runShellCommand(
            args['command'],
            parsedArgs,
            parsedEnvs,
          );
          if (res.success) {
            final data = res.data ?? const <String, String>{};
            pushPartial(
              _toolTerminalMarker(
                preview,
                stdout: data['stdout'] ?? '',
                stderr: data['stderr'] ?? '',
                exitCode: data['exitCode'],
              ),
            );
          } else {
            pushPartial(
              _toolTerminalMarker(
                preview,
                stderr: res.error ?? 'Error running shell command',
                exitCode: 'error',
              ),
            );
          }
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error running shell command');
        case 'gitStatus':
          final res = await tools.gitStatus();
          return res.success
            ? jsonEncode(res.data?.toJson())
            : (res.error ?? 'Error getting git status');
        case 'gitDiff':
          final res = await tools.gitDiff(
            filePath: args['filePath'],
            staged: args['staged'] ?? false,
            contextLines: args['contextLines'] ?? 3,
          );
          return res.success
            ? (res.data ?? '')
            : (res.error ?? 'Error getting git diff');
        case 'gitLog':
          final res = await tools.gitLog(
            limit: args['limit'] ?? 20,
            filePath: args['filePath'],
          );
          return res.success
              ? jsonEncode(res.data?.map((c) => c.toJson()).toList() ?? [])
              : (res.error ?? 'Error getting git log');
        default:
          return 'Unknown tool: $functionName';
      }
    } catch (e) {
      return 'Error executing tool $functionName: $e';
    }
  }

  Future<String> _sendExternalToolCallingPrompt({
    required Models chatModel,
    required List<AIConversation> history,
    required String prompt,
    required ChatMode chatMode,
    required void Function(String) pushPartial,
  }) async {
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final availableTools = chatMode == ChatMode.agent
      ? tools.getTools()
      : tools.getTools(readAccessOnly: true);

    final conversationMessages = _buildChatHistory(history);
    if (chatMode == ChatMode.agent) {
      conversationMessages.insert(0, {
        'role': 'system',
        'content': 'You are running in Panda IDE with workspace tool access. Use available tools to inspect, edit, and run commands when asked for code changes. Do not claim missing permissions unless a tool call fails with an explicit permission error.',
      });
    }
    conversationMessages.add({'role': 'user', 'content': prompt});

    _currentClient = http.Client();
    final streamedOutput = StringBuffer();

    void appendOutput(String text) {
      if (text.isEmpty) return;
      streamedOutput.write(text);
      pushPartial(text);
    }

    try {
      var loop = 0;
      while (loop < 8) {
        loop++;
        final requestBody = chatModel.buildToolCallingRequest(
          messages: conversationMessages,
          tools: availableTools,
          stream: false,
        );

        final response = await _currentClient!.post(
          Uri.parse(chatModel.chatUrl),
          headers: chatModel.headers,
          body: jsonEncode(requestBody),
        );

        if (response.statusCode != 200) {
          throw Exception(
            'Request failed with status ${response.statusCode}: ${response.body}',
          );
        }

        final decoded = jsonDecode(response.body);
        final assistantText = chatModel.parseChatMessage(decoded);
        final toolCalls = chatModel.parseToolCalls(decoded);

        conversationMessages.add({
          'role': 'assistant',
          'content': assistantText,
          if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
        });

        if (assistantText.isNotEmpty) {
          appendOutput(assistantText);
        }

        if (toolCalls.isEmpty) {
          final output = streamedOutput.toString();
          if (output.isNotEmpty) return output;
          return assistantText;
        }

        appendOutput(_toolStatusMarker('Processing'));

        final toolResults = <String>[];
        for (final call in toolCalls) {
          final callFunction = call['function'];
          if (callFunction is! Map) {
            toolResults.add('Malformed tool call without function payload');
            continue;
          }

          final function = Map<String, dynamic>.from(callFunction);
          final functionName = function['name']?.toString();
          if (functionName == null || functionName.isEmpty) {
            toolResults.add('Malformed tool call without function name');
            continue;
          }

          appendOutput(_toolStatusMarker(_toolStatusForFunction(functionName)));

          final rawArgs = function['arguments'];
          Map<String, dynamic> args = <String, dynamic>{};
          if (rawArgs is String && rawArgs.trim().isNotEmpty) {
            try {
              final parsed = jsonDecode(rawArgs);
              if (parsed is Map<String, dynamic>) {
                args = parsed;
              } else if (parsed is Map) {
                args = Map<String, dynamic>.from(parsed);
              }
            } catch (_) {}
          } else if (rawArgs is Map<String, dynamic>) {
            args = rawArgs;
          } else if (rawArgs is Map) {
            args = Map<String, dynamic>.from(rawArgs);
          }

          final result = await _executeExternalToolCall(
            tools: tools,
            functionName: functionName,
            args: args,
            pushPartial: appendOutput,
          );
          toolResults.add(result);
        }

        conversationMessages.addAll(
          chatModel.buildToolResultMessages(toolCalls, toolResults),
        );
      }

      throw Exception('Tool loop exceeded maximum iterations');
    } finally {
      _currentClient?.close();
      _currentClient = null;
    }
  }
  
  String? _parseStreamChunk(String chunk, Models chatModel) {
    final buffer = StringBuffer();
    
    switch (chatModel) {
      case Gemini():
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6).trim();
            if (data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final text = json["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
              if (text != null) buffer.write(text);
            } catch (_) {}
          } else if (trimmed.isNotEmpty && !trimmed.startsWith(':')) {
            try {
              final json = jsonDecode(trimmed);
              if (json is List && json.isNotEmpty) {
                for (final item in json) {
                  final text = item["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
                  if (text != null) buffer.write(text);
                }
              } else if (json is Map) {
                final text = json["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
                if (text != null) buffer.write(text);
              }
            } catch (_) {}
          } else {
            buffer.write(chunk);
          }
        }
        
      case Claude():
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]' || data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final type = json["type"];
              if (type == "content_block_delta") {
                final text = json["delta"]?["text"];
                if (text != null) buffer.write(text);
              }
            } catch (e) {
              buffer.write(e.toString());
            }
          }
        }
        
      case OpenAI():
      case Copilot():
      case Grok():
      case Groq():
      case DeepSeek():
      case Mistral():
      case TogetherAi():
      case Perplexity():
      case OpenRouter():
      case FireWorks():
      case PandaGateway():
      case CustomModel():
      case Cohere():
      case Cerebras():
      case Novita():
      case Hyperbolic():
      case SambaNova():
      case Qwen():
      case Ollama():
      case LmStudio():
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]' || data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final content = json["choices"]?[0]?["delta"]?["content"];
              if (content != null) buffer.write(content);
            } catch (_) {}
          }
        }
      
      case LocalLlama(): return '';
    }
    
    return buffer.isEmpty ? null : buffer.toString();
  }

  String _getStreamingUrl(Models chatModel) {
    switch (chatModel) {
      case Gemini():
        final uri = Uri.parse(chatModel.url);
        final newPath = uri.path.replaceFirst(':generateContent', ':streamGenerateContent');
        final newParams = Map<String, String>.from(uri.queryParameters);
        newParams['alt'] = 'sse';
        return uri.replace(path: newPath, queryParameters: newParams).toString();
      case OpenAI():
        return chatModel.chatUrl;
      case Claude():
        return chatModel.url; 
      default:
        return chatModel.url; 
    }
  }
  
  Map<String, dynamic> _buildRequestBody(Models chatModel, String prompt, List<AIConversation> history) {
    switch (chatModel) {
      case Gemini():
        final geminiHistory = _buildGeminiHistory(history);
        geminiHistory.add({
          "role": "user",
          "parts": [{"text": prompt}]
        });
        return {
          "contents": geminiHistory,
          "generationConfig": {
            "temperature": 1.0,
            "maxOutputTokens": 8192,
            "topP": 0.8,
            "topK": 10,
          },
        };
      case Claude():
        final messages = _buildChatHistory(history);
        messages.add({"role": "user", "content": prompt});
        return {
          "model": chatModel.model,
          "max_tokens": 4096,
          "stream": true,
          "messages": messages,
        };
      case OpenAI():
      case Copilot():
      case Grok():
      case Groq():
      case DeepSeek():
      case Mistral():
      case TogetherAi():
      case Perplexity():
      case OpenRouter():
      case FireWorks():
      case PandaGateway():
      case CustomModel():
      case Cohere():
      case Cerebras():
      case Novita():
      case Hyperbolic():
      case SambaNova():
      case Qwen():
      case Ollama():
      case LmStudio():
        final messages = _buildChatHistory(history);
        messages.add({"role": "user", "content": prompt});
        return {
          "model": chatModel.model,
          "stream": true,
          "messages": messages,
        };
      case LocalLlama(): return {};
    }
  }

  void _sendPrompt(Models chatModel, List<AIConversation> currentList, String? sessionId) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final chatSessionBloc = context.read<ChatSessionBloc>();
    final chatMode = mounted
      ? context.read<AIChatUIBloc>().state.chatMode
      : ChatMode.ask;
    final isFirstMessage = currentList.isEmpty;

    final newList = currentList.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
    newList.add(AIConversation(prompt, ""));
    
    chatSessionBloc.add(UpdateCurrentSession(conversations: newList));

    final int index = newList.length - 1;
    _promptController.clear();
    
    _updateBlocState(isGenerating: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    if (chatMode == ChatMode.agent && chatModel.supportsToolCalling) {
      try {
        final response = await _sendExternalToolCallingPrompt(
          chatModel: chatModel,
          history: currentList,
          prompt: prompt,
          chatMode: chatMode,
          pushPartial: (partial) {
            newList[index] = newList[index].copyWith(
              modelResponse: (newList[index].modelResponse ?? '') + partial,
            );
            chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
          },
        );

        final currentSession = chatSessionBloc.state.currentSession;
        if (currentSession != null) {
          final updated = currentSession.conversations
              .map((c) => AIConversation(c.userRequest, c.modelResponse))
              .toList();

          if (index < updated.length) {
            updated[index] = updated[index].copyWith(modelResponse: response);
            chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
          }
        }

        _updateBlocState(isGenerating: false);

        if (isFirstMessage && response.isNotEmpty) {
          _generateTitle(chatModel, prompt, response);
        }
      } catch (e, st) {
        _logChatError('sendPrompt.agenticExternal', e, st);
        final currentSession = chatSessionBloc.state.currentSession;
        if (currentSession != null) {
          final updated = currentSession.conversations
              .map((c) => AIConversation(c.userRequest, c.modelResponse))
              .toList();
          if (index < updated.length) {
            updated[index] = updated[index].copyWith(
              modelResponse: _userFacingChatErrorMessage(e),
            );
            chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
          }
        }
        _updateBlocState(isGenerating: false);
      }
      return;
    }

    final url = Uri.parse(_getStreamingUrl(chatModel));
    _currentClient = http.Client();
    final request = http.Request('POST', url);
    request.headers.addAll(chatModel.headers);
    
    final historyForRequest = currentList;
    request.body = jsonEncode(_buildRequestBody(chatModel, prompt, historyForRequest));

    try {
      final streamedResponse = await _currentClient!.send(request);
      final StringBuffer fullResponse = StringBuffer();
      
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        final parsed = _parseStreamChunk(chunk, chatModel);
        if (parsed != null) {
          fullResponse.write(parsed);
          
          final currentSession = chatSessionBloc.state.currentSession;
          if (currentSession != null) {
            final updated = currentSession.conversations
              .map((c) => AIConversation(c.userRequest, c.modelResponse))
              .toList();

            if (index < updated.length) {
              updated[index] = updated[index].copyWith(
                modelResponse: fullResponse.toString(),
              );
              chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
            }
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }

      if (fullResponse.isEmpty) {
        final fallbackClient = http.Client();
        try {
          final response = await fallbackClient.post(
            Uri.parse(chatModel.url),
            headers: chatModel.headers,
            body: jsonEncode(_buildRequestBody(chatModel, prompt, historyForRequest)..remove('stream')),
          );
          if (response.statusCode == 200) {
            final json = jsonDecode(response.body);
            final parsed = chatModel.responseParser(json);
            final currentSession = chatSessionBloc.state.currentSession;
            if (currentSession != null) {
              final updated = currentSession.conversations
                  .map((c) => AIConversation(c.userRequest, c.modelResponse))
                  .toList();
              if (index < updated.length) {
                updated[index] = updated[index].copyWith(modelResponse: parsed);
                chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
              }
            }
          }
        } finally {
          fallbackClient.close();
        }
      }
      
      _currentClient?.close();
      _currentClient = null;
      _updateBlocState(isGenerating: false);
      
      if (isFirstMessage && fullResponse.isNotEmpty) {
        _generateTitle(chatModel, prompt, fullResponse.toString());
      }
    } catch (e, st) {
      _logChatError('sendPrompt', e, st);
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: _userFacingChatErrorMessage(e),
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }
      }
      _currentClient?.close();
      _currentClient = null;
      _updateBlocState(isGenerating: false);
    }
  }

  Future<void> _generateTitle(Models chatModel, String userPrompt, String aiResponse) async {
    final chatSessionBloc = context.read<ChatSessionBloc>();
    final currentSession = chatSessionBloc.state.currentSession;
    if (currentSession == null) return;

    try {
      final titlePrompt = "Generate a short title (max 5 words) for this conversation. Only respond with the title, nothing else.\n\nUser: $userPrompt\n\nAssistant: ${aiResponse.substring(0, aiResponse.length > 200 ? 200 : aiResponse.length)}";
      
      final url = Uri.parse(chatModel.url);
      final titleRequest = http.Request('POST', url);
      titleRequest.headers.addAll(chatModel.headers);
      
      Map<String, dynamic> requestBody;
      switch (chatModel) {
        case Gemini():
          requestBody = {
            "contents": [
              {
                "parts": [{"text": titlePrompt}]
              }
            ],
            "generationConfig": {
              "temperature": 0.7,
              "maxOutputTokens": 50,
            },
          };
        default:
          requestBody = {
            "model": chatModel.model,
            "messages": [
              {"role": "user", "content": titlePrompt}
            ],
            "max_tokens": 50,
            "temperature": 0.7,
          };
      }
      
      titleRequest.body = jsonEncode(requestBody);
      
      final client = http.Client();
      final httpResponse = await client.post(url, headers: chatModel.headers, body: titleRequest.body);
      
      if (httpResponse.statusCode == 200) {
        final json = jsonDecode(httpResponse.body);
        try {
          String title = chatModel.responseParser(json);
          
          title = title.replaceAll('"', '').replaceAll('\n', ' ').replaceAll('*', '').trim();
          
          title = title.replaceFirst(RegExp(r'^(Title:|Topic:|Subject:)\s*', caseSensitive: false), '');
          if (title.length > 50) title = title.substring(0, 50);
          if (title.isNotEmpty && title.toLowerCase() != 'ai completion not available') {
            chatSessionBloc.add(UpdateSessionTitle(
              sessionId: currentSession.id,
              title: title,
            ));
          }
        } catch (e) {
          
          final fallbackTitle = userPrompt.split(' ').take(5).join(' ');
          chatSessionBloc.add(UpdateSessionTitle(
            sessionId: currentSession.id,
            title: fallbackTitle,
          ));
        }
      }
      client.close();
    } catch (e) {
      
      try {
        final fallbackTitle = userPrompt.split(' ').take(5).join(' ');
        chatSessionBloc.add(UpdateSessionTitle(
          sessionId: currentSession.id,
          title: fallbackTitle,
        ));
      } catch (_) {}
    }
  }

  void _sendCopilotChatPrompt(List<AIConversation> currentList, String? sessionId, String modelId, String workspacePath) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final copilotChatBloc = context.read<CopilotChatBloc>();
    final chatSessionBloc = context.read<ChatSessionBloc>();

    if (copilotChatBloc.chatClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copilot chat not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final newList = currentList.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
    newList.add(AIConversation(prompt, ""));
    
    chatSessionBloc.add(UpdateCurrentSession(conversations: newList));

    final int index = newList.length - 1;
    _promptController.clear();
    
    _updateBlocState(isGenerating: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      final messages = _buildChatHistory(currentList);
      final chatMode = mounted
          ? context.read<AIChatUIBloc>().state.chatMode
          : ChatMode.ask;
      if (chatMode == ChatMode.agent) {
        messages.insert(0, {
          'role': 'system',
          'content': 'You are running in Panda IDE with workspace tool access. Use available tools to inspect, edit, and run commands when asked for code changes. Do not claim missing permissions unless a tool call fails with an explicit permission error.',
        });
      }
      messages.add({'role': 'user', 'content': prompt});
      copilotChatBloc.chatClient!.agenticTools = AgenticTools(workspacePath: workspacePath, context: context);
      final response = await copilotChatBloc.chatClient!.chatWithModel(
        model: modelId,
        messages: messages,
        chatMode: chatMode,
        onPartial: (partial) {
          newList[index] = newList[index].copyWith(modelResponse: (newList[index].modelResponse ?? "") + partial);
          chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
        },
      );
      
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations
            .map((c) => AIConversation(c.userRequest, c.modelResponse))
            .toList();

        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: response,
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }

        if (index == 0 && response.isNotEmpty) {
          final fallbackTitle = prompt.split(' ').take(5).join(' ');
          chatSessionBloc.add(UpdateSessionTitle(
            sessionId: currentSession.id,
            title: fallbackTitle,
          ));
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
      
      _updateBlocState(isGenerating: false);
    } catch (e, st) {
      _logChatError('sendCopilotChatPrompt', e, st);
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations
            .map((c) => AIConversation(c.userRequest, c.modelResponse))
            .toList();
        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: _userFacingChatErrorMessage(e),
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }
      }
      
      _updateBlocState(isGenerating: false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendLocalLlamaPrompt(
    LocalLlama model,
    List<AIConversation> currentList,
    String? sessionId,
  ) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final llamaBloc = context.read<LocalLlamaBloc>();
    final chatSessionBloc = context.read<ChatSessionBloc>();
    final chatMode = mounted
      ? context.read<AIChatUIBloc>().state.chatMode
      : ChatMode.ask;
    final isFirstMessage = currentList.isEmpty;

    if (llamaBloc.state.loadedModelPath != model.modelPath || !llamaBloc.state.isReady) {
      llamaBloc.add(LocalLlamaLoadModel(model));
      await llamaBloc.stream.firstWhere(
        (s) => s.status == LocalLlamaStatus.ready || s.status == LocalLlamaStatus.error,
      );
      if (llamaBloc.state.status == LocalLlamaStatus.error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load model: ${llamaBloc.state.error}'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    final controller = llamaBloc.controller;
    if (controller == null) return;

    final newList = currentList.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
    newList.add(AIConversation(prompt, ''));
    chatSessionBloc.add(UpdateCurrentSession(conversations: newList));

    final int index = newList.length - 1;
    _promptController.clear();
    _updateBlocState(isGenerating: true);

    _scrollToBottom();

    try {
      final messages = _buildChatHistory(currentList).map((m) => ChatMessage(
        role: m['role'] as String,
        content: m['content'] as String,
      )).toList();

      if (chatMode == ChatMode.agent && mounted) {
        final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
        
        final toolList = tools.getTools()
          .map((tool) {
            final func = tool['function'];
            final name = func['name']?.toString() ?? '';
            final desc = func['description']?.toString() ?? '';
            return '- $name: $desc';
          })
          .join('\n');

        messages.insert(0, ChatMessage(
          role: 'system',
          content: '''You are a code completion agent in Panda IDE.

  When you need to use a tool, respond with a JSON block like:
  {"type": "tool_call", "function": "toolName", "arguments": {"key": "value"}}

  Available tools:
  $toolList

  After each tool call, I will provide the result. Continue with your response.
  Do not claim missing permissions unless a tool call fails explicitly.''',
        ));
      }

      messages.add(ChatMessage(role: 'user', content: prompt));

      final fullResponse = StringBuffer();
      var toolCallsParsed = <Map<String, dynamic>>[];

      try {
        final generateFuture = controller.generateChat(
          messages: messages,
          maxTokens: model.maxTokens,
          temperature: model.temperature,
          topP: model.topP,
          topK: model.topK,
          repeatPenalty: model.repeatPenalty,
          frequencyPenalty: model.frequencyPenalty,
          presencePenalty: model.presencePenalty,
          repeatLastN: model.repeatLastN,
          seed: model.seed,
          mirostat: model.mirostat,
          mirostatTau: model.mirostatTau,
          mirostatEta: model.mirostatEta,
        ).listen(
          (token) {
            fullResponse.write(token);
            newList[index] = newList[index].copyWith(
              modelResponse: fullResponse.toString(),
            );
            chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
            _scrollToBottom();
          },
          onError: (e) {
            debugPrint('[LocalLlama] Stream error: $e');
            final currentSession = chatSessionBloc.state.currentSession;
            if (currentSession != null) {
              final updated = currentSession.conversations
                .map((c) => AIConversation(c.userRequest, c.modelResponse))
                .toList();
              if (index < updated.length) {
                updated[index] = updated[index].copyWith(
                  modelResponse: _userFacingChatErrorMessage(e),
                );
                chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
              }
            }
          },
        ).asFuture();

        await generateFuture.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            throw TimeoutException('Local model generation timed out after 120s');
          },
        );
      } catch (e) {
        if (e is TimeoutException) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Generation timeout: ${e.message}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
        _logChatError('sendLocalLlama.generateChat', e, StackTrace.current);
        _updateBlocState(isGenerating: false);
        return;
      }

      if (chatMode == ChatMode.agent && fullResponse.isNotEmpty) {
        toolCallsParsed = _extractToolCallsFromPrompt(fullResponse.toString());

        if (toolCallsParsed.isNotEmpty && mounted) {
          final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
          var currentMessages = List<ChatMessage>.from(messages);
          currentMessages.add(ChatMessage(role: 'assistant', content: fullResponse.toString()));

          for (var turnIdx = 0; turnIdx < 3 && toolCallsParsed.isNotEmpty; turnIdx++) {
            final toolResults = <String>[];

            for (final call in toolCallsParsed) {
              final functionName = call['function']?.toString();
              final args = call['arguments'] as Map<String, dynamic>? ?? {};

              if (functionName != null && functionName.isNotEmpty) {
                try {
                  final result = await _executeExternalToolCall(
                    tools: tools,
                    functionName: functionName,
                    args: args,
                    pushPartial: (partial) {},
                  );
                  toolResults.add(result);
                } catch (e) {
                  toolResults.add('Error executing $functionName: $e');
                }
              }
            }

            currentMessages.add(ChatMessage(
              role: 'user',
              content: 'Tool results:\n${toolResults.join('\n')}\n\nContinue your response based on the tool results.',
            ));

            final nextTurnResponse = StringBuffer();
            try {
              final nextGenerateFuture = controller.generateChat(
                messages: currentMessages,
                maxTokens: model.maxTokens,
                temperature: model.temperature,
                topP: model.topP,
                topK: model.topK,
                repeatPenalty: model.repeatPenalty,
                frequencyPenalty: model.frequencyPenalty,
                presencePenalty: model.presencePenalty,
                repeatLastN: model.repeatLastN,
                seed: model.seed,
                mirostat: model.mirostat,
                mirostatTau: model.mirostatTau,
                mirostatEta: model.mirostatEta,
              ).listen(
                (token) {
                  nextTurnResponse.write(token);
                  fullResponse.write(token);
                  newList[index] = newList[index].copyWith(
                    modelResponse: fullResponse.toString(),
                  );
                  chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
                  _scrollToBottom();
                },
                onError: (e) {
                  debugPrint('[LocalLlama] Tool loop stream error: $e');
                },
              ).asFuture();

              await nextGenerateFuture.timeout(
                const Duration(seconds: 120),
                onTimeout: () {
                  throw TimeoutException('Tool loop generation timed out after 120s');
                },
              );
            } catch (e) {
              if (e is TimeoutException) {
                debugPrint('[LocalLlama] Tool turn timed out: ${e.message}');
              } else {
                debugPrint('[LocalLlama] Tool turn error: $e');
              }
              break;
            }

            currentMessages.add(ChatMessage(role: 'assistant', content: nextTurnResponse.toString()));

            toolCallsParsed = _extractToolCallsFromPrompt(nextTurnResponse.toString());

            if (toolCallsParsed.isEmpty) {
              break;
            }
          }
        }
      }

      _updateBlocState(isGenerating: false);

      if (isFirstMessage && fullResponse.isNotEmpty) {
        final currentSession = chatSessionBloc.state.currentSession;
        if (currentSession != null) {
          chatSessionBloc.add(UpdateSessionTitle(
            sessionId: currentSession.id,
            title: prompt.split(' ').take(5).join(' '),
          ));
        }
      }
    } catch (e, st) {
      _logChatError('sendLocalLlama', e, st);
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations
          .map((c) => AIConversation(c.userRequest, c.modelResponse))
          .toList();
        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: _userFacingChatErrorMessage(e),
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }
      }
      _updateBlocState(isGenerating: false);
    }
  }

  List<Map<String, dynamic>> _extractToolCallsFromPrompt(String response) {
    final calls = <Map<String, dynamic>>[];
    try {
      final pattern = RegExp(
        r'\{\s*"type"\s*:\s*"tool_call".*?\}',
        dotAll: true,
        multiLine: true,
      );
      
      for (final match in pattern.allMatches(response)) {
        try {
          final json = jsonDecode(match.group(0)!);
          if (json is Map && json['type'] == 'tool_call') {
            calls.add({
              'function': json['function'],
              'arguments': json['arguments'] ?? {},
            });
          }
        } catch (_) {}
      }
    } catch (_) {}
    return calls;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasPendingConversationEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasPendingConversationEdit) {
          _restorePendingConversationEdit();
        }
      },
      child: BlocBuilder<AIChatUIBloc, AIChatUIState>(
        builder: (context, aiChatUIState) {
          return BlocBuilder<AppThemeBloc, AppThemeState>(
            builder: (context, appThemeState) {
              return BlocBuilder<AIBloc, AIState>(
                builder: (context, aiState) {
                  final Models? chatModel = aiState.chatModel;
                  final bool externalModelConfigured = !(aiState.config.isEmpty || aiState.modelSelected.isEmpty);

                  return BlocBuilder<ChatSessionBloc, ChatSessionState>(
                    builder: (context, sessionState) {
                      final baseConversations = sessionState.currentSession?.conversations ?? [];
                      final conversations = _pendingEditedConversations ?? baseConversations;
                      final sessionTitle = sessionState.currentSession?.title ?? 'New Chat';
                      final textColor = appThemeState.appTheme.selectScreenCardTextColor;
                      final isDark = appThemeState.appTheme.isDark;
                      
                      return BlocBuilder<GithubAuthCubit, GithubAuthState>(
                        builder: (context, authState) {
                          final githubSignedIn = authState.isSignedIn;
                          final copilotSignedIn = context.watch<CopilotBloc>().state.isSignedIn || _copilotSignedInFromPrefs;
                          final bool copilotModelsAvailable = githubSignedIn || copilotSignedIn;
                          
                          if (!externalModelConfigured && !copilotModelsAvailable) {
                            return Center(
                              child: Text(
                                "Chat model is not configured. Either create a model in settings or sign in with GitHub Copilot.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                ),
                              ),
                            );
                          }
                          
                          return BlocBuilder<LocalLlamaBloc, LocalLlamaState>(
                            builder: (context, llamaState) {
                              return BlocBuilder<CopilotChatBloc, CopilotChatState>(
                                builder: (context, chatState) {
                                  _updatePendingPolling(aiChatUIState.isGenerating);
                                  final pendingCounts = _pendingDiffCounts(_pendingEdits);
    
                                  if ((githubSignedIn || copilotSignedIn) && !_requestedCopilotModelRefresh && !chatState.isFetchingModels) {
                                    _requestedCopilotModelRefresh = true;
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      context.read<CopilotChatBloc>().add(CopilotChatFetchModels(forceRefresh: true));
                                    });
                                  }
                                  
                                  return SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                            child: Column(
                                              children: [
                                                if (llamaState.isLoading)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 5.5),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.teal.withAlpha(30),
                                                      borderRadius: BorderRadius.circular(8)
                                                    ),
                                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                                    child: Row(
                                                      children: [
                                                        const SizedBox(
                                                          width: 14, height: 14,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.teal,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'Loading ${llamaState.loadedModelName ?? 'model'}…',
                                                          style: const TextStyle(
                                                            color: Colors.teal,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                Column(
                                                  spacing: 3.5,
                                                  children: [
                                                    _buildModelSelector(
                                                      context, 
                                                      aiState, 
                                                      chatState, 
                                                      textColor, 
                                                      isDark,
                                                      githubSignedIn,
                                                      copilotSignedIn,
                                                      aiChatUIState.selectedModelId,
                                                    ),
                                                    Row(
                                                      children: [
                                                        Expanded(child: _buildModeSelector(textColor, isDark, aiChatUIState.chatMode)),
                                                        IconButton(
                                                          onPressed: () => _showHistoryDialog(context, appThemeState.appTheme, sessionState),
                                                          icon: Icon(Icons.history, color: textColor.withAlpha(200), size: 20),
                                                          tooltip: 'Chat History',
                                                          visualDensity: VisualDensity.compact,
                                                        ),
                                                        IconButton(
                                                          onPressed: () => context.read<ChatSessionBloc>().add(CreateNewSession()),
                                                          icon: Icon(Icons.add_comment_outlined, color: textColor.withAlpha(200), size: 20),
                                                          tooltip: 'New Chat',
                                                          visualDensity: VisualDensity.compact,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        sessionTitle,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w500,
                                                          fontSize: 14,
                                                          color: textColor.withAlpha(180),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          TextField(
                                            controller: _promptController,
                                            cursorColor: appThemeState.appTheme.selectScreenCardTextColor,
                                            textAlignVertical: TextAlignVertical.top,
                                            style: TextStyle(
                                              color: appThemeState.appTheme.selectScreenCardTextColor,
                                            ),
                                            maxLines: null,
                                            decoration: InputDecoration(
                                              focusedBorder: const OutlineInputBorder(
                                                borderSide: BorderSide(color: Color(0xff0178b9)),
                                              ),
                                              suffix: IconButton(
                                                onPressed: aiChatUIState.isGenerating
                                                  ? _stopGeneration
                                                  : () async {
                                                      if (_hasPendingConversationEdit) {
                                                        final currentText = _promptController.text.trim();
                                                        final oldText = _pendingEditOriginalText?.trim() ?? '';
                                                        if (currentText == oldText) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            const SnackBar(
                                                              content: Text('Text must be different'),
                                                              backgroundColor: Colors.orange,
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                      }
    
                                                      final sendingConversations = _cloneConversations(conversations);
                                                      if (_hasPendingConversationEdit) {
                                                        setState(() {
                                                          _pendingEditBaseConversations = null;
                                                          _pendingEditedConversations = null;
                                                          _pendingEditOriginalText = null;
                                                        });
                                                      }
    
                                                      String selectedModelId = aiChatUIState.selectedModelId ?? '';
                                                      if (selectedModelId.isEmpty) {
                                                        selectedModelId = aiState.modelSelected['chat'] ?? '';
                                                      }
                                                      if (selectedModelId.isEmpty && aiState.config.isNotEmpty) {
                                                        selectedModelId = aiState.config.keys.first;
                                                      }
                                                      final selectedModelConfig = aiState.config[selectedModelId];
                                                      final isLocalModel = selectedModelConfig is Map &&
                                                          (selectedModelConfig['apiProvider'] ?? selectedModelConfig['provider']) == 'LocalLlama';
                                                      final isCopilotModel = chatState.models.any((model) => model['id'] == selectedModelId);

                                                      if (isLocalModel) {
                                                        final config = selectedModelConfig as Map<String, dynamic>;
                                                        final localModel = LocalLlama(
                                                          modelPath: config['modelPath'] ?? '',
                                                          displayName: config['modelName'] ?? config['model'] ?? 'Local Model',
                                                          threads: config['threads'] ?? 4,
                                                          contextSize: config['contextSize'] ?? 4096,
                                                          gpuLayers: config['gpuLayers'] ?? 0,
                                                        );
                                                        _sendLocalLlamaPrompt(localModel, sendingConversations, sessionState.currentSession?.id);
                                                      } else if (isCopilotModel) {
                                                        _sendCopilotChatPrompt(sendingConversations, sessionState.currentSession?.id, selectedModelId, widget.workspacePath);
                                                      } else if (chatModel != null) {
                                                        _sendPrompt(chatModel, sendingConversations, sessionState.currentSession?.id);
                                                      } else {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(content: Text('Chat model not available'), backgroundColor: Colors.orange),
                                                        );
                                                      }
    
                                                    },
                                                icon: Icon(
                                                  aiChatUIState.isGenerating ? Icons.stop_circle_outlined : Icons.send,
                                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                                ),
                                              ),
                                              contentPadding: EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              ),
                                              labelText: 'Ask AI',
                                              labelStyle: TextStyle(
                                                color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8, right: 2.5),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: languages.firstWhere(
                                                    (item) => item.extension.contains(
                                                      path.extension(widget.filePath).isNotEmpty ? path.extension(widget.filePath).substring(1) : '',
                                                    ),
                                                    orElse: () => languages.first,
                                                  ).icon,
                                                ),
                                                SizedBox(width: 3),
                                                Text(
                                                  path.basename(widget.filePath),
                                                  style: TextStyle(
                                                    color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                                  ),
                                                ),
                                                if (pendingCounts.added > 0 || pendingCounts.removed > 0) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '+${pendingCounts.added}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF2E7D32),
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '-${pendingCounts.removed}',
                                                    style: const TextStyle(
                                                      color: Color(0xFFC62828),
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: BlocBuilder<ConfigBloc, ConfigState>(
                                              builder: (context, configState) {
                                                final theme = getMergedHighlightThemes(configState.codeForgeConfig)[configState.codeForgeConfig['theme']] ?? atomOneDarkTheme;
                                                
                                                if (!_initialScrollDone && conversations.isNotEmpty) {
                                                  _initialScrollDone = true;
                                                  final savedOffset = aiChatUIState.scrollOffset;
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    if (_scrollController.hasClients) {
                                                      if (savedOffset < 0) {
                                                        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                                                      } else {
                                                        final clampedOffset = savedOffset.clamp(
                                                          _scrollController.position.minScrollExtent,
                                                          _scrollController.position.maxScrollExtent,
                                                        );
                                                        _scrollController.jumpTo(clampedOffset);
                                                      }
                                                    }
                                                  });
                                                }
                                                
                                                return ListView.builder(
                                                  controller: _scrollController,
                                                  itemCount: conversations.length,
                                                  itemBuilder: (context, index) {
                                                    final isDark = appThemeState.appTheme.isDark;
                                                    final fileExtension = path.extension(widget.filePath);
                                                    final extensionWithoutDot = fileExtension.startsWith('.')
                                                      ? fileExtension.substring(1)
                                                      : fileExtension;
                                                    final previewLanguage = languages.singleWhere(
                                                      (item) => extensionWithoutDot.isNotEmpty &&
                                                          item.extension.contains(extensionWithoutDot),
                                                      orElse: () => languages.first,
                                                    );
                                                    final config = isDark
                                                      ? MarkdownConfig.darkConfig.copy(
                                                          configs: [
                                                            PConfig(
                                                              textStyle: TextStyle(
                                                                color: appThemeState.appTheme.selectScreenCardTextColor,
                                                              ),
                                                            ),
                                                            PreConfig(
                                                              language: previewLanguage.name.toLowerCase(),
                                                              theme: theme,
                                                              styleNotMatched: TextStyle(
                                                                color: theme['root']!.color,
                                                                fontFamily: configState.codeForgeConfig['fontFamily'],
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: theme['root']!.backgroundColor
                                                              )
                                                            )
                                                          ],
                                                        )
                                                      : MarkdownConfig.defaultConfig;
                                                    final conv = conversations[index];
                                                    final hasResponse =
                                                      conv.modelResponse != null &&
                                                      conv.modelResponse!.isNotEmpty;
                                                    final isStreaming = conv.modelResponse != null && conv.modelResponse!.isEmpty;
                                                    return Padding(
                                                      padding: const EdgeInsets.only(top: 8),
                                                      child: Column(
                                                        children: [
                                                          Align(
                                                            alignment: Alignment.centerRight,
                                                            child: Padding(
                                                              padding: const EdgeInsets.symmetric(
                                                                vertical: 6.5,
                                                              ),
                                                              child: GestureDetector(
                                                                onLongPress: () => _showUserBubbleActions(
                                                                  index: index,
                                                                  conversation: conv,
                                                                  baseConversations: baseConversations,
                                                                  aiChatUIState: aiChatUIState,
                                                                  sessionState: sessionState,
                                                                  chatState: chatState,
                                                                  chatModel: chatModel,
                                                                  appTheme: appThemeState.appTheme,
                                                                ),
                                                                child: Container(
                                                                  padding: EdgeInsets.symmetric(
                                                                    vertical: 5,
                                                                    horizontal: 8,
                                                                  ),
                                                                  decoration: BoxDecoration(
                                                                    color: Colors.blueAccent.withAlpha(
                                                                      200,
                                                                    ),
                                                                    borderRadius: BorderRadius.only(
                                                                      topLeft: Radius.circular(16),
                                                                      topRight: Radius.zero,
                                                                      bottomLeft: Radius.circular(16),
                                                                      bottomRight: Radius.circular(16),
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    conv.userRequest,
                                                                    style: TextStyle(
                                                                      color: Colors.white,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Align(
                                                            alignment: Alignment.centerLeft,
                                                            child: hasResponse
                                                              ? _buildAssistantResponseContent(
                                                                  conv.modelResponse!,
                                                                  config,
                                                                  appThemeState.appTheme,
                                                                )
                                                              : isStreaming
                                                                ? Row(
                                                                    children: [
                                                                      SizedBox(
                                                                        width: 16,
                                                                        height: 16,
                                                                        child: CircularProgressIndicator(
                                                                          strokeWidth: 2,
                                                                          color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 8),
                                                                      Text(
                                                                        'Thinking...',
                                                                        style: TextStyle(
                                                                          color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                                                          fontStyle: FontStyle.italic,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  )
                                                                : const SizedBox.shrink(),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: _buildPendingDiffDrawerPanel(appThemeState.appTheme),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, AppTheme appTheme, ChatSessionState initialState) {
    showDialog(
      context: context,
      builder: (dialogContext) => BlocBuilder<ChatSessionBloc, ChatSessionState>(
        builder: (context, sessionState) {
          return AlertDialog(
            backgroundColor: appTheme.isDark ? const Color(0xff1e1e2e) : Colors.white,
            title: Row(
              children: [
                Icon(
                  Icons.history,
                  color: appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 12),
                Text(
                  'Chat History',
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: sessionState.sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: appTheme.selectScreenCardTextColor.withAlpha(100),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No chat history yet',
                          style: TextStyle(
                            color: appTheme.selectScreenCardTextColor.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: sessionState.sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessionState.sessions[index];
                      final isSelected = sessionState.currentSession?.id == session.id;
                      return Card(
                        color: isSelected
                          ? (appTheme.isDark ? const Color(0xff3d3d5c) : Colors.blue.withAlpha(30))
                          : (appTheme.isDark ? const Color(0xff2a2a3e) : Colors.grey.shade100),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            Icons.chat,
                            color: isSelected
                              ? Colors.blue
                              : appTheme.selectScreenCardTextColor.withAlpha(150),
                          ),
                          title: Text(
                            session.title,
                            style: TextStyle(
                              color: appTheme.selectScreenCardTextColor,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _formatDate(session.createdAt),
                            style: TextStyle(
                              color: appTheme.selectScreenCardTextColor.withAlpha(100),
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Colors.red.withAlpha(180),
                              size: 20,
                            ),
                            onPressed: () {
                              _showDeleteConfirmation(context, appTheme, session.id, session.title);
                            },
                          ),
                          onTap: () {
                            context.read<ChatSessionBloc>().add(SelectSession(session.id));
                            Navigator.of(dialogContext).pop();
                          },
                        ),
                      );
                    },
                  ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: appTheme.isDark ? Colors.blue.shade300 : Colors.blue,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppTheme appTheme, String sessionId, String sessionTitle) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: appTheme.isDark ? const Color(0xff1e1e2e) : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Chat',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this chat?',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appTheme.isDark 
                  ? Colors.white.withAlpha(10) 
                  : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat,
                    size: 20,
                    color: appTheme.selectScreenCardTextColor.withAlpha(150),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionTitle,
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor.withAlpha(150),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: appTheme.isDark ? Colors.white70 : Colors.grey.shade700,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatSessionBloc>().add(DeleteSession(sessionId));
              Navigator.of(dialogContext).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

const List<Color> _gitGraphColors = [
  Color(0xFF569CD6),
  Color(0xFFD7BA7D),
  Color(0xFFC586C0),
  Color(0xFF4EC9B0),
  Color(0xFFD16969),
  Color(0xFF6A9955),
  Color(0xFFCE9178),
  Color(0xFFB5CEA8),
  Color(0xFFDCDCAA),
  Color(0xFF4FC1FF),
];

Color _getGraphColor(int index) {
  return _gitGraphColors[index % _gitGraphColors.length];
}
