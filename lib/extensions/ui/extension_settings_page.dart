/// Page Settings des extensions — Phase 14.
///
/// Auto-génère une UI de configuration depuis contributes.configuration du manifest.
/// Les settings sont persistés via ConfigStore et synchronisés avec
/// vscode.workspace.getConfiguration() côté JS.
///
/// Usage :
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => ExtensionSettingsPage(extension: installedExt),
///   ));
import 'package:flutter/material.dart';
import '../config_store.dart';
import '../extension_registry.dart';

library;



// ── Settings Schema parser ─────────────────────────────────────────────────

enum SettingType { string, boolean, number, integer, array, object, enumType }

class SettingItem {
  final String key;           // full key ex: "editor.fontSize"
  final String title;         // human label
  final String? description;
  final SettingType type;
  final dynamic defaultValue;
  final List<dynamic>? enumValues;
  final List<String>? enumDescriptions;
  final double? minimum;
  final double? maximum;
  final String? markdownDescription;
  final Map<String, dynamic>? properties; // for object type
  final bool isDeprecated;
  final String? deprecationMessage;

  const SettingItem({
    required this.key,
    required this.title,
    this.description,
    required this.type,
    this.defaultValue,
    this.enumValues,
    this.enumDescriptions,
    this.minimum,
    this.maximum,
    this.markdownDescription,
    this.properties,
    this.isDeprecated = false,
    this.deprecationMessage,
  });

  factory SettingItem.fromJson(String key, Map<String, dynamic> json) {
    SettingType type = SettingType.string;
    final rawType = json['type'] as String?;
    switch (rawType) {
      case 'boolean': type = SettingType.boolean; break;
      case 'number': type = SettingType.number; break;
      case 'integer': type = SettingType.integer; break;
      case 'array': type = SettingType.array; break;
      case 'object': type = SettingType.object; break;
      default:
        if (json.containsKey('enum')) type = SettingType.enumType;
    }

    final enumVals = json['enum'] as List?;

    return SettingItem(
      key: key,
      title: (json['title'] as String?) ?? _keyToTitle(key),
      description: json['description'] as String? ?? json['markdownDescription'] as String?,
      type: type,
      defaultValue: json['default'],
      enumValues: enumVals,
      enumDescriptions: (json['enumDescriptions'] as List?)?.map((e) => e.toString()).toList(),
      minimum: (json['minimum'] as num?)?.toDouble(),
      maximum: (json['maximum'] as num?)?.toDouble(),
      markdownDescription: json['markdownDescription'] as String?,
      properties: json['properties'] as Map<String, dynamic>?,
      isDeprecated: json['deprecationMessage'] != null,
      deprecationMessage: json['deprecationMessage'] as String?,
    );
  }

  static String _keyToTitle(String key) {
    final last = key.split('.').last;
    return last
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .trim()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class SettingsSection {
  final String title;
  final String? description;
  final List<SettingItem> items;

  const SettingsSection({
    required this.title,
    this.description,
    required this.items,
  });
}

List<SettingsSection> parseContributesConfiguration(Map<String, dynamic> contributes) {
  final config = contributes['configuration'];
  if (config == null) return [];

  final sections = <SettingsSection>[];

  void parseSection(Map<String, dynamic> section) {
    final title = section['title'] as String? ?? 'Settings';
    final description = section['description'] as String?;
    final properties = section['properties'] as Map<String, dynamic>? ?? {};

    final items = properties.entries
        .map((e) => SettingItem.fromJson(e.key, e.value as Map<String, dynamic>))
        .where((s) => !s.isDeprecated)
        .toList();

    if (items.isNotEmpty) {
      sections.add(SettingsSection(title: title, description: description, items: items));
    }
  }

  if (config is Map<String, dynamic>) {
    parseSection(config);
  } else if (config is List) {
    for (final section in config) {
      if (section is Map<String, dynamic>) parseSection(section);
    }
  }

  return sections;
}

// ── Settings Page ─────────────────────────────────────────────────────────────

class ExtensionSettingsPage extends StatefulWidget {
  final InstalledExtension extension;

  const ExtensionSettingsPage({super.key, required this.extension});

  @override
  State<ExtensionSettingsPage> createState() => _ExtensionSettingsPageState();
}

class _ExtensionSettingsPageState extends State<ExtensionSettingsPage> {
  List<SettingsSection> _sections = [];
  bool _loading = true;
  bool _hasChanges = false;

  // Current values for all settings
  final Map<String, dynamic> _values = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final contributes = widget.extension.manifest.raw['contributes'] as Map<String, dynamic>?;
    if (contributes == null) {
      setState(() => _loading = false);
      return;
    }

    final sections = parseContributesConfiguration(contributes);

    // Load current values from ConfigStore
    for (final section in sections) {
      for (final item in section.items) {
        final parts = item.key.split('.');
        final sectionKey = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : null;
        final valueKey = parts.last;
        final config = ConfigStore.instance.getSectionProxy(sectionKey);
        final stored = (config['items'] as Map<String, dynamic>?)?[valueKey];
        _values[item.key] = stored ?? item.defaultValue;
      }
    }

    setState(() {
      _sections = sections;
      _loading = false;
    });
  }

  Future<void> _updateValue(SettingItem item, dynamic value) async {
    setState(() {
      _values[item.key] = value;
      _hasChanges = true;
    });

    // Persist immediately
    final parts = item.key.split('.');
    final sectionKey = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : null;
    final valueKey = parts.last;
    await ConfigStore.instance.update(sectionKey, valueKey, value, 1);
  }

  Future<void> _resetToDefaults() async {
    for (final section in _sections) {
      for (final item in section.items) {
        await _updateValue(item, item.defaultValue);
      }
    }
    setState(() => _hasChanges = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cs     = theme.colorScheme;
    final appBarBg = theme.appBarTheme.backgroundColor ?? cs.surface;
    final appBarFg = theme.appBarTheme.foregroundColor ?? cs.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        title: Text(
          '${widget.extension.manifest.displayName} — Settings',
          style: TextStyle(fontSize: 15, color: appBarFg),
        ),
        elevation: 0,
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _resetToDefaults,
              child: Text('Reset',
                  style: TextStyle(fontSize: 12, color: cs.primary)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sections.isEmpty
              ? _NoSettings(extensionName: widget.extension.manifest.displayName)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sections.length,
                  itemBuilder: (_, i) => _SettingsSectionWidget(
                    section: _sections[i],
                    values: _values,
                    onChanged: _updateValue,
                    isDark: isDark,
                  ),
                ),
    );
  }
}

// ── Section widget ────────────────────────────────────────────────────────────

class _SettingsSectionWidget extends StatelessWidget {
  final SettingsSection section;
  final Map<String, dynamic> values;
  final Future<void> Function(SettingItem, dynamic) onChanged;
  final bool isDark;

