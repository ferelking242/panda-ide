import 'package:flutter/material.dart';

class PendingDiffFile {
  final String filePath;
  final String originalContent;
  final String modifiedContent;
  final List<DiffHunk> hunks;

  PendingDiffFile({
    required this.filePath,
    required this.originalContent,
    required this.modifiedContent,
    required this.hunks,
  });
}

class DiffHunk {
  final int oldStart;
  final int newStart;
  final List<String> oldLines;
  final List<String> newLines;
  bool isAccepted;

  DiffHunk({
    required this.oldStart,
    required this.newStart,
    required this.oldLines,
    required this.newLines,
    this.isAccepted = true,
  });
}

class AgentDiffViewer extends StatefulWidget {
  final List<PendingDiffFile> diffFiles;
  final Function(String filePath, bool accept) onFileDecision;
  final Function(String filePath, int hunkIndex, bool accept) onHunkDecision;
  final VoidCallback onAcceptAll;
  final VoidCallback onRejectAll;

  const AgentDiffViewer({
    super.key,
    required this.diffFiles,
    required this.onFileDecision,
    required this.onHunkDecision,
    required this.onAcceptAll,
    required this.onRejectAll,
  });

  @override
  State<AgentDiffViewer> createState() => _AgentDiffViewerState();
}

class _AgentDiffViewerState extends State<AgentDiffViewer> {
  int _selectedFileIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff181825) : const Color(0xfff5f5f7);
    final cardBg = isDark ? const Color(0xff1e1e2e) : Colors.white;

    if (widget.diffFiles.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('Diff Viewer')),
        body: const Center(
          child: Text('Aucune modification en attente.'),
        ),
      );
    }

    final activeFile = widget.diffFiles[_selectedFileIndex.clamp(0, widget.diffFiles.length - 1)];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Modifications en attente (${widget.diffFiles.length})'),
        actions: [
          TextButton.icon(
            onPressed: widget.onAcceptAll,
            icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
            label: const Text('Tout accepter', style: TextStyle(color: Colors.green)),
          ),
          TextButton.icon(
            onPressed: widget.onRejectAll,
            icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
            label: const Text('Tout rejeter', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: Row(
        children: [
          // File List Sidebar
          SizedBox(
            width: 220,
            child: Container(
              color: cardBg,
              child: ListView.builder(
                itemCount: widget.diffFiles.length,
                itemBuilder: (context, index) {
                  final file = widget.diffFiles[index];
                  final isSelected = index == _selectedFileIndex;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: isDark ? const Color(0xff313244) : const Color(0xffe6e9ef),
                    title: Text(
                      file.filePath.split('/').last,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      file.filePath,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => setState(() => _selectedFileIndex = index),
                  );
                },
              ),
            ),
          ),
          const VerticalDivider(width: 1),

          // Diff Viewer Main Content
          Expanded(
            child: Column(
              children: [
                // Header per file
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: cardBg,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          activeFile.filePath,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => widget.onFileDecision(activeFile.filePath, true),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Accepter fichier'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => widget.onFileDecision(activeFile.filePath, false),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Rejeter'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Unified Diff view lines
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: activeFile.hunks.asMap().entries.map((entry) {
                      final hunkIndex = entry.key;
                      final hunk = entry.value;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: cardBg,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Hunk @@ -${hunk.oldStart} +${hunk.newStart} @@',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: Icon(Icons.check_circle, color: hunk.isAccepted ? Colors.green : Colors.grey, size: 20),
                                    onPressed: () {
                                      setState(() => hunk.isAccepted = !hunk.isAccepted);
                                      widget.onHunkDecision(activeFile.filePath, hunkIndex, hunk.isAccepted);
                                    },
                                    tooltip: hunk.isAccepted ? 'Hunk accepté' : 'Hunk rejeté',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ...hunk.oldLines.map((line) => Container(
                                width: double.infinity,
                                color: Colors.red.withOpacity(0.15),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text('- $line', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.red)),
                              )),
                              ...hunk.newLines.map((line) => Container(
                                width: double.infinity,
                                color: Colors.green.withOpacity(0.15),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text('+ $line', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.green)),
                              )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
