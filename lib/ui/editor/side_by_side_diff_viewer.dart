import 'package:flutter/material.dart';

class SideBySideDiffViewer extends StatelessWidget {
  final String originalText;
  final String modifiedText;

  const SideBySideDiffViewer({
    super.key,
    required this.originalText,
    required this.modifiedText,
  });

  @override
  Widget build(BuildContext context) {
    final origLines = originalText.split('\n');
    final modLines = modifiedText.split('\n');
    final maxLines = origLines.length > modLines.length ? origLines.length : modLines.length;

    return Row(
      children: [
        // Original Pane
        Expanded(
          child: Container(
            color: Colors.red.shade900.withValues(alpha: 0.1),
            child: ListView.builder(
              itemCount: maxLines,
              itemBuilder: (context, index) {
                final line = index < origLines.length ? origLines[index] : '';
                final isDiff = index >= modLines.length || (index < origLines.length && origLines[index] != modLines[index]);
                return Container(
                  color: isDiff ? Colors.red.withValues(alpha: 0.2) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDiff ? Colors.redAccent : Colors.grey,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Modified Pane
        Expanded(
          child: Container(
            color: Colors.green.shade900.withValues(alpha: 0.1),
            child: ListView.builder(
              itemCount: maxLines,
              itemBuilder: (context, index) {
                final line = index < modLines.length ? modLines[index] : '';
                final isDiff = index >= origLines.length || (index < modLines.length && modLines[index] != origLines[index]);
                return Container(
                  color: isDiff ? Colors.green.withValues(alpha: 0.2) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDiff ? Colors.greenAccent : Colors.white70,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