  const _SettingsSectionWidget({
    required this.section,
    required this.values,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = isDark ? Colors.white54 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (section.description != null)
                Text(
                  section.description!,
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 4),

        // Setting items
        ...section.items.map((item) => _SettingItemWidget(
          item: item,
          value: values[item.key],
          onChanged: (v) => onChanged(item, v),
          isDark: isDark,
        )),
      ],
    );
  }
}

// ── Setting item widget ───────────────────────────────────────────────────────

class _SettingItemWidget extends StatelessWidget {
  final SettingItem item;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool isDark;

  const _SettingItemWidget({
    required this.item,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = isDark ? Colors.white54 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      item.key,
                      style: TextStyle(fontSize: 10, color: subColor, fontFamily: 'monospace'),
                    ),
                    if (item.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.description!,
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildControl(context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControl(BuildContext context) {
    switch (item.type) {
      case SettingType.boolean:
        return Switch(
          value: (value as bool?) ?? (item.defaultValue as bool?) ?? false,
          onChanged: onChanged,
          activeColor: const Color(0xFF0066B8),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );

      case SettingType.number:
      case SettingType.integer:
        return SizedBox(
          width: 80,
          child: _NumberField(
            value: (value as num?)?.toDouble() ?? (item.defaultValue as num?)?.toDouble() ?? 0,
            minimum: item.minimum,
            maximum: item.maximum,
            isInteger: item.type == SettingType.integer,
            onChanged: (v) => onChanged(item.type == SettingType.integer ? v.toInt() : v),
            isDark: isDark,
          ),
        );

      case SettingType.enumType:
        final enumVals = item.enumValues ?? [];
        final current = value?.toString() ?? item.defaultValue?.toString();
        return DropdownButton<String>(
          value: enumVals.contains(current) ? current : null,
          hint: Text(current ?? 'Select', style: const TextStyle(fontSize: 12)),
          style: const TextStyle(fontSize: 12),
          underline: const SizedBox(),
          isDense: true,
          items: enumVals.map((e) {
            final idx = enumVals.indexOf(e);
            final label = item.enumDescriptions != null && idx < item.enumDescriptions!.length
                ? item.enumDescriptions![idx]
                : e.toString();
            return DropdownMenuItem(
              value: e.toString(),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
          onChanged: onChanged,
        );

      default:
        // String / array / object → text field
        return SizedBox(
          width: 160,
          child: _StringField(
            value: value?.toString() ?? item.defaultValue?.toString() ?? '',
            onSubmitted: onChanged,
            isDark: isDark,
          ),
        );
    }
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _NumberField extends StatefulWidget {
  final double value;
  final double? minimum;
  final double? maximum;
  final bool isInteger;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _NumberField({
    required this.value,
    this.minimum,
    this.maximum,
    required this.isInteger,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.isInteger ? widget.value.toInt().toString() : widget.value.toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: !widget.isInteger),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onSubmitted: (v) {
        final n = double.tryParse(v);
        if (n == null) return;
        final clamped = n.clamp(
          widget.minimum ?? double.negativeInfinity,
          widget.maximum ?? double.infinity,
        );
        widget.onChanged(clamped);
      },
    );
  }
}

class _StringField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onSubmitted;
  final bool isDark;

  const _StringField({required this.value, required this.onSubmitted, required this.isDark});

  @override
  State<_StringField> createState() => _StringFieldState();
}

class _StringFieldState extends State<_StringField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onSubmitted: widget.onSubmitted,
      onEditingComplete: () => widget.onSubmitted(_ctrl.text),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _NoSettings extends StatelessWidget {
  final String extensionName;
  const _NoSettings({required this.extensionName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '$extensionName',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Cette extension ne déclare pas de settings configurables.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
