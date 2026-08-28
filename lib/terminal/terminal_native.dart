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
import '../utils/rootfs_manager.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
import '../utils/themes.dart';
import './terminal_bridge.dart';
import './terminal_keyboard_menu.dart';

/// Taille de police par défaut du terminal — source de vérité du zoom
/// (100%). Le pinch et les boutons A+/A− gravitent autour de cette valeur.
const double kDefaultTerminalFontSize = 15.0;

/// Reconnaissance de geste dédiée au pinch à DEUX doigts.
///
/// Contrairement au ScaleGestureRecognizer générique, celle-ci revendique
/// l'arène dès que le deuxième doigt touche l'écran : le pinch ne peut plus
/// être interprété comme un tap (ouverture du clavier), un scroll ou un
/// swipe de pages. À un seul doigt elle ne se manifeste jamais, donc le
/// comportement natif du terminal (tap, long-press, drag) reste intact.
class _TwoFingerPinchRecognizer extends OneSequenceGestureRecognizer {
  _TwoFingerPinchRecognizer({super.debugOwner});

  void Function()? onStart;
  void Function(double scale)? onUpdate;
  void Function()? onEnd;

  final Map<int, Offset> _pointers = {};
  double? _baseSpan;

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2 && _baseSpan == null) {
      resolve(GestureDisposition.accepted);
      _baseSpan = _currentSpan;
      onStart?.call();
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _pointers.containsKey(event.pointer)) {
      _pointers[event.pointer] = event.position;
      final base = _baseSpan;
      if (base != null && base > 0) {
        onUpdate?.call(_currentSpan / base);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      stopTrackingPointer(event.pointer);
      if (_baseSpan != null && _pointers.length < 2) {
        _baseSpan = null;
        onEnd?.call();
      }
    }
  }

  double get _currentSpan {
    final points = _pointers.values.toList(growable: false);
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // Gesture arena dropped us (all pointers gone / cancelled): drop any
    // stale pinch state so a next two-finger gesture starts from scratch.
    _pointers.clear();
    _baseSpan = null;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {}

  @override
  String get debugDescription => 'two finger pinch zoom';
}

// ── Exit banner data ─────────────────────────────────────────────────────────
class _ExitBannerData {
  final int exitCode;
  final String sessionTitle;
  _ExitBannerData({required this.exitCode, required this.sessionTitle});
}

class SetupTerminal extends StatefulWidget {
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
    this.commandToExecuteInSSH
  });

  @override
  State<SetupTerminal> createState() => _SetupTerminalState();
}

class EmbeddedTerminal extends StatelessWidget {
  final String projectDir;
  final List<String> args;
  final bool showKeyboardMenu;
  final bool readOnly;

  const EmbeddedTerminal({
    super.key,
    required this.projectDir,
    this.args = const [],
    this.showKeyboardMenu = true,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return SetupTerminal(
      projectDir: projectDir,
      args: args,
      useScaffold: false,
      showKeyboardMenu: showKeyboardMenu,
      readOnly: readOnly,
    );
  }
}

@immutable
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
  late TerminalSessionBloc _sessionBloc;
  late final List<SSHInfo> sshServerList;
  late final SSHPrivateKey? termuxInfo;
  // Pointe vers le store global : les références existantes continuent
  // de fonctionner, mais les sessions survivent aux remounts.
  Map<String, _TerminalRuntime> get _sessionRuntimes =>
      TerminalSessionStore.instance.runtimes;
  AnimationStatus _terminalSelectionStatus = AnimationStatus.dismissed;
  String _sharedPath = '';
  late final PageController _pageController;
  bool _syncingPage = false;

  OverlayEntry? _selectionToolbarOverlay;
  bool _hasSelection = false;
  // Horloge de repositionnement des poignées de sélection (scroll, layout,
  // changement de police) : incrémente un tick qui reconstruit l'overlay.
  final ValueNotifier<int> _selectionUiTick = ValueNotifier<int>(0);
  Timer? _selectionUiSyncTimer;
  final GlobalKey _terminalHostKey = GlobalKey();

  final ValueNotifier<List<String>?> _suggestionsNotifier = ValueNotifier(null);
  final ScrollController _suggestionScrollController = ScrollController();
  int _selectedSuggestionIndex = 0;
  List<String> _pathBinaries = [];

  // ── Feature 1: Exit code banner ────────────────────────────────────────────
  final ValueNotifier<_ExitBannerData?> _exitBannerNotifier = ValueNotifier(null);
  Timer? _exitBannerTimer;

  // ── Modifier state for keyboard menu (shared, never replaces onOutput) ──
  bool _modCtrl = false;
  bool _modAlt = false;
  bool _modShift = false;
  VoidCallback? _modResetCallback;

  // ── Feature 3: Fullscreen ──────────────────────────────────────────────────
  bool _isFullscreen = false;

  // ── Feature 4: Split terminals ─────────────────────────────────────────────
  bool _isSplitView = false;
  String? _splitSessionId;
  Axis _splitAxis = Axis.horizontal;

  // ── Pinch-to-zoom ────────────────────────────────────────────────────────
  double _pinchBaseFontSize = kDefaultTerminalFontSize;

  void _onPinchStart() {
    _pinchBaseFontSize = _sessionBloc.state.fontSize;
    // Un pinch ne doit JAMAIS faire apparaître le clavier.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onPinchUpdate(double scale) {
    final newSize = (_pinchBaseFontSize * scale).clamp(8.0, 40.0);
    if ((newSize - _sessionBloc.state.fontSize).abs() >= 0.35) {
      _onTerminalFontSizeChanged(newSize);
    }
  }

  void _onPinchEnd() {}

  @override
  void initState() {
    super.initState();
    // Réutilise le bloc global si une vue précédente existe (expand/collapse)
    _sessionBloc = TerminalSessionStore.instance.bloc ??= TerminalSessionBloc(
      initialFontSize: _terminalFontSizeFromConfig(),
    );
    sshServerList = context.read<SSHServersCubit>().state.serverList.where((server) => server.isConnected).toList();
    termuxInfo = context.read<TermuxCubit>().state.termInfo;
    _pageController = PageController(initialPage: 0);
    _bootstrapTerminalPage();
    _loadPathBinaries();
  }

