import 'package:flutter/material.dart';

/// A breakpoint that can be conditional.
class Breakpoint {
  final int line;
  final String? condition; // null = unconditional
  final String? logMessage; // logpoint
  final bool enabled;
  final String? id;

  const Breakpoint({
    required this.line,
    this.condition,
    this.logMessage,
    this.enabled = true,
    this.id,
  });

  bool get isConditional => condition != null && condition!.isNotEmpty;
  bool get isLogPoint => logMessage != null && logMessage!.isNotEmpty;

  Breakpoint copyWith({
    int? line,
    String? condition,
    String? logMessage,
    bool? enabled,
    String? id,
  }) {
    return Breakpoint(
      line: line ?? this.line,
      condition: condition ?? this.condition,
      logMessage: logMessage ?? this.logMessage,
      enabled: enabled ?? this.enabled,
      id: id ?? this.id,
    );
  }
}

/// Dialog to add/edit conditional breakpoints.
class ConditionalBreakpointDialog extends StatefulWidget {
  final int line;
  final Breakpoint? existing;

  const ConditionalBreakpointDialog({
    super.key,
    required this.line,
    this.existing,
  });

  static Future<Breakpoint?> show(BuildContext context, {required int line, Breakpoint? existing}) {
    return showModalBottomSheet<Breakpoint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConditionalBreakpointDialog(line: line, existing: existing),
    );
  }

  @override
  State<ConditionalBreakpointDialog> createState() => _ConditionalBreakpointDialogState();
}

class _ConditionalBreakpointDialogState extends State<ConditionalBreakpointDialog> {
  late TextEditingController _conditionCtrl;
  late TextEditingController _logMsgCtrl;
  String _type = 'breakpoint'; // 'breakpoint', 'conditional', 'logpoint'

  @override
  void initState() {
    super.initState();
    _conditionCtrl = TextEditingController(text: widget.existing?.condition ?? '');
    _logMsgCtrl = TextEditingController(text: widget.existing?.logMessage ?? '');
    if (widget.existing?.isLogPoint == true) {
      _type = 'logpoint';
    } else if (widget.existing?.isConditional == true) {
      _type = 'conditional';
    }
  }

  @override
  void dispose() {
    _conditionCtrl.dispose();
    _logMsgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Breakpoint at line ${widget.line}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // Type selector
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'breakpoint', label: Text('Breakpoint'), icon: Icon(Icons.circle, size: 12)),
              ButtonSegment(value: 'conditional', label: Text('Conditional'), icon: Icon(Icons.question_mark, size: 12)),
              ButtonSegment(value: 'logpoint', label: Text('Logpoint'), icon: Icon(Icons.terminal, size: 12)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),

          if (_type == 'conditional') ...[
            TextField(
              controller: _conditionCtrl,
              decoration: const InputDecoration(
                labelText: 'Expression',
                hintText: 'e.g. x > 5, index == 0',
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Breakpoint will only pause when this expression is true.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],

          if (_type == 'logpoint') ...[
            TextField(
              controller: _logMsgCtrl,
              decoration: const InputDecoration(
                labelText: 'Log Message',
                hintText: 'e.g. x is {x}, loop iteration {i}',
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Message will be printed to Debug Console when this line is hit.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final result = Breakpoint(
                    line: widget.line,
                    condition: _type == 'conditional' ? _conditionCtrl.text : null,
                    logMessage: _type == 'logpoint' ? _logMsgCtrl.text : null,
                    enabled: true,
                    id: widget.existing?.id,
                  );
                  Navigator.pop(context, result);
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
