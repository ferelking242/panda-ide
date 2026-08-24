/// Bridge vscode.tasks — Phase 11.
///
/// Permet aux extensions de déclarer et exécuter des tâches (build, test, etc.).
/// Les tâches sont exécutées via le terminal intégré (flutter_pty déjà présent).
///
/// Architecture :
///   Extension → vscode.tasks.registerTaskProvider → TasksBridge.registerProvider()
///   Extension → vscode.tasks.executeTask(task) → lance dans flutter_pty
///   Flutter UI → affiche les tâches disponibles / en cours
library;
import 'package:flutter/foundation.dart';



// ── Modèles ─────────────────────────────────────────────────────────────────

/// Représente une tâche définie par une extension.
class VsTask {
  final String name;
  final String type;          // 'shell', 'process', etc.
  final String? detail;
  final String? command;      // command à lancer
  final List<String> args;
  final String? cwd;
  final Map<String, String> env;
  final String? group;        // 'build', 'test', 'none', etc.
  final bool isBackground;
  final String? presentationReveal; // 'always', 'silent', 'never'
  final String extensionId;
  final String taskId;

  const VsTask({
    required this.name,
    required this.type,
    this.detail,
    this.command,
    this.args = const [],
    this.cwd,
    this.env = const {},
    this.group,
    this.isBackground = false,
    this.presentationReveal,
    required this.extensionId,
    required this.taskId,
  });

  factory VsTask.fromJson(Map<String, dynamic> json, String extensionId, String taskId) {
    final exec = json['execution'] as Map<String, dynamic>? ?? {};
    return VsTask(
      name: json['name'] as String? ?? 'Task',
      type: json['type'] as String? ?? 'shell',
      detail: json['detail'] as String?,
      command: exec['command'] as String? ?? json['command'] as String?,
      args: (exec['args'] as List? ?? json['args'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      cwd: exec['cwd'] as String? ?? json['cwd'] as String?,
      env: (exec['env'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      group: json['group'] as String?,
      isBackground: json['isBackground'] as bool? ?? false,
      presentationReveal: json['presentation']?['reveal'] as String?,
      extensionId: extensionId,
      taskId: taskId,
    );
  }
}

/// Une tâche en cours d'exécution.
class TaskExecution {
  final String executionId;
  final VsTask task;
  bool isRunning;
  int? exitCode;
  final DateTime startTime;

  TaskExecution({
    required this.executionId,
    required this.task,
  }) : isRunning = true,
       startTime = DateTime.now();
}

// ── Bridge singleton ──────────────────────────────────────────────────────────

class TasksBridge extends ChangeNotifier {
  static final TasksBridge instance = TasksBridge._();
  TasksBridge._();

  final Map<String, List<VsTask>> _providerTasks = {}; // extensionId → tasks
  final Map<String, TaskExecution> _executions = {};   // executionId → execution
  int _execCounter = 0;

  // Callback pour lancer une commande dans le terminal flutter_pty
  // À brancher depuis main.dart / terminal widget
  Future<void> Function(String command, String? cwd, Map<String, String> env)? launchInTerminal;

  List<VsTask> get allTasks =>
      _providerTasks.values.expand((t) => t).toList();

  List<TaskExecution> get activeExecutions =>
      _executions.values.where((e) => e.isRunning).toList();

  // ── API appelée depuis ExtensionApiRouter ──────────────────────────────────

  /// vscode.tasks.registerTaskProvider(type, provider)
  /// → L'extension push ses tâches directement depuis JS via tasks.provideTasks()
  void registerTaskProvider(String extensionId, String type) {
    _providerTasks.putIfAbsent(extensionId, () => []);
    debugPrint('[TasksBridge] Provider registered for type=$type ext=$extensionId');
  }

  /// Reçu quand l'extension répond à provideTasks()
  void setProviderTasks(String extensionId, List<dynamic> tasks) {
    final id = extensionId;
    int counter = 0;
    _providerTasks[id] = tasks
        .whereType<Map<String, dynamic>>()
        .map((t) => VsTask.fromJson(t, id, '${id}_task_${counter++}'))
        .toList();
    notifyListeners();
  }

  /// vscode.tasks.fetchTasks(filter?)
  Future<List<VsTask>> fetchTasks({String? type}) async {
    final all = allTasks;
    if (type == null) return all;
    return all.where((t) => t.type == type).toList();
  }

  /// vscode.tasks.executeTask(task)
  Future<String?> executeTask(Map<String, dynamic> taskJson, String extensionId) async {
    final taskId = taskJson['_taskId'] as String? ?? 'unknown';
    final task = allTasks.firstWhere(
      (t) => t.taskId == taskId,
      orElse: () => VsTask.fromJson(taskJson, extensionId, taskId),
    );

    final execId = 'exec_${_execCounter++}';
    final execution = TaskExecution(executionId: execId, task: task);
    _executions[execId] = execution;
    notifyListeners();

    // Lance dans le terminal si disponible
    if (task.command != null && launchInTerminal != null) {
      try {
        final cmd = [task.command!, ...task.args].join(' ');
        await launchInTerminal!(cmd, task.cwd, task.env);
      } catch (e) {
        debugPrint('[TasksBridge] executeTask error: $e');
      }
    }

    return execId;
  }

  void taskFinished(String execId, int exitCode) {
    final exec = _executions[execId];
    if (exec == null) return;
    exec.isRunning = false;
    exec.exitCode = exitCode;
    notifyListeners();
  }

  void unregisterProvider(String extensionId) {
    _providerTasks.remove(extensionId);
    notifyListeners();
  }
}
