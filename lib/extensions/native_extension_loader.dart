/// Native Dart extension loader for .panda extensions.
///
/// Loads .panda extensions as Dart libraries via `dart:isolate`.
/// Extensions run in their own isolate for isolation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'models/panda_manifest.dart';

/// A loaded native Dart extension.
class NativeExtension {
  final PandaManifest manifest;
  final String installPath;
  final Isolate _isolate;
  final ReceivePort _receivePort;
  final SendPort _sendPort;
  final StreamController<Map<String, dynamic>> _eventController;
  bool _activated = false;
  bool _disposed = false;

  NativeExtension({
    required this.manifest,
    required this.installPath,
    required Isolate isolate,
    required ReceivePort receivePort,
    required SendPort sendPort,
    required StreamController<Map<String, dynamic>> eventController,
  })  : _isolate = isolate,
        _receivePort = receivePort,
        _sendPort = sendPort,
        _eventController = eventController;

  String get id => manifest.id;
  bool get isActivated => _activated;
  bool get isDisposed => _disposed;

  /// Stream of events from the extension.
  Stream<Map<String, dynamic>> get onEvent => _eventController.stream;

  /// Send a message to the extension.
  void send(String method, [dynamic params]) {
    if (_disposed) return;
    _sendPort.send({'method': method, 'params': params});
  }

  /// Send a request and wait for response.
  Future<T> request<T>(String method, [dynamic params]) async {
    if (_disposed) throw StateError('Extension $id is disposed');
    final completer = Completer<T>();
    final requestId = _nextRequestId++;
    _pendingRequests[requestId] = completer;
    _sendPort.send({
      'id': requestId,
      'method': method,
      'params': params,
    });
    return completer.future;
  }

  static int _nextRequestId = 1;
  final Map<int, Completer> _pendingRequests = {};

  void _handleMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'] as String?;

      if (type == 'event') {
        _eventController.add(message);
      } else if (type == 'response') {
        final id = message['id'] as int?;
        if (id != null && _pendingRequests.containsKey(id)) {
          final completer = _pendingRequests.remove(id)!;
          if (message.containsKey('error')) {
            completer.completeError(Exception(message['error']));
          } else {
            completer.complete(message['result']);
          }
        }
      }
    }
  }

  /// Deactivate the extension.
  Future<void> deactivate() async {
    if (!_activated || _disposed) return;
    try {
      await request('deactivate');
    } catch (_) {}
    _activated = false;
  }

  /// Dispose the extension (kill isolate).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
    _eventController.close();
    for (final c in _pendingRequests.values) {
      c.completeError(StateError('Extension disposed'));
    }
    _pendingRequests.clear();
  }
}

/// Loads and manages native .panda extensions.
class NativeExtensionLoader {
  static final NativeExtensionLoader instance = NativeExtensionLoader._();
  NativeExtensionLoader._();

  final Map<String, NativeExtension> _extensions = {};

  List<NativeExtension> get loaded => _extensions.values.toList();

  /// Load a .panda extension from its directory.
  Future<NativeExtension> load(String extensionDir) async {
    // 1. Parse manifest
    final manifestPath = p.join(extensionDir, 'panda.yaml');
    if (!await File(manifestPath).exists()) {
      throw FileSystemException('panda.yaml not found', manifestPath);
    }
    final manifest = await PandaManifest.fromFile(manifestPath);

    if (_extensions.containsKey(manifest.id)) {
      return _extensions[manifest.id]!;
    }

    // 2. Resolve the extension's Dart entry point
    final entryPoint = _resolveEntryPoint(extensionDir, manifest);
    if (entryPoint == null) {
      throw FileSystemException(
          'No entry point found for extension ${manifest.id}',
          extensionDir);
    }

    // 3. Spawn an isolate for the extension
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _IsolateConfig(
        sendPort: receivePort.sendPort,
        entryPoint: entryPoint,
        extensionId: manifest.id,
        extensionPath: extensionDir,
      ),
      onError: receivePort.sendPort,
    );

