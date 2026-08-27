import 'package:flutter/material.dart';
import 'package:broken_icons/broken_icons.dart';

/// Displays a plan with checkable steps.
///
/// Used in Plan mode to show the planned steps and their completion status.
class PlanViewer extends StatelessWidget {
  final List<PlanStep> steps;
  final bool isDark;

  const PlanViewer({
    super.key,
    required this.steps,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final fg = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    final bg = isDark ? const Color(0xff1a1a2e) : const Color(0xfff5f5f8);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '📋 Plan (${steps.where((s) => s.done).length}/${steps.length})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(height: 6),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.done
                        ? Broken.tick_circle
                        : step.active
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                    size: 14,
                    color: step.done
                        ? Colors.green
                        : step.active
                            ? Colors.blue
                            : fg.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: step.done
                            ? fg.withValues(alpha: 0.5)
                            : fg,
                        decoration:
                            step.done ? TextDecoration.lineThrough : null,
                      ),
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

class PlanStep {
  final String description;
  final bool done;
  final bool active;

  const PlanStep({
    required this.description,
    this.done = false,
    this.active = false,
  });
}
