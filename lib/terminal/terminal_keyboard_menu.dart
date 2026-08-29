import 'package:flutter/material.dart';

// Terminal keyboard menu — compact single-row scrollable bar.
// Provides: modifier toggle (Ctrl/Alt/Shift), ESC, arrows, PgUp/PgDn,
// Home/End, Tab, common Ctrl shortcuts, special chars, copy/paste.

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
  bool _isExpanded = true;  // collapse/expand toggle

  void _resetModifiers() {
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

  /// Apply active modifiers to a character and send.
  void _sendWithModifiers(String char) {
    String seq = char;
    if (isCtrlActive && char.length == 1) {
      final c = char.toLowerCase();
      final code = c.codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        // a=0x01 .. z=0x1a
        seq = String.fromCharCode(code - 96);
      } else if (c == '[') {
        seq = '\x1b';
      } else if (c == '\\') {
        seq = '\x1c';
      } else if (c == ']') {
        seq = '\x1d';
      } else if (c == '^') {
        seq = '\x1e';
      } else if (c == '_') {
        seq = '\x1f';
      } else if (c == '?') {
        seq = '\x7f'; // DEL
      } else if (c == ' ') {
        seq = '\x00'; // NUL
      }
    }
    if (isAltActive) {
      seq = '\x1b' + seq;
    }
    widget.onSendSequence(seq);
    _resetModifiers();
  }

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );
    const activeStyle = TextStyle(
      color: Color(0xffffd700),
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );
    const shortcutStyle = TextStyle(
      color: Color(0xff90caf9),
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );
    const divColor = Color(0xff454545);
    const chipBg = Color(0xff2d2d2d);
    const activeBg = Color(0xff3a3000);
    const chipBorder = Color(0xff454545);
    const activeBorder = Color(0xffffd700);
    const shortcutBg = Color(0xff1a2a3a);
    const shortcutBorder = Color(0xff2a4a6a);

    Widget chip(String label, VoidCallback onTap, {bool active = false}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: active ? activeBg : chipBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? activeBorder : chipBorder,
              width: 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Text(label, style: active ? activeStyle : baseStyle),
        ),
      );
    }

    /// Shortcut chip — sends a fixed control sequence directly (bypasses modifiers).
    Widget shortcutChip(String label, String seq) {
      return GestureDetector(
        onTap: () {
          _resetModifiers();
          widget.onSendSequence(seq);
        },
        child: Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: shortcutBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: shortcutBorder, width: 0.8),
          ),
          alignment: Alignment.center,
          child: Text(label, style: shortcutStyle),
        ),
      );
    }

    Widget iconChip(IconData icon, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          width: 36,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: chipBorder, width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      );
    }

    Widget div() => Container(
      width: 1,
      height: 20,
      color: divColor,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Dongle handle (tap to collapse/expand)
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            height: 20,
            color: const Color(0xff181818),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xff555555),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 14,
                    color: Color(0xff888888),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Keyboard bar (2 rows when expanded)
        if (_isExpanded)
          Container(
            color: const Color(0xff181818),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: modifiers + core keys + shortcuts
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                // ── Core keys ──
                chip('ESC', () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b');
                }),
                chip('CTRL', _toggleCtrl, active: isCtrlActive),
                chip('ALT', _toggleAlt, active: isAltActive),
                chip('SHIFT', _toggleShift, active: isShiftActive),
                chip('TAB', () => _sendWithModifiers('\t')),
                chip('SPC', () => _sendWithModifiers(' ')),
                div(),
                // ── Common Ctrl shortcuts (direct sequences) ──
                shortcutChip('CtrlC', '\x03'),   // SIGINT
                shortcutChip('CtrlZ', '\x1a'),   // SIGTSTP
                shortcutChip('CtrlD', '\x04'),   // EOF
                shortcutChip('CtrlL', '\x0c'),   // clear
                shortcutChip('CtrlA', '\x01'),   // home
                shortcutChip('CtrlE', '\x05'),   // end
                shortcutChip('CtrlK', '\x0b'),   // kill line
                shortcutChip('CtrlU', '\x15'),   // kill before
                shortcutChip('CtrlW', '\x17'),   // delete word
              ],
                    ),
                  ),
                  // Row 2: arrows + nav + special chars + copy/paste
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                // ── Arrows ──
                iconChip(Icons.arrow_upward_rounded, () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[A');
                }),
                iconChip(Icons.arrow_downward_rounded, () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[B');
                }),
                iconChip(Icons.arrow_back_rounded, () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[D');
                }),
                iconChip(Icons.arrow_forward_rounded, () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[C');
                }),
                div(),
                // ── Navigation ──
                chip('HOME', () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[H');
                }),
                chip('END', () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[F');
                }),
                chip('PgUp', () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[5~');
                }),
                chip('PgDn', () {
                  _resetModifiers();
                  widget.onSendSequence('\x1b[6~');
                }),
                div(),
                // ── Special chars ──
                chip('|', () => _sendWithModifiers('|')),
                chip('&', () => _sendWithModifiers('&')),
                chip(';', () => _sendWithModifiers(';')),
                chip('~', () => _sendWithModifiers('~')),
                chip('.', () => _sendWithModifiers('.')),
                chip('/', () => _sendWithModifiers('/')),
                chip('\\', () => _sendWithModifiers('\\')),
                chip('`', () => _sendWithModifiers('`')),
                chip('"', () => _sendWithModifiers('"')),
                chip("'", () => _sendWithModifiers("'")),
                div(),
                chip('(', () => _sendWithModifiers('(')),
                chip(')', () => _sendWithModifiers(')')),
                chip('{', () => _sendWithModifiers('{')),
                chip('}', () => _sendWithModifiers('}')),
                chip('[', () => _sendWithModifiers('[')),
                chip(']', () => _sendWithModifiers(']')),
                chip('!', () => _sendWithModifiers('!')),
                chip('#', () => _sendWithModifiers('#')),
                chip('%', () => _sendWithModifiers('%')),
                chip('^', () => _sendWithModifiers('^')),
                chip('@', () => _sendWithModifiers('@')),
                chip('*', () => _sendWithModifiers('*')),
                chip('>', () => _sendWithModifiers('>')),
                chip('<', () => _sendWithModifiers('<')),
                div(),
                // ── Copy / Paste ──
                iconChip(Icons.copy_rounded, () => widget.onCopy?.call()),
                iconChip(Icons.paste_rounded, () => widget.onPaste?.call()),
              ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
