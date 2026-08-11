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
import './terminal_bridge.dart';

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
    this.isProot = false,
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

class _SetupTerminalState extends State<SetupTerminal> {
  late final TerminalSessionBloc _sessionBloc;
  late final List<SSHInfo> sshServerList;
  late final SSHPrivateKey? termuxInfo;
  final Map<String, _TerminalRuntime> _sessionRuntimes = {};
  AnimationStatus _terminalSelectionStatus = AnimationStatus.dismissed;
  String _sharedPath = '';
  late final PageController _pageController;
  bool _syncingPage = false;

  OverlayEntry? _selectionToolbarOverlay;
  bool _hasSelection = false;

  final ValueNotifier<List<String>?> _suggestionsNotifier = ValueNotifier(null);
  final ScrollController _suggestionScrollController = ScrollController();
  int _selectedSuggestionIndex = 0;
  List<String> _pathBinaries = [];

  // ── Feature 1: Exit code banner ────────────────────────────────────────────
  final ValueNotifier<_ExitBannerData?> _exitBannerNotifier = ValueNotifier(null);
  Timer? _exitBannerTimer;

  // ── Feature 3: Fullscreen ──────────────────────────────────────────────────
  bool _isFullscreen = false;

  // ── Feature 4: Split terminals ─────────────────────────────────────────────
  bool _isSplitView = false;
  String? _splitSessionId;
  Axis _splitAxis = Axis.horizontal;

  @override
  void initState() {
    super.initState();
    _sessionBloc = TerminalSessionBloc(
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
    SSHInfo? externalServer,
    bool useProot = false,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sessionTitle = title ?? _nextSessionTitle();
    final runtime = _TerminalRuntime(
      sessionId: id,
      title: sessionTitle,
      terminal: Terminal(platform: TerminalTargetPlatform.android),
      controller: TerminalController(selectionMode: SelectionMode.block),
      isProot: useProot,
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

    await _startPty(runtime, args: args, externalServer: externalServer, useProot: useProot);

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
    await _startPty(runtime, useProot: runtime.isProot);
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

      // ── Feature 2 : prompt oh-my-zsh style ──────────────────────────────
      const gitBranchFn = r'''# Git branch helper & Termux pkg helper
__git_branch() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  echo " \033[38;5;214m🌿 ${branch}\033[0m"
}
apk() {
  if [ -x "/data/data/com.panda.ide/bin/proot" ] && [ -d "/data/data/com.panda.ide/runtimes/alpine-linux" ]; then
    "/data/data/com.panda.ide/bin/proot" --rootfs="/data/data/com.panda.ide/runtimes/alpine-linux" -b /dev -b /proc -b /sys -w /root /sbin/apk "$@"
  else
    echo -e "\033[38;5;208m[Panda Linux]\033[0m L'environnement Alpine Linux n'est pas installé."
    echo -e "Téléchargez-le depuis la \033[36mMarketplace (Section Runtimes -> Alpine Linux)\033[0m."
  fi
}
pkg() {
  if [ -x "/data/data/com.panda.ide/bin/proot" ] && [ -d "/data/data/com.panda.ide/runtimes/alpine-linux" ]; then
    apk "$@"
  elif [ -x "/data/data/com.termux/files/usr/bin/pkg" ]; then
    /data/data/com.termux/files/usr/bin/pkg "$@"
  else
    echo -e "\033[38;5;208m[Panda Linux]\033[0m 'pkg' nécessite l'environnement Linux (Alpine)."
    echo -e "Téléchargez \033[36mAlpine Linux\033[0m depuis la Marketplace (Runtimes) pour installer tout paquet Linux (git, node, python...)."
  fi
}
apt() {
  pkg "$@"
}
winget() {
  echo -e "\033[38;5;208m[Panda Linux]\033[0m 'winget' est pour Windows. Sur Panda Linux Android, utilisez \033[1m'apk add <paquet>'\033[0m ou \033[1m'pkg install <paquet>'\033[0m."
}''';
      const richPS1 = r'''# Oh My Zsh / Starship Flash Prompt
export PS1='\['\033[38;5;141m\]🐼 panda \[\033[38;5;75m\]📁 \w\[\033[0m\]$(__git_branch) \[\033[38;5;118m\]➜\[\033[0m\] ' ''';
      final aliases = [
        'alias ls="ls --color=auto"',
        'alias ll="ls -la --color=auto"',
        'alias la="ls -la"',
        'alias grep="grep --color=auto"',
        'alias cp="cp -i"',
        'alias mv="mv -i"',
        'alias ..="cd .."',
        'alias ...="cd ../.."',
      ];

      final fullContent = '${gitBranchFn.trimRight()}\n${richPS1.trimRight()}\n${aliases.join('\n')}\n';

      if (!await bashrc.exists()) {
        await bashrc.create(recursive: true);
        await bashrc.writeAsString(fullContent, flush: true);
        return;
      }

      final existing = await bashrc.readAsString();
      final needsGitFn  = !existing.contains('__git_branch');
      final needsPS1    = !existing.contains('__git_branch') || !existing.contains("PS1=");
      final missingAliases = aliases.where((a) => !existing.contains(a)).toList();

      if (needsGitFn || needsPS1 || missingAliases.isNotEmpty) {
        final extra = StringBuffer();
        if (needsGitFn) extra.write('\n$gitBranchFn');
        if (needsPS1)   extra.write('\n$richPS1');
        if (missingAliases.isNotEmpty) extra.write('\n${missingAliases.join('\n')}\n');
        await bashrc.writeAsString(
          '${existing.trimRight()}\n${extra.toString().trimLeft()}\n',
          flush: true,
        );
      }
    } catch (_) {}
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
    _exitBannerTimer?.cancel();
    _exitBannerNotifier.value =
        _ExitBannerData(exitCode: code, sessionTitle: meta.title);
    _exitBannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _exitBannerNotifier.value = null;
    });
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

