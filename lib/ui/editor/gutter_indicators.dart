import 'package:flutter/material.dart';

enum GutterLineStatus { none, added, modified, deleted }

class GutterDiffIndicator {
  static List<GutterLineStatus> calculateLineDiff(String original, String current) {
    final origLines = original.split('\n');
    final currLines = current.split('\n');
    final List<GutterLineStatus> statuses = List.filled(currLines.length, GutterLineStatus.none);

    final maxIdx = currLines.length;
    for (int i = 0; i < maxIdx; i++) {
      if (i >= origLines.length) {
        statuses[i] = GutterLineStatus.added;
      } else if (origLines[i] != currLines[i]) {
        statuses[i] = GutterLineStatus.modified;
      }
    }
    return statuses;
  }

  static Color getColor(GutterLineStatus status, BuildContext context) {
    switch (status) {
      case GutterLineStatus.added:
        return const Color(0xFF4CAF50); // Green
      case GutterLineStatus.modified:
        return const Color(0xFF2196F3); // Blue
      case GutterLineStatus.deleted:
        return const Color(0xFFF44336); // Red
      case GutterLineStatus.none:
        return Colors.transparent;
    }
  }

  static Widget buildGutterBar(GutterLineStatus status, BuildContext context) {
    if (status == GutterLineStatus.none) return const SizedBox(width: 3);
    return Container(
      width: 3,
      color: getColor(status, context),
    );
  }
}
