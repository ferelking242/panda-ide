import 'dart:io';
import 'package:path/path.dart' as path;

class CheckpointEntry {
  final String timestamp;
  final String filePath;
  final String backupPath;

  CheckpointEntry({
    required this.timestamp,
    required this.filePath,
    required this.backupPath,
  });
}

class AgentCheckpointService {
  static const String _checkpointDir = '.panda/checkpoints';

  static Future<String?> createSnapshot(String workspacePath, String filePath) async {
    if (workspacePath.isEmpty || filePath.isEmpty) return null;
    try {
      final fullPath = path.isAbsolute(filePath) ? filePath : path.join(workspacePath, filePath);
      final file = File(fullPath);
      if (!await file.exists()) return null;

      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final relPath = path.isWithin(workspacePath, fullPath)
          ? path.relative(fullPath, from: workspacePath)
          : path.basename(fullPath);

      final backupDir = Directory(path.join(workspacePath, _checkpointDir, ts));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final backupPath = path.join(backupDir.path, relPath);
      final parentDir = Directory(path.dirname(backupPath));
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      await file.copy(backupPath);
      return backupPath;
    } catch (_) {
      return null;
    }
  }

  static Future<List<CheckpointEntry>> listCheckpoints(String workspacePath) async {
    final results = <CheckpointEntry>[];
    if (workspacePath.isEmpty) return results;
    try {
      final dir = Directory(path.join(workspacePath, _checkpointDir));
      if (!await dir.exists()) return results;

      final subdirs = dir.listSync().whereType<Directory>().toList();
      for (final subdir in subdirs) {
        final ts = path.basename(subdir.path);
        final files = subdir.listSync(recursive: true).whereType<File>();
        for (final f in files) {
          final relPath = path.relative(f.path, from: subdir.path);
          results.add(CheckpointEntry(
            timestamp: ts,
            filePath: relPath,
            backupPath: f.path,
          ));
        }
      }
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {}
    return results;
  }

  static Future<bool> restoreSnapshot(String workspacePath, CheckpointEntry entry) async {
    try {
      final backup = File(entry.backupPath);
      if (!await backup.exists()) return false;
      final targetPath = path.join(workspacePath, entry.filePath);
      final target = File(targetPath);
      await backup.copy(target.path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
