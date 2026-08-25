import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/render.dart' show RenderTerminal;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../ui/notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/debian_setup.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
import '../utils/themes.dart';
import './terminal_bridge.dart';

// Terminal session BLoC and models
// Extracted from terminal_native.dart

class TerminalSessionMeta {
  final String id;
  final String title;
  final DateTime createdAt;
  final bool isRunning;

  const TerminalSessionMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.isRunning,
  });

  TerminalSessionMeta copyWith({String? title, bool? isRunning}) {
    return TerminalSessionMeta(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

@immutable
abstract class TerminalSessionEvent {}

class CreateTerminalSession extends TerminalSessionEvent {
  final String id;
  final String title;
  final bool makeActive;
  final bool isRunning;

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

class TerminalSessionState {
  final List<TerminalSessionMeta> sessions;
  final String? activeSessionId;
  double fontSize;

  TerminalSessionState({
    required this.sessions,
    required this.activeSessionId,
    this.fontSize = 13.0
  });

  TerminalSessionState copyWith({
    List<TerminalSessionMeta>? sessions,
    String? activeSessionId,
    double? fontSize,
    bool clearActive = false,
  }) {
    return TerminalSessionState(
      sessions: sessions ?? this.sessions,
      activeSessionId: clearActive
        ? null
        : activeSessionId ?? this.activeSessionId,
      fontSize: fontSize ?? this.fontSize
    );
  }
}

class TerminalSessionBloc extends Bloc<TerminalSessionEvent, TerminalSessionState> {
  TerminalSessionBloc({double initialFontSize = 13}) : super(TerminalSessionState(sessions: [], activeSessionId: null, fontSize: initialFontSize)) {
    on<CreateTerminalSession>((event, emit) {
      final newSession = TerminalSessionMeta(
        id: event.id,
        title: event.title,
        createdAt: DateTime.now(),
        isRunning: event.isRunning,
      );
      final sessions = [newSession, ...state.sessions];
      emit(
        state.copyWith(
          sessions: sessions,
          activeSessionId: event.makeActive ? event.id : state.activeSessionId,
        ),
      );
    });

    on<SetActiveTerminalSession>((event, emit) {
      emit(state.copyWith(activeSessionId: event.id));
    });

    on<DeleteTerminalSession>((event, emit) {
      final sessions = state.sessions.where((session) => session.id != event.id).toList();
      if (sessions.isEmpty) {
        emit(state.copyWith(sessions: sessions, clearActive: true));
        return;
      }
      final activeId = state.activeSessionId == event.id ? sessions.first.id : state.activeSessionId;
      emit(state.copyWith(sessions: sessions, activeSessionId: activeId));
    });

    on<UpdateTerminalSessionStatus>((event, emit) {
      final sessions = state.sessions.map((session) {
        if (session.id == event.id) {
          return session.copyWith(isRunning: event.isRunning);
        }
        return session;
      }).toList();
      emit(state.copyWith(sessions: sessions));
    });

    on<UpdateTerminalFontSize>((event, emit) {
      emit(state.copyWith(fontSize: event.fontSize));
    });
  }
}

class _TerminalRuntime {
  final String sessionId;
  final String title;
  final Terminal terminal;
  final TerminalController controller;
  final bool isProot;

  Pty? pty;
  SSHSession? sshSession;
  String currentInput = '';
  VoidCallback? selectionListener;

  _TerminalRuntime({
    required this.sessionId,
    required this.title,
    required this.terminal,
    required this.controller,
    this.isProot = true,
  });

  bool get isRunning {
    if (sshSession != null) return true;
    return pty != null;
  }

  void stopProcess() {
    if(sshSession != null){
      sshSession!.kill(SSHSignal.KILL);
    }
    if (pty != null) {
      try {
        pty!.kill(ProcessSignal.sigint);
      } catch (_) {}
      try {
        pty!.kill(ProcessSignal.sigterm);
      } catch (_) {}
      try {
        pty!.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    pty = null;
  }

  Future<void> dispose() async {
    stopProcess();
    if (selectionListener != null) {
      controller.removeListener(selectionListener!);
    }
    controller.dispose();
  }
}

/// Store GLOBAL des sessions terminal : survit aux remounts du widget.
///
/// Quand le terminal passe du panneau bas au plein écran (et inversement),
/// le StatefulWidget est recréé — sans ce store, un NOUVEAU PTY était
/// lancé et la session en cours (apk install, flutter run…) mourait.
class TerminalSessionStore {
  TerminalSessionStore._();
  static final TerminalSessionStore instance = TerminalSessionStore._();

  /// Sessions vivantes (PTY inclus). Vidé uniquement à la fermeture
  /// explicite de chaque onglet, jamais au remount du widget.
  final Map<String, _TerminalRuntime> runtimes = {};

  /// Bloc partagé : police, sessions, onglet actif restent cohérents
  /// entre la vue embarquée et la vue étendue.
  TerminalSessionBloc? bloc;
}

class _SetupTerminalState extends State<SetupTerminal> {
