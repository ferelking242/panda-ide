import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

typedef BridgeCommandHandler = Future<dynamic> Function(Map<String, dynamic> cmd);

/// GatewayWebViewBridge — serveur HTTP local (port 9221 par défaut)
///
/// Le module Python android_page.py envoie des commandes HTTP POST à ce
/// serveur. Le bridge les transmet à la WebView Flutter via le callback
/// [onCommand], qui exécute le JavaScript correspondant.
///
/// Protocole :
///   POST /cmd  { "action": "eval"|"navigate"|"ping", ... }
///   → 200 { "result": <valeur JSON> }
///   → 500 { "error": "message" }
class GatewayWebViewBridge {
  static const int defaultPort = 9221;

  final int port;
  BridgeCommandHandler? onCommand;

  HttpServer? _server;
  bool _running = false;

  GatewayWebViewBridge({this.port = defaultPort});

  bool get isRunning => _running;

  // ── Démarrage ──────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _running = true;
      debugPrint('[GatewayBridge] Listening on http://127.0.0.1:$port');
      _serve();
    } catch (e) {
      debugPrint('[GatewayBridge] Failed to bind port $port: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _running = false;
    debugPrint('[GatewayBridge] Stopped');
  }

  // ── Request handler ───────────────────────────────────────────────────────

  void _serve() {
    _server!.listen((HttpRequest req) async {
      // CORS
      req.response.headers
        ..add('Access-Control-Allow-Origin', '*')
        ..add('Access-Control-Allow-Methods', 'POST, OPTIONS')
        ..add('Access-Control-Allow-Headers', 'Content-Type')
        ..contentType = ContentType.json;

      if (req.method == 'OPTIONS') {
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }

      if (req.method != 'POST') {
        req.response.statusCode = 405;
        req.response.write(json.encode({'error': 'Method not allowed'}));
        await req.response.close();
        return;
      }

      Map<String, dynamic> body;
      try {
        final raw = await utf8.decoder.bind(req).join();
        body = json.decode(raw) as Map<String, dynamic>;
      } catch (e) {
        req.response.statusCode = 400;
        req.response.write(json.encode({'error': 'Invalid JSON: $e'}));
        await req.response.close();
        return;
      }

      try {
        final result = await _dispatch(body);
        req.response.statusCode = 200;
        req.response.write(json.encode({'result': result}));
      } catch (e) {
        req.response.statusCode = 500;
        req.response.write(json.encode({'error': e.toString()}));
      }

      await req.response.close();
    });
  }

  Future<dynamic> _dispatch(Map<String, dynamic> cmd) async {
    final action = cmd['action'] as String? ?? '';

    switch (action) {
      case 'ping':
        return 'pong';

      case 'eval':
      case 'navigate':
        if (onCommand == null) {
          throw Exception('No WebView attached to bridge — open the Gateway panel first');
        }
        return await onCommand!(cmd);

      default:
        throw Exception('Unknown action: $action');
    }
  }
}
