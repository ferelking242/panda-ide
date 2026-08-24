import 'package:flutter/material.dart';
import '../../core/broken_icons.dart';
import '../../utils/themes.dart';

/// Shows when no tabs are open — Panda logo ghost + hint text.
class EmptyEditor extends StatelessWidget {
  final AppTheme appTheme;
  const EmptyEditor({super.key, required this.appTheme});

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;
    final muted  = isDark ? Colors.grey[700]! : Colors.grey[400]!;
    final hint   = isDark ? Colors.grey[600]! : Colors.grey[400]!;
    return Stack(
      children: [
        Center(
          child: Opacity(
            opacity: 0.06,
            child: Image.asset(
              'assets/icons/app-icon.png',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Text('🐼', style: TextStyle(fontSize: 120)),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 200),
              Text('Ouvrir un fichier pour commencer',
                  style: TextStyle(fontSize: 13, color: muted)),
              const SizedBox(height: 6),
              Text(
                'Ctrl+O  Ouvrir un fichier   •   Ctrl+Shift+E  Explorateur',
                style: TextStyle(fontSize: 11, color: hint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