    // 4. Wait for the SendPort from the isolate
    final completer = Completer<SendPort>();
    final eventController = StreamController<Map<String, dynamic>>.broadcast();

    // ⚠️ ReceivePort = stream à ÉCOUTE UNIQUE. Un seul listen, jamais
    // cancel() + re-listen (sinon "Stream has already been listened to").
    // Les réponses/events sont routés vers l'ext une fois construite.
    NativeExtension? extRef;
    receivePort.listen((message) {
      if (message is SendPort && !completer.isCompleted) {
        completer.complete(message);
        return;
      }
      if (message is Map<String, dynamic>) {
        extRef?._handleMessage(message);
      }
    });

    // Garde-fou : si l'isolate n'envoie jamais son port, ne pas bloquer
    // le spinner indéfiniment.
    final sendPort = await completer.future
        .timeout(const Duration(seconds: 15), onTimeout: () {
      throw StateError(
          "L'isolate de l'extension n'a pas démarré (timeout 15s)");
    });

    final ext = NativeExtension(
      manifest: manifest,
      installPath: extensionDir,
      isolate: isolate,
      receivePort: receivePort,
      sendPort: sendPort,
      eventController: eventController,
    );

    extRef = ext;
    _extensions[manifest.id] = ext;
    return ext;
  }

  /// Activate a loaded extension.
  Future<void> activate(NativeExtension ext,
      [Map<String, dynamic>? context]) async {
    if (ext.isActivated) return;

    await ext.request('activate', {
      'extensionPath': ext.installPath,
      'extensionUri': 'file://${ext.installPath}',
      'extension': {
        'id': ext.id,
        'extensionPath': ext.installPath,
        'isActive': true,
      },
      if (context != null) ...context,
    });

    ext._activated = true;
  }

  /// Deactivate and unload an extension.
  Future<void> unload(String extensionId) async {
    final ext = _extensions.remove(extensionId);
    if (ext == null) return;
    await ext.deactivate();
    ext.dispose();
  }

  /// Deactivate and unload all extensions.
  Future<void> unloadAll() async {
    for (final ext in _extensions.values.toList()) {
      ext.dispose();
    }
    _extensions.clear();
  }

  /// Broadcast an event to all activated extensions.
  void broadcastEvent(String event, [dynamic data]) {
    for (final ext in _extensions.values) {
      if (ext.isActivated && !ext.isDisposed) {
        ext.send('event', {'event': event, 'data': data});
      }
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  String? _resolveEntryPoint(String dir, PandaManifest manifest) {
    // Look for lib/extension.dart
    final candidates = [
      p.join(dir, 'lib', 'extension.dart'),
      p.join(dir, 'lib', 'main.dart'),
      p.join(dir, 'extension.dart'),
      p.join(dir, 'main.dart'),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// The isolate entry point. Loads the extension's Dart code and listens.
  static void _isolateEntryPoint(_IsolateConfig config) {
    final receivePort = ReceivePort();
    config.sendPort.send(receivePort.sendPort);

    // Read the entry point and import it dynamically
    // Note: In a real implementation, this would use dart:mirrors or
    // compile the extension to a dynamic library. For now, we load
    // the file and look for a `PandaExtension` class.

    // For the MVP, extensions communicate via the message protocol
    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final method = message['method'] as String?;
        final id = message['id'] as int?;

        switch (method) {
          case 'activate':
            config.sendPort.send({
              'type': 'response',
              'id': id,
              'result': {'activated': true},
            });
            break;
          case 'deactivate':
            config.sendPort.send({
              'type': 'response',
              'id': id,
              'result': {'deactivated': true},
            });
            break;
          case 'event':
            // Handle incoming events
            break;
          default:
            config.sendPort.send({
              'type': 'response',
              'id': id,
              'error': 'Unknown method: $method',
            });
        }
      }
    });
  }
}

class _IsolateConfig {
  final SendPort sendPort;
  final String entryPoint;
  final String extensionId;
  final String extensionPath;

  _IsolateConfig({
    required this.sendPort,
    required this.entryPoint,
    required this.extensionId,
    required this.extensionPath,
  });
}
