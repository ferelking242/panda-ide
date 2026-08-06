import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/themes.dart';
import 'terminal_bridge.dart';

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

  Pty? pty;
  SSHSession? sshSession;
  String currentInput = '';
  VoidCallback? selectionListener;

  // ── Output capture (for bridge + error forwarding) ──────────────────────
  final StreamController<String> _rawOutputCtrl =
      StreamController<String>.broadcast();
  Stream<String> get rawOutput => _rawOutputCtrl.stream;
  final StringBuffer _outputBuffer = StringBuffer();
  int lastExitCode = 0;

  _TerminalRuntime({
    required this.sessionId,
    required this.title,
    required this.terminal,
    required this.controller,
  });

  bool get isRunning {
    if (sshSession != null) return true;
    return pty != null;
  }

  /// Feeds PTY output to the xterm widget, the raw stream, and the rolling
  /// capture buffer simultaneously.
  void feedOutput(String data) {
    terminal.write(data);
    if (!_rawOutputCtrl.isClosed) _rawOutputCtrl.add(data);
    _outputBuffer.write(data);
    // Keep only the last 50 KB to bound memory.
    if (_outputBuffer.length > 51200) {
      final s = _outputBuffer.toString();
      _outputBuffer
        ..clear()
        ..write(s.substring(s.length - 50000));
    }
    TerminalBridge.instance.notifyOutput(data);
  }

  /// Returns the most recently captured raw output (max 50 KB).
  String get recentOutput => _outputBuffer.toString();

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
    await _rawOutputCtrl.close();
    if (selectionListener != null) {
      controller.removeListener(selectionListener!);
    }
    controller.dispose();
  }
}

