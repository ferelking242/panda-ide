import 'dart:async';
import 'package:flutter/material.dart';
import '../../extensions/debug_bridge.dart';

/// Debug console panel that displays DAP output, stdout/stderr, and events.
/// Shown as a bottom panel tab when a debug session is active.
class DebugConsole extends StatefulWidget {
  const DebugConsole({super.key});

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  final List<DebugOutputEntry> _entries = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _listenToSession();
    DebugBridge.instance.addListener(_onDebugChanged);
  }

  @override
  void dispose() {
    DebugBridge.instance.removeListener(_onDebugChanged);
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDebugChanged() {
    _sub?.cancel();
    _listenToSession();
    if (mounted) setState(() {});
  }

  void _listenToSession() {
    final session = DebugBridge.instance.activeSession;
    if (session == null) return;

    _sub = session.messages.listen((msg) {
      if (!mounted) return;

      if (msg.type == 'event') {
        final event = msg.event;
        final body = msg.body;

        if (event == 'output') {
          final category = body?['category'] as String? ?? 'stdout';
          final output = body?['output'] as String? ?? '';
          setState(() {
            _entries.add(DebugOutputEntry(
              text: output,
              type: category == 'stderr'
                  ? DebugOutputType.error
                  : category == 'console'
                      ? DebugOutputType.info
                      : DebugOutputType.output,
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        } else if (event == 'stopped') {
          final reason = body?['reason'] as String? ?? 'unknown';
          final line = body?['line'] as int?;
          final text = line != null
              ? '⏸ Stopped at line $line ($reason)'
              : '⏸ Stopped ($reason)';
          setState(() {
            _entries.add(DebugOutputEntry(
              text: text,
              type: DebugOutputType.event,
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        } else if (event == 'terminated') {
          setState(() {
            _entries.add(DebugOutputEntry(
              text: '⏹ Debug session terminated',
              type: DebugOutputType.event,
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        } else if (event == 'thread') {
          final reason = body?['reason'] as String? ?? '';
          final threadId = body?['threadId'] as int?;
          if (reason == 'started') {
            setState(() {
              _entries.add(DebugOutputEntry(
                text: '▶ Thread $threadId started',
                type: DebugOutputType.info,
                timestamp: DateTime.now(),
              ));
            });
          } else if (reason == 'exited') {
            setState(() {
              _entries.add(DebugOutputEntry(
                text: '■ Thread $threadId exited',
                type: DebugOutputType.info,
                timestamp: DateTime.now(),
              ));
            });
          }
          _scrollToBottom();
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = DebugBridge.instance.activeSession;

    if (session == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No debug session active.\nStart debugging from the terminal or use the Run menu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6C7086),
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Console header
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF181825),
            border: Border(
              bottom: BorderSide(color: Color(0xFF313244), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 12, color: Color(0xFF89B4FA)),
              const SizedBox(width: 4),
              const Text(
                'DEBUG CONSOLE',
                style: TextStyle(
                  color: Color(0xFF89B4FA),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Clear button
              InkWell(
                onTap: () => setState(() => _entries.clear()),
                child: const Icon(Icons.delete_sweep, size: 14, color: Color(0xFF6C7086)),
              ),
            ],
          ),
        ),
        // Entries
        Expanded(
          child: _entries.isEmpty
              ? const Center(
                  child: Text(
                    'Waiting for output...',
                    style: TextStyle(color: Color(0xFF585B70), fontSize: 11),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return _DebugOutputLine(entry: entry);
                  },
                ),
        ),
      ],
    );
  }
}

enum DebugOutputType { output, error, info, event }

class DebugOutputEntry {
  final String text;
  final DebugOutputType type;
  final DateTime timestamp;

  const DebugOutputEntry({
    required this.text,
    required this.type,
    required this.timestamp,
  });
}

class _DebugOutputLine extends StatelessWidget {
  final DebugOutputEntry entry;

  const _DebugOutputLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.type) {
      DebugOutputType.error => const Color(0xFFF38BA8),
      DebugOutputType.event => const Color(0xFFF9E2AF),
      DebugOutputType.info => const Color(0xFF89B4FA),
      DebugOutputType.output => const Color(0xFFCDD6F4),
    };

    final prefix = switch (entry.type) {
      DebugOutputType.error => '❌ ',
      DebugOutputType.event => '',
      DebugOutputType.info => 'ℹ️ ',
      DebugOutputType.output => '',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$prefix${entry.text}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontFamily: 'jetBrainsMono',
          height: 1.4,
        ),
      ),
    );
  }
}
