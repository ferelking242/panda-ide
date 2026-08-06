/// TerminalBridge — singleton qui permet au terminal d'envoyer
/// du texte sélectionné directement à l'agent Panda.
///
/// Usage côté terminal :
///   TerminalBridge.instance.sendToAgent(selectedText);
///
/// Usage côté home.dart (initState / dispose) :
///   TerminalBridge.instance.onSendToAgent = _sendToAgentFromBridge;
///   TerminalBridge.instance.onSendToAgent = null;
class TerminalBridge {
  TerminalBridge._();
  static final TerminalBridge instance = TerminalBridge._();

  /// Callback installé par home.dart pour recevoir les messages du terminal.
  void Function(String text)? onSendToAgent;

  /// Vrai si home.dart a enregistré un listener.
  bool get isActive => onSendToAgent != null;

  /// Envoie [text] à l'agent (no-op si aucun listener n'est enregistré).
  void sendToAgent(String text) => onSendToAgent?.call(text);
}
