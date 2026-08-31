import 'package:flutter/material.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

enum AgentActivityStatus { pending, running, completed, error }
enum AgentActivityType { thinking, tool, status, output }

// ── AgentActivityEvent ─────────────────────────────────────────────────────

class AgentActivityEvent {
  final String id;
  final DateTime timestamp;
  AgentActivityType type;
  AgentActivityStatus status;
  String label;
  String? toolName;
  Map<String, dynamic>? toolArgs;
  String? toolResult;
  String? outputText;
  Duration? duration;
  bool isExpanded;

  AgentActivityEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.status,
    required this.label,
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.outputText,
    this.duration,
    this.isExpanded = false,
  });
}

// ── toolHumanLabel ─────────────────────────────────────────────────────────

/// Map raw tool names + args → human-readable French labels.
/// NEVER returns "runShellCommand" or raw tool names.
String toolHumanLabel(String toolName, Map<String, dynamic> args) {
  final n = toolName.toLowerCase();
  if (n.contains('shell') || n.contains('command') || n.contains('bash')) {
    final cmd = (args['command'] ?? args['cmd'] ?? '').toString();
    if (cmd.contains('git clone')) return 'Cloning\u2026';
    if (cmd.contains('git push')) return 'Push vers GitHub\u2026';
    if (cmd.contains('git commit')) return 'Cr\u00e9ation du commit\u2026';
    if (cmd.contains('git pull')) return 'Pull en cours\u2026';
    if (cmd.contains('npm install') || cmd.contains('bun install') || cmd.contains('pip install')) {
      return 'Installation des d\u00e9pendances\u2026';
    }
    if (cmd.contains('flutter build')) return 'Build en cours\u2026';
    if (cmd.contains('flutter test') || cmd.contains('dart test')) return 'Tests en cours\u2026';
    if (cmd.contains('flutter pub get') || cmd.contains('dart pub get')) {
      return 'R\u00e9solution des d\u00e9pendances\u2026';
    }
    if (cmd.contains('rm ') || cmd.contains('del ')) return 'Suppression\u2026';
    if (cmd.contains('mkdir')) return 'Cr\u00e9ation de dossier\u2026';
    if (cmd.contains('cp ') || cmd.contains('mv ')) return 'D\u00e9placement\u2026';
    if (cmd.contains('curl') || cmd.contains('wget')) return 'T\u00e9l\u00e9chargement\u2026';
    if (cmd.contains('git ')) return 'Commande Git\u2026';
    final preview = cmd.length > 35 ? '${cmd.substring(0, 35)}\u2026' : cmd;
    return preview.isEmpty ? 'Ex\u00e9cution\u2026' : 'Ex\u00e9cution: $preview';
  }
  if (n.contains('read') || n.contains('open') || n.contains('view')) return 'Lecture du fichier\u2026';
  if (n.contains('write') || n.contains('edit') || n.contains('save') || n.contains('multi')) {
    return '\u00c9dition du fichier\u2026';
  }
  if (n.contains('search') || n.contains('grep') || n.contains('glob') || n.contains('find')) {
    return 'Recherche\u2026';
  }
  if (n.contains('list') || n.contains('dir')) return 'Exploration du dossier\u2026';
  if (n.contains('web') || n.contains('fetch') || n.contains('http') || n.contains('url')) {
    return 'Recherche sur internet\u2026';
  }
  if (n.contains('git')) return 'Commande Git\u2026';
  if (n.contains('delete') || n.contains('remove')) return 'Suppression\u2026';
  if (n.contains('agent') || n.contains('task') || n.contains('delegate')) {
    return 'D\u00e9l\u00e9gation\u2026';
  }
  return 'Action en cours\u2026';
}

// ── AgentActivityController ────────────────────────────────────────────────

/// State machine for the activity feed.
///
/// Priority: ACTIVE REAL TOOL > Narrative update > "Running"
/// A real tool is NEVER interrupted by thinking/text chunks.
/// Only completeTool(toolId) can end a running tool.
class AgentActivityController {
  final List<AgentActivityEvent> history = [];
  AgentActivityEvent? activeActivity;
  VoidCallback? _onUpdate;

  bool isToolRunning = false;
  String? activeToolId;

  void setOnUpdate(VoidCallback cb) => _onUpdate = cb;
  void _notify() => _onUpdate?.call();
  String _nextId() => 'act_${DateTime.now().microsecondsSinceEpoch}';

