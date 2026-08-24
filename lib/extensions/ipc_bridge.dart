/// Pont IPC entre Flutter et un process Node.js Extension Host.
///
/// Protocole : newline-delimited JSON sur stdin/stdout.
/// Chaque ligne = un IpcMessage JSON complet.
///
/// Flutter → Node.js :  call (activate, events éditeur)
/// Node.js → Flutter :  apiCall (vscode.window.show..., etc.)
library;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'models/extension_message.dart';




typedef ApiCallHandler = Future<dynamic> Function(IpcMessage msg);

/// Gère la communication JSON-RPC avec un process Node.js.
class IpcBridge {
  final Process _process;
  final ApiCallHandler _onApiCall;

  int _nextId = 1;
  final Map<int, Completer<dynamic>> _pending = {};
  StreamSubscription<String>? _sub;
  bool _closed = false;

  IpcBridge._(this._process, this._onApiCall);

  // ── Factory ──────────────────────────────────────────────────────────────

  static Future<IpcBridge> attach(
    Process process,
    ApiCallHandler onApiCall,
  ) async {
    final bridge = IpcBridge._(process, onApiCall);
    bridge._listen();
    return bridge;
  }

  // ── API publique ─────────────────────────────────────────────────────────

  /// Envoie un call et attend le retour.
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    if (_closed) throw StateError('IpcBridge is closed');

    final id = _nextId++;
    final msg = IpcMessage.call(id, method, params);
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    _send(msg);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('IPC call "$method" timed out after 30s');
      },
    );
  }

  /// Envoie un event unidirectionnel (pas de réponse attendue).
  void fireEvent(String event, [dynamic data]) {
    if (_closed) return;
    _send(IpcMessage.event(event, data));
  }

  /// Ferme proprement le bridge et tue le process.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    // Annuler tous les pending
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('IpcBridge disposed'));
      }
    }
    _pending.clear();
    _process.kill();
    await _process.exitCode;
  }

  bool get isClosed => _closed;

  // ── Réception ────────────────────────────────────────────────────────────

  void _listen() {
    _sub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (e) => _closeWithError('stdout error: $e'),
          onDone: () => _closed = true,
        );

    // Les erreurs stderr sont loggées mais n'interrompent pas le bridge
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      // ignore: avoid_print
      print('[ExtHost stderr] $line');
    });
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      // ligne non-JSON (ex: console.log de l'extension) → on ignore
      return;
    }

    final msg = IpcMessage.fromJson(json);

    switch (msg.type) {
      case IpcMessageType.ret:
        // Réponse à un de nos calls
        final c = _pending.remove(msg.id);
        if (c != null && !c.isCompleted) {
          c.complete(msg.result);
        }

      case IpcMessageType.error:
        // Erreur en réponse à un de nos calls
        final c = _pending.remove(msg.id);
        if (c != null && !c.isCompleted) {
          c.completeError(Exception(msg.error ?? 'Unknown IPC error'));
        }

      case IpcMessageType.apiCall:
        // L'extension demande quelque chose à l'IDE → on traite et on répond
        _handleApiCall(msg);

      case IpcMessageType.event:
        // Notification unilatérale de l'extension (rare en direction Node→Flutter)
        // On les ignore pour l'instant (les events vont surtout Flutter→Node)
        break;

      default:
        break;
    }
  }

  Future<void> _handleApiCall(IpcMessage msg) async {
    try {
      final result = await _onApiCall(msg);
      _send(IpcMessage.apiReturn(msg.id, msg.method, result));
    } catch (e) {
      _send(IpcMessage.apiError(msg.id, msg.method, e.toString()));
    }
  }

  // ── Envoi ────────────────────────────────────────────────────────────────

  void _send(IpcMessage msg) {
    if (_closed) return;
    try {
      final line = '${jsonEncode(msg.toJson())}\n';
      _process.stdin.write(line);
    } catch (e) {
      // ignore: avoid_print
      print('[IpcBridge] send error: $e');
    }
  }

  void _closeWithError(String reason) {
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError(reason));
    }
    _pending.clear();
  }
}
