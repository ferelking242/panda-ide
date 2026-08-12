import 'dart:io';

class PandaCheckpoint {
  final String id;
  final String description;
  final DateTime timestamp;
  final Map<String, String> fileSnapshots; // filePath -> content

  PandaCheckpoint({
    required this.id,
    required this.description,
    required this.timestamp,
    required this.fileSnapshots,
  });
}

class AgentCheckpointManager {
  static final AgentCheckpointManager _instance = AgentCheckpointManager._internal();
  factory AgentCheckpointManager() => _instance;
  AgentCheckpointManager._internal();

  final List<PandaCheckpoint> _checkpoints = [];

  List<PandaCheckpoint> get checkpoints => List.unmodifiable(_checkpoints);

  Future<PandaCheckpoint> createCheckpoint(String description, List<String> filePaths) async {
    final Map<String, String> snapshots = {};
    for (var path in filePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          snapshots[path] = await file.readAsString();
        }
      } catch (_) {}
    }

    final checkpoint = PandaCheckpoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      description: description,
      timestamp: DateTime.now(),
      fileSnapshots: snapshots,
    );

    _checkpoints.add(checkpoint);
    return checkpoint;
  }

  Future<bool> rollbackToCheckpoint(String checkpointId) async {
    final checkpoint = _checkpoints.firstWhere(
      (c) => c.id == checkpointId,
      orElse: () => PandaCheckpoint(
        id: '',
        description: '',
        timestamp: DateTime.now(),
        fileSnapshots: {},
      ),
    );

    if (checkpoint.id.isEmpty) return false;

    for (var entry in checkpoint.fileSnapshots.entries) {
      try {
        final file = File(entry.key);
        await file.writeAsString(entry.value);
      } catch (_) {}
    }
    return true;
  }
}
