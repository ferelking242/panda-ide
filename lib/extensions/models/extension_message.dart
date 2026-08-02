/// Modèle de message IPC entre Flutter et le process Node.js Extension Host.
/// Protocole : newline-delimited JSON sur stdin/stdout.
library;

enum IpcMessageType {
  /// Flutter → Node.js : appel de méthode (activate, deactivate, fireEvent)
  call,
  /// Node.js → Flutter : retour de résultat après un call
  ret,
  /// Node.js → Flutter : appel d'API vscode.* (l'extension demande qqch à l'IDE)
  apiCall,
  /// Flutter → Node.js : réponse à un apiCall
  apiReturn,
  /// Unidirectionnel : notification sans réponse attendue
  event,
  /// Erreur
  error,
}

class IpcMessage {
  /// ID unique de la transaction (incrémenté par l'émetteur).
  /// Les events ont id = 0.
  final int id;
  final IpcMessageType type;

  /// Nom de la méthode / API / event.
  final String method;

  /// Paramètres (pour call, apiCall, event).
  final List<dynamic> params;

  /// Résultat (pour ret, apiReturn).
  final dynamic result;

  /// Erreur (pour error).
  final String? error;

  const IpcMessage({
    required this.id,
    required this.type,
    required this.method,
    this.params = const [],
    this.result,
    this.error,
  });

  // ── Constructeurs de convenance ──────────────────────────────────────────

  /// Appel Flutter → Node.js (activer extension, envoyer un event éditeur, etc.)
  factory IpcMessage.call(int id, String method, [List<dynamic> params = const []]) =>
      IpcMessage(id: id, type: IpcMessageType.call, method: method, params: params);

  /// Retour Flutter → Node.js en réponse à un apiCall de l'extension.
  factory IpcMessage.apiReturn(int id, String method, dynamic result) =>
      IpcMessage(id: id, type: IpcMessageType.apiReturn, method: method, result: result);

  /// Retour Flutter → Node.js pour signaler une erreur lors d'un apiCall.
  factory IpcMessage.apiError(int id, String method, String error) =>
      IpcMessage(id: id, type: IpcMessageType.error, method: method, error: error);

  /// Event unidirectionnel Flutter → Node.js (ex: onDidChangeTextDocument).
  factory IpcMessage.event(String event, [dynamic data]) =>
      IpcMessage(id: 0, type: IpcMessageType.event, method: event, params: data != null ? [data] : []);

  // ── Sérialisation ────────────────────────────────────────────────────────

  factory IpcMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'call';
    final type = switch (typeStr) {
      'call'      => IpcMessageType.call,
      'ret'       => IpcMessageType.ret,
      'apiCall'   => IpcMessageType.apiCall,
      'apiReturn' => IpcMessageType.apiReturn,
      'event'     => IpcMessageType.event,
      _           => IpcMessageType.error,
    };

    return IpcMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: type,
      method: json['method'] as String? ?? '',
      params: (json['params'] as List?)?.cast<dynamic>() ?? const [],
      result: json['result'],
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      IpcMessageType.call      => 'call',
      IpcMessageType.ret       => 'ret',
      IpcMessageType.apiCall   => 'apiCall',
      IpcMessageType.apiReturn => 'apiReturn',
      IpcMessageType.event     => 'event',
      IpcMessageType.error     => 'error',
    };

    return {
      'id': id,
      'type': typeStr,
      'method': method,
      if (params.isNotEmpty) 'params': params,
      if (result != null) 'result': result,
      if (error != null) 'error': error,
    };
  }

  @override
  String toString() => 'IpcMessage($type, id=$id, method=$method)';
}
