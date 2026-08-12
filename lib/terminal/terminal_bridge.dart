/// TerminalBridge — singleton qui permet au terminal d'envoyer
/// du texte sélectionné directement à l'agent Panda et d'accéder aux sorties terminal.

class TerminalBridge {
  TerminalBridge._();
  static final TerminalBridge instance = TerminalBridge._();

  /// Callback installé par home.dart pour recevoir les messages du terminal.
  void Function(String text)? onSendToAgent;

  /// Vrai si home.dart a enregistré un listener.
  bool get isActive => onSendToAgent != null;

  /// Envoie [text] à l'agent (no-op si aucun listener n'est enregistré).
  void sendToAgent(String text) => onSendToAgent?.call(text);

  final List<String> _outputBuffer = [];
  static const int _maxBufferLines = 500;

  void appendOutput(String data) {
    final lines = data.split('\n');
    _outputBuffer.addAll(lines);
    if (_outputBuffer.length > _maxBufferLines) {
      _outputBuffer.removeRange(0, _outputBuffer.length - _maxBufferLines);
    }
  }

  String getRecentOutput([int lines = 100]) {
    if (_outputBuffer.isEmpty) return '(Aucune sortie terminal récente)';
    final count = lines > _outputBuffer.length ? _outputBuffer.length : lines;
    final slice = _outputBuffer.sublist(_outputBuffer.length - count);
    return slice.join('\n');
  }
}
