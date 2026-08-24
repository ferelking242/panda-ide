import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents a code symbol in the outline view.
class CodeSymbol {
  final String name;
  final SymbolKind kind;
  final int line;
  final int character;
  final List<CodeSymbol> children;
  final bool isDeprecated;

  const CodeSymbol({
    required this.name,
    required this.kind,
    required this.line,
    this.character = 0,
    this.children = const [],
    this.isDeprecated = false,
  });
}

enum SymbolKind {
  file,
  module,
  namespace,
  package,
  class_,
  method,
  property,
  field,
  constructor,
  enum_,
  interface,
  function,
  variable,
  constant,
  string,
  number,
  boolean,
  array,
}

/// VS Code-style outline/symbols panel.
class OutlineView extends StatefulWidget {
  final List<CodeSymbol> symbols;
  final void Function(CodeSymbol symbol) onSymbolTap;
  final int? activeLine;

  const OutlineView({
    super.key,
    required this.symbols,
    required this.onSymbolTap,
    this.activeLine,
  });

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? widget.symbols
        : widget.symbols.where((s) => s.name.toLowerCase().contains(_filter.toLowerCase())).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Outline...',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 16),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        // Symbol list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No symbols',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _buildSymbolTile(filtered[i], 0),
                ),
        ),
      ],
    );
  }

  Widget _buildSymbolTile(CodeSymbol symbol, int depth) {
    final isActive = widget.activeLine == symbol.line;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onSymbolTap(symbol),
          child: Container(
            padding: EdgeInsets.only(left: 8.0 + depth * 16.0, right: 8, top: 4, bottom: 4),
            color: isActive ? cs.primaryContainer.withValues(alpha: 0.3) : null,
            child: Row(
              children: [
                Icon(_symbolIcon(symbol.kind), size: 14, color: _symbolColor(symbol.kind)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    symbol.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: symbol.kind == SymbolKind.class_ || symbol.kind == SymbolKind.interface_
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: symbol.isDeprecated ? Colors.grey : null,
                      decoration: symbol.isDeprecated ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        ...symbol.children.map((child) => _buildSymbolTile(child, depth + 1)),
      ],
    );
  }

  IconData _symbolIcon(SymbolKind kind) {
    switch (kind) {
      case SymbolKind.class_: return Icons.class_;
      case SymbolKind.interface_: return Icons.device_hub;
      case SymbolKind.enum_: return Icons.list;
      case SymbolKind.method: return Icons.functions;
      case SymbolKind.function_: return Icons.code;
      case SymbolKind.property: return Icons.tune;
      case SymbolKind.field: return Icons.input;
      case SymbolKind.variable: return Icons.change_history;
      case SymbolKind.constant: return Icons.lock;
      case SymbolKind.constructor: return Icons.construction;
      case SymbolKind.module: return Icons.folder;
      case SymbolKind.namespace: return Icons.language;
      case SymbolKind.file: return Icons.insert_drive_file;
      default: return Icons.circle;
    }
  }

  Color _symbolColor(SymbolKind kind) {
    switch (kind) {
      case SymbolKind.class_: return Colors.blue;
      case SymbolKind.interface_: return Colors.purple;
      case SymbolKind.enum_: return Colors.orange;
      case SymbolKind.method: return Colors.teal;
      case SymbolKind.function_: return Colors.cyan;
      case SymbolKind.property: return Colors.green;
      case SymbolKind.field: return Colors.brown;
      case SymbolKind.variable: return Colors.indigo;
      case SymbolKind.constant: return Colors.amber;
      case SymbolKind.constructor: return Colors.deepOrange;
      default: return Colors.grey;
    }
  }
}
