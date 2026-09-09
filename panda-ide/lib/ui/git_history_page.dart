import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/git/git_operations.dart';
import '../utils/git/git_diff.dart';
import '../utils/models/editor_models.dart';

/// VS Code-style Git log/history page with commit graph.
class GitHistoryPage extends StatefulWidget {
  final String workspacePath;
  const GitHistoryPage({super.key, required this.workspacePath});

  @override
  State<GitHistoryPage> createState() => _GitHistoryPageState();
}

class _GitHistoryPageState extends State<GitHistoryPage> {
  List<CommitNode> _commits = [];
  bool _loading = true;
  String? _currentBranch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final commits = await getGraph(widget.workspacePath);
      final branch = await gitCurrentBranch(widget.workspacePath);
      if (mounted) {
        setState(() {
          _commits = commits;
          _currentBranch = branch;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.history, size: 18),
            const SizedBox(width: 8),
            Text('Git History', style: const TextStyle(fontSize: 14)),
            if (_currentBranch != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_currentBranch!, style: TextStyle(fontSize: 11, color: cs.primary)),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _commits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('No commits yet', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _commits.length,
                    itemBuilder: (ctx, i) => _buildCommitTile(_commits[i], cs),
                  ),
                ),
    );
  }

  Widget _buildCommitTile(CommitNode commit, ColorScheme cs) {
    final isHead = commit.isHead;
    final isRemote = commit.isRemoteHead;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: isHead ? cs.primaryContainer.withValues(alpha: 0.3) : null,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHead
                ? cs.primary.withValues(alpha: 0.2)
                : isRemote
                    ? Colors.orange.withValues(alpha: 0.2)
                    : cs.surfaceContainerHighest,
          ),
          child: Center(
            child: isHead
                ? Icon(Icons.circle, size: 10, color: cs.primary)
                : isRemote
                    ? Icon(Icons.language, size: 14, color: Colors.orange)
                    : Icon(Icons.commit, size: 14, color: cs.onSurfaceVariant),
          ),
        ),
        title: Text(
          commit.message,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isHead ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${commit.author} • ${commit.hash.substring(0, 7)} • ${commit.date}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 14),
          tooltip: 'Copy hash',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: commit.hash));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hash copied')),
            );
          },
        ),
      ),
    );
  }
}
