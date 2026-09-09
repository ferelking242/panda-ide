/// Symbol picker — navigate to symbols in the current file (Ctrl+Shift+O).
library;
import 'dart:async';
import 'package:flutter/material.dart';




/// Represents a symbol in the current file.
class FileSymbol {
  final String name;
  final String kind; // 'class', 'method', 'function', 'variable', 'enum', 'interface'
  final int line;
  final int column;
  final String? detail;
  final List<FileSymbol> children;

  const FileSymbol({
    required this.name,
    required this.kind,
    required this.line,
    this.column = 0,
    this.detail,
    this.children = const [],
  });

  IconData get icon {
    switch (kind) {
      case 'class': return Icons.class_;
      case 'method': return Icons.functions;
      case 'function': return Icons.code;
      case 'variable': return Icons.data_object;
      case 'enum': return Icons.list;
      case 'interface': return Icons.device_hub;
      case 'property': return Icons.label;
      case 'constant': return Icons.lock;
      case 'constructor': return Icons.build;
      case 'field': return Icons.view_sidebar;
      default: return Icons.help_outline;
    }
  }

  Color get color {
    switch (kind) {
      case 'class': return const Color(0xFF4CAF50);
      case 'method': return const Color(0xFF2196F3);
      case 'function': return const Color(0xFF9C27B0);
      case 'variable': return const Color(0xFFFF9800);
      case 'enum': return const Color(0xFF00BCD4);
      case 'constant': return const Color(0xFFE91E63);
      default: return const Color(0xFF607D8B);
    }
  }
}

/// Extracts symbols from code using simple regex parsing.
class SymbolExtractor {
  static List<FileSymbol> extract(String code, {String? language}) {
    final lines = code.split('\n');
    final symbols = <FileSymbol>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Class
      final classMatch = RegExp(r'^(?:abstract\s+)?class\s+(\w+)').firstMatch(line);
      if (classMatch != null) {
        symbols.add(FileSymbol(
          name: classMatch.group(1)!, kind: 'class', line: i,
        ));
        continue;
      }

      // Enum
      final enumMatch = RegExp(r'^enum\s+(\w+)').firstMatch(line);
      if (enumMatch != null) {
        symbols.add(FileSymbol(
          name: enumMatch.group(1)!, kind: 'enum', line: i,
        ));
        continue;
      }

      // Method/function
      final methodMatch = RegExp(r'^(?:static\s+)?(?:Future|Stream|void|int|String|bool|double|dynamic|List|Map|Set|[\w<>]+)\s+(\w+)\s*[\(<]').firstMatch(line);
      if (methodMatch != null) {
        final isStatic = line.contains('static');
        symbols.add(FileSymbol(
          name: methodMatch.group(1)!,
          kind: isStatic ? 'function' : 'method',
          line: i,
        ));
        continue;
      }

      // Variable
      final varMatch = RegExp(r'^(?:final|const|var|late)\s+[\w<>,\s]+\s+(\w+)\s*[=;]').firstMatch(line);
      if (varMatch != null) {
        symbols.add(FileSymbol(
          name: varMatch.group(1)!, kind: 'variable', line: i,
        ));
      }
    }

    return symbols;
  }
}

/// Shows a symbol picker dialog.
class SymbolPicker extends StatefulWidget {
  final List<FileSymbol> symbols;
  final void Function(FileSymbol symbol) onSelected;

  const SymbolPicker({
    super.key,
    required this.symbols,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<FileSymbol> symbols,
    required void Function(FileSymbol symbol) onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SymbolPicker(symbols: symbols, onSelected: onSelected),
    );
  }

  @override
  State<SymbolPicker> createState() => _SymbolPickerState();
}

class _SymbolPickerState extends State<SymbolPicker> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<FileSymbol> _filtered = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _filtered = widget.symbols;
    _ctrl.addListener(_filter);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _ctrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.symbols
          : widget.symbols.where((s) => s.name.toLowerCase().contains(q)).toList();
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl, focusNode: _focus,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search symbols...',
                  prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                  isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  filled: true, fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final sym = _filtered[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(sym.icon, size: 16, color: sym.color),
                    title: Text(sym.name, style: TextStyle(fontSize: 13, color: cs.onSurface, fontFamily: 'monospace')),
                    subtitle: Text('L${sym.line + 1} • ${sym.kind}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                    onTap: () { Navigator.pop(context); widget.onSelected(sym); },
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
