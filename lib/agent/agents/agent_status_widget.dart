import 'package:flutter/material.dart';

import '../events/event_ui_bridge.dart';
import '../../ui/agent_runner.dart' show AgentPhase;

/// Compact agent status display showing current phase and active operations.
///
/// Appears at the top of the agent panel to show what the agent is doing.
class AgentStatusWidget extends StatelessWidget {
  final AgentUiState uiState;
  final bool isDark;

  const AgentStatusWidget({
    super.key,
    required this.uiState,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: uiState,
      builder: (context, _) {
        if (!uiState.isGenerating && uiState.phase == AgentPhase.idle) {
          return const SizedBox.shrink();
        }

        final fg = isDark ? Colors.grey[300]! : Colors.grey[700]!;
        final bg = isDark ? const Color(0xff1a1a2e) : const Color(0xfff5f5f8);

        final (icon, label) = _getStateInfo();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (uiState.phase == AgentPhase.thinking ||
                  uiState.phase == AgentPhase.streaming)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _phaseColor(),
                  ),
                )
              else
                Icon(icon, size: 14, color: _phaseColor()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (uiState.error != null)
                Icon(Icons.error_outline, size: 14, color: Colors.red),
            ],
          ),
        );
      },
    );
  }

  (IconData, String) _getStateInfo() {
    switch (uiState.phase) {
      case AgentPhase.idle:
        return (Icons.pause, 'En attente');
      case AgentPhase.thinking:
        return (Icons.psychology, 'Réflexion…');
      case AgentPhase.streaming:
        return (Icons.text_fields, 'Génération…');
      case AgentPhase.toolRunning:
        return (Icons.build, '🔧 ${uiState.currentTool}');
      case AgentPhase.toolDone:
        return (Icons.check, 'Terminé');
      case AgentPhase.done:
        return (Icons.check_circle, 'Terminé');
      case AgentPhase.error:
        return (Icons.error, 'Erreur: ${uiState.error}');
      default:
        return (Icons.help_outline, 'Inconnu');
    }
  }

  Color _phaseColor() {
    switch (uiState.phase) {
      case AgentPhase.thinking:
        return Colors.purple;
      case AgentPhase.streaming:
        return Colors.blue;
      case AgentPhase.toolRunning:
      case AgentPhase.toolDone:
        return Colors.orange;
      case AgentPhase.done:
        return Colors.green;
      case AgentPhase.error:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
