// ── Web terminal preview ─────────────────────────────────────────────────────
// The real PTY is native-only, but the web build should still expose the same
// terminal surface so GitHub Pages can be used to review the UI.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'terminal_keyboard_menu.dart';
export 'terminal_keyboard_menu.dart';

// ── SetupTerminal ─────────────────────────────────────────────────────────────
class SetupTerminal extends StatelessWidget {
  final String projectDir;
  final List<String> args;
  final bool useScaffold, showKeyboardMenu, readOnly;
  final int? sshId, termuxId;
  final String? commandToExecuteInSSH;

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
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff08090b),
      body: _WebTerminalPreview(showKeyboardMenu: showKeyboardMenu),
    );
  }
}
// ── EmbeddedTerminal ──────────────────────────────────────────────────────────
class EmbeddedTerminal extends StatelessWidget {
  final String projectDir;
  final List<String> args;
  final bool showKeyboardMenu, readOnly;

  const EmbeddedTerminal({
    super.key,
    required this.projectDir,
    this.args = const [],
    this.showKeyboardMenu = true,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return _WebTerminalPreview(
      showKeyboardMenu: showKeyboardMenu,
    );
  }
}

class _WebTerminalPreview extends StatefulWidget {
  final bool showKeyboardMenu;

  const _WebTerminalPreview({required this.showKeyboardMenu});

  @override
  State<_WebTerminalPreview> createState() => _WebTerminalPreviewState();
}

class _WebTerminalPreviewState extends State<_WebTerminalPreview> {
  final _lines = <String>[
    'Panda Terminal  •  Web preview',
    '',
    r'~ $ echo "Panda Terminal OK"',
    'Panda Terminal OK',
    r'~ $ pwd',
    '/workspace',
    r'~ $ git status --short',
    ' M lib/terminal/terminal_keyboard_menu.dart',
    ' M lib/ui/home.dart',
    r'~ $ _',
  ];

  void _sendSequence(String sequence) {
    if (sequence.isEmpty) return;
    final visible = sequence
        .replaceAll('\x1b[A', '↑')
        .replaceAll('\x1b[B', '↓')
        .replaceAll('\x1b[C', '→')
        .replaceAll('\x1b[D', '←')
        .replaceAll('\x1b', 'ESC')
        .replaceAll('\n', '↵')
        .replaceAll('\t', 'TAB');
    setState(() {
      _lines
        ..removeLast()
        ..add('~ $visible')
        ..add(r'~ $ _');
    });
  }

  Widget _sessionHeader(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xff17191d),
        border: Border(
          bottom: BorderSide(color: Color(0xff30343b), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              color: Color(0xff0d0f12),
              border: Border(
                bottom: BorderSide(color: Color(0xff6d79ff), width: 2),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded, size: 15, color: Color(0xff9da6ff)),
                SizedBox(width: 7),
                Text(
                  'Terminal',
                  style: TextStyle(
                    color: Color(0xffe9ebf0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 10),
                Icon(Icons.close_rounded, size: 14, color: Color(0xff777d88)),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Nouvelle session',
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xff9097a3)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          IconButton(
            tooltip: 'Options du terminal',
            onPressed: () {},
            icon: const Icon(Icons.more_horiz_rounded, size: 19, color: Color(0xff9097a3)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff050607),
      child: Column(
        children: [
          _sessionHeader(context),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                final isCommand = line.startsWith('~ \$');
                final isOutput = line == 'Panda Terminal OK';
                return Text(
                  line,
                  style: TextStyle(
                    color: isCommand
                        ? const Color(0xff9da6ff)
                        : isOutput
                            ? const Color(0xff82d99d)
                            : const Color(0xffd7d9de),
                    fontFamily: 'jetBrainsMono',
                    fontSize: 12,
                    height: 1.45,
                  ),
                );
              },
            ),
          ),
          if (widget.showKeyboardMenu)
            TerminalKeyboardMenu(
              onSendSequence: _sendSequence,
              onModifierChanged: (ctrl, alt, shift, reset) {},
              onCopy: () {},
              onPaste: () {},
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
  }) =>
      TerminalSessionState(
        sessions: sessions ?? this.sessions,
        activeSessionId: clearActive ? null : activeSessionId ?? this.activeSessionId,
        fontSize: fontSize ?? this.fontSize,
      );
}

// ── Bloc ──────────────────────────────────────────────────────────────────────
class TerminalSessionBloc
    extends Bloc<TerminalSessionEvent, TerminalSessionState> {
  TerminalSessionBloc({double initialFontSize = 13})
      : super(TerminalSessionState(
            sessions: [], activeSessionId: null, fontSize: initialFontSize)) {
    on<CreateTerminalSession>((e, emit) {});
    on<SetActiveTerminalSession>((e, emit) {});
    on<DeleteTerminalSession>((e, emit) {});
    on<UpdateTerminalSessionStatus>((e, emit) {});
    on<UpdateTerminalFontSize>((e, emit) {});
  }
}
