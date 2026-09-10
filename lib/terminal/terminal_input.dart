import 'dart:convert';
import 'dart:typed_data';

/// Encodes terminal input using the conventions used by xterm-compatible
/// Ubuntu terminals.
///
/// Keeping this class independent from Flutter makes the byte mapping usable
/// by the accessory keyboard, Gboard's text input callback, and physical
/// keyboard events without giving any of those paths a different behavior.
class TerminalInputEncoder {
  const TerminalInputEncoder._();

  static Uint8List encodeBytes(
    String value, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool isKeySequence = false,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        _encode(
          value,
          ctrl: ctrl,
          alt: alt,
          shift: shift,
          isKeySequence: isKeySequence,
        ),
      ),
    );
  }

  static String encode(
    String value, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool isKeySequence = false,
  }) {
    return _encode(
      value,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      isKeySequence: isKeySequence,
    );
  }

  static String _encode(
    String value, {
    required bool ctrl,
    required bool alt,
    required bool shift,
    required bool isKeySequence,
  }) {
    if (value.isEmpty) return value;

    if (isKeySequence || value.length > 1 || _isAnsi(value)) {
      return _encodeKeySequence(
        value,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
      );
    }

    var sequence = value;
    if (ctrl) {
      final code = controlCode(sequence);
      if (code != null) {
        sequence = String.fromCharCode(code);
      }
    } else if (shift) {
      // Gboard normally gives us the already-shifted character. This also
      // covers accessory input and platforms that report the base character.
      sequence = sequence.toUpperCase();
    }

    if (alt) sequence = '\x1b$sequence';
    return sequence;
  }

  static String _encodeKeySequence(
    String sequence, {
    required bool ctrl,
    required bool alt,
    required bool shift,
  }) {
    if (sequence == '\t') {
      if (shift) {
        if (!ctrl && !alt) return '\x1b[Z';
        return _modifiedCsi('Z', ctrl: ctrl, alt: alt, shift: true);
      }
      if (ctrl || alt) {
        return _modifiedCsi('I', ctrl: ctrl, alt: alt, shift: false);
      }
      return sequence;
    }

    if (_isAnsi(sequence)) {
      final modifier = _modifierValue(ctrl: ctrl, alt: alt, shift: shift);
      if (modifier == 1) return sequence;
      return _applyAnsiModifier(sequence, modifier);
    }

    if (sequence == '\x7f' && ctrl) {
      // Readline's conventional word erase. Ctrl+Backspace is not a
      // printable control character and must not become DEL.
      return alt ? '\x1b\x17' : '\x17';
    }

    if (sequence.length == 1) {
      var text = sequence;
      if (ctrl) {
        final code = controlCode(text);
        if (code != null) text = String.fromCharCode(code);
      } else if (shift) {
        text = text.toUpperCase();
      }
      if (alt) text = '\x1b$text';
      return text;
    }

    return sequence;
  }

  static String _modifiedCsi(
    String finalByte, {
    required bool ctrl,
    required bool alt,
    required bool shift,
  }) {
    final modifier = _modifierValue(ctrl: ctrl, alt: alt, shift: shift);
    if (modifier == 1) return '\x1b[$finalByte';
    return '\x1b[1;${modifier}$finalByte';
  }

  static String _applyAnsiModifier(String sequence, int modifier) {
    if (sequence.startsWith('\x1bO') && sequence.length == 3) {
      // F1-F4 use SS3 without modifiers and CSI with modifiers.
      return '\x1b[1;${modifier}${sequence.substring(2)}';
    }

    if (!sequence.startsWith('\x1b[') || sequence.length < 3) {
      return sequence;
    }

    final body = sequence.substring(2);
    final finalByte = body.substring(body.length - 1);
    final parameters = body.substring(0, body.length - 1);

    if (finalByte == '~') {
      return '\x1b[$parameters;${modifier}~';
    }
    if (parameters.isEmpty) {
      return '\x1b[1;${modifier}$finalByte';
    }
    return '\x1b[$parameters;${modifier}$finalByte';
  }

  static int _modifierValue({
    required bool ctrl,
    required bool alt,
    required bool shift,
  }) {
    var modifier = 1;
    if (shift) modifier += 1;
    if (alt) modifier += 2;
    if (ctrl) modifier += 4;
    return modifier;
  }

  static bool _isAnsi(String value) {
    return value.startsWith('\x1b[') || value.startsWith('\x1bO');
  }

  /// Returns the POSIX terminal byte for Ctrl+[key].
  static int? controlCode(String value) {
    if (value.length != 1) return null;
    final code = value.toLowerCase().codeUnitAt(0);
    if (code >= 97 && code <= 122) return code - 96;
    return switch (code) {
      0x40 || 0x20 => 0,
      0x5b => 27,
      0x5c => 28,
      0x5d => 29,
      0x5e => 30,
      0x5f => 31,
      0x3f => 127,
      // Number-row aliases produced by common Ubuntu keyboard layouts.
      0x32 => 0,
      0x36 => 30,
      0x2d || 0x2f => 31,
      _ => null,
    };
  }
}