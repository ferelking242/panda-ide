import 'dart:async';
import 'dart:convert';

class LSPRequest {
  final int id;
  final String method;
  final Map<String, dynamic> params;

  LSPRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };
}

class LSPDiagnostic {
  final String message;
  final int line;
  final int character;
  final int severity; // 1: Error, 2: Warning

  LSPDiagnostic({
    required this.message,
    required this.line,
    required this.character,
    required this.severity,
  });

  factory LSPDiagnostic.fromJson(Map<String, dynamic> json) {
    final range = json['range'] as Map<String, dynamic>? ?? {};
    final start = range['start'] as Map<String, dynamic>? ?? {};
    return LSPDiagnostic(
      message: json['message'] as String? ?? '',
      line: start['line'] as int? ?? 0,
      character: start['character'] as int? ?? 0,
      severity: json['severity'] as int? ?? 1,
    );
  }
}

class LSPBridge {
  int _requestIdCounter = 1;
  final StreamController<List<LSPDiagnostic>> _diagnosticsController = StreamController.broadcast();

  Stream<List<LSPDiagnostic>> get onDiagnostics => _diagnosticsController.stream;

  LSPRequest buildInitializeRequest(String rootUri) {
    return LSPRequest(
      id: _requestIdCounter++,
      method: 'initialize',
      params: {
        'processId': null,
        'rootUri': rootUri,
        'capabilities': {
          'textDocument': {
            'completion': {'completionItem': {'snippetSupport': true}},
            'hover': {'contentFormat': ['markdown', 'plaintext']},
          }
        }
      },
    );
  }

  LSPRequest buildDidOpenRequest(String fileUri, String languageId, String text) {
    return LSPRequest(
      id: _requestIdCounter++,
      method: 'textDocument/didOpen',
      params: {
        'textDocument': {
          'uri': fileUri,
          'languageId': languageId,
          'version': 1,
          'text': text,
        }
      },
    );
  }

  LSPRequest buildCompletionRequest(String fileUri, int line, int character) {
    return LSPRequest(
      id: _requestIdCounter++,
      method: 'textDocument/completion',
      params: {
        'textDocument': {'uri': fileUri},
        'position': {'line': line, 'character': character},
      },
    );
  }

  void handleServerNotification(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      final method = json['method'] as String?;
      if (method == 'textDocument/publishDiagnostics') {
        final params = json['params'] as Map<String, dynamic>? ?? {};
        final diagnostics = (params['diagnostics'] as List<dynamic>?)
            ?.map((d) => LSPDiagnostic.fromJson(d as Map<String, dynamic>))
            .toList() ?? [];
        _diagnosticsController.add(diagnostics);
      }
    } catch (_) {}
  }
}
