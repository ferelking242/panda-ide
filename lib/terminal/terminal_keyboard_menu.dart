import 'package:flutter/material.dart';

/// Touch keyboard for the terminal.
///
/// The compact state intentionally mirrors the Android terminal layout:
/// modifier keys on the left and a four-way arrow cluster on the right.
/// Less frequently used keys stay behind the more button so the primary row
/// never becomes a cramped, horizontally scrolling wall of controls.
class TerminalKeyboardMenu extends StatefulWidget {
  final Function(String) onSendSequence;
  final Function(bool ctrl, bool alt, bool shift, VoidCallback resetCallback)
      onModifierChanged;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;

  const TerminalKeyboardMenu({
    super.key,
    required this.onSendSequence,
    required this.onModifierChanged,
    this.onCopy,
    this.onPaste,
  });

  @override
  State<TerminalKeyboardMenu> createState() => _TerminalKeyboardMenuState();
}

class _TerminalKeyboardMenuState extends State<TerminalKeyboardMenu> {
  bool isCtrlActive = false;
  bool isAltActive = false;
  bool isShiftActive = false;
  bool _isExpanded = false;

  static const _surface = Color(0xff17181b);
  static const _key = Color(0xff2b2d32);
  static const _border = Color(0xff42454d);
  static const _blueBorder = Color(0xff4f83b6);
  static const _blueText = Color(0xffc7e3ff);

  void _resetModifiers() {
    if (!mounted) return;
    setState(() {
      isCtrlActive = false;
      isAltActive = false;
      isShiftActive = false;
    });
    _notifyModifiers();
  }

  void _notifyModifiers() {
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleCtrl() {
    setState(() => isCtrlActive = !isCtrlActive);
    _notifyModifiers();
  }

  void _toggleAlt() {
    setState(() => isAltActive = !isAltActive);
    _notifyModifiers();
  }

  void _toggleShift() {
    setState(() => isShiftActive = !isShiftActive);
    _notifyModifiers();
  }

  /// Apply active modifiers to a character and send it to the PTY.
  void _sendWithModifiers(String char) {
    String sequence = char;
    if (isCtrlActive && char.length == 1) {
      final code = char.toLowerCase().codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        sequence = String.fromCharCode(code - 96);
      } else {
        sequence = switch (char) {
          '[' => '\x1b',
          '\\' => '\x1c',
          ']' => '\x1d',
          '^' => '\x1e',
          '_' => '\x1f',
          '?' => '\x7f',
          ' ' => '\x00',
          _ => char,
        };
      }
    }
    if (isAltActive) sequence = '\x1b$sequence';
    widget.onSendSequence(sequence);
    _resetModifiers();
  }

  void _send(String sequence) {
    _resetModifiers();
    widget.onSendSequence(sequence);
  }

  Widget _keyButton(
    String label,
    VoidCallback onTap, {
    bool active = false,
    bool shortcut = false,
    double minWidth = 37,
  }) {
    final borderColor = active
        ? const Color(0xffffc857)
        : shortcut
            ? _blueBorder
            : _border;
    final textColor = active
        ? const Color(0xffffd978)
        : shortcut
            ? _blueText
            : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Material(
        color: active ? const Color(0xff443816) : shortcut ? const Color(0xff1e2c3b) : _key,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 34,
            constraints: BoxConstraints(minWidth: minWidth),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 0.8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: label.length > 4 ? 10.5 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    IconData icon,
    VoidCallback onTap, {
    String? tooltip,
    bool shortcut = false,
    double width = 43,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: shortcut ? const Color(0xff1e2c3b) : _key,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 34,
              width: width,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: shortcut ? _blueBorder : _border,
                  width: 0.8,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 19,
                color: shortcut ? _blueText : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _separator() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white.withValues(alpha: 0.12),
      );

  Widget _primaryRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        children: [
          _keyButton('ESC', () => _send('\x1b')),
          _keyButton('CTRL', _toggleCtrl, active: isCtrlActive, minWidth: 46),
          _keyButton('ALT', _toggleAlt, active: isAltActive, minWidth: 42),
          _keyButton('SHIFT', _toggleShift, active: isShiftActive, minWidth: 49),
          _keyButton('TAB', () => _sendWithModifiers('\t')),
          _separator(),
          _iconButton(Icons.arrow_upward_rounded, () => _send('\x1b[A'), tooltip: 'Flèche haut'),
          _iconButton(Icons.arrow_downward_rounded, () => _send('\x1b[B'), tooltip: 'Flèche bas'),
          _iconButton(Icons.arrow_back_rounded, () => _send('\x1b[D'), tooltip: 'Flèche gauche'),
          _iconButton(Icons.arrow_forward_rounded, () => _send('\x1b[C'), tooltip: 'Flèche droite'),
          _separator(),
          _iconButton(
            _isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.more_horiz_rounded,
            () => setState(() => _isExpanded = !_isExpanded),
            tooltip: _isExpanded ? 'Réduire le clavier' : 'Plus de touches',
            shortcut: true,
            width: 38,
          ),
        ],
      ),
    );
  }

  Widget _expandedRows() {
    Widget shortcut(String label, String sequence) => _keyButton(
          label,
          () {
            _resetModifiers();
            widget.onSendSequence(sequence);
          },
          shortcut: true,
          minWidth: 48,
        );

    Widget symbol(String value) => _keyButton(value, () => _sendWithModifiers(value));

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: !_isExpanded
          ? const SizedBox.shrink()
          : Column(
              children: [
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Row(
                    children: [
                      shortcut('Ctrl+C', '\x03'),
                      shortcut('Ctrl+Z', '\x1a'),
                      shortcut('Ctrl+D', '\x04'),
                      shortcut('Ctrl+L', '\x0c'),
                      shortcut('Ctrl+A', '\x01'),
                      shortcut('Ctrl+E', '\x05'),
                      shortcut('Ctrl+K', '\x0b'),
                      shortcut('Ctrl+U', '\x15'),
                      shortcut('Ctrl+W', '\x17'),
                      _separator(),
                      _keyButton('HOME', () => _send('\x1b[H'), minWidth: 48),
                      _keyButton('END', () => _send('\x1b[F'), minWidth: 48),
                      _keyButton('PgUp', () => _send('\x1b[5~'), minWidth: 48),
                      _keyButton('PgDn', () => _send('\x1b[6~'), minWidth: 48),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Row(
                    children: [
                      for (final value in const [
                        '|', '&', ';', '~', '.', '/', '\\', '`', '"', "'", '(', ')',
                        '{', '}', '[', ']', '!', '#', '%', '^', '@', '*', '>', '<',
                      ])
                        symbol(value),
                      _separator(),
                      _iconButton(Icons.copy_rounded, () => widget.onCopy?.call(),
                          tooltip: 'Copier', shortcut: true),
                      _iconButton(Icons.paste_rounded, () => widget.onPaste?.call(),
                          tooltip: 'Coller', shortcut: true),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The outside breathing room is what makes all four corners visible,
      // matching the rounded workspace bar instead of looking edge-to-edge.
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A small handle gives touch users an obvious affordance without
                // consuming a second permanent row in the compact layout.
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: SizedBox(
                    height: 7,
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
                _primaryRow(),
                _expandedRows(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}