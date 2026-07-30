/// CommandPalette — interface VSCode style ">" — Phase 5.
///
/// Bottom sheet modal filtrable listant toutes les commandes des extensions.
/// Accessible via Ctrl+Shift+P ou un bouton dans l'AppBar.
///
/// Usage :
///   CommandPalette.show(context);
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../command_registry.dart';

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// Affiche la CommandPalette dans un bottom sheet modal.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CommandPaletteSheet(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  @override
  Widget build(BuildContext context) {
    return const _CommandPaletteSheet();
  }
}

// ── Bottom sheet interne ──────────────────────────────────────────────────

class _CommandPaletteSheet extends StatefulWidget {
  const _CommandPaletteSheet();

  @override
  State<_CommandPaletteSheet> createState() => __CommandPaletteSheetState();
}

class __CommandPaletteSheetState extends State<_CommandPaletteSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<RegisteredCommand> _results = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _results = CommandRegistry.instance.all;
    _ctrl.addListener(_onQuery);
    // Focus automatique sur le champ de recherche
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onQuery);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQuery() {
    final filtered = CommandRegistry.instance.search(_ctrl.text);
    setState(() {
      _results = filtered;
      _selectedIndex = 0;
    });
  }

  void _execute(RegisteredCommand cmd) {
    Navigator.of(context).pop();
    CommandRegistry.instance.execute(cmd.command, []);
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex =
          (_selectedIndex + delta).clamp(0, _results.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor    = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final inputBg    = isDark ? const Color(0xFF3C3C3C) : Colors.white;
    final selColor   = isDark ? const Color(0xFF094771) : const Color(0xFFD6EBFF);
    final textColor  = isDark ? Colors.white : Colors.black87;
    final hintColor  = isDark ? Colors.white38 : Colors.black38;
    final borderCol  = isDark ? const Color(0xFF454545) : const Color(0xFFD4D4D4);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Drag handle ────────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: hintColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Search input ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _moveSelection(1);
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _moveSelection(-1);
                    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                      if (_results.isNotEmpty) {
                        _execute(_results[_selectedIndex]);
                      }
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  style: TextStyle(color: textColor, fontSize: 14),
                  cursorColor: const Color(0xFF0066B8),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputBg,
                    hintText: 'Type a command name…',
                    hintStyle: TextStyle(color: hintColor, fontSize: 14),
                    prefixIcon: Icon(Icons.terminal, color: hintColor, size: 18),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, color: hintColor, size: 18),
                            onPressed: () => _ctrl.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderCol),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderCol),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFF0066B8), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),

            // ── Count label ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  Text(
                    '${_results.length} commands',
                    style: TextStyle(color: hintColor, fontSize: 11),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // ── Results list ───────────────────────────────────────────────
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        'No commands match "${_ctrl.text}"',
                        style: TextStyle(color: hintColor, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: _results.length,
                      itemExtent: 44,
                      itemBuilder: (_, i) {
                        final cmd = _results[i];
                        final isSelected = i == _selectedIndex;
                        return Material(
                          color: isSelected ? selColor : Colors.transparent,
                          child: InkWell(
                            onTap: () => _execute(cmd),
                            onHover: (h) {
                              if (h) setState(() => _selectedIndex = i);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Row(
                                children: [
                                  // Category badge
                                  if (cmd.category != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0066B8)
                                            .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        cmd.category!,
                                        style: const TextStyle(
                                          color: Color(0xFF0066B8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  // Label
                                  Expanded(
                                    child: Text(
                                      cmd.title ?? cmd.command,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Extension ID
                                  Text(
                                    cmd.extensionId,
                                    style: TextStyle(
                                      color: hintColor,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
