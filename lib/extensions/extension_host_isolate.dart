import 'dart:async';
import 'dart:isolate';

class ExtensionHostMessage {
  final String extensionId;
  final String action;
  final Map<String, dynamic> payload;

  ExtensionHostMessage({
    required this.extensionId,
    required this.action,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
    'extensionId': extensionId,
    'action': action,
    'payload': payload,
  };
}

class ExtensionHostIsolate {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isReady = false;

  bool get isReady => _isReady;

  Future<void> startHost() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);

    final completer = Completer<void>();
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isReady = true;
        completer.complete();
      } else if (message is Map<String, dynamic>) {
        _handleHostEvent(message);
      }
    });

    return completer.future;
  }

  void _handleHostEvent(Map<String, dynamic> message) {
    // Event callback from isolate extension host
  }

  void sendToHost(ExtensionHostMessage message) {
    if (_isReady && _sendPort != null) {
      _sendPort!.send(message.toJson());
    }
  }

  void stopHost() {
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isReady = false;
  }

  static void _isolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final action = message['action'] as String?;
        if (action == 'activate') {
          mainSendPort.send({
            'status': 'activated',
            'extensionId': message['extensionId'],
          });
        }
      }
    });
  }
}
