/// Bridge vscode.debug — Debug Adapter Protocol (DAP) — Phase 12.
///
/// Implémente l'interface DAP (JSON over TCP socket) pour connecter les
/// debug adapters des extensions (Python debugpy, Node.js inspector, etc.).
///
/// Architecture :
///   Extension → vscode.debug.startDebugging(config) → DebugBridge.startSession()
///   DebugBridge → lance le debug adapter (via flutter_pty ou Process)
///   DebugBridge ↔ Adapter : protocole DAP JSON over TCP socket
///   Flutter UI ← DebugBridge : breakpoints, variables, call stack, console
///
/// DAP spec : https://microsoft.github.io/debug-adapter-protocol/
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

library;



// ── DAP types ─────────────────────────────────────────────────────────────────

class DapMessage {
  final int seq;
  final String type; // 'request' | 'response' | 'event'

  // Request
  final String? command;
  final dynamic arguments;

  // Response
  final int? requestSeq;
  final bool? success;
  final dynamic body;
  final String? message;

  // Event
  final String? event;

  const DapMessage({
    required this.seq,
    required this.type,
    this.command,
    this.arguments,
    this.requestSeq,
    this.success,
    this.body,
    this.message,
    this.event,
  });

  factory DapMessage.request(int seq, String command, dynamic args) =>
      DapMessage(seq: seq, type: 'request', command: command, arguments: args);

  factory DapMessage.fromJson(Map<String, dynamic> json) => DapMessage(
    seq: (json['seq'] as num?)?.toInt() ?? 0,
    type: json['type'] as String? ?? 'request',
    command: json['command'] as String?,
    arguments: json['arguments'],
    requestSeq: (json['request_seq'] as num?)?.toInt(),
    success: json['success'] as bool?,
    body: json['body'],
    message: json['message'] as String?,
    event: json['event'] as String?,
  );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'seq': seq, 'type': type};
    if (command != null) m['command'] = command;
    if (arguments != null) m['arguments'] = arguments;
    if (requestSeq != null) m['request_seq'] = requestSeq;
    if (success != null) m['success'] = success;
    if (body != null) m['body'] = body;
    if (message != null) m['message'] = message;
    if (event != null) m['event'] = event;
    return m;
  }

  /// Encode en DAP wire format : "Content-Length: N\r\n\r\n{json}"
  List<int> encode() {
    final json = jsonEncode(toJson());
    final bytes = utf8.encode(json);
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';
    return [...utf8.encode(header), ...bytes];
  }
}

// ── DebugSession ───────────────────────────────────────────────────────────────

class DebugSession {
  final String sessionId;
  final String name;
  final Map<String, dynamic> config;
  final String extensionId;

  bool _running = false;
  Socket? _socket;
  StreamSubscription? _sub;

  int _nextSeq = 1;
  final Map<int, Completer<DapMessage>> _pending = {};
  final _messageController = StreamController<DapMessage>.broadcast();

  DebugSession({
    required this.sessionId,
    required this.name,
    required this.config,
    required this.extensionId,
  });