  Future<void> _bootstrapTerminalPage() async {
    _sharedPath = await NativeChannel.getLibraryPath();
    final workDir = Directory(widget.projectDir);
    if (!workDir.existsSync()) {
      await workDir.create(recursive: true);
    }
    if (!mounted) return;
    // Sessions déjà vivantes (remount expand/collapse) → on ne relance PAS
    // un PTY : on rebranche simplement l'onglet actif sur la session existante.
    final live = TerminalSessionStore.instance.runtimes.values
        .where((r) => r.isProot)
        .toList();
    if (live.isNotEmpty && _sessionBloc.state.sessions.isNotEmpty) {
      _sessionBloc.add(SetActiveTerminalSession(
          _sessionBloc.state.activeSessionId ?? live.first.sessionId));
      // Re-attach onOutput for live sessions — dispose() nulled it,
      // but the PTY is still alive. Without this, user input goes nowhere.
      for (final r in live) {
        if (r.pty != null && r.terminal.onOutput == null) {
          final proc = r.pty!;
          r.terminal.onOutput = (data) {
            if (widget.readOnly) return;

            String sequence = '';
            if (_modCtrl) {
              if (data.length == 1) {
                int code = data.toUpperCase().codeUnitAt(0);
                if (code >= 65 && code <= 90) {
                  sequence = String.fromCharCode(code - 64);
                }
              }
              if (_modResetCallback != null) _modResetCallback!();
              _modCtrl = false; _modAlt = false; _modShift = false; _modResetCallback = null;
            } else if (_modAlt) {
              sequence = '\x1b$data';
              if (_modResetCallback != null) _modResetCallback!();
              _modCtrl = false; _modAlt = false; _modShift = false; _modResetCallback = null;
            } else if (_modShift) {
              sequence = data.toUpperCase();
              if (_modResetCallback != null) _modResetCallback!();
              _modCtrl = false; _modAlt = false; _modShift = false; _modResetCallback = null;
            } else {
              sequence = data;
            }

            if (sequence.isNotEmpty) {
              proc.write(const Utf8Encoder().convert(sequence));
            }
            final activeId = _sessionBloc.state.activeSessionId;
            if (activeId == r.sessionId) {
              _handleInputForAutocomplete(r, sequence);
            }
          };
        }
      }
      return;
    }
    await _createSession(
      args: widget.args,
      makeActive: true,
      title: 'Session 1',
      externalServer: ((){
        final sshId = widget.sshId;
        final termuxId = widget.termuxId;
        if (sshId != null) {
          return sshServerList.singleWhere((server) => server.id == sshId);
        } else if(termuxId != null) {
          return termuxInfo;
        }
      })()
    );
  }

  void _onSelectionChanged(String sessionId) {
    if (_sessionBloc.state.activeSessionId != sessionId) return;
    final runtime = _sessionRuntimes[sessionId];
    if (runtime == null) return;

    final hasSelection = runtime.controller.selection != null;
    if (hasSelection != _hasSelection) {
      _hasSelection = hasSelection;
      if (hasSelection) {
        _showSelectionUI();
      } else {
        _hideSelectionUI();
      }
    }
  }

  _TerminalRuntime? _activeRuntime() {
    final activeId = _sessionBloc.state.activeSessionId;
    if (activeId == null) return null;
    return _sessionRuntimes[activeId];
  }

  String _nextSessionTitle() {
    final count = _sessionRuntimes.length + 1;
    return 'Session $count';
  }

