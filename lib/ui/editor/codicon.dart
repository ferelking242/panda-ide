/// Official VS Code codicons rendered as exact SVGs.
///
/// SVG sources: microsoft/vscode-codicons (MIT, CC-BY-4.0 for icons),
/// cloned locally under `reference/codicons/src/icons/`.
/// Rendered with flutter_svg and tinted via ColorFilter (the source files
/// use fill="currentColor").
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

library;


// ── Exact SVG payloads (verbatim from microsoft/vscode-codicons) ────────────

abstract final class Codicon {
  /// Customize Layout (toolbar button 1).
  static const String layout = '''
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path fill-rule="evenodd" clip-rule="evenodd" d="M5.5 1C6.327 1 7 1.673 7 2.5V13.5C7 14.327 6.327 15 5.5 15H2.5C1.673 15 1 14.327 1 13.5V2.5C1 1.673 1.673 1 2.5 1H5.5ZM2.5 2C2.225 2 2 2.225 2 2.5V13.5C2 13.775 2.225 14 2.5 14H5.5C5.775 14 6 13.775 6 13.5V2.5C6 2.225 5.775 2 5.5 2H2.5Z"/><path fill-rule="evenodd" clip-rule="evenodd" d="M13.5 9C14.327 9 15 9.673 15 10.5V13.5C15 14.327 14.327 15 13.5 15H10.5C9.673 15 9 14.327 9 13.5V10.5C9 9.673 9.673 9 10.5 9H13.5ZM10.5 10C10.225 10 10 10.225 10 10.5V13.5C10 13.775 10.225 14 10.5 14H13.5C13.775 14 14 13.775 14 13.5V10.5C14 10.225 13.775 10 13.5 10H10.5Z"/><path fill-rule="evenodd" clip-rule="evenodd" d="M13.5 1C14.327 1 15 1.673 15 2.5V5.5C15 6.327 14.327 7 13.5 7H10.5C9.673 7 9 6.327 9 5.5V2.5C9 1.673 9.673 1 10.5 1H13.5ZM10.5 2C10.225 10 10 10.225 10 10.5V13.5C10 13.775 10.225 14 10.5 14H13.5C13.775 14 14 13.775 14 13.5V10.5C14 10.225 13.775 10 13.5 10H10.5Z"/></svg>
''';

  /// Toggle Primary Side Bar (toolbar button 2).
  static const String layoutSidebarLeft = '''
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M12.5 1C13.881 1 15 2.119 15 3.5V12.5C15 13.881 13.881 15 12.5 15H3.5C2.119 15 1 13.881 1 12.5V3.5C1 2.119 2.119 1 3.5 1H12.5ZM12.5 14C13.328 14 14 13.328 14 12.5V3.5C14 2.672 13.328 2 12.5 2H7V14H12.5Z"/></svg>
''';

  /// Toggle Panel / Terminal (toolbar button 3).
  static const String layoutPanel = '''
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M15 12.5C15 13.881 13.881 15 12.5 15H3.5C2.119 15 1 13.881 1 12.5V3.5C1 2.119 2.119 1 3.5 1H12.5C13.881 1 15 2.119 15 3.5V12.5ZM2 10H14V3.5C14 2.672 13.328 2 12.5 2H3.5C2.672 2 2 2.672 2 3.5V10Z"/></svg>
''';

  /// Toggle Secondary Side Bar — Panda Agent (toolbar button 4).
  static const String layoutSidebarRight = '''
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M12.5 1C13.881 1 15 2.119 15 3.5V12.5C15 13.881 13.881 15 12.5 15H3.5C2.119 15 1 13.881 1 12.5V3.5C1 2.119 2.119 1 3.5 1H12.5ZM9 14V2H3.5C2.672 2 2 2.672 2 3.5V12.5C2 13.328 2.672 14 3.5 14H9Z"/></svg>
''';

  /// Split Editor — side-by-side panes (tab bar action).
  static const String splitHorizontal = '''
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M12.5 1H3.5C2.122 1 1 2.122 1 3.5V12.5C1 13.878 2.122 15 3.5 15H12.5C13.878 15 15 13.878 15 12.5V3.5C15 2.122 13.878 1 12.5 1ZM2 12.5V3.5C2 2.673 2.673 2 3.5 2H7.5V14H3.5C2.673 14 2 13.327 2 12.5ZM14 12.5C14 13.327 13.327 14 12.5 14H8.5V2H12.5C13.327 2 14 2.673 14 3.5V12.5Z"/></svg>
''';

  /// Ellipsis — More Actions (tab bar "...").
  static const String ellipsis = '''
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M5 8C5 8.55229 4.55228 9 4 9C3.44772 9 3 8.55229 3 8C3 7.44772 3.44772 7 4 7C4.55228 7 5 7.44772 5 8ZM9 8C9 8.55229 8.55229 9 8 9C7.44772 9 7 8.55229 7 8C7 7.44772 7.44772 7 8 7C8.55229 7 9 7.44772 9 8ZM12 9C12.5523 9 13 8.55229 13 8C13 7.44772 12.5523 7 12 7C11.4477 7 11 7.44772 11 8C11 8.55229 11.4477 9 12 9Z"/></svg>
''';

  /// Close (tab close X).
  static const String close = '''
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M13.85 13.1502C14.05 13.3502 14.05 13.6602 13.85 13.8602C13.75 13.9602 13.62 14.0102 13.5 14.0102C13.38 14.0102 13.24 13.9602 13.15 13.8602L8 8.71023L2.85 13.8602C2.75 13.9602 2.62 14.0102 2.5 14.0102C2.38 14.0102 2.24 13.9602 2.15 13.8602C1.95 13.6602 1.95 13.3502 2.15 13.1502L7.3 8.00023L2.15 2.85023C1.95 2.65023 1.95 2.34023 2.15 2.14023C2.35 1.94023 2.66 1.94023 2.86 2.14023L8.01 7.29023L13.16 2.14023C13.36 1.94023 13.67 1.94023 13.87 2.14023C14.07 2.34023 14.07 2.65023 13.87 2.85023L8.72 8.00023L13.87 13.1502H13.85Z"/></svg>
''';
}

// ── Widget ──────────────────────────────────────────────────────────────────

/// Renders an official VS Code codicon SVG, tinted like an IconData icon.
class CodIcon extends StatelessWidget {
  final String svg;
  final double size;
  final Color? color;

  const CodIcon(this.svg, {super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color;
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter:
          tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