  /// Called once when the agent turn begins. Creates "Running" card.
  void startRun() {
    reset();
    activeActivity = AgentActivityEvent(
      id: _nextId(),
      timestamp: DateTime.now(),
      type: AgentActivityType.status,
      status: AgentActivityStatus.running,
      label: 'Generating...',
    );
    _notify();
  }

  /// Update label of active card. Ignored if a real tool is running.
  void updateNarrative(String label) {
    if (isToolRunning) return;
    if (activeActivity == null) return;
    activeActivity!.label = label;
    _notify();
  }

  /// Start a real tool. Moves current narrative to history.
  void startTool({required String toolId, required String toolName, required Map<String, dynamic> args}) {
    if (activeActivity != null) {
      activeActivity!.status = AgentActivityStatus.completed;
      activeActivity!.isExpanded = false;
      history.add(activeActivity!);
    }
    final label = toolHumanLabel(toolName, args);
    activeActivity = AgentActivityEvent(
      id: toolId,
      timestamp: DateTime.now(),
      type: AgentActivityType.tool,
      status: AgentActivityStatus.running,
      label: label,
      toolName: toolName,
      toolArgs: args,
    );
    isToolRunning = true;
    activeToolId = toolId;
    _notify();
  }

  /// Complete a tool. ONLY if toolId matches.
  void completeTool({required String toolId, String? result}) {
    if (activeToolId != toolId) return;
    final a = activeActivity;
    if (a == null) return;
    a.status = AgentActivityStatus.completed;
    a.toolResult = result;
    a.isExpanded = false;
    history.add(a);
    activeActivity = null;
    isToolRunning = false;
    activeToolId = null;
    // Create new "Running" card for next activity
    activeActivity = AgentActivityEvent(
      id: _nextId(),
      timestamp: DateTime.now(),
      type: AgentActivityType.status,
      status: AgentActivityStatus.running,
      label: 'Generating...',
    );
    _notify();
  }

  /// Fail a tool.
  void failTool({required String toolId, String? error}) {
    if (activeToolId != toolId) return;
    final a = activeActivity;
    if (a == null) return;
    a.status = AgentActivityStatus.error;
    a.toolResult = error;
    a.isExpanded = false;
    history.add(a);
    activeActivity = null;
    isToolRunning = false;
    activeToolId = null;
    _notify();
  }

  /// Finish the entire run.
  void finishRun({String? error}) {
    if (activeActivity != null) {
      if (error != null) {
        activeActivity!.status = AgentActivityStatus.error;
        activeActivity!.label = error;
      } else {
        activeActivity!.status = AgentActivityStatus.completed;
      }
      activeActivity!.isExpanded = false;
      history.add(activeActivity!);
      activeActivity = null;
    }
    isToolRunning = false;
    activeToolId = null;
    _notify();
  }

  void toggleExpand(String id) {
    for (final e in history) {
      if (e.id == id) {
        e.isExpanded = !e.isExpanded;
        _notify();
        return;
      }
    }
  }

  void reset() {
    history.clear();
    activeActivity = null;
    isToolRunning = false;
    activeToolId = null;
    _notify();
  }
}

// ── Utility functions ─────────────────────────────────────────────────────

Widget agentToolIconWidget(String name, double size, Color color) {
  final lower = name.toLowerCase();
  IconData icon;
  if (lower.contains('read') || lower.contains('file')) {
    icon = Icons.description_outlined;
  } else if (lower.contains('write') || lower.contains('create')) {
    icon = Icons.edit_note;
  } else if (lower.contains('search') || lower.contains('grep') || lower.contains('find')) {
    icon = Icons.search;
  } else if (lower.contains('terminal') || lower.contains('bash') || lower.contains('exec') || lower.contains('run')) {
    icon = Icons.terminal;
  } else if (lower.contains('git')) {
    icon = Icons.account_tree;
  } else if (lower.contains('delete') || lower.contains('remove')) {
    icon = Icons.delete_outline;
  } else if (lower.contains('list') || lower.contains('dir')) {
    icon = Icons.folder_open;
  } else {
    icon = Icons.build_outlined;
  }
  return Icon(icon, size: size, color: color);
}

String wrapLongTokensForDisplay(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAll('/', '/\u200B')
      .replaceAll('\\', '\\\u200B')
      .replaceAll('.', '.\u200B')
      .replaceAll('-', '-\u200B')
      .replaceAll('_', '_\u200B')
      .replaceAll(':', ':\u200B');
}