  Future<void> _createSession({
    List<String> args = const [],
    bool makeActive = true,
    String? title,
    bool showFeedback = false,
    SSHInfo? externalServer,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sessionTitle = title ?? _nextSessionTitle();
    final runtime = _TerminalRuntime(
      sessionId: id,
      title: sessionTitle,
      terminal: Terminal(platform: TerminalTargetPlatform.android),
      controller: TerminalController(selectionMode: SelectionMode.line),
      isProot: true,
    );
    runtime.selectionListener = () => _onSelectionChanged(id);
    runtime.controller.addListener(runtime.selectionListener!);
    _sessionRuntimes[id] = runtime;

    _sessionBloc.add(
      CreateTerminalSession(
        id: id,
        title: sessionTitle,
        makeActive: makeActive,
        isRunning: false,
      ),
    );

    await _startPty(runtime, args: args, externalServer: externalServer);

    if (showFeedback && mounted) {
      PandaNotifications.show(
        context: context,
        title: 'Session Créée',
        message: 'Nouvelle session: $sessionTitle',
      );
    }
  }

  Future<void> _restartSession(String sessionId) async {
    final runtime = _sessionRuntimes[sessionId];
    if (runtime == null) return;
    runtime.stopProcess();
    runtime.currentInput = '';
    if (_sessionBloc.state.activeSessionId == sessionId) {
      _suggestionsNotifier.value = null;
    }
    await _startPty(runtime);
  }
  void _terminateSession(String sessionId) {
    final runtime = _sessionRuntimes[sessionId];
    if (runtime == null || !runtime.isRunning) return;
    runtime.stopProcess();
    _sessionBloc.add(
      UpdateTerminalSessionStatus(id: sessionId, isRunning: false),
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    if (!_sessionRuntimes.containsKey(sessionId)) return;

    final isLastSession = _sessionRuntimes.length == 1;

    if (isLastSession) {
      final runtime = _sessionRuntimes.remove(sessionId);
      await runtime?.dispose();
      _sessionBloc.add(DeleteTerminalSession(sessionId));
      _hideSelectionUI();
      _suggestionsNotifier.value = null;
      _hasSelection = false;

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      }
      return;
    }

    final runtime = _sessionRuntimes.remove(sessionId);
    await runtime?.dispose();
    _sessionBloc.add(DeleteTerminalSession(sessionId));

    if (_sessionBloc.state.activeSessionId == sessionId) {
      _hideSelectionUI();
      _suggestionsNotifier.value = null;
      _hasSelection = false;
    }
  }

  Future<void> _loadPathBinaries() async {
    final pathDirs = [
      binDir,
      '$runtimesDir/flutter/bin',
      '$runtimesDir/android-sdk/platform-tools',
      '$runtimesDir/node/bin',
      '/bin',
      '/usr/bin',
      '/sbin',
      '/usr/sbin',
    ];

    final binaries = <String>{};
    for (final dirPath in pathDirs) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File) {
              final name = entity.path.split('/').last;
              binaries.add(name);
            }
          }
        }
      } catch (_) {}
    }
    _pathBinaries = binaries.toList()..sort();
  }

  // ── Feature 1: show exit code banner ────────────────────────────────────
  void _showExitBanner(String sessionId, int code) {
    if (!mounted) return;
    final meta = _sessionBloc.state.sessions
        .firstWhere((s) => s.id == sessionId,
            orElse: () => TerminalSessionMeta(
                  id: sessionId,
                  title: 'Terminal',
                  createdAt: DateTime.now(),
                  isRunning: false,
                ));
                
    if (code != 0) {
      PandaNotifications.show(
        context: context,
        title: 'Session Terminée: ${meta.title}',
        message: 'Le processus s\'est terminé avec le code d\'erreur $code.',
        isError: true,
      );
    }
  }

  double _terminalFontSizeFromConfig() {
    try {
      final raw = context.read<ConfigBloc>().state.codeForgeConfig['terminalFontSize'];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? kDefaultTerminalFontSize;
    } catch (_) {}
    return kDefaultTerminalFontSize;
  }

  String _terminalFontFamilyFromConfig() {
    try {
      final raw = context.read<ConfigBloc>().state.codeForgeConfig['fontFamily'];
      if (raw is String && raw.trim().isNotEmpty) {
        final value = raw.trim();
        if (value.toLowerCase().contains('jetbrains')) return 'jetBrainsMonoNF';
        if (fonts.contains(value)) return value;
      }
    } catch (_) {}
    return 'jetBrainsMonoNF';
  }

  Future<void> _saveTerminalFontSize(double fontSize) async {
    final configState = context.read<ConfigBloc>().state;
    final currentConfig = Map<String, dynamic>.from(configState.codeForgeConfig);
    currentConfig['terminalFontSize'] = fontSize;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('codeForgeConfig', jsonEncode(currentConfig));
    if (!mounted) return;
    context.read<ConfigBloc>().add(ChangeConfigEvent(currentConfig));
  }

  void _onTerminalFontSizeChanged(double fontSize) {
    if (fontSize < 8) fontSize = 8;
    if (fontSize > 40) fontSize = 40;
    _sessionBloc.add(UpdateTerminalFontSize(fontSize: fontSize));
    _saveTerminalFontSize(fontSize);
  }

  // ── Serveur adb partagé (survit à la fermeture des terminaux) ───────────────
  // Un proot détaché (sans --kill-on-exit) héberge `adb start-server`.
  // Toutes les sessions terminal partagent ce daemon sur 127.0.0.1:5037 :
  // fermer/réouvrir un terminal NE PERD PLUS la connexion adb.
  static Process? _sharedAdbHost;

  Future<void> _ensureSharedAdbServer(String prootBin, String rootfsDir) async {
    if (_sharedAdbHost != null) return;
    try {
      final sessionEnv = await DebianSetup.prootSessionEnvironment();
      // Endpoint mémorisé par l'extension Panda Device (IP:port de debug)
      String endpoint = '';
      try {
        final f = File('$appDir/adb_endpoint.txt');
        if (f.existsSync()) endpoint = f.readAsStringSync().trim();
      } catch (_) {}

      final env = <String, String>{...sessionEnv, if (endpoint.isNotEmpty) 'ADB_ENDPOINT': endpoint};
      final hostArgs = <String>[
        '-0',
        '--link2symlink',
        '--sysvipc',
        '--rootfs=$rootfsDir',
        '-b', '/dev',
        '-b', '/proc',
        '-b', '/sys',
        if (Directory(tempDir).existsSync()) ...['-b', '$tempDir:/tmp'],
        if (Directory(appDir).existsSync()) ...['-b', appDir],
        '-w', '/root',
        '/bin/sh',
        '-c',
        'adb start-server >/dev/null 2>&1 || true; '
            'if [ -n "\$ADB_ENDPOINT" ]; then '
            'adb connect "\$ADB_ENDPOINT" >/dev/null 2>&1 || true; fi; '
            'exec sleep infinity',
      ];
      _sharedAdbHost = await Process.start(prootBin, hostArgs,
          environment: env, workingDirectory: appDir, mode: ProcessStartMode.detached);
      PandaLog.i('Terminal', 'Shared adb server host started${endpoint.isNotEmpty ? " (endpoint=$endpoint)" : ""}');
    } catch (e) {
      PandaLog.w('Terminal', 'Shared adb host failed (non fatal): $e');
    }
  }

  // ── PRoot + Alpine session ─────────────────────────────────────────────────

  Future<void> _startProotSession(_TerminalRuntime runtime, {List<String> args = const []}) async {
    final activeType = await RootfsManager.getActiveTerminal();
    final rootfsDir = (await RootfsManager.rootfsDir(activeType)).path;
    final sw = Stopwatch()..start();

    if (!await RootfsManager.isInstalled(activeType)) {
      // Alpine should have been extracted during SettingUpScreen.
      // If we're here, the extraction failed or was skipped.
      PandaLog.e('Terminal', 'Linux rootfs incomplete — cannot start PRoot session');
      runtime.terminal.write('\r\n\x1b[31m[Linux non configuré]\x1b[0m\r\n');
      runtime.terminal.write('\x1b[31m  Le rootfs Linux n\'a pas été extrait correctement.\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m  Solution:\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m    1. Fermer et relancer Panda IDE\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m    2. L\'extraction se fera automatiquement\x1b[0m\r\n');
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
      return;
    }
    PandaLog.d('Terminal', 'Linux rootfs verified complete');
    await DebianSetup.ensureDebianRuntimeFiles();

    PandaLog.i('Terminal', 'Locating PRoot binary in rootfs=$rootfsDir');
    final prootBin = await DebianSetup.locateProotBinary(rootfsDir);
    if (prootBin == null) {
      PandaLog.e('Terminal', 'PRoot binary not found or incompatible (nativeLibDir checked)');
      final nativeLib = await DebianSetup.nativeLibDir();
      PandaLog.e('Terminal', 'nativeLibDir=$nativeLib, prootExists=${File("$nativeLib/libproot.so").existsSync()}');
      runtime.terminal.write('\r\n\x1b[31m[PRoot introuvable ou incompatible]\x1b[0m\r\n');
      runtime.terminal.write('\x1b[31m  Le binaire libproot.so est introuvable ou ne fonctionne pas.\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m  Dossier libs natives: $nativeLib\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m  Logs:\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m    /panda-ide/Logs/panda-*.log\x1b[0m\r\n');
      runtime.terminal.write('\x1b[36m  Essayez de réinstaller ou de vider le cache Alpine\x1b[0m\r\n');
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
      return;
    }
    PandaLog.i('Terminal', 'PRoot binary found: $prootBin');
    final loaderPath = await DebianSetup.prootLoaderPath();
    if (loaderPath == null) {
      PandaLog.w('Terminal', 'PRoot loader (libproot-loader.so) not found');
      runtime.terminal.write('\r\n\x1b[33m[Avertissement: loader PRoot (libproot-loader.so) absent du dossier de libs natives.]\x1b[0m\r\n');
    }

    // Serveur adb partagé démarré AVANT la session (survit aux terminaux)
    await _ensureSharedAdbServer(prootBin, rootfsDir);

    // Le dossier de projet vit souvent sur le stockage public Android
    // (/storage/emulated/0/...). Sans la permission « acces a tous les
    // fichiers », il existe mais reste illisible : `ls` renvoie alors
    // "Permission denied". On teste la lisibilite reelle avant de choisir
    // le repertoire de travail de la session.
    // Termux behaviour: no project open -> silent session in ~ (/root).
    // The project (when any) is bind-mounted at /root/workspace.
    final projectReadable = widget.projectDir.trim().isNotEmpty &&
        DebianSetup.isDirAccessible(widget.projectDir);

    try {
      final prootArgs = <String>[
        '-0',
        '--link2symlink',
        '--sysvipc',
        '--kill-on-exit',
        '--rootfs=$rootfsDir',
        // Inconditional binds
        '-b', '/dev',
        '-b', '/proc',
        '-b', '/sys',
      ];

      void addConditionalBind(String hostPath, [String? guestPath]) {
        try {
          final host = hostPath.split(':').first;
          if (Directory(host).existsSync() || File(host).existsSync()) {
            final target = guestPath != null ? '$hostPath:$guestPath' : hostPath;
            prootArgs.addAll(['-b', target]);
          }
        } catch (_) {}
      }

      // Conditional binds
      addConditionalBind('/dev/pts');
      addConditionalBind('/dev/urandom');
      addConditionalBind('/dev/shm');
      addConditionalBind('/proc/self/fd', '/dev/fd');
      addConditionalBind('/system');
      addConditionalBind('/apex');
      addConditionalBind('/linkerconfig');
      addConditionalBind('/vendor');
      addConditionalBind('/sdcard');
      addConditionalBind('/storage');
      addConditionalBind(appDir);
      // PROOT_TMP_DIR must exist on the host: PRoot extracts its internal
      // loader there and chmods it before starting the tracee.
      try {
        Directory(tempDir).createSync(recursive: true);
        addConditionalBind(tempDir, '/tmp');
      } catch (_) {}
      // Point de montage stable du projet : evite les chemins Android
      // exotiques et donne un cwd previsible dans l'invite.
      if (projectReadable) {
        addConditionalBind(widget.projectDir, DebianSetup.workspaceMount);
      }

      prootArgs.addAll([
        '-w', '/root',
        '/bin/bash',
        '-l',
        ...args,
      ]);

      // LD_LIBRARY_PATH doit pointer vers le dossier des libs natives de
      // l'APK : PRoot y trouve libtalloc.so / libandroid-shmem.so, et
      // PROOT_LOADER designe le loader embarque (libproot-loader.so).
      final sessionEnv = await DebianSetup.prootSessionEnvironment();
      PandaLog.i('Terminal', 'Starting PRoot PTY', body: 'bin=$prootBin args=${prootArgs.length} env=${sessionEnv.keys.join(',')}');

      final process = Pty.start(
        prootBin,
        arguments: prootArgs,
        workingDirectory: appDir,
        environment: sessionEnv,
        rows: runtime.terminal.viewHeight,
        columns: runtime.terminal.viewWidth,
      );

      runtime.pty = process;
      PandaLog.i('Terminal', 'PRoot PTY started successfully in ${sw.elapsedMilliseconds}ms, session=${runtime.sessionId}');
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: true));
      // Notification persistante « Panda IDE working » → anti-kill Android
      const MethodChannel('com.panda.ide').invokeMethod('startKeepAlive');

      process.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(runtime.terminal.write);

      process.exitCode.then((code) {
        PandaLog.i('Terminal', 'PRoot session ended with exit code $code', body: 'session=${runtime.sessionId}');
        if (!_sessionRuntimes.containsKey(runtime.sessionId)) return;
        runtime.pty = null;
        runtime.terminal.write('\r\n\r\n[Alpine session ended with exit code ' + code.toString() + ']');
        _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
        _showExitBanner(runtime.sessionId, code);
      });

      runtime.terminal.onOutput = (data) {
        if (widget.readOnly) return;

        String sequence = '';
        if (_modCtrl) {
          if (data.length == 1) {
            int code = data.toUpperCase().codeUnitAt(0);
            if (code >= 65 && code <= 90) {
              sequence = String.fromCharCode(code - 64);
            }
          }
          // Reset modifier after one key
          if (_modResetCallback != null) _modResetCallback!();
          _modCtrl = false;
          _modAlt = false;
          _modShift = false;
          _modResetCallback = null;
        } else if (_modAlt) {
          sequence = '\x1b$data';
          if (_modResetCallback != null) _modResetCallback!();
          _modCtrl = false;
          _modAlt = false;
          _modShift = false;
          _modResetCallback = null;
        } else if (_modShift) {
          sequence = data.toUpperCase();
          if (_modResetCallback != null) _modResetCallback!();
          _modCtrl = false;
          _modAlt = false;
          _modShift = false;
          _modResetCallback = null;
        } else {
          sequence = data;
        }

        if (sequence.isNotEmpty) {
          process.write(const Utf8Encoder().convert(sequence));
        }
        final activeSessionId = _sessionBloc.state.activeSessionId;
        if (activeSessionId == runtime.sessionId) {
          _handleInputForAutocomplete(runtime, sequence);
        }
      };

      runtime.terminal.onResize = (w, h, pw, ph) {
        process.resize(h, w);
      };
    } catch (e, stack) {
      PandaLog.e('Terminal', 'PRoot execution failed: $e', error: e.toString());
      runtime.terminal.write('\r\n\x1b[31m[Erreur PRoot / Alpine]\x1b[0m\r\n');
      runtime.terminal.write('\x1b[31m  $e\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m  Logs:\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m    /panda-ide/Logs/panda-*.log\x1b[0m\r\n');
      runtime.terminal.write('\x1b[33m    /panda-ide/Logs/crash/\x1b[0m\r\n');
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startPty(
    _TerminalRuntime runtime, {
    List<String> args = const [],
    SSHInfo? externalServer,
  }) async {
    if (externalServer == null) {
      await _startProotSession(runtime, args: args);
      return;
    }
    if(externalServer != null && externalServer.client != null){
      final terminal = runtime.terminal;
      final session = await externalServer.client!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      runtime.sshSession = session;

      terminal.buffer.clear();
      terminal.buffer.setCursor(0, 0);
      terminal.onResize = (w, h, pw, ph) {
        session.resizeTerminal(w, h, pw, ph);
      };
      
      if(widget.termuxId != null) {
        session.write(utf8.encode("cd ${widget.projectDir}\n"));
      }
      
      if(widget.commandToExecuteInSSH != null){
        session.write(utf8.encode("${widget.commandToExecuteInSSH}\n"));
      }

      terminal.onOutput = (data) {
        session.write(utf8.encode(data));
      };

      session.stdout
        .cast<List<int>>()
        .transform(Utf8Decoder())
        .listen(terminal.write);

      session.stderr
        .cast<List<int>>()
        .transform(Utf8Decoder())
        .listen(terminal.write);

      session.done.then((_) {
        if (!_sessionRuntimes.containsKey(runtime.sessionId)) return;
        final code = session.exitCode ?? 0;
        runtime.terminal.write('\r\n\n[Program finished with exit code $code]');
        _sessionBloc.add(
          UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false),
        );
        _showExitBanner(runtime.sessionId, code);
      });

      return;
    }
  }

  void _handleInputForAutocomplete(_TerminalRuntime runtime, String data) {
    if (data == '\r' || data == '\n') {
      _suggestionsNotifier.value = null;
      runtime.currentInput = '';
      return;
    }

    if (data == '\x7f' || data == '\b') {
      if (runtime.currentInput.isNotEmpty) {
        runtime.currentInput = runtime.currentInput.substring(
          0,
          runtime.currentInput.length - 1,
        );
      }
    } else if (data == '\t') {
      final suggestions = _suggestionsNotifier.value;
      if (suggestions != null && suggestions.isNotEmpty) {
        _acceptSuggestion(runtime, suggestions[_selectedSuggestionIndex]);
      }
      return;
    } else if (data == ' ' || data.contains('\x1b')) {
      _suggestionsNotifier.value = null;
      runtime.currentInput = '';
      return;
    } else if (data.length == 1 && data.codeUnitAt(0) >= 32) {
      runtime.currentInput += data;
    } else {
      return;
    }

    _updateSuggestions(runtime);
  }

  Future<void> _updateSuggestions(_TerminalRuntime runtime) async {
    if (runtime.currentInput.isEmpty) {
      _suggestionsNotifier.value = null;
      return;
    }

    final query = runtime.currentInput.toLowerCase();
    List<String> matches = [];

    if (runtime.currentInput.startsWith('./') ||
        runtime.currentInput.startsWith('/') ||
        runtime.currentInput.startsWith('~/') ||
        runtime.currentInput.contains('/')) {
      matches = await _getPathSuggestions(runtime.currentInput);
    } else {
      matches = _pathBinaries
          .where((bin) => bin.toLowerCase().startsWith(query))
          .take(10)
          .toList();
    }

    if (matches.isEmpty) {
      _suggestionsNotifier.value = null;
    } else {
      _selectedSuggestionIndex = 0;
      _suggestionsNotifier.value = matches;
    }
  }

  Future<List<String>> _getPathSuggestions(String input) async {
    try {
      String searchPath;
      String prefix = '';

      if (input.startsWith('~/')) {
        searchPath = homeDir + input.substring(1);
        prefix = '~/';
      } else if (input.startsWith('./')) {
        searchPath = '${widget.projectDir}/${input.substring(2)}';
        prefix = './';
      } else if (input.startsWith('/')) {
        searchPath = input;
        prefix = '';
      } else {
        searchPath = '${widget.projectDir}/$input';
        prefix = '';
      }

      final lastSlash = searchPath.lastIndexOf('/');
      final dirPath = lastSlash >= 0
          ? searchPath.substring(0, lastSlash + 1)
          : searchPath;
      final partial = lastSlash >= 0
          ? searchPath.substring(lastSlash + 1).toLowerCase()
          : '';

      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final suggestions = <String>[];
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (partial.isEmpty || name.toLowerCase().startsWith(partial)) {
          final isDir = entity is Directory;
          final displayPath = prefix.isEmpty
              ? entity.path
              : prefix +
                    entity.path.substring(
                      input.startsWith('~/')
                          ? homeDir.length
                          : input.startsWith('./')
                          ? widget.projectDir.length + 1
                          : 0,
                    );
          suggestions.add(isDir ? '$displayPath/' : displayPath);
        }
      }

      suggestions.sort();
      return suggestions.take(10).toList();
    } catch (_) {
      return [];
    }
  }

  void _acceptSuggestion(_TerminalRuntime runtime, String suggestion) {
    final process = runtime.pty;
    if (process == null) return;
    final toSend = suggestion.substring(runtime.currentInput.length);
    process.write(const Utf8Encoder().convert(toSend));
    runtime.currentInput = suggestion;
    _suggestionsNotifier.value = null;
  }

  // ── UI de sélection : barre compacte + poignées déplaçables ────────────────

  void _showSelectionUI() {
    _hideSelectionUI();
    if (!mounted) return;

    final runtime = _activeRuntime();
    if (runtime == null) return;

    final overlay = Overlay.of(context);

    _selectionToolbarOverlay = OverlayEntry(
      builder: (overlayCtx) {
        return ValueListenableBuilder<int>(
          valueListenable: _selectionUiTick,
          builder: (context, _, __) {
            if (runtime.controller.selection == null) return const SizedBox.shrink();

            return Stack(
              children: [
                // ── Poignées de sélection ────────────────────────────────
                ..._buildSelectionHandles(runtime),
                // ── Barre d'actions compacte ─────────────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(overlayCtx).viewInsets.bottom + 48,
                  child: Center(
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xdd1c1c1e),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x2effffff)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _toolbarIconButton(
                              icon: Icons.select_all_rounded,
                              tooltip: 'Tout sélectionner',
                              onTap: () => _selectAll(runtime),
                            ),
                            _toolbarIconButton(
                              icon: Icons.copy_rounded,
                              tooltip: 'Copier la sélection',
                              onTap: () => _copySelection(runtime),
                            ),
                            _toolbarIconButton(
                              icon: Icons.paste_rounded,
                              tooltip: 'Coller',
                              onTap: () => _pasteIntoTerminal(runtime),
                            ),
                            _toolbarIconButton(
                              icon: Icons.manage_search_rounded,
                              tooltip: 'Rechercher dans le projet',
                              onTap: () => _grepSelection(runtime),
                            ),
                            _toolbarIconButton(
                              icon: Icons.auto_awesome,
                              tooltip: "Envoyer à l'agent",
                              onTap: () {
                                final text = _selectedText(runtime);
                                if (text.isNotEmpty) {
                                  TerminalBridge.instance.sendToAgent(text);
                                }
                                runtime.controller.clearSelection();
                              },
                            ),
                            _toolbarIconButton(
                              icon: Icons.close_rounded,
                              tooltip: 'Fermer',
                              onTap: () => runtime.controller.clearSelection(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    overlay.insert(_selectionToolbarOverlay!);

    // Les poignées doivent suivre la sélection pendant le scroll / layout.
    _selectionUiSyncTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      _selectionUiTick.value++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectionToolbarOverlay != null) _selectionUiTick.value++;
    });
  }

  /// RenderTerminal de la vue active — donne accès à la conversion
  /// pixel <-> cellule (scroll et padding inclus).
  RenderTerminal? get _renderTerminal {
    final ctx = _terminalHostKey.currentContext;
    if (ctx == null) return null;
    final root = ctx.findRenderObject();
    if (root == null || !root.attached) return null;
    final queue = <RenderObject>[root];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (current is RenderTerminal && current.attached) return current;
      current.visitChildren(queue.add);
    }
    return null;
  }

  /// Positions écran des deux poignées : coin haut-gauche de la cellule de
  /// début et bas de ligne de la cellule de fin.
  (Offset?, Offset?) _handlePositions(_TerminalRuntime runtime) {
    final rt = _renderTerminal;
    final sel = runtime.controller.selection;
    if (rt == null || sel == null || !rt.hasSize) return (null, null);
    try {
      final range = sel.normalized;
      final startPx = rt.localToGlobal(rt.getOffset(range.begin));
      final endCol = range.end.x > 0 ? range.end.x - 1 : range.end.x;
      final endPx = rt.localToGlobal(rt.getOffset(CellOffset(endCol, range.end.y + 1)));
      return (startPx, endPx);
    } catch (_) {
      return (null, null);
    }
  }

  List<Widget> _buildSelectionHandles(_TerminalRuntime runtime) {
    final (startPx, endPx) = _handlePositions(runtime);
    if (startPx == null || endPx == null) return const [];

    Widget handle(Offset pos, bool isStart) {
      return Positioned(
        left: pos.dx - 20,
        top: isStart ? pos.dy - 28 : pos.dy + 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) =>
              _dragSelectionHandle(runtime, isStart, details.globalPosition),
          onPanEnd: (_) => _selectionUiTick.value++,
          child: SizedBox(
            width: 40,
            height: 30,
            child: Center(
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xff4c8dff),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [handle(startPx, true), handle(endPx, false)];
  }

  /// Déplace une poignée : convertit le doigt en cellule puis reconstruit
  /// la sélection avec de nouvelles ancres.
  void _dragSelectionHandle(
    _TerminalRuntime runtime,
    bool isStart,
    Offset globalPos,
  ) {
    final rt = _renderTerminal;
    final sel = runtime.controller.selection;
    if (rt == null || sel == null) return;
    try {
      var cell = rt.getCellOffset(rt.globalToLocal(globalPos));
      if (!isStart && cell.y == sel.end.y && cell.x < sel.end.x) {
        cell = CellOffset(cell.x + 1, cell.y);
      }
      final base = isStart ? cell : sel.begin;
      final extent = isStart ? sel.end : cell;
      final buffer = runtime.terminal.buffer;
      runtime.controller.setSelection(
        buffer.createAnchorFromOffset(base),
        buffer.createAnchorFromOffset(extent),
        mode: SelectionMode.line,
      );
    } catch (_) {}
  }

  void _selectAll(_TerminalRuntime runtime) {
    final buffer = runtime.terminal.buffer;
    final rows = buffer.lines.length;
    if (rows <= 0) return;
    final cols = runtime.terminal.viewWidth > 0 ? runtime.terminal.viewWidth : 80;
    try {
      runtime.controller.setSelection(
        buffer.createAnchorFromOffset(CellOffset(0, 0)),
        buffer.createAnchorFromOffset(CellOffset(cols - 1, rows - 1)),
        mode: SelectionMode.line,
      );
      _selectionUiTick.value++;
    } catch (_) {}
  }

  String _selectedText(_TerminalRuntime runtime) {
    final sel = runtime.controller.selection;
    if (sel == null) return '';
    try {
      return runtime.terminal.buffer.getText(sel);
    } catch (_) {
      return '';
    }
  }

  void _copySelection(_TerminalRuntime runtime) {
    final selectedText = _selectedText(runtime);
    if (selectedText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: selectedText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copié'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _pasteIntoTerminal(_TerminalRuntime runtime) async {
    if (widget.readOnly) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      runtime.pty?.write(const Utf8Encoder().convert(text));
    }
  }

  void _grepSelection(_TerminalRuntime runtime) {
    final selectedText = _selectedText(runtime);
    runtime.controller.clearSelection();
    if (selectedText.isEmpty || widget.readOnly) return;
    final escaped = selectedText.replaceAll('"', '\\"');
    runtime.pty?.write(const Utf8Encoder().convert('grep -r "$escaped" .'));
  }

  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 34,
          height: 32,
          child: Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.92)),
        ),
      ),
    );
  }

  void _hideSelectionUI() {
    _selectionUiSyncTimer?.cancel();
    _selectionUiSyncTimer = null;
    _selectionToolbarOverlay?.remove();
    _selectionToolbarOverlay = null;
  }

  void sendToPty(String sequence) {
    final runtime = _activeRuntime();
    runtime?.pty?.write(const Utf8Encoder().convert(sequence));
  }

  void _setTerminalOutputWithAutocomplete({
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    VoidCallback? resetCallback,
  }) {
    _modCtrl = ctrl;
    _modAlt = alt;
    _modShift = shift;
    _modResetCallback = resetCallback;
  }

  @override
  void dispose() {
    _hideSelectionUI();
    _selectionUiTick.dispose();
    _suggestionsNotifier.dispose();
    _suggestionScrollController.dispose();
    _pageController.dispose();
    // Les sessions/PTY vivent dans TerminalSessionStore : elles survivent
    // au dispose (remount plein écran ↔ panneau). Détache juste les
    // listeners d'UI propres à cette vue.
    for (final runtime in _sessionRuntimes.values) {
      runtime.terminal.onOutput = null;
    }
    _exitBannerTimer?.cancel();
    _exitBannerNotifier.dispose();
    super.dispose();
  }

  // ── Feature 1: Exit code overlay banner ─────────────────────────────────
  Widget _buildExitBanner() {
    return const SizedBox.shrink();
  }

  Widget _buildSingleTerminalPage(TerminalSessionState state, TerminalThemePreset activeTheme) {
    if (state.sessions.isEmpty) return const Center(child: CircularProgressIndicator());
    return PageView.builder(
      controller: _pageController,
      physics: state.sessions.length <= 1
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      onPageChanged: (index) {
        if (_syncingPage) return;
        if (index < state.sessions.length) {
          _syncingPage = true;
          _sessionBloc.add(SetActiveTerminalSession(state.sessions[index].id));
          Future.delayed(Duration.zero, () => _syncingPage = false);
        }
      },
      itemCount: state.sessions.length,
      itemBuilder: (context, index) {
        final session = state.sessions[index];
        final runtime = _sessionRuntimes[session.id];
        if (runtime == null) return const SizedBox();
        return RawGestureDetector(
          gestures: {
            _TwoFingerPinchRecognizer:
                GestureRecognizerFactoryWithHandlers<_TwoFingerPinchRecognizer>(
              () => _TwoFingerPinchRecognizer(),
              (instance) {
                instance.onStart = _onPinchStart;
                instance.onUpdate = _onPinchUpdate;
                instance.onEnd = _onPinchEnd;
              },
            ),
          },
          child: TerminalView(
            runtime.terminal,
            readOnly: widget.readOnly,
            padding: EdgeInsets.zero,
            controller: runtime.controller,
            autofocus: session.id == state.activeSessionId,
            theme: activeTheme.theme,
            cursorType: TerminalCursorType.verticalBar,
            alwaysShowCursor: true,
            deleteDetection: true,
            keyboardType: TextInputType.text,
            textStyle: TerminalStyle(
              fontSize: state.fontSize,
              fontFamily: _terminalFontFamilyFromConfig(),
              height: 1.2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSplitTerminalView(TerminalSessionState state, TerminalThemePreset activeTheme) {
    final primary = _sessionRuntimes[state.activeSessionId];
    final splitRuntime = _splitSessionId != null ? _sessionRuntimes[_splitSessionId] : null;

    Widget termView(_TerminalRuntime? r, bool isActive) {
      if (r == null) return const Center(child: CircularProgressIndicator());
      return GestureDetector(
        onTap: () {
          if (!isActive) {
            _sessionBloc.add(SetActiveTerminalSession(r.sessionId));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            border: isActive
                ? Border.all(color: activeTheme.theme.cursor, width: 1.5)
                : Border.all(color: activeTheme.theme.selection, width: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: RawGestureDetector(
              gestures: {
                _TwoFingerPinchRecognizer: GestureRecognizerFactoryWithHandlers<
                    _TwoFingerPinchRecognizer>(
                  () => _TwoFingerPinchRecognizer(),
                  (instance) {
                    instance.onStart = _onPinchStart;
                    instance.onUpdate = _onPinchUpdate;
                    instance.onEnd = _onPinchEnd;
                  },
                ),
              },
              child: TerminalView(
                r.terminal,
                readOnly: widget.readOnly,
                padding: EdgeInsets.zero,
                controller: r.controller,
                autofocus: isActive,
                theme: activeTheme.theme,
                cursorType: TerminalCursorType.verticalBar,
                alwaysShowCursor: true,
                deleteDetection: true,
                keyboardType: TextInputType.text,
                textStyle: TerminalStyle(
                  fontSize: state.fontSize,
                  fontFamily: _terminalFontFamilyFromConfig(),
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final children = [
      Expanded(child: termView(primary, true)),
      const SizedBox(width: 4, height: 4),
      Expanded(child: termView(splitRuntime, false)),
    ];

    return _splitAxis == Axis.horizontal
        ? Row(children: children)
        : Column(children: children);
  }

  Future<void> _enableSplitView(Axis axis) async {
    if (_isSplitView && _splitAxis == axis) {
      setState(() { _isSplitView = false; _splitSessionId = null; });
      return;
    }
    // Create a new session for the split pane
    final newTitle = 'Split ${_sessionRuntimes.length + 1}';
    await _createSession(makeActive: false, title: newTitle);
    final sessions = _sessionBloc.state.sessions;
    // The newly created session is the first (prepended)
    final newId = sessions.first.id;
    setState(() {
      _isSplitView = true;
      _splitAxis = axis;
      _splitSessionId = newId;
    });
  }

  Widget _buildSuggestionBox() {
    if (widget.readOnly) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<List<String>?>(
      valueListenable: _suggestionsNotifier,
      builder: (context, suggestions, _) {
        if (suggestions == null || suggestions.isEmpty) {
          _selectedSuggestionIndex = 0;
          return const SizedBox.shrink();
        }

        final screenWidth = MediaQuery.of(context).size.width;
        const itemHeight = 40.0;
        final maxHeight = (suggestions.length * itemHeight).clamp(0.0, 300.0);

        return Positioned(
          left: 8,
          right: 8,
          bottom: 100,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xff252526),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: maxHeight,
                maxWidth: screenWidth - 16,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff3c3c3c), width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RawScrollbar(
                  thumbVisibility: true,
                  thumbColor: Colors.white.withValues(alpha: 0.3),
                  controller: _suggestionScrollController,
                  child: ListView.builder(
                    controller: _suggestionScrollController,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemExtent: itemHeight,
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = suggestions[index];
                      final isSelected = index == _selectedSuggestionIndex;
                      final isDirectory = suggestion.endsWith('/');
                      final isPath = suggestion.contains('/');
                      final activeRuntime = _activeRuntime();

                      return InkWell(
                        onTap: activeRuntime == null
                            ? null
                            : () =>
                                  _acceptSuggestion(activeRuntime, suggestion),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: isSelected
                              ? const Color(0xff094771)
                              : Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isDirectory
                                      ? Colors.amber.withValues(alpha: 0.15)
                                      : isPath
                                      ? Colors.blue.withValues(alpha: 0.15)
                                      : Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  isDirectory
                                      ? Icons.folder_rounded
                                      : isPath
                                      ? Icons.insert_drive_file_rounded
                                      : Icons.terminal_rounded,
                                  size: 16,
                                  color: isDirectory
                                      ? Colors.amber
                                      : isPath
                                      ? Colors.blue.shade300
                                      : Colors.green.shade300,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  suggestion,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 14,
                                     fontFamily: _terminalFontFamilyFromConfig(),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!isPath)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'cmd',
                                    style: TextStyle(
                                      color: Colors.green.shade300,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              if (isDirectory)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'dir',
                                    style: TextStyle(
                                      color: Colors.amber.shade300,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              if (isPath && !isDirectory)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'file',
                                    style: TextStyle(
                                      color: Colors.blue.shade300,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionDrawer(TerminalSessionState state, AppTheme appTheme) {
    return Drawer(
      backgroundColor: appTheme.selectScreenDrawerBg,
      surfaceTintColor: Colors.transparent,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: appTheme.editorPageDrawerBg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Terminal Sessions',
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${state.sessions.length} active tabs',
                  style: TextStyle(
                    color: appTheme.editorPageToolColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.sessions.length,
              itemBuilder: (context, index) {
                final session = state.sessions[index];
                final isActive = session.id == state.activeSessionId;

                return ListTile(
                  leading: Icon(
                    session.isRunning ? Icons.terminal : Icons.pause_circle,
                    color: session.isRunning
                        ? appTheme.editorPageToolSelectedColor
                        : appTheme.editorPageToolColor,
                  ),
                  title: Text(
                    session.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: appTheme.selectScreenCardTextColor),
                  ),
                  subtitle: Text(
                    session.isRunning ? 'Running' : 'Stopped',
                    style: TextStyle(color: appTheme.editorPageToolColor),
                  ),
                  selected: isActive,
                  selectedTileColor: appTheme.editorPageToolSelectedBgColor,
                  onTap: () {
                    _sessionBloc.add(SetActiveTerminalSession(session.id));
                    Navigator.of(context).pop();
                  },
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Restart session',
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _restartSession(session.id),
                        icon: Icon(
                          Icons.refresh,
                          size: 18,
                          color: appTheme.editorPageToolColor,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Stop session',
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: session.isRunning
                            ? () => _terminateSession(session.id)
                            : null,
                        icon: Icon(
                          Icons.stop_circle_outlined,
                          size: 18,
                          color: session.isRunning
                              ? appTheme.editorPageToolColor
                              : appTheme.editorPageToolColor.withValues(
                                  alpha: 0.45,
                                ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete session',
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _deleteSession(session.id),
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: appTheme.editorPageToolColor,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper: popup menu item ──────────────────────────────────────────────
  Widget _menuItem(IconData icon, String label, bool isDark) {
    final fg = isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xff1a1a1a);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: fg.withValues(alpha: 0.6)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: fg, fontSize: 13)),
      ],
    );
  }

  // ── Feature 5 + Session tab bar (replaces drawer as primary navigation) ──

  Widget _buildSessionTabBar(
    TerminalSessionState state,
    AppTheme appTheme,
    TerminalThemePreset terminalPreset,
  ) {
    final isDark = appTheme.isDark;
    final bgColor = terminalPreset.theme.background;
    final activeTabColor = terminalPreset.theme.background.withValues(alpha: 0.78);
    final inactiveTextColor = terminalPreset.theme.foreground.withValues(alpha: 0.55);
    final activeTextColor = terminalPreset.theme.foreground;
    final accentColor = terminalPreset.theme.cursor;
    final terminalBorder = terminalPreset.theme.selection;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: terminalBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.sessions.length,
              itemBuilder: (context, index) {
                final session = state.sessions[index];
                final isActive = session.id == state.activeSessionId;
                return GestureDetector(
                  onTap: () {
                    if (!isActive) {
                      _syncingPage = true;
                      _sessionBloc.add(SetActiveTerminalSession(session.id));
                      _pageController
                          .animateToPage(
                            index,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                          )
                          .then((_) => _syncingPage = false);
                    }
                  },
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isActive ? activeTabColor : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? accentColor : Colors.transparent,
                          width: 2,
                        ),
                        right: BorderSide(
                           color: terminalBorder,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: session.isRunning
                                ? Colors.green.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            session.title,
                            style: TextStyle(
                              color: isActive ? activeTextColor : inactiveTextColor,
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _deleteSession(session.id),
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 11,
                              color: isActive
                                  ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // + new session button
          _buildNewSessionButton(state, appTheme),
          const SizedBox(width: 2),
          // 3-dot options menu icon
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.more_vert_rounded,
              size: 18,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            tooltip: 'Options du terminal',
            color: terminalPreset.theme.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: terminalBorder,
                width: 0.5,
              ),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'fullscreen':
                  setState(() => _isFullscreen = !_isFullscreen);
                  break;
                case 'split_h':
                  await _enableSplitView(Axis.horizontal);
                  break;
                case 'split_v':
                  await _enableSplitView(Axis.vertical);
                  break;
                case 'close_split':
                  setState(() { _isSplitView = false; _splitSessionId = null; });
                  break;
                case 'font_reset':
                  _onTerminalFontSizeChanged(14);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'fullscreen',
                child: _menuItem(
                  _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  _isFullscreen ? 'Quitter le plein écran' : 'Plein écran',
                  isDark,
                ),
              ),
              if (!_isSplitView) ...[
                PopupMenuItem(
                  value: 'split_h',
                  child: _menuItem(Icons.vertical_split_rounded, 'Split horizontal', isDark),
                ),
                PopupMenuItem(
                  value: 'split_v',
                  child: _menuItem(Icons.horizontal_split_rounded, 'Split vertical', isDark),
                ),
              ] else
                PopupMenuItem(
                  value: 'close_split',
                  child: _menuItem(Icons.close_fullscreen_rounded, 'Fermer le split', isDark),
                ),
              PopupMenuItem(
                value: 'font_reset',
                child: _menuItem(Icons.format_size_rounded, 'Réinitialiser police', isDark),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildNewSessionButton(TerminalSessionState state, AppTheme appTheme) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(appTheme.selectScreenCardsBg),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      ),
      animated: true,
      onAnimationStatusChanged: (status) => _terminalSelectionStatus = status,
      menuChildren: [
        MenuItemButton(
          onPressed: () => _createSession(makeActive: true, showFeedback: true, title: 'Linux Terminal'),
          leadingIcon: Icon(Icons.terminal_rounded, color: appTheme.selectScreenCardTextColor, size: 18),
          child: Text('Nouvelle session Alpine', style: TextStyle(color: appTheme.selectScreenCardTextColor)),
        ),
        ...sshServerList.map((server) => MenuItemButton(
          onPressed: () => _createSession(makeActive: true, showFeedback: true, externalServer: server),
          leadingIcon: Padding(
            padding: const EdgeInsets.only(left: 3),
            child: FaIcon(FontAwesomeIcons.server, color: appTheme.selectScreenCardTextColor, size: 17),
          ),
          child: Text(server.name, style: TextStyle(color: appTheme.selectScreenCardTextColor)),
        )),
        if (termuxInfo != null && termuxInfo!.isConnected)
          MenuItemButton(
            onPressed: () => _createSession(makeActive: true, showFeedback: true, externalServer: termuxInfo),
            leadingIcon: SvgPicture.asset("assets/icons/Termux.svg", height: 18, width: 18),
            child: Text(termuxInfo!.name, style: TextStyle(color: appTheme.selectScreenCardTextColor)),
          ),

      ],
      builder: (context, controller, child) => InkWell(
        onTap: () => _terminalSelectionStatus.isForwardOrCompleted
            ? controller.close()
            : controller.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 17, color: Colors.grey.shade500),
              Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _sessionBloc,
      child: BlocListener<TerminalSessionBloc, TerminalSessionState>(
        listenWhen: (previous, current) =>
            previous.activeSessionId != current.activeSessionId,
        listener: (context, state) {
          _hideSelectionUI();
          _suggestionsNotifier.value = null;
          _hasSelection = false;
          // Sync page to active session
          if (!_syncingPage) {
            final idx = state.sessions
                .indexWhere((s) => s.id == state.activeSessionId);
            if (idx >= 0 && _pageController.hasClients) {
              _syncingPage = true;
              _pageController
                  .animateToPage(
                    idx,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                  )
                  .then((_) => _syncingPage = false);
            }
          }
        },
        child: BlocBuilder<TerminalSessionBloc, TerminalSessionState>(
          builder: (context, state) {
            final appTheme = context.watch<AppThemeBloc>().state.appTheme;
            final configState = context.watch<ConfigBloc>().state;
            final activeTerminalTheme = terminalThemePresetById(
              configState.codeForgeConfig['terminalTheme']?.toString(),
            );

            // ── Terminal body ──────────────────────────────────────────────
            final mainTermView = _isSplitView
                ? _buildSplitTerminalView(state, activeTerminalTheme)
                : _buildSingleTerminalPage(state, activeTerminalTheme);

            final terminalContent = Stack(key: _terminalHostKey, children: [
                Column(
                  children: [
                    Expanded(child: mainTermView),
                    if (widget.showKeyboardMenu)
                      TerminalKeyboardMenu(
                        onSendSequence: sendToPty,
                        onModifierChanged: (ctrl, alt, shift, resetCallback) {
                          _setTerminalOutputWithAutocomplete(
                            ctrl: ctrl,
                            alt: alt,
                            shift: shift,
                            resetCallback: resetCallback,
                          );
                        },
                        onCopy: () {
                          final runtime = _activeRuntime();
                          if (runtime == null) return;
                          final selectedText = runtime.controller.selection != null
                              ? runtime.terminal.buffer.getText(runtime.controller.selection!)
                              : '';
                          if (selectedText.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: selectedText));
                          }
                        },
                        onPaste: () async {
                          final runtime = _activeRuntime();
                          if (runtime == null) return;
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            runtime.pty?.write(const Utf8Encoder().convert(data!.text!));
                          }
                        },
                      ),
                  ],
                ),
                // Feature 1: exit banner overlay
                _buildExitBanner(),
                _buildSuggestionBox(),
                // ── Indicateur de zoom : tap = retour à la taille normale ────
                if ((state.fontSize - kDefaultTerminalFontSize).abs() > 0.1)
                  Positioned(
                    top: 6,
                    right: 8,
                    child: Material(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _onTerminalFontSizeChanged(kDefaultTerminalFontSize),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Text(
                            '${(state.fontSize / kDefaultTerminalFontSize * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );

            if (!widget.useScaffold) return terminalContent;

            // ── Feature 3: fullscreen wraps entire screen ──────────────────
            final isDark   = appTheme.isDark;
            final barColor = isDark ? const Color(0xff1e1e1e) : const Color(0xffececec);

            Widget scaffold = Scaffold(
              backgroundColor: isDark ? const Color(0xff1e1e1e) : const Color(0xffececec),
              appBar: _isFullscreen
                  ? null   // hide app bar in fullscreen
                  : AppBar(
                      toolbarHeight: 44,
                      backgroundColor: barColor,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 17),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      title: Text(
                        _activeRuntime()?.title ?? 'Terminal',
                        style: TextStyle(
                          color: appTheme.selectScreenCardTextColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      actions: [
                        // Font size controls
                        IconButton(
                          tooltip: 'Police −',
                          onPressed: () => _onTerminalFontSizeChanged(state.fontSize - 1),
                          icon: const Icon(Icons.text_decrease, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Police +',
                          onPressed: () => _onTerminalFontSizeChanged(state.fontSize + 1),
                          icon: const Icon(Icons.text_increase, size: 18),
                        ),
                        // Feature 3: 3-dot menu ⋯
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          tooltip: 'Plus d\'options',
                          color: isDark ? const Color(0xff252526) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: activeTerminalTheme.theme.selection,
                              width: 0.5,
                            ),
                          ),
                          onSelected: (value) async {
                            switch (value) {
                              case 'fullscreen':
                                setState(() => _isFullscreen = true);
                                break;
                              case 'split_h':
                                await _enableSplitView(Axis.horizontal);
                                break;
                              case 'split_v':
                                await _enableSplitView(Axis.vertical);
                                break;
                              case 'close_split':
                                setState(() { _isSplitView = false; _splitSessionId = null; });
                                break;
                              case 'font_reset':
                                _onTerminalFontSizeChanged(14);
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'fullscreen',
                              child: _menuItem(Icons.fullscreen_rounded, 'Plein écran', isDark),
                            ),
                            if (!_isSplitView) ...[
                              PopupMenuItem(
                                value: 'split_h',
                                child: _menuItem(Icons.vertical_split_rounded, 'Split horizontal', isDark),
                              ),
                              PopupMenuItem(
                                value: 'split_v',
                                child: _menuItem(Icons.horizontal_split_rounded, 'Split vertical', isDark),
                              ),
                            ] else
                              PopupMenuItem(
                                value: 'close_split',
                                child: _menuItem(Icons.close_fullscreen_rounded, 'Fermer le split', isDark),
                              ),
                            PopupMenuItem(
                              value: 'font_reset',
                              child: _menuItem(Icons.format_size_rounded, 'Réinitialiser police', isDark),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
              body: Column(
                children: [
                  // Feature 5: tab bar with rounded top corners
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(0),
                      topRight: Radius.circular(0),
                    ),
                    child: _buildSessionTabBar(state, appTheme, activeTerminalTheme),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: terminalContent,
                    ),
                  ),
                ],
              ),
            );

            // Feature 3: fullscreen overlay
            if (_isFullscreen) {
              return Stack(
                children: [
                  scaffold,
                  Positioned(
                    top: 0, left: 0, right: 0, bottom: 0,
                    child: Scaffold(
                      backgroundColor: isDark ? const Color(0xff121212) : Colors.white,
                      body: Stack(
                        children: [
                          Column(
                            children: [
                              // Slim fullscreen header
                              Container(
                                height: 40,
                                color: barColor,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.terminal_rounded, size: 16, color: Colors.grey.shade500),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _activeRuntime()?.title ?? 'Terminal',
                                        style: TextStyle(
                                          color: appTheme.selectScreenCardTextColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Quitter le plein écran',
                                      icon: const Icon(Icons.fullscreen_exit_rounded, size: 20),
                                      onPressed: () => setState(() => _isFullscreen = false),
                                    ),
                                  ],
                                ),
                              ),
                              _buildSessionTabBar(state, appTheme, activeTerminalTheme),
                              Expanded(child: terminalContent),
                            ],
                          ),
                          _buildExitBanner(),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return scaffold;
          },
        ),
      ),
    );
  }
}
