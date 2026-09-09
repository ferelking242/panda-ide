import 'package:flutter/material.dart';
import '../../utils/themes.dart';

// Diagnostics pane helper utilities for editor.
// Extracted from editor_page.dart — the main logic lives there.

Color diagnosticSeverityColor(int severity, AppTheme appTheme) {
  switch (severity) {
    case 1:
      return const Color(0xFFF14C4C);
    case 2:
      return const Color(0xFFCCA700);
    case 3:
      return const Color(0xFF75BEFF);
    default:
      return appTheme.editorPageToolColor;
  }
}

IconData diagnosticSeverityIcon(int severity) {
  switch (severity) {
    case 1:
      return Icons.error_outline;
    case 2:
      return Icons.warning_amber_outlined;
    case 3:
      return Icons.info_outline;
    default:
      return Icons.help_outline;
  }
}

int offsetFromLineAndCharacter(String text, int line, int character) {
  final lines = text.split('\n');
  int offset = 0;
  for (int i = 0; i < line && i < lines.length; i++) {
    offset += lines[i].length + 1;
  }
  if (line < lines.length) {
    offset += character.clamp(0, lines[line].length);
  }
  return offset;
}
