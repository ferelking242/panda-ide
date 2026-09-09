import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Manages Zen mode state across the app.
class ZenModeController extends ChangeNotifier {
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  void toggle() {
    _isEnabled = !_isEnabled;
    if (_isEnabled) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    notifyListeners();
  }

  void enable() {
    if (!_isEnabled) toggle();
  }

  void disable() {
    if (_isEnabled) toggle();
  }
}

/// Zen mode overlay that shows a floating bar at the top.
class ZenModeBar extends StatelessWidget {
  final bool isVisible;
  final VoidCallback onExit;
  final String? fileName;

  const ZenModeBar({
    super.key,
    required this.isVisible,
    required this.onExit,
    this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: MouseRegion(
        onEnter: (_) {},
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 4,
            color: Colors.transparent,
            child: Center(
              child: MouseRegion(
                onEnter: (_) {},
                child: GestureDetector(
                  onTap: onExit,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen_exit, size: 14,
                            color: Theme.of(context).colorScheme.onSurface),
                        const SizedBox(width: 6),
                        Text(
                          fileName ?? 'Zen Mode',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ESC to exit',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
