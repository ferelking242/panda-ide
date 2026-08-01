// ── Web stub — terminal unavailable on web platform ──────────────────────────
// This file is selected by terminal.dart conditional export when compiling for
// dart:html (web). It provides empty / no-op implementations of every class
// that the rest of the codebase imports from terminal.dart.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('Terminal not available on web',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
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
    return const Center(
      child: Text('Terminal not available on web',
          style: TextStyle(color: Colors.grey)),
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

// ── TerminalKeyboardMenu ──────────────────────────────────────────────────────
class TerminalKeyboardMenu extends StatelessWidget {
  const TerminalKeyboardMenu({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