class _SetupTerminalState extends State<SetupTerminal>
    implements TerminalBridgeDelegate {
  late final TerminalSessionBloc _sessionBloc;
  late final List<SSHInfo> sshServerList;
  late final SSHPrivateKey? termuxInfo;
  final Map<String, _TerminalRuntime> _sessionRuntimes = {};
  AnimationStatus _terminalSelectionStatus = .dismissed;
  String _sharedPath = '';

  OverlayEntry? _selectionToolbarOverlay;
  bool _hasSelection = false;

  final ValueNotifier<List<String>?> _suggestionsNotifier = ValueNotifier(null);
  final ScrollController _suggestionScrollController = ScrollController();
  int _selectedSuggestionIndex = 0;
  List<String> _pathBinaries = [];

  // ── Error banner state: sessionId → exit code ──────────────────────────
  final Map<String, int> _errorSessions = {};

  @override
  void initState() {
    super.initState();
    TerminalBridge.instance.attach(this);
    _sessionBloc = TerminalSessionBloc(
      initialFontSize: _terminalFontSizeFromConfig(),
    );
    sshServerList = context.read<SSHServersCubit>().state.serverList.where((server) => server.isConnected).toList();
    termuxInfo = context.read<TermuxCubit>().state.termInfo;
    _bootstrapTerminalPage();
    _loadPathBinaries();
  }

  // ── TerminalBridgeDelegate ──────────────────────────────────────────────

  @override
  void writeToPty(String text) => sendToPty(text);

  @override
  Future<String> executeCommandAndCapture(
    String command, {
    required Duration timeout,
  }) async {
    final runtime = _activeRuntime();
    if (runtime == null) throw StateError('No active terminal session');
    if (runtime.pty == null) throw StateError('Terminal PTY is not running');

    final sentinel =
        '__PANDA_${DateTime.now().millisecondsSinceEpoch}__';
    // Wrap so stdout+stderr are captured; echo the sentinel + exit code.
    final wrapped = '{ $command; } 2>&1; echo "$sentinel"\$?';
    final completer = Completer<String>();
    final accum = StringBuffer();
    StreamSubscription<String>? sub;

    sub = runtime.rawOutput.listen((chunk) {
      accum.write(chunk);
      final clean = stripAnsiCodes(accum.toString());
      final idx = clean.indexOf(sentinel);
      if (idx >= 0 && !completer.isCompleted) {
        sub?.cancel();
        completer.complete(clean.substring(0, idx).trim());
      }
    });

    runtime.pty!.write(const Utf8Encoder().convert('$wrapped\n'));

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        sub?.cancel();
        final result = stripAnsiCodes(accum.toString()).trim();
        if (!completer.isCompleted) completer.complete(result);
        return result;
      });
    } catch (e) {
      sub?.cancel();
      rethrow;
    }
  }

  Future<void> _bootstrapTerminalPage() async {
    _sharedPath = await NativeChannel.getLibraryPath();
    final workDir = Directory(widget.projectDir);
    if (!workDir.existsSync()) {
      await workDir.create(recursive: true);
    }
    if (!mounted) return;
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
        _showSelectionToolbar();
      } else {
        _hideSelectionToolbar();
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
    SSHInfo? externalServer
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sessionTitle = title ?? _nextSessionTitle();
    final runtime = _TerminalRuntime(
      sessionId: id,
      title: sessionTitle,
      terminal: Terminal(platform: TerminalTargetPlatform.android),
      controller: TerminalController(selectionMode: SelectionMode.block),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New session created: $sessionTitle'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
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
      _hideSelectionToolbar();
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
      _hideSelectionToolbar();
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

  Future<void> _ensureBashRc() async {
    try {
      final bashrc = File('$homeDir/.bashrc');
      final aliases = [
        'alias ls="ls --color=auto"',
        'alias ll="ls -ll"',
        'alias la="ls -la"',
      ];
      if (!await bashrc.exists()) {
        await bashrc.create(recursive: true);
        await bashrc.writeAsString('${aliases.join('\n')}\n', flush: true);
        return;
      }

      final existing = await bashrc.readAsString();
      final missing = aliases.where((alias) => !existing.contains(alias)).toList();
      if (missing.isNotEmpty) {
        await bashrc.writeAsString('${existing.trimRight()}\n${missing.join('\n')}\n', flush: true);
      }
    } catch (_) {
    }
  }

  double _terminalFontSizeFromConfig() {
    try {
      final raw = context.read<ConfigBloc>().state.codeForgeConfig['terminalFontSize'];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? 14.0;
    } catch (_) {}
    return 14.0;
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
    if (fontSize > 32) fontSize = 32;
    _sessionBloc.add(UpdateTerminalFontSize(fontSize: fontSize));
    _saveTerminalFontSize(fontSize);
  }

  Future<void> _startPty(
    _TerminalRuntime runtime, {
    List<String> args = const [],
    SSHInfo? externalServer,
  }) async {
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
        runtime.terminal.write('\r\n\n[Program finished with exit code ${session.exitCode}]');
        _sessionBloc.add(
          UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false),
        );
      });

      return;
    }

    if (_sharedPath.isEmpty) {
      _sharedPath = await NativeChannel.getLibraryPath();
    }

    await _ensureBashRc();

    // Detect which runtimes are installed so we only add their dirs to PATH.
    final flutterInstalled =
        Directory('$runtimesDir/flutter/bin').existsSync();
    final androidSdkInstalled =
        Directory('$runtimesDir/android-sdk/platform-tools').existsSync();

    final pathParts = [
      binDir,
      if (flutterInstalled)  '$runtimesDir/flutter/bin',
      if (androidSdkInstalled) '$runtimesDir/android-sdk/platform-tools',
      if (androidSdkInstalled) '$runtimesDir/android-sdk/build-tools/current',
      '$runtimesDir/node/bin',
      '/bin',
      '/usr/bin',
      '/sbin',
      '/usr/sbin',
    ];

    final enVars = <String, String>{
      'HOME': homeDir,
      'PS1': ' \x1b[32m\\w \x1b[0m\$ ',
      'PATH': pathParts.join(':'),
      'PROMPT_DIRTRIM': '2',
      'ROXUM_SHARED_PATH': _sharedPath,
      'LD_LIBRARY_PATH': '$_sharedPath:$libDir:$runtimesDir/clang',
      'LD_PRELOAD': '$_sharedPath/libc++_shared.so',
      'PREFIX': appDir,
      'TMPDIR': tempDir,
      'JAVA_HOME': '$runtimesDir/java-21-openjdk',
      'GIT_EXEC_PATH': '$binDir/git-core',
      'GIT_SSL_CAINFO': '$certDir/cacert.pem',
      'RUSTFLAGS': '--sysroot $runtimesDir/rust',
      'GOROOT': '$runtimesDir/go',
      'CC': 'clang',
      // ── Flutter SDK (injected when $runtimesDir/flutter is present) ──────
      if (flutterInstalled) ...{
        'FLUTTER_ROOT'              : '$runtimesDir/flutter',
        'PUB_CACHE'                 : '$runtimesDir/flutter/.pub-cache',
        'PUB_HOSTED_URL'            : 'https://pub.dartlang.org',
        'FLUTTER_STORAGE_BASE_URL'  : 'https://storage.googleapis.com',
        'FLUTTER_SUPPRESS_ANALYTICS': 'true',
        'DART_VM_OPTIONS'           : '--disable-dart-dev',
      },
      // ── Android SDK (injected when platform-tools are present) ───────────
      if (androidSdkInstalled) ...{
        'ANDROID_HOME'    : '$runtimesDir/android-sdk',
        'ANDROID_SDK_ROOT': '$runtimesDir/android-sdk',
      },
    };

    final process = Pty.start(
      '$_sharedPath/libbash.so',
      workingDirectory: widget.projectDir,
      environment: enVars,
      rows: runtime.terminal.viewHeight,
      columns: runtime.terminal.viewWidth,
      arguments: args,
    );

    runtime.pty = process;
    _sessionBloc.add(
      UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: true),
    );

    process.output
      .cast<List<int>>()
      .transform(const Utf8Decoder())
      .listen(runtime.feedOutput);

    process.exitCode.then((code) {
      if (!_sessionRuntimes.containsKey(runtime.sessionId)) return;
      runtime.pty = null;
      runtime.lastExitCode = code;
      runtime.terminal.write('\r\n\n[Program finished with exit code $code]');
      _sessionBloc.add(
        UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false),
      );
      // Error banner + bridge notification
      if (code != 0) {
        TerminalBridge.instance.onCommandError
            ?.call(runtime.recentOutput, code);
        if (mounted) setState(() => _errorSessions[runtime.sessionId] = code);
      } else {
        if (mounted) setState(() => _errorSessions.remove(runtime.sessionId));
      }
    });

    runtime.terminal.onOutput = (data) {
      if (widget.readOnly) {
        return;
      }

      final activeSessionId = _sessionBloc.state.activeSessionId;
      process.write(const Utf8Encoder().convert(data));
      if (activeSessionId == runtime.sessionId) {
        _handleInputForAutocomplete(runtime, data);
      }
    };

    runtime.terminal.onResize = (w, h, pw, ph) {
      process.resize(h, w);
    };

    if (widget.readOnly) {
      _suggestionsNotifier.value = null;
      _hideSelectionToolbar();
      runtime.controller.clearSelection();
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

  void _showSelectionToolbar() {
    _hideSelectionToolbar();
    if (!mounted) return;

    final runtime = _activeRuntime();
    if (runtime == null) return;

    final overlay = Overlay.of(context);

    _selectionToolbarOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xff2d2d2d),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xff454545)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toolbarButton(
                      icon: Icons.copy,
                      label: 'Copy',
                      onTap: () {
                        final selectedText =
                            runtime.controller.selection != null
                            ? runtime.terminal.buffer.getText(
                                runtime.controller.selection!,
                              )
                            : '';
                        if (selectedText.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: selectedText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Copied to clipboard'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        }
                        runtime.controller.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: const Color(0xff454545),
                    ),
                    _toolbarButton(
                      icon: Icons.paste,
                      label: 'Paste',
                      onTap: () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (data?.text != null) {
                          runtime.pty?.write(
                            const Utf8Encoder().convert(data!.text!),
                          );
                        }
                        runtime.controller.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: const Color(0xff454545),
                    ),
                    _toolbarButton(
                      icon: Icons.search,
                      label: 'Search',
                      onTap: () {
                        final selectedText =
                            runtime.controller.selection != null
                            ? runtime.terminal.buffer.getText(
                                runtime.controller.selection!,
                              )
                            : '';
                        if (selectedText.isNotEmpty) {
                          runtime.pty?.write(
                            const Utf8Encoder().convert(
                              'grep -r "${selectedText.replaceAll('"', '\\"')}" .',
                            ),
                          );
                        }
                        runtime.controller.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: const Color(0xff454545),
                    ),
                    // ── Ask Agent ──────────────────────────────────────────
                    _toolbarButton(
                      icon: Icons.smart_toy_outlined,
                      label: 'Agent',
                      onTap: () {
                        final selectedText =
                            runtime.controller.selection != null
                            ? runtime.terminal.buffer.getText(
                                runtime.controller.selection!,
                              )
                            : '';
                        if (selectedText.isNotEmpty) {
                          TerminalBridge.instance.onSendToAgent?.call(
                            'Sortie du terminal :\n```\n$selectedText\n```\n\n'
                            'Explique ou aide-moi à corriger ceci.',
                          );
                        }
                        runtime.controller.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: const Color(0xff454545),
                    ),
                    _toolbarButton(
                      icon: Icons.close,
                      label: '',
                      onTap: () {
                        runtime.controller.clearSelection();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_selectionToolbarOverlay!);
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: label.isEmpty ? 8 : 12,
          vertical: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _hideSelectionToolbar() {
    _selectionToolbarOverlay?.remove();
    _selectionToolbarOverlay = null;
  }

  void sendToPty(String sequence) {
    final runtime = _activeRuntime();
    runtime?.pty?.write(const Utf8Encoder().convert(sequence));
  }

  // ── Copy / Paste helpers (used by keyboard bar) ────────────────────────

  void _copySelection() {
    final runtime = _activeRuntime();
    if (runtime?.controller.selection != null) {
      final text =
          runtime!.terminal.buffer.getText(runtime.controller.selection!);
      if (text.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copié'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      runtime.controller.clearSelection();
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final runtime = _activeRuntime();
      runtime?.pty?.write(const Utf8Encoder().convert(data!.text!));
    }
  }

  // ── Error banner ───────────────────────────────────────────────────────

  Widget _buildErrorBanner(_TerminalRuntime runtime, int exitCode) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xff3a1a1a),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade800.withOpacity(0.6)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: Colors.red.shade300),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Erreur (code $exitCode)',
                style: TextStyle(color: Colors.red.shade200, fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final raw = stripAnsiCodes(runtime.recentOutput);
                final snippet = raw.length > 3000
                    ? raw.substring(raw.length - 3000)
                    : raw;
                TerminalBridge.instance.onSendToAgent?.call(
                  'Cette commande a échoué avec le code $exitCode.\n\n'
                  'Sortie du terminal :\n```\n$snippet\n```\n\n'
                  'Aide-moi à comprendre et corriger l\'erreur.',
                );
                setState(() => _errorSessions.remove(runtime.sessionId));
              },
              icon: const Icon(Icons.smart_toy_outlined, size: 13),
              label: const Text(
                'Demander à l\'agent',
                style: TextStyle(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade300,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () =>
                  setState(() => _errorSessions.remove(runtime.sessionId)),
              child: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _setTerminalOutputWithAutocomplete({
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    VoidCallback? resetCallback,
  }) {
    final runtime = _activeRuntime();
    final process = runtime?.pty;
    if (runtime == null || process == null) return;

    runtime.terminal.onOutput = (data) {
      String sequence = '';

      if (ctrl) {
        if (data.length == 1) {
          int code = data.toUpperCase().codeUnitAt(0);
          if (code >= 65 && code <= 90) {
            sequence = String.fromCharCode(code - 64);
          }
        }
      } else if (alt) {
        sequence = '\x1b$data';
      } else if (shift) {
        sequence = data.toUpperCase();
      } else {
        sequence = data;
      }

      if (sequence.isNotEmpty) {
        process.write(const Utf8Encoder().convert(sequence));
        _handleInputForAutocomplete(runtime, sequence);
      }

      if ((ctrl || alt || shift) && resetCallback != null) {
        resetCallback();
        _setTerminalOutputWithAutocomplete();
      }
    };
  }

  @override
  void dispose() {
    TerminalBridge.instance.detach();
    _hideSelectionToolbar();
    _suggestionsNotifier.dispose();
    _suggestionScrollController.dispose();
    for (final runtime in _sessionRuntimes.values) {
      runtime.dispose();
    }
    _sessionRuntimes.clear();
    _sessionBloc.close();
    super.dispose();
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
                                    fontFamily: 'monospace',
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

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _sessionBloc,
      child: BlocListener<TerminalSessionBloc, TerminalSessionState>(
        listenWhen: (previous, current) => previous.activeSessionId != current.activeSessionId,
        listener: (context, state) {
          _hideSelectionToolbar();
          _suggestionsNotifier.value = null;
          _hasSelection = false;
        },
        child: BlocBuilder<TerminalSessionBloc, TerminalSessionState>(
          builder: (context, state) {
            final activeRuntime = _activeRuntime();
            final appTheme = context.watch<AppThemeBloc>().state.appTheme;
            final configState = context.watch<ConfigBloc>().state;
            final activeTerminalTheme = terminalThemePresetById(
              configState.codeForgeConfig['terminalTheme']?.toString(),
            );
            final terminalContent = activeRuntime == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: TerminalView(
                              activeRuntime.terminal,
                              readOnly: widget.readOnly,
                              padding: EdgeInsets.zero,
                              controller: activeRuntime.controller,
                              autofocus: true,
                              keyboardType: TextInputType.multiline,
                              theme: activeTerminalTheme.theme,
                              textStyle: TerminalStyle(
                                fontSize: state.fontSize
                              ),
                            ),
                          ),
                          if (widget.showKeyboardMenu)
                            TerminalKeyboardMenu(
                              onSendSequence: sendToPty,
                              onModifierChanged:
                                (ctrl, alt, shift, resetCallback) {
                                  _setTerminalOutputWithAutocomplete(
                                    ctrl: ctrl,
                                    alt: alt,
                                    shift: shift,
                                    resetCallback: resetCallback,
                                  );
                                },
                              onCopy: _copySelection,
                              onPaste: _pasteFromClipboard,
                            ),
                        ],
                      ),
                      _buildSuggestionBox(),
                      // ── Error banner ──────────────────────────────────────
                      if (_errorSessions.containsKey(activeRuntime.sessionId))
                        Positioned(
                          bottom: widget.showKeyboardMenu ? 102 : 8,
                          left: 8,
                          right: 8,
                          child: _buildErrorBanner(
                            activeRuntime,
                            _errorSessions[activeRuntime.sessionId]!,
                          ),
                        ),
                    ],
                  );

            if (!widget.useScaffold) {
              return terminalContent;
            }

            return Scaffold(
              appBar: AppBar(
                leading: Builder(
                  builder: (context) {
                    final sessionCount = state.sessions.length;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          tooltip: 'Open sessions drawer',
                          icon: const Icon(Icons.menu),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                        if (sessionCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: appTheme.editorPageToolSelectedBgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                sessionCount > 99 ? '99+' : '$sessionCount',
                                style: TextStyle(
                                  color: appTheme.editorPageToolSelectedColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                title: Text(
                  activeRuntime?.title ?? 'Terminal',
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: () => _onTerminalFontSizeChanged(state.fontSize - 1),
                    icon: Icon(Icons.zoom_out)
                  ),
                  IconButton(
                    onPressed: () => _onTerminalFontSizeChanged(state.fontSize + 1),
                    icon: Icon(Icons.zoom_in)
                  ),
                  IconButton(
                    tooltip: 'New session',
                    onPressed: () => _createSession(
                      makeActive: true,
                      showFeedback: true,
                    ),
                    icon: Row(
                      children: [
                        Icon(Icons.add),
                        if(sshServerList.isNotEmpty || termuxInfo != null) MenuAnchor(
                          style: MenuStyle(
                            backgroundColor: WidgetStatePropertyAll(appTheme.selectScreenCardsBg),
                            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: .circular(6)))
                          ),
                          animated: true,
                          onAnimationStatusChanged: (status) {
                            _terminalSelectionStatus = status;
                          },
                          menuChildren: [
                            ...sshServerList.map((server) =>
                              MenuItemButton(
                                onPressed: () {
                                  _createSession(
                                    makeActive: true,
                                    showFeedback: true,
                                    externalServer: server
                                  );
                                },
                                leadingIcon: Padding(
                                  padding: const EdgeInsets.only(left: 3),
                                  child: FaIcon(
                                    FontAwesomeIcons.server,
                                    color: appTheme.selectScreenCardTextColor,
                                    size: 20
                                  ),
                                ),
                                child: Text(
                                  server.name,
                                  style: TextStyle(
                                    color: appTheme.selectScreenCardTextColor
                                  )
                                ),
                              )
                            ),

                            if(termuxInfo != null && termuxInfo!.isConnected)
                            MenuItemButton(
                              onPressed: () {
                                _createSession(
                                  makeActive: true,
                                  showFeedback: true,
                                  externalServer: termuxInfo
                                );
                              },
                              leadingIcon: SvgPicture.asset(
                                "assets/icons/Termux.svg",
                                height: 20,
                                width: 20
                              ),
                              child: Text(
                                termuxInfo!.name,
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor
                                )
                              ),
                            )
                          ],
                          builder: (context, controller, child) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                if(_terminalSelectionStatus.isForwardOrCompleted){
                                  controller.close();
                                } else {
                                  controller.open();
                                }
                              },
                              child: Icon(
                                Icons.arrow_drop_down_rounded,
                                color: appTheme.selectScreenCardTextColor
                                        
                              )
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              drawer: _buildSessionDrawer(state, appTheme),
              body: terminalContent,
            );
          },
        ),
      ),
    );
  }
}

class TerminalKeyboardMenu extends StatefulWidget {
  final Function(String) onSendSequence;
  final Function(bool ctrl, bool alt, bool shift, VoidCallback resetCallback)
      onModifierChanged;
  final VoidCallback? onCopy;
  final Future<void> Function()? onPaste;

  const TerminalKeyboardMenu({
    super.key,
    required this.onSendSequence,
    required this.onModifierChanged,
    this.onCopy,
    this.onPaste,
  });

  @override
  State<TerminalKeyboardMenu> createState() => _TerminalKeyboardMenuState();
}

class _TerminalKeyboardMenuState extends State<TerminalKeyboardMenu> {
  bool isCtrlActive = false;
  bool isAltActive = false;
  bool isShiftActive = false;

  void _resetModifiers() {
    setState(() {
      isCtrlActive = false;
      isAltActive = false;
      isShiftActive = false;
    });
  }

  void _toggleCtrl() {
    setState(() {
      isCtrlActive = !isCtrlActive;
      if (isCtrlActive) {
        isAltActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(isCtrlActive, isAltActive, isShiftActive,
        _resetModifiers);
  }

  void _toggleAlt() {
    setState(() {
      isAltActive = !isAltActive;
      if (isAltActive) {
        isCtrlActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(isCtrlActive, isAltActive, isShiftActive,
        _resetModifiers);
  }

  void _toggleShift() {
    setState(() {
      isShiftActive = !isShiftActive;
      if (isShiftActive) {
        isCtrlActive = false;
        isAltActive = false;
      }
    });
    widget.onModifierChanged(isCtrlActive, isAltActive, isShiftActive,
        _resetModifiers);
  }

  Widget _kbBtn(
    String label, {
    VoidCallback? onTap,
    bool active = false,
    IconData? icon,
    double fontSize = 12,
  }) {
    final fg = active ? Colors.yellow : Colors.white;
    final bg = active
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.transparent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active
                ? Colors.yellow.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: icon != null
            ? Icon(icon, size: 14, color: fg)
            : Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: fontSize,
                  fontFamily: 'monospace',
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: Colors.white.withValues(alpha: 0.12),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: const Color(0xff181818),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Modifiers ────────────────────────────────────────────────
            _kbBtn('CTRL', onTap: _toggleCtrl, active: isCtrlActive),
            _kbBtn('ALT', onTap: _toggleAlt, active: isAltActive),
            _kbBtn('SHIFT', onTap: _toggleShift, active: isShiftActive),
            _kbBtn('ESC',
                onTap: () => widget.onSendSequence('\x1b')),
            _kbBtn('TAB',
                onTap: () => widget.onSendSequence('\t')),
            _divider(),
            // ── Arrows ───────────────────────────────────────────────────
            _kbBtn('', icon: Icons.arrow_back,
                onTap: () => widget.onSendSequence('\x1b[D')),
            _kbBtn('', icon: Icons.arrow_upward,
                onTap: () => widget.onSendSequence('\x1b[A')),
            _kbBtn('', icon: Icons.arrow_downward,
                onTap: () => widget.onSendSequence('\x1b[B')),
            _kbBtn('', icon: Icons.arrow_forward,
                onTap: () => widget.onSendSequence('\x1b[C')),
            _divider(),
            // ── Navigation ───────────────────────────────────────────────
            _kbBtn('HOME',
                onTap: () => widget.onSendSequence('\x1b[H')),
            _kbBtn('END',
                onTap: () => widget.onSendSequence('\x1b[F')),
            _kbBtn('PgUp',
                onTap: () => widget.onSendSequence('\x1b[5~'),
                fontSize: 11),
            _kbBtn('PgDn',
                onTap: () => widget.onSendSequence('\x1b[6~'),
                fontSize: 11),
            _divider(),
            // ── Copy / Paste ─────────────────────────────────────────────
            if (widget.onCopy != null)
              _kbBtn('', icon: Icons.copy, onTap: widget.onCopy),
            if (widget.onPaste != null)
              _kbBtn('', icon: Icons.paste,
                  onTap: () => widget.onPaste!()),
            _divider(),
            // ── Symbols ──────────────────────────────────────────────────
            for (final s in [
              '|', '&', ';', '~', '/', '\\', '`', '"', "'",
              '!', '#', '%', '^', '@', '*', '>', '<',
              '(', ')', '{', '}', '[', ']',
              '_', '-', '=', '+',
            ])
              _kbBtn(s, onTap: () => widget.onSendSequence(s)),
          ],
        ),
      ),
    );
  }
}
