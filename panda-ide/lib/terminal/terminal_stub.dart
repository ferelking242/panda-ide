// ── Web terminal preview ─────────────────────────────────────────────────────
// The web build cannot spawn the native PTY. It still exposes a real text
// input, visible cursor and local echo so the terminal panel remains useful
// while developing or previewing Panda IDE in a browser.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/broken_icons.dart';

// ── SetupTerminal ─────────────────────────────────────────────────────────────
class SetupTerminal extends StatelessWidget {
  final String projectDir;
  final List<String> args;
  final bool useScaffold, showKeyboardMenu, readOnly;
  final int? sshId, termuxId;
  final String? commandToExecuteInSSH;
  final VoidCallback? onOpenInTab;

  const SetupTerminal({
    super.key,
    required this.projectDir,
    this.args = const [],
    this.useScaffold = true,
    this.showKeyboardMenu = true,
    this.readOnly = false,
    this.sshId,
    this.termuxId,
    this.commandToExecuteInSSH,
    this.onOpenInTab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmbeddedTerminal(
        projectDir: projectDir,
        args: args,
        showKeyboardMenu: showKeyboardMenu,
        readOnly: readOnly,
        onOpenInTab: onOpenInTab,
      ),
    );
  }
}

// ── EmbeddedTerminal ──────────────────────────────────────────────────────────
class EmbeddedTerminal extends StatefulWidget {
  final String projectDir;
  final List<String> args;
  final bool showKeyboardMenu, readOnly;
  final VoidCallback? onOpenInTab;

  const EmbeddedTerminal({
    super.key,
    required this.projectDir,
    this.args = const [],
    this.showKeyboardMenu = true,
    this.readOnly = false,
    this.onOpenInTab,
  });

  @override
  State<EmbeddedTerminal> createState() => _EmbeddedTerminalState();
}

class _EmbeddedTerminalState extends State<EmbeddedTerminal> {
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  final ScrollController _scrollController = ScrollController();
  final List<String> _lines = [
    'root@localhost:~#',
    'Panda IDE web preview — les commandes restent locales.',
    '',
  ];

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _inputFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.readOnly) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.readOnly) return;
    final command = _inputController.text.trim();
    if (command.isEmpty) return;
    setState(() {
      _lines
        ..add('root@localhost:~# $command')
        ..add('preview: commande non exécutée dans le navigateur')
        ..add('');
      _inputController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff101114),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              itemCount: _lines.length,
              itemBuilder: (_, index) => Text(
                _lines[index],
                style: const TextStyle(
                  color: Color(0xffd7dae0),
                  fontFamily: 'jetBrainsMonoNF',
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 5, 10, 8),
            decoration: const BoxDecoration(
              color: Color(0xff101114),
              border: Border(top: BorderSide(color: Color(0xff24262d))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'root@localhost:~#',
                  style: TextStyle(
                    color: Color(0xff8b93a7),
                    fontFamily: 'jetBrainsMonoNF',
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    readOnly: widget.readOnly,
                    autofocus: false,
                    showCursor: !widget.readOnly,
                    cursorColor: const Color(0xff9b8cff),
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(
                      color: Color(0xfff0f1f4),
                      fontFamily: 'jetBrainsMonoNF',
                      fontSize: 12.5,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Tapez une commande…',
                      hintStyle: TextStyle(
                        color: Color(0xff666b78),
                        fontFamily: 'jetBrainsMonoNF',
                        fontSize: 12.5,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Envoyer',
                  onPressed: widget.readOnly ? null : _submit,
                  icon: const Icon(Broken.send_2, size: 17),
                  color: const Color(0xff9b8cff),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TerminalSessionMeta ───────────────────────────────────────────────────────
class TerminalSessionMeta {
  final String id, title;
  final DateTime createdAt;
  final bool isRunning;

  const TerminalSessionMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.isRunning,
  });

  TerminalSessionMeta copyWith({String? title, bool? isRunning}) =>
      TerminalSessionMeta(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        isRunning: isRunning ?? this.isRunning,
      );
}

// ── Events ────────────────────────────────────────────────────────────────────
abstract class TerminalSessionEvent {}

class CreateTerminalSession extends TerminalSessionEvent {
  final String id, title;
  final bool makeActive, isRunning;
  CreateTerminalSession({
    required this.id,
    required this.title,
    required this.makeActive,
    required this.isRunning,
  });
}

class SetActiveTerminalSession extends TerminalSessionEvent {
  final String id;
  SetActiveTerminalSession(this.id);
}

class DeleteTerminalSession extends TerminalSessionEvent {
  final String id;
  DeleteTerminalSession(this.id);
}

class UpdateTerminalSessionStatus extends TerminalSessionEvent {
  final String id;
  final bool isRunning;
  UpdateTerminalSessionStatus({required this.id, required this.isRunning});
}

class UpdateTerminalFontSize extends TerminalSessionEvent {
  final double fontSize;
  UpdateTerminalFontSize({required this.fontSize});
}

// ── State ─────────────────────────────────────────────────────────────────────
class TerminalSessionState {
  final List<TerminalSessionMeta> sessions;
  final String? activeSessionId;
  double fontSize;

  TerminalSessionState({
    required this.sessions,
    required this.activeSessionId,
    this.fontSize = 13.0,
  });

  TerminalSessionState copyWith({
    List<TerminalSessionMeta>? sessions,
    String? activeSessionId,
    double? fontSize,
    bool clearActive = false,
  }) => TerminalSessionState(
    sessions: sessions ?? this.sessions,
    activeSessionId: clearActive
        ? null
        : activeSessionId ?? this.activeSessionId,
    fontSize: fontSize ?? this.fontSize,
  );
}

// ── Bloc ──────────────────────────────────────────────────────────────────────
class TerminalSessionBloc
    extends Bloc<TerminalSessionEvent, TerminalSessionState> {
  TerminalSessionBloc({double initialFontSize = 13})
    : super(
        TerminalSessionState(
          sessions: [],
          activeSessionId: null,
          fontSize: initialFontSize,
        ),
      ) {
    on<CreateTerminalSession>((e, emit) {});
    on<SetActiveTerminalSession>((e, emit) {});
    on<DeleteTerminalSession>((e, emit) {});
    on<UpdateTerminalSessionStatus>((e, emit) {});
    on<UpdateTerminalFontSize>((e, emit) {});
  }
}

// ── TerminalKeyboardMenu ──────────────────────────────────────────────────────
class TerminalKeyboardMenu extends StatelessWidget {
  const TerminalKeyboardMenu({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
