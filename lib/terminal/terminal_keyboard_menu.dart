import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/render.dart' show RenderTerminal;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../ui/notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/alpine_setup.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/panda_log.dart';
import '../utils/themes.dart';
import './terminal_bridge.dart';

// Terminal keyboard menu overlay
// Extracted from terminal_native.dart

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

  void _resetModifiers() {
    setState(() {
      isCtrlActive = false;
      isAltActive = false;
      isShiftActive = false;
    });
  }

  void _toggleCtrl() {
    setState(() {
      isCtrlActive = !isCtrlActive;
      if (isCtrlActive) {
        isAltActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleAlt() {
    setState(() {
      isAltActive = !isAltActive;
      if (isAltActive) {
        isCtrlActive = false;
        isShiftActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  void _toggleShift() {
    setState(() {
      isShiftActive = !isShiftActive;
      if (isShiftActive) {
        isCtrlActive = false;
        isAltActive = false;
      }
    });
    widget.onModifierChanged(
      isCtrlActive,
      isAltActive,
      isShiftActive,
      _resetModifiers,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Compact single-row scrollable keyboard bar — ~44px height vs old ~90px.
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
    const divColor = Color(0xff454545);
    const chipBg   = Color(0xff2d2d2d);
    const activeBg = Color(0xff3a3000);
    const chipBorder = Color(0xff454545);
    const activeBorder = Color(0xffffd700);

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

    return Container(
      height: 44,
      color: const Color(0xff181818),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            chip('ESC',   () => widget.onSendSequence('\x1b')),
            chip('CTRL',  _toggleCtrl,  active: isCtrlActive),
            chip('ALT',   _toggleAlt,   active: isAltActive),
            chip('SHIFT', _toggleShift, active: isShiftActive),
            chip('TAB',   () => widget.onSendSequence('\t')),
            div(),
            iconChip(Icons.arrow_upward_rounded,  () => widget.onSendSequence('\x1b[A')),
            iconChip(Icons.arrow_downward_rounded, () => widget.onSendSequence('\x1b[B')),
            iconChip(Icons.arrow_back_rounded,    () => widget.onSendSequence('\x1b[D')),
            iconChip(Icons.arrow_forward_rounded, () => widget.onSendSequence('\x1b[C')),
            div(),
            chip('HOME',  () => widget.onSendSequence('\x1b[H')),
            chip('END',   () => widget.onSendSequence('\x1b[F')),
            chip('PgUp',  () => widget.onSendSequence('\x1b[5~')),
            chip('PgDn',  () => widget.onSendSequence('\x1b[6~')),
            div(),
            chip('|',  () => widget.onSendSequence('|')),
            chip('&',  () => widget.onSendSequence('&')),
            chip(';',  () => widget.onSendSequence(';')),
            chip('~',  () => widget.onSendSequence('~')),
            chip('/',  () => widget.onSendSequence('/')),
            chip('\\', () => widget.onSendSequence('\\')),
            chip('`',  () => widget.onSendSequence('`')),
            chip('"',  () => widget.onSendSequence('"')),
            chip("'",  () => widget.onSendSequence("'")),
            div(),
            chip('(',  () => widget.onSendSequence('(')),
            chip(')',  () => widget.onSendSequence(')')),
            chip('{',  () => widget.onSendSequence('{')),
            chip('}',  () => widget.onSendSequence('}')),
            chip('[',  () => widget.onSendSequence('[')),
            chip(']',  () => widget.onSendSequence(']')),
            chip('!',  () => widget.onSendSequence('!')),
            chip('#',  () => widget.onSendSequence('#')),
            chip('%',  () => widget.onSendSequence('%')),
            chip('^',  () => widget.onSendSequence('^')),
            chip('@',  () => widget.onSendSequence('@')),
            chip('*',  () => widget.onSendSequence('*')),
            chip('>',  () => widget.onSendSequence('>')),
            chip('<',  () => widget.onSendSequence('<')),
            div(),
            iconChip(Icons.copy_rounded,  () => widget.onCopy?.call()),
            iconChip(Icons.paste_rounded, () => widget.onPaste?.call()),
          ],
        ),
      ),
    );
  }
}
