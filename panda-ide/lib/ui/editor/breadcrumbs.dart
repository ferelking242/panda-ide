/// VS Code-style Breadcrumb Navigation for Panda IDE.
///
/// Shows: folder > folder > file > class > method hierarchy
/// Each segment is clickable for navigation.
library;
import 'package:flutter/material.dart';



// ═══════════════════════════════════════════════════════════════
// Breadcrumb Segment
// ═══════════════════════════════════════════════════════════════

enum BreadcrumbType { folder, file, symbol }

class BreadcrumbSegment {
  final String label;
  final BreadcrumbType type;
  final IconData? icon;
  final VoidCallback? onTap;

  const BreadcrumbSegment({
    required this.label,
    required this.type,
    this.icon,
    this.onTap,
  });
}

// ═══════════════════════════════════════════════════════════════
// Breadcrumb Widget
// ═══════════════════════════════════════════════════════════════

class BreadcrumbBar extends StatelessWidget {
  final List<BreadcrumbSegment> segments;

  const BreadcrumbBar({super.key, required this.segments});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _buildItems(),
      ),
    );
  }

  List<Widget> _buildItems() {
    final items = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final isLast = i == segments.length - 1;

      if (i > 0) {
        items.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right, size: 14, color: Colors.white38),
        ));
      }

      items.add(
        InkWell(
          onTap: seg.onTap,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  seg.icon ?? _iconForType(seg.type),
                  size: 13,
                  color: _colorForType(seg.type),
                ),
                const SizedBox(width: 3),
                Text(
                  seg.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLast ? Colors.white : Colors.white70,
                    fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return items;
  }

  IconData _iconForType(BreadcrumbType type) => switch (type) {
    BreadcrumbType.folder => Icons.folder,
    BreadcrumbType.file => Icons.description,
    BreadcrumbType.symbol => Icons.code,
  };

  Color _colorForType(BreadcrumbType type) => switch (type) {
    BreadcrumbType.folder => const Color(0xFFDCAB6A),
    BreadcrumbType.file => const Color(0xFF75BEFF),
    BreadcrumbType.symbol => const Color(0xFF4EC9B0),
  };
}

// ═══════════════════════════════════════════════════════════════
// Helper: Build breadcrumbs from file path
// ═══════════════════════════════════════════════════════════════

List<BreadcrumbSegment> buildBreadcrumbsFromPath(
  String filePath, {
  String? workspaceRoot,
  String? symbolName,
  BreadcrumbType? symbolType,
}) {
  final segments = <BreadcrumbSegment>[];

  // Parse path components
  final parts = filePath.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return segments;

  // File name (last part)
  final fileName = parts.removeLast();

  // Folders
  final startIdx = workspaceRoot != null ? workspaceRoot.split('/').length : 0;
  for (var i = startIdx; i < parts.length; i++) {
    segments.add(BreadcrumbSegment(
      label: parts[i],
      type: BreadcrumbType.folder,
    ));
  }

  // File
  segments.add(BreadcrumbSegment(
    label: fileName,
    type: BreadcrumbType.file,
  ));

  // Symbol (if provided)
  if (symbolName != null) {
    segments.add(BreadcrumbSegment(
      label: symbolName,
      type: symbolType ?? BreadcrumbType.symbol,
    ));
  }

  return segments;
}