  // ── proot + Alpine helpers ─────────────────────────────────────────────────

  bool _isAlpineInstalled() {
    return File('$binDir/proot').existsSync() &&
        Directory('$runtimesDir/alpine-linux').existsSync();
  }

  Future<void> _startProotSession(_TerminalRuntime runtime) async {
    final prootBin = '$binDir/proot';
    final rootfsDir = '$runtimesDir/alpine-linux';

    if (!File(prootBin).existsSync()) {
      runtime.terminal.write(
        '\r\n\x1b[31m[proot binary not found. Install Alpine Linux from the Downloads section.]\x1b[0m\r\n',
      );
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
      return;
    }
    if (!Directory(rootfsDir).existsSync()) {
      runtime.terminal.write(
        '\r\n\x1b[31m[Alpine rootfs not found. Install Alpine Linux from the Downloads section.]\x1b[0m\r\n',
      );
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
      return;
    }

    final process = Pty.start(
      prootBin,
      arguments: [
        '--rootfs=$rootfsDir',
        '-b', '/dev',
        '-b', '/proc',
        '-b', '/sys',
        '-w', '/root',
        '/bin/sh',
      ],
      workingDirectory: rootfsDir,
      environment: {
        'HOME': '/root',
        'TERM': 'xterm-256color',
        'SHELL': '/bin/sh',
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        'TMPDIR': '/tmp',
        'PROOT_TMP_DIR': tempDir,
      },
      rows: runtime.terminal.viewHeight,
      columns: runtime.terminal.viewWidth,
    );

    runtime.pty = process;
    _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: true));

    process.output
      .cast<List<int>>()
      .transform(const Utf8Decoder())
      .listen(runtime.terminal.write);

    process.exitCode.then((code) {
      if (!_sessionRuntimes.containsKey(runtime.sessionId)) return;
      runtime.pty = null;
      runtime.terminal.write('\r\n\n[Alpine session ended with exit code $code]');
      _sessionBloc.add(UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false));
      _showExitBanner(runtime.sessionId, code);
    });

    runtime.terminal.onOutput = (data) {
      if (widget.readOnly) return;
      process.write(const Utf8Encoder().convert(data));
      final activeSessionId = _sessionBloc.state.activeSessionId;
      if (activeSessionId == runtime.sessionId) {
        _handleInputForAutocomplete(runtime, data);
      }
    };

    runtime.terminal.onResize = (w, h, pw, ph) {
      process.resize(h, w);
    };
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startPty(
    _TerminalRuntime runtime, {
    List<String> args = const [],
    SSHInfo? externalServer,
    bool useProot = false,
  }) async {
    if (useProot) {
      await _startProotSession(runtime);
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
      // PS1 is set by .bashrc (rich prompt with git branch) — keep a safe fallback
      'PS1': r'\[\033[38;5;141m\]🐼 panda \[\033[38;5;75m\]📁 \w\[\033[0m\] \[\033[38;5;118m\]➜\[\033[0m\] ',
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
      arguments: args.isNotEmpty ? args : ['--rcfile', '$homeDir/.bashrc', '-i'],
    );

    runtime.pty = process;
    _sessionBloc.add(
      UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: true),
    );

    process.output
      .cast<List<int>>()
      .transform(const Utf8Decoder())
      .listen(runtime.terminal.write);

    process.exitCode.then((code) {
      if (!_sessionRuntimes.containsKey(runtime.sessionId)) return;
      runtime.pty = null;
      runtime.terminal.write('\r\n\n[Program finished with exit code $code]');
      _sessionBloc.add(
        UpdateTerminalSessionStatus(id: runtime.sessionId, isRunning: false),
      );
      _showExitBanner(runtime.sessionId, code);
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
                    _toolbarButton(
                      icon: Icons.auto_awesome,
                      label: 'Agent',
                      onTap: () {
                        final selectedText =
                            runtime.controller.selection != null
                            ? runtime.terminal.buffer.getText(
                                runtime.controller.selection!,
                              )
                            : '';
                        if (selectedText.isNotEmpty) {
                          TerminalBridge.instance.sendToAgent(selectedText);
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
    _hideSelectionToolbar();
    _suggestionsNotifier.dispose();
    _suggestionScrollController.dispose();
    _pageController.dispose();
    for (final runtime in _sessionRuntimes.values) {
      runtime.dispose();
    }
    _sessionRuntimes.clear();
    _sessionBloc.close();
    _exitBannerTimer?.cancel();
    _exitBannerNotifier.dispose();
    super.dispose();
  }

  // ── Feature 1: Exit code overlay banner ─────────────────────────────────
  Widget _buildExitBanner() {
    return ValueListenableBuilder<_ExitBannerData?>(
      valueListenable: _exitBannerNotifier,
      builder: (context, data, _) {
        if (data == null) return const SizedBox.shrink();
        final isSuccess = data.exitCode == 0;
        final bgColor   = isSuccess ? const Color(0xff1b4332) : const Color(0xff4a1919);
        final bdColor   = isSuccess ? const Color(0xff40b06e) : const Color(0xffef5350);
        final fgColor   = isSuccess ? const Color(0xff86efac) : const Color(0xffef9a9a);
        return Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            shadowColor: bdColor.withValues(alpha: 0.4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: bdColor, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                    size: 18,
                    color: bdColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isSuccess
                          ? '✓  ${data.sessionTitle} — terminé avec succès (code 0)'
                          : '✗  ${data.sessionTitle} — exit code ${data.exitCode}',
                      style: TextStyle(
                        color: fgColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _exitBannerNotifier.value = null,
                    child: Icon(Icons.close_rounded, size: 15, color: fgColor.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Feature 4: Split terminal view ──────────────────────────────────────
  Widget _buildSingleTerminalPage(TerminalSessionState state, TerminalThemePreset activeTheme) {
    if (state.sessions.isEmpty) return const Center(child: CircularProgressIndicator());
    return PageView.builder(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
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
        return TerminalView(
          runtime.terminal,
          readOnly: widget.readOnly,
          padding: EdgeInsets.zero,
          controller: runtime.controller,
          autofocus: session.id == state.activeSessionId,
          keyboardType: TextInputType.multiline,
          theme: activeTheme.theme,
          textStyle: TerminalStyle(fontSize: state.fontSize),
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
                ? Border.all(color: const Color(0xff5090c8), width: 1.5)
                : Border.all(color: const Color(0xff3c3c3c), width: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: TerminalView(
              r.terminal,
              readOnly: widget.readOnly,
              padding: EdgeInsets.zero,
              controller: r.controller,
              autofocus: isActive,
              keyboardType: TextInputType.multiline,
              theme: activeTheme.theme,
              textStyle: TerminalStyle(fontSize: state.fontSize),
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

  Widget _buildSessionTabBar(TerminalSessionState state, AppTheme appTheme) {
    final isDark = appTheme.isDark;
    final bgColor = isDark ? const Color(0xff1a1a1a) : const Color(0xffe4e4e4);
    final activeTabColor = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final inactiveTextColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    final activeTextColor = isDark ? Colors.white : const Color(0xff1a1a1a);
    const accentColor = Color(0xff5090c8);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xff2e2e2e) : const Color(0xffcccccc),
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
                          color: isDark ? const Color(0xff383838) : const Color(0xffcccccc),
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
            color: isDark ? const Color(0xff252526) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isDark ? const Color(0xff3c3c3c) : const Color(0xffcccccc),
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
          onPressed: () => _createSession(makeActive: true, showFeedback: true),
          leadingIcon: Icon(Icons.terminal, color: appTheme.selectScreenCardTextColor, size: 18),
          child: Text('bash', style: TextStyle(color: appTheme.selectScreenCardTextColor)),
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
        MenuItemButton(
          onPressed: () => _createSession(
            makeActive: true,
            showFeedback: true,
            title: 'Alpine Linux',
            useProot: true,
          ),
          leadingIcon: Icon(Icons.terminal_rounded, color: Colors.blue.shade300, size: 18),
          child: Text('Alpine Linux (proot)', style: TextStyle(color: appTheme.selectScreenCardTextColor)),
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
          _hideSelectionToolbar();
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

            final terminalContent = Stack(
              children: [
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
                              color: isDark ? const Color(0xff3c3c3c) : const Color(0xffcccccc),
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
                    child: _buildSessionTabBar(state, appTheme),
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
                              _buildSessionTabBar(state, appTheme),
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

class TerminalKeyboardMenu extends StatefulWidget {
  final Function(String) onSendSequence;
  final Function(bool ctrl, bool alt, bool shift, VoidCallback resetCallback)
  onModifierChanged;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;

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
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleAlt() {
    setState(() {
      isAltActive = !isAltActive;
      if (isAltActive) {
        isCtrlActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleShift() {
    setState(() {
      isShiftActive = !isShiftActive;
      if (isShiftActive) {
        isCtrlActive = false;
        isAltActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Compact single-row scrollable keyboard bar — ~44px height vs old ~90px.
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );
    const activeStyle = TextStyle(
      color: Color(0xffffd700),
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );
    const divColor = Color(0xff454545);
    const chipBg   = Color(0xff2d2d2d);
    const activeBg = Color(0xff3a3000);
    const chipBorder = Color(0xff454545);
    const activeBorder = Color(0xffffd700);

    Widget chip(String label, VoidCallback onTap, {bool active = false}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: active ? activeBg : chipBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? activeBorder : chipBorder,
              width: 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(label, style: active ? activeStyle : baseStyle),
        ),
      );
    }

    Widget iconChip(IconData icon, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          width: 36,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: chipBorder, width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      );
    }

    Widget div() => Container(
      width: 1,
      height: 20,
      color: divColor,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );

    return Container(
      height: 44,
      color: const Color(0xff181818),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            chip('ESC',   () => widget.onSendSequence('\x1b')),
            chip('CTRL',  _toggleCtrl,  active: isCtrlActive),
            chip('ALT',   _toggleAlt,   active: isAltActive),
            chip('SHIFT', _toggleShift, active: isShiftActive),
            chip('TAB',   () => widget.onSendSequence('\t')),
            div(),
            iconChip(Icons.arrow_upward_rounded,  () => widget.onSendSequence('\x1b[A')),
            iconChip(Icons.arrow_downward_rounded, () => widget.onSendSequence('\x1b[B')),
            iconChip(Icons.arrow_back_rounded,    () => widget.onSendSequence('\x1b[D')),
            iconChip(Icons.arrow_forward_rounded, () => widget.onSendSequence('\x1b[C')),
            div(),
            chip('HOME',  () => widget.onSendSequence('\x1b[H')),
            chip('END',   () => widget.onSendSequence('\x1b[F')),
            chip('PgUp',  () => widget.onSendSequence('\x1b[5~')),
            chip('PgDn',  () => widget.onSendSequence('\x1b[6~')),
            div(),
            chip('|',  () => widget.onSendSequence('|')),
            chip('&',  () => widget.onSendSequence('&')),
            chip(';',  () => widget.onSendSequence(';')),
            chip('~',  () => widget.onSendSequence('~')),
            chip('/',  () => widget.onSendSequence('/')),
            chip('\\', () => widget.onSendSequence('\\')),
            chip('`',  () => widget.onSendSequence('`')),
            chip('"',  () => widget.onSendSequence('"')),
            chip("'",  () => widget.onSendSequence("'")),
            div(),
            chip('(',  () => widget.onSendSequence('(')),
            chip(')',  () => widget.onSendSequence(')')),
            chip('{',  () => widget.onSendSequence('{')),
            chip('}',  () => widget.onSendSequence('}')),
            chip('[',  () => widget.onSendSequence('[')),
            chip(']',  () => widget.onSendSequence(']')),
            chip('!',  () => widget.onSendSequence('!')),
            chip('#',  () => widget.onSendSequence('#')),
            chip('%',  () => widget.onSendSequence('%')),
            chip('^',  () => widget.onSendSequence('^')),
            chip('@',  () => widget.onSendSequence('@')),
            chip('*',  () => widget.onSendSequence('*')),
            chip('>',  () => widget.onSendSequence('>')),
            chip('<',  () => widget.onSendSequence('<')),
            div(),
            iconChip(Icons.copy_rounded,  () => widget.onCopy?.call()),
            iconChip(Icons.paste_rounded, () => widget.onPaste?.call()),
          ],
        ),
      ),
    );
  }
}
