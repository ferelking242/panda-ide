import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../extensions/debug_bridge.dart';

/// Floating debug toolbar shown during active debug sessions.
/// Provides play/pause/step/continue/stop controls.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();

    DebugBridge.instance.addListener(_onDebugChanged);
  }

  @override
  void dispose() {
    DebugBridge.instance.removeListener(_onDebugChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onDebugChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = DebugBridge.instance.activeSession;
    if (session == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -20 * (1 - _slideAnim.value)),
          child: Opacity(
            opacity: _slideAnim.value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF89B4FA).withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Session name
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF89B4FA).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                session.name,
                style: const TextStyle(
                  color: Color(0xFF89B4FA),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),

            // Continue / Play
            _DebugButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Continue',
              color: const Color(0xFFA6E3A1),
              onPressed: () => _continue(session),
            ),

            // Pause
            _DebugButton(
              icon: Icons.pause_rounded,
              tooltip: 'Pause',
              color: const Color(0xFFF9E2AF),
              onPressed: () => _pause(session),
            ),

            // Step Over
            _DebugButton(
              icon: Icons.north_east_rounded,
              tooltip: 'Step Over',
              color: const Color(0xFFCDD6F4),
              onPressed: () => _stepOver(session),
            ),

            // Step In
            _DebugButton(
              icon: Icons.arrow_downward_rounded,
              tooltip: 'Step In',
              color: const Color(0xFFCDD6F4),
              onPressed: () => _stepIn(session),
            ),

            // Step Out
            _DebugButton(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'Step Out',
              color: const Color(0xFFCDD6F4),
              onPressed: () => _stepOut(session),
            ),

            const SizedBox(width: 4),
            Container(width: 1, height: 20, color: const Color(0xFF45475A)),
            const SizedBox(width: 4),

            // Stop
            _DebugButton(
              icon: Icons.stop_rounded,
              tooltip: 'Stop',
              color: const Color(0xFFF38BA8),
              onPressed: () => _stop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _continue(DebugSession session) async {
    try {
      final threads = await _getThreads(session);
      if (threads.isNotEmpty) {
        await session.continueExecution(threads.first['id'] as int);
      }
    } catch (e) {
      debugPrint('[DebugOverlay] Continue error: $e');
    }
  }

  Future<void> _pause(DebugSession session) async {
    try {
      final threads = await _getThreads(session);
      if (threads.isNotEmpty) {
        await session.pause(threads.first['id'] as int);
      }
    } catch (e) {
      debugPrint('[DebugOverlay] Pause error: $e');
    }
  }

  Future<void> _stepOver(DebugSession session) async {
    try {
      final threads = await _getThreads(session);
      if (threads.isNotEmpty) {
        await session.stepOver(threads.first['id'] as int);
      }
    } catch (e) {
      debugPrint('[DebugOverlay] StepOver error: $e');
    }
  }

  Future<void> _stepIn(DebugSession session) async {
    try {
      final threads = await _getThreads(session);
      if (threads.isNotEmpty) {
        await session.stepIn(threads.first['id'] as int);
      }
    } catch (e) {
      debugPrint('[DebugOverlay] StepIn error: $e');
    }
  }

  Future<void> _stepOut(DebugSession session) async {
    try {
      final threads = await _getThreads(session);
      if (threads.isNotEmpty) {
        await session.stepOut(threads.first['id'] as int);
      }
    } catch (e) {
      debugPrint('[DebugOverlay] StepOut error: $e');
    }
  }

  Future<void> _stop() async {
    await DebugBridge.instance.stopDebugging(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debug session stopped'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _getThreads(DebugSession session) async {
    try {
      final response = await session.send('threads', {});
      if (response.success != true) return [];
      return (response.body?['threads'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
    } catch (_) {
      return [];
    }
  }
}

class _DebugButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _DebugButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
