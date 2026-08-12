import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GhostTextSuggestion {
  final String text;
  final int cursorPosition;

  GhostTextSuggestion({required this.text, required this.cursorPosition});
}

class GhostTextEngine extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;
  final Future<String> Function(String textBeforeCursor, String fileContext)? fetchSuggestion;

  const GhostTextEngine({
    Key? key,
    required this.controller,
    required this.focusNode,
    required this.child,
    this.fetchSuggestion,
  }) : super(key: key);

  @override
  State<GhostTextEngine> createState() => _GhostTextEngineState();
}

class _GhostTextEngineState extends State<GhostTextEngine> {
  Timer? _debounceTimer;
  String? _ghostText;

  @override
  void initState() {
    super.initState() ;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    if (_ghostText != null) {
      setState(() => _ghostText = null);
    }

    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      if (widget.fetchSuggestion != null && widget.focusNode.hasFocus) {
        final currentText = widget.controller.text;
        final selection = widget.controller.selection;
        if (selection.isCollapsed && selection.baseOffset >= 0) {
          final textBefore = currentText.substring(0, selection.baseOffset);
          final suggestion = await widget.fetchSuggestion!(textBefore, currentText);
          if (mounted && suggestion.isNotEmpty) {
            setState(() {
              _ghostText = suggestion;
            });
          }
        }
      }
    });
  }

  void _acceptGhostText() {
    if (_ghostText == null) return;
    final selection = widget.controller.selection;
    final text = widget.controller.text;
    final newText = text.substring(0, selection.baseOffset) +
        _ghostText! +
        text.substring(selection.baseOffset);

    widget.controller.text = newText;
    widget.controller.selection = TextSelection.collapsed(
      offset: selection.baseOffset + _ghostText!.length,
    );
    setState(() => _ghostText = null);
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.tab && _ghostText != null) {
            _acceptGhostText();
          } else if (event.logicalKey == LogicalKeyboardKey.escape && _ghostText != null) {
            setState(() => _ghostText = null);
          }
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_ghostText != null)
            Positioned(
              bottom: 8,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 12, color: Colors.blueAccent),
                    const SizedBox(width: 4),
                    Text(
                      'Tab to accept: $_ghostText',
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
