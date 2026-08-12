import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PandaRemoteGateway {
  HttpServer? _server;
  final int port;
  final String authToken;
  bool _isRunning = false;

  PandaRemoteGateway({
    this.port = 8080,
    required this.authToken,
  });

  bool get isRunning => _isRunning;

  Future<void> startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;

      _server!.listen((HttpRequest request) {
        if (request.headers.value('x-panda-auth') != authToken &&
            request.uri.queryParameters['token'] != authToken) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write('Unauthorized: Invalid token')
            ..close();
          return;
        }

        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then(_handleWebSocket);
        } else {
          _handleHttpRequest(request);
        }
      });
    } catch (_) {}
  }

  void _handleHttpRequest(HttpRequest request) {
    if (request.uri.path == '/status') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'online', 'ide': 'Panda IDE Mobile Remote Gateway'}))
        ..close();
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
    }
  }

  void _handleWebSocket(WebSocket socket) {
    socket.listen((message) {
      // Synchronize editor buffer and terminal commands with web client
      final response = jsonEncode({
        'type': 'ack',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'echo': message,
      });
      socket.add(response);
    });
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _isRunning = false;
  }
}
