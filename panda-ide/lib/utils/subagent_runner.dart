import 'dart:async';

enum SubagentStatus { ready, running, completed, failed }

class SubagentTask {
  final String id;
  final String description;
  SubagentStatus status;
  String result;
  DateTime createdAt;

  SubagentTask({
    required this.id,
    required this.description,
    this.status = SubagentStatus.ready,
    this.result = '',
    required this.createdAt,
  });
}

class SubagentRunner {
  static final Map<String, SubagentTask> _tasks = {};

  static SubagentTask spawnSubagent(String description) {
    final id = 'subagent_${DateTime.now().millisecondsSinceEpoch}';
    final task = SubagentTask(
      id: id,
      description: description,
      status: SubagentStatus.running,
      createdAt: DateTime.now(),
    );
    _tasks[id] = task;

    // Simulate async execution or link to AgentRunner sub-task
    Future.delayed(const Duration(seconds: 3), () {
      task.status = SubagentStatus.completed;
      task.result = 'Tâche sous-agent "$description" exécutée avec succès.';
    });

    return task;
  }

  static SubagentTask? getTask(String id) => _tasks[id];

  static List<SubagentTask> getAllTasks() => _tasks.values.toList();
}