  bool get isRunning => _running;
  Stream<DapMessage> get messages => _messageController.stream;

  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port)
        .timeout(const Duration(seconds: 10));
    _running = true;

    final buffer = StringBuffer();
    int? expectedLength;

    _sub = _socket!.cast<List<int>>().transform(utf8.decoder).listen((chunk) {
      buffer.write(chunk);
      _processBuffer(buffer, (msg) {
        _handleMessage(msg);
      });
    }, onError: (e) {
      debugPrint('[DAP] Socket error: $e');
      dispose();
    }, onDone: () {
      _running = false;
    });
  }

  void _processBuffer(StringBuffer buf, void Function(DapMessage) handler) {
    // DAP wire format: "Content-Length: N\r\n\r\n{json}"
    final str = buf.toString();
    int pos = 0;

    while (pos < str.length) {
      final headerEnd = str.indexOf('\r\n\r\n', pos);
      if (headerEnd < 0) break;

      final header = str.substring(pos, headerEnd);
      final lengthMatch = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (lengthMatch == null) { pos = headerEnd + 4; continue; }

      final length = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + length;

      if (str.length < bodyEnd) break;

      final body = str.substring(bodyStart, bodyEnd);
      pos = bodyEnd;

      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        handler(DapMessage.fromJson(json));
      } catch (e) {
        debugPrint('[DAP] Parse error: $e');
      }
    }

    // Keep unprocessed part
    if (pos > 0 && pos < str.length) {
      final remaining = str.substring(pos);
      buf.clear();
      buf.write(remaining);
    } else if (pos >= str.length) {
      buf.clear();
    }
  }

  void _handleMessage(DapMessage msg) {
    _messageController.add(msg);

    if (msg.type == 'response' && msg.requestSeq != null) {
      final c = _pending.remove(msg.requestSeq);
      if (c != null && !c.isCompleted) c.complete(msg);
    }
  }

  Future<DapMessage> send(String command, dynamic args) async {
    if (!_running || _socket == null) {
      throw StateError('Debug session not connected');
    }
    final seq = _nextSeq++;
    final msg = DapMessage.request(seq, command, args);
    final completer = Completer<DapMessage>();
    _pending[seq] = completer;
    _socket!.add(msg.encode());
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(seq);
        throw TimeoutException('DAP "$command" timed out');
      },
    );
  }

  // ── Common DAP requests ────────────────────────────────────────────────────

  Future<void> initialize() async {
    await send('initialize', {
      'adapterID': 'panda',
      'clientID': 'panda-ide',
      'clientName': 'Panda IDE',
      'locale': 'en',
      'linesStartAt1': true,
      'columnsStartAt1': true,
      'pathFormat': 'path',
      'supportsVariableType': true,
      'supportsRunInTerminalRequest': false,
    });
  }

  Future<void> launch(Map<String, dynamic> config) async {
    await send('launch', config);
  }

  Future<void> pause(int threadId) async {
    await send('pause', {'threadId': threadId});
  }

  Future<void> continueExecution(int threadId) async {
    await send('continue', {'threadId': threadId});
  }

  Future<void> stepOver(int threadId) async {
    await send('next', {'threadId': threadId});
  }

  Future<void> stepIn(int threadId) async {
    await send('stepIn', {'threadId': threadId});
  }

  Future<void> stepOut(int threadId) async {
    await send('stepOut', {'threadId': threadId});
  }

  Future<List<Map<String, dynamic>>> getStackTrace(int threadId) async {
    final r = await send('stackTrace', {'threadId': threadId});
    if (r.success != true) return [];
    final frames = (r.body?['stackFrames'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return frames;
  }

  Future<List<Map<String, dynamic>>> getScopes(int frameId) async {
    final r = await send('scopes', {'frameId': frameId});
    if (r.success != true) return [];
    return (r.body?['scopes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<List<Map<String, dynamic>>> getVariables(int variablesReference) async {
    final r = await send('variables', {'variablesReference': variablesReference});
    if (r.success != true) return [];
    return (r.body?['variables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> setBreakpoints(String path, List<int> lines) async {
    await send('setBreakpoints', {
      'source': {'path': path},
      'breakpoints': lines.map((l) => {'line': l}).toList(),
    });
  }

  Future<void> terminateSession() async {
    try {
      await send('terminate', {});
    } catch (_) {}
    dispose();
  }

  void dispose() {
    _running = false;
    _sub?.cancel();
    _socket?.close();
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Session disposed'));
    }
    _pending.clear();
    _messageController.close();
  }
}

// ── Bridge singleton ──────────────────────────────────────────────────────────

class DebugBridge extends ChangeNotifier {
  static final DebugBridge instance = DebugBridge._();
  DebugBridge._();

  final Map<String, DebugSession> _sessions = {};
  int _sessionCounter = 0;

  DebugSession? get activeSession =>
      _sessions.values.firstWhereOrNull((s) => s.isRunning);

  List<DebugSession> get allSessions => _sessions.values.toList();

  // Callback to fire IPC event to extension
  void Function(String extensionId, String event, dynamic data)? fireEvent;

  // ── API appelée depuis ExtensionApiRouter ──────────────────────────────────

  /// vscode.debug.startDebugging(folder, nameOrConfig)
  Future<String?> startDebugging({
    required String extensionId,
    required Map<String, dynamic> config,
  }) async {
    final sessionId = 'debug_${_sessionCounter++}';
    final name = config['name'] as String? ?? 'Debug Session';

    final session = DebugSession(
      sessionId: sessionId,
      name: name,
      config: config,
      extensionId: extensionId,
    );

    _sessions[sessionId] = session;

    // Forward DAP events to extension
    session.messages.listen((msg) {
      if (msg.type == 'event') {
        fireEvent?.call(extensionId, 'debug.event.${msg.event}.$sessionId', msg.body);
      }
    });

    notifyListeners();

    // Notify extension that session started
    fireEvent?.call(extensionId, 'debug.sessionStarted.$sessionId', {
      'id': sessionId,
      'name': name,
      'type': config['type'],
    });

    return sessionId;
  }

  /// Connect to an already-running debug adapter at host:port
  Future<void> connectSession(String sessionId, String host, int port) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    try {
      await session.connect(host, port);
      await session.initialize();
      await session.launch(session.config);
      notifyListeners();
    } catch (e) {
      debugPrint('[DebugBridge] Connect error: $e');
      _sessions.remove(sessionId);
      notifyListeners();
    }
  }

  /// vscode.debug.stopDebugging(session?)
  Future<void> stopDebugging(String? sessionId) async {
    if (sessionId != null) {
      await _sessions[sessionId]?.terminateSession();
      _sessions.remove(sessionId);
    } else {
      // Stop all sessions
      for (final s in _sessions.values) {
        await s.terminateSession();
      }
      _sessions.clear();
    }
    notifyListeners();
  }

  DebugSession? getSession(String sessionId) => _sessions[sessionId];

  void disposeAll() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    notifyListeners();
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
