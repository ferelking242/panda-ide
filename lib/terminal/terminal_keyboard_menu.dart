import 'package:flutter/material.dart';

/// Compact terminal accessory keyboard.
///
/// It deliberately stays docked in two slim rows.  The terminal itself owns
/// focus and hardware-key shortcuts; this row only sends the same sequences
/// when a physical keyboard is not available.
class TerminalKeyboardMenu extends StatefulWidget {
  final Function(String) onSendSequence;
  final Function(bool ctrl, bool alt, bool shift, VoidCallback resetCallback)
      onModifierChanged;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onSelectAll;

  const TerminalKeyboardMenu({
    super.key,
    required this.onSendSequence,
    required this.onModifierChanged,
    this.onCopy,
    this.onPaste,
    this.onSelectAll,
  });

  @override
  State<TerminalKeyboardMenu> createState() => _TerminalKeyboardMenuState();
}

class _TerminalKeyboardMenuState extends State<TerminalKeyboardMenu> {
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  bool _showFunctionKeys = false;

  static const _foreground = Color(0xffc4c7cc);
  static const _mutedForeground = Color(0xff92969d);
  static const _divider = Color(0xff3b3d41);
  static const _chipBackground = Color(0xff242629);
  static const _activeBackground = Color(0xff3a3d42);
  static const _chipBorder = Color(0xff45484d);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff18191b),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow([
            _chip('ESC', () => _send('\x1b')),
            _modifierChip('CTRL', Modifier.ctrl, _ctrl),
            _modifierChip('ALT', Modifier.alt, _alt),
            _modifierChip('SHIFT', Modifier.shift, _shift),
            _chip('TAB', () => _sendWithModifiers('\t')),
            _iconChip(Icons.arrow_upward_rounded, () => _send('\x1b[A')),
            _iconChip(Icons.arrow_downward_rounded, () => _send('\x1b[B')),
            _iconChip(Icons.arrow_back_rounded, () => _send('\x1b[D')),
            _iconChip(Icons.arrow_forward_rounded, () => _send('\x1b[C')),
          ]),
          _buildRow([
            _chip('FN', () {
              setState(() => _showFunctionKeys = !_showFunctionKeys);
            }, active: _showFunctionKeys),
            _chip('HOME', () => _send('\x1b[H')),
            _chip('END', () => _send('\x1b[F')),
            _chip('PgUp', () => _send('\x1b[5~')),
            _chip('PgDn', () => _send('\x1b[6~')),
            _chip('INS', () => _send('\x1b[2~')),
            _iconChip(Icons.keyboard_return_rounded, () => _send('\r')),
            _iconChip(Icons.backspace_rounded, () => _send('\x7f')),
            _chip('DEL', () => _send('\x1b[3~')),
            _dividerWidget(),
            _iconChip(Icons.select_all_rounded, () => widget.onSelectAll?.call()),
            _iconChip(Icons.copy_rounded, () => widget.onCopy?.call()),
            _iconChip(Icons.paste_rounded, () => widget.onPaste?.call()),
          ]),
          if (_showFunctionKeys)
            _buildRow([
              for (var i = 1; i <= 12; i++)
                _chip('F$i', () => _send(_functionKeySequence(i))),
            ]),
        ],
      ),
    );
  }

  Widget _buildRow(List<Widget> children) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: children,
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap, {bool active = false}) {
    return _TerminalKeyButton(
      label: label,
      onTap: onTap,
      color: active ? Colors.white : _foreground,
      background: active ? _activeBackground : _chipBackground,
      border: active ? _foreground : _chipBorder,
    );
  }

  Widget _modifierChip(String label, Modifier modifier, bool active) {
    return _TerminalKeyButton(
      label: label,
      onTap: () {
        setState(() {
          switch (modifier) {
            case Modifier.ctrl:
              _ctrl = !_ctrl;
              break;
            case Modifier.alt:
              _alt = !_alt;
              break;
            case Modifier.shift:
              _shift = !_shift;
              break;
          }
        });
        _notifyModifiers();
      },
      color: active ? Colors.white : _mutedForeground,
      background: active ? _activeBackground : _chipBackground,
      border: active ? _foreground : _chipBorder,
      minWidth: 42,
    );
  }

  Widget _iconChip(IconData icon, VoidCallback onTap) {
    return _TerminalKeyButton(
      icon: icon,
      onTap: onTap,
      color: _foreground,
      background: _chipBackground,
      border: _chipBorder,
      minWidth: 31,
    );
  }

  Widget _dividerWidget() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      color: _divider,
    );
  }

  void _send(String sequence) {
    widget.onSendSequence(sequence);
    // The parent must see the active modifiers while it encodes the sequence.
    // Reset only after dispatching so arrow keys and function keys do not
    // silently lose Ctrl/Alt/Shift.
    _resetModifiers();
  }

  void _sendWithModifiers(String value) {
    // Modifier encoding is centralized in the terminal owner. This method is
    // retained as the semantic entry point for text-like keys such as TAB.
    _send(value);
  }

  void _resetModifiers() {
    setState(() {
      _ctrl = false;
      _alt = false;
      _shift = false;
    });
    _notifyModifiers();
  }

  void _notifyModifiers() {
    widget.onModifierChanged(
      _ctrl,
      _alt,
      _shift,
      _resetModifiers,
    );
  }

  String _functionKeySequence(int key) {
    return switch (key) {
      1 => '\x1bOP',
      2 => '\x1bOQ',
      3 => '\x1bOR',
      4 => '\x1bOS',
      5 => '\x1b[15~',
      6 => '\x1b[17~',
      7 => '\x1b[18~',
      8 => '\x1b[19~',
      9 => '\x1b[20~',
      10 => '\x1b[21~',
      11 => '\x1b[23~',
      _ => '\x1b[24~',
    };
  }
}

enum Modifier { ctrl, alt, shift }

class _TerminalKeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color color;
  final Color background;
  final Color border;
  final double minWidth;

  const _TerminalKeyButton({
    this.label,
    this.icon,
    required this.onTap,
    required this.color,
    required this.background,
    required this.border,
    this.minWidth = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            constraints: BoxConstraints(minWidth: minWidth, minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: border, width: 0.6),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 14, color: color)
                : Text(
                    label!,
                    style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}