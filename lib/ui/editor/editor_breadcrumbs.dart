import 'package:flutter/material.dart';

class EditorBreadcrumbs extends StatelessWidget {
  final String filePath;
  final Function(String selectedPath)? onSegmentTap;

  const EditorBreadcrumbs({
    super.key,
    required this.filePath,
    this.onSegmentTap,
  });

  @override
  Widget build(BuildContext meContext) {
    if (filePath.isEmpty) return const SizedBox.shrink();

    final segments = filePath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(meContext).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_right,
          size: 14,
          color: Theme.of(meContext).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        itemBuilder: (context, index) {
          final isLast = index == segments.length - 1;
          final segment = segments[index];
          final partialPath = '/${segments.sublist(0, index + 1).join('/')}';

          return InkWell(
            onTap: () => onSegmentTap?.call(partialPath),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLast ? Icons.insert_drive_file_outlined : Icons.folder_open_outlined,
                    size: 14,
                    color: isLast
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    segment,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                      color: isLast
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
