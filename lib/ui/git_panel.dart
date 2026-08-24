/// Git Panel — commit, push, pull, staging, branch management.
///
/// Full Git integration for Panda IDE.
library;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/git/git_operations.dart' show gitStash, gitStashPop, gitStashDrop, gitStashList, GitStashEntry;




// ═══════════════════════════════════════════════════════════════
// Git Operations
// ═══════════════════════════════════════════════════════════════

/// Represents a Git file change.
class GitFileChange {
  final String path;
  final String status; // M=modified, A=added, D=deleted, R=renamed, U=untracked
  final bool staged;

  const GitFileChange({
    required this.path,
    required this.status,
    this.staged = false,
  });

  String get statusLabel {
    switch (status) {
      case 'M': return 'Modified';
      case 'A': return 'Added';
      case 'D': return 'Deleted';
      case 'R': return 'Renamed';
      case 'U': return 'Untracked';
      case '?': return 'Untracked';
      default: return status;
    }
  }

  IconData get icon {
    switch (status) {
      case 'M': return Icons.edit;
      case 'A': return Icons.add_circle;
      case 'D': return Icons.remove_circle;
      case 'R': return Icons.rename;
      case 'U': case '?': return Icons.help_outline;
      default: return Icons.insert_drive_file;
    }
  }

  Color get color {
    switch (status) {
      case 'M': return const Color(0xFFFFC107);
      case 'A': return const Color(0xFF4CAF50);
      case 'D': return const Color(0xFFF44336);
      case 'R': return const Color(0xFF2196F3);
      case 'U': case '?': return const Color(0xFF9E9E9E);
      default: return const Color(0xFF9E9E9E);
    }
  }
}

/// Represents a Git branch.
class GitBranch {
  final String name;
  final bool isCurrent;
  final String? upstream;

  const GitBranch({required this.name, this.isCurrent = false, this.upstream});
}

/// Represents a Git commit.
class GitCommit {
  final String hash;
  final String message;
  final String author;
  final DateTime date;

  const GitCommit({
    required this.hash,
    required this.message,
    required this.author,
    required this.date,
  });
}

/// Core Git operations wrapper.
class GitOperations {
  final String workspacePath;

  GitOperations(this.workspacePath);

  /// Run a git command and return output.
  Future<String> _runGit(List<String> args) async {
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workspacePath,
        environment: {'GIT_TERMINAL_PROMPT': '0'},
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0 && result.stderr.toString().isNotEmpty) {
        throw Exception('Git error: ${result.stderr}');
      }
      return result.stdout.toString().trim();
    } catch (e) {
      throw Exception('Git command failed: $e');
    }
  }

  /// Check if the workspace is a git repo.
  Future<bool> isGitRepo() async {
    try {
      await _runGit(['rev-parse', '--git-dir']);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get current branch name.
  Future<String?> getCurrentBranch() async {
    try {
      return await _runGit(['branch', '--show-current']);
    } catch (_) {
      return null;
    }
  }

  /// Get status of all files.
  Future<List<GitFileChange>> getStatus() async {
    try {
      final output = await _runGit(['status', '--porcelain', '-u']);
      if (output.isEmpty) return [];

      return output.split('\n').where((l) => l.isNotEmpty).map((line) {
        final status = line.length >= 2 ? line.substring(0, 2).trim() : '?';
        final path = line.length > 3 ? line.substring(3).trim() : '';
        return GitFileChange(path: path, status: status);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Stage a file.
  Future<void> stageFile(String filePath) async {
    await _runGit(['add', filePath]);
  }

  /// Unstage a file.
  Future<void> unstageFile(String filePath) async {
    await _runGit(['reset', 'HEAD', '--', filePath]);
  }

  /// Stage all files.
  Future<void> stageAll() async {
    await _runGit(['add', '.']);
  }

  /// Discard changes to a file.
  Future<void> discardChanges(String filePath) async {
    await _runGit(['checkout', '--', filePath]);
  }

  /// Commit with message.
  Future<String> commit(String message, {String? author}) async {
    final args = ['commit', '-m', message];
    if (author != null) {
      args.addAll(['--author', author]);
    }
    return await _runGit(args);
  }

  /// Push to remote.
  Future<String> push({String remote = 'origin', String? branch}) async {
    final args = ['push', remote];
    if (branch != null) args.add(branch);
    return await _runGit(args);
  }

  /// Pull from remote.
  Future<String> pull({String remote = 'origin', String? branch}) async {
    final args = ['pull', remote];
    if (branch != null) args.add(branch);
    return await _runGit(args);
  }

  /// Fetch from remote.
  Future<String> fetch({String remote = 'origin'}) async {
    return await _runGit(['fetch', remote]);
  }

  /// Get list of branches.
  Future<List<GitBranch>> getBranches() async {
    try {
      final output = await _runGit(['branch', '-a']);
      final current = await getCurrentBranch();
      return output.split('\n')
          .where((l) => l.isNotEmpty)
          .map((line) {
            final name = line.replaceFirst('*', '').trim();
            final isCurrent = line.startsWith('*');
            final isRemote = name.startsWith('remotes/');
            final branchName = isRemote ? name.replaceFirst('remotes/', '').replaceFirst(RegExp(r'^origin/'), '') : name;
            return GitBranch(
              name: branchName,
              isCurrent: isCurrent,
              upstream: isRemote ? name : null,
            );
          })
          .where((b) => !b.name.contains('HEAD'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Switch to a branch.
  Future<void> switchBranch(String branch) async {
    await _runGit(['checkout', branch]);
  }

  /// Create a new branch.
  Future<void> createBranch(String name) async {
    await _runGit(['checkout', '-b', name]);
  }

  /// Get recent commits.
  Future<List<GitCommit>> getLog({int count = 20}) async {
    try {
      final output = await _runGit([
        'log', '--format=%H|%s|%an|%aI', '-n', count.toString(),
      ]);
      if (output.isEmpty) return [];

      return output.split('\n').where((l) => l.isNotEmpty).map((line) {
        final parts = line.split('|');
        if (parts.length < 4) return null;
        return GitCommit(
          hash: parts[0],
          message: parts[1],
          author: parts[2],
          date: DateTime.tryParse(parts[3]) ?? DateTime.now(),
        );
      }).whereType<GitCommit>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Get diff for a file.
  Future<String> getDiff(String filePath, {bool staged = false}) async {
    final args = ['diff'];
    if (staged) args.add('--cached');
    args.addAll(['--', filePath]);
    return await _runGit(args);
  }

  /// Get diff stats.
  Future<Map<String, int>> getDiffStats() async {
    try {
      final output = await _runGit(['diff', '--stat']);
      final match = RegExp(r'(\d+) files? changed').firstMatch(output);
      final files = match != null ? int.parse(match.group(1)!) : 0;

      final insMatch = RegExp(r'(\d+) insertions?').firstMatch(output);
      final ins = insMatch != null ? int.parse(insMatch.group(1)!) : 0;

      final delMatch = RegExp(r'(\d+) deletions?').firstMatch(output);
      final del = delMatch != null ? int.parse(delMatch.group(1)!) : 0;

      return {'files': files, 'insertions': ins, 'deletions': del};
    } catch (_) {
      return {'files': 0, 'insertions': 0, 'deletions': 0};
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Git Panel Widget
// ═══════════════════════════════════════════════════════════════

class GitPanel extends StatefulWidget {
  final String workspacePath;

  const GitPanel({super.key, required this.workspacePath});

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  late GitOperations _git;
  List<GitFileChange> _changes = [];
  List<GitStashEntry> _stashEntries = [];
  String? _currentBranch;
  bool _loading = true;
  final _commitCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _git = GitOperations(widget.workspacePath);
    _refresh();
  }

  @override
  void dispose() {
    _commitCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final changes = await _git.getStatus();
      final branch = await _git.getCurrentBranch();
      final stash = await gitStashList(widget.workspacePath);
      if (!mounted) return;
      setState(() {
        _changes = changes;
        _currentBranch = branch;
        _stashEntries = stash;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _commit() async {
    final msg = _commitCtrl.text.trim();
    if (msg.isEmpty) return;

    try {
      await _git.stageAll();
      await _git.commit(msg);
      _commitCtrl.clear();
      _showSnack('Committed: $msg');
      await _refresh();
    } catch (e) {
      _showSnack('Commit failed: $e', isError: true);
    }
  }

  Future<void> _push() async {
    try {
      await _git.push();
      _showSnack('Pushed to remote');
    } catch (e) {
      _showSnack('Push failed: $e', isError: true);
    }
  }

  Future<void> _pull() async {
    try {
      await _git.pull();
      _showSnack('Pulled from remote');
      await _refresh();
    } catch (e) {
      _showSnack('Pull failed: $e', isError: true);
    }
  }

  // ── Stash operations ─────────────────────────────────────────────────────
  Future<void> _stash() async {
    try {
      await gitStash(widget.workspacePath);
      _showSnack('Changes stashed');
      await _refresh();
      await _loadStash();
    } catch (e) {
      _showStash('Stash failed: $e', isError: true);
    }
  }

  Future<void> _stashPop() async {
    try {
      await gitStashPop(widget.workspacePath);
      _showSnack('Stash applied');
      await _refresh();
      await _loadStash();
    } catch (e) {
      _showStash('Stash pop failed: $e', isError: true);
    }
  }

  Future<void> _stashDrop(int index) async {
    try {
      await gitStashDrop(widget.workspacePath, ref: 'stash@{$index}');
      _showSnack('Stash dropped');
      await _loadStash();
    } catch (e) {
      _showStash('Stash drop failed: $e', isError: true);
    }
  }

  Future<void> _loadStash() async {
    try {
      final entries = await gitStashList(widget.workspacePath);
      if (!mounted) return;
      setState(() => _stashEntries = entries);
    } catch (_) {}
  }

  void _showStash(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : null),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final staged = _changes.where((c) => c.staged || c.status == 'A').toList();
    final unstaged = _changes.where((c) => !c.staged && c.status != 'A').toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.git_branch, size: 18),
            const SizedBox(width: 8),
            Text(_currentBranch ?? 'No branch', style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.archive, size: 18),
            tooltip: 'Stash Changes',
            onPressed: _stash,
          ),
          IconButton(
            icon: const Icon(Icons.pull, size: 18),
            tooltip: 'Pull',
            onPressed: _pull,
          ),
          IconButton(
            icon: const Icon(Icons.push_pin, size: 18),
            tooltip: 'Push',
            onPressed: _push,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Commit input
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commitCtrl,
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Commit message...',
                            hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onSubmitted: (_) => _commit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _commitCtrl.text.trim().isEmpty ? null : _commit,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
                        child: const Text('Commit', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),

                // Stats bar
                if (_changes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        _statChip('${_changes.length} changes', cs.primary),
                        const SizedBox(width: 8),
                        if (staged.isNotEmpty) _statChip('${staged.length} staged', Colors.green),
                        if (unstaged.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _statChip('${unstaged.length} unstaged', Colors.orange),
                        ],
                      ],
                    ),
                  ),

                // File list
                Expanded(
                  child: _changes.isEmpty
                      ? ListView(
                          children: [
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 40),
                                  Icon(Icons.check_circle, size: 48, color: Colors.green.withValues(alpha: 0.5)),
                                  const SizedBox(height: 12),
                                  Text('Working tree clean', style: TextStyle(color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            // Stash section always visible
                            if (_stashEntries.isNotEmpty) ...[
                              _sectionHeader('Stash', _stashEntries.length, cs),
                              ..._stashEntries.asMap().entries.map((entry) =>
                                _buildStashTile(entry.value, entry.key, cs)),
                            ],
                          ],
                        )
                      : ListView(
                          children: [
                            if (staged.isNotEmpty) ...[
                              _sectionHeader('Staged', staged.length, cs),
                              ...staged.map((c) => _buildChangeTile(c, cs, staged: true)),
                            ],
                            if (unstaged.isNotEmpty) ...[
                              _sectionHeader('Changes', unstaged.length, cs),
                              ...unstaged.map((c) => _buildChangeTile(c, cs, staged: false)),
                            ],
                            // Stash section
                            if (_stashEntries.isNotEmpty) ...[
                              _sectionHeader('Stash', _stashEntries.length, cs),
                              ..._stashEntries.asMap().entries.map((entry) =>
                                _buildStashTile(entry.value, entry.key, cs)),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, int count, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeTile(GitFileChange change, ColorScheme cs, {required bool staged}) {
    return ListTile(
      dense: true,
      leading: Icon(change.icon, size: 16, color: change.color),
      title: Text(p.basename(change.path), style: TextStyle(fontSize: 12, color: cs.onSurface)),
      subtitle: Text(change.statusLabel, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(staged ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 16),
            tooltip: staged ? 'Unstage' : 'Stage',
            onPressed: () async {
              if (staged) {
                await _git.unstageFile(change.path);
              } else {
                await _git.stageFile(change.path);
              }
              _refresh();
            },
          ),
          if (!staged)
            IconButton(
              icon: const Icon(Icons.undo, size: 16),
              tooltip: 'Discard',
              onPressed: () async {
                await _git.discardChanges(change.path);
                _refresh();
              },
            ),
        ],
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildStashTile(GitStashEntry entry, int index, ColorScheme cs) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.archive, size: 16, color: cs.primary),
      title: Text(entry.message, style: TextStyle(fontSize: 12, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${entry.branch} • ${entry.date}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 16),
            tooltip: 'Apply Stash',
            onPressed: () async {
              await gitStashPop(widget.workspacePath);
              _showSnack('Stash applied');
              await _refresh();
              await _loadStash();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Drop Stash',
            onPressed: () => _stashDrop(index),
          ),
        ],
      ),
    );
  }
}
