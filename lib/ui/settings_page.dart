/// Complete settings UI — Editor, Terminal, Git, Extensions, AI, Keybindings.
/// All switches, steppers, and dropdowns are wired to SettingsService for persistence.
library;

import 'package:flutter/material.dart';

import '../utils/settings_service.dart';
import '../extensions/extension_registry.dart';

/// Settings page with sections.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedSection = 0;
  late SettingsService _s;

  static const _sections = [
    _Section('Editor', Icons.edit_note),
    _Section('Terminal', Icons.terminal),
    _Section('Git', Icons.git_branch),
    _Section('Extensions', Icons.extension),
    _Section('AI', Icons.smart_toy),
    _Section('Appearance', Icons.palette),
    _Section('Keybindings', Icons.keyboard),
    _Section('About', Icons.info_outline),
  ];

  @override
  void initState() {
    super.initState();
    _s = SettingsService.I;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 200,
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _sections.length,
                    itemBuilder: (_, i) {
                      final s = _sections[i];
                      final isSelected = _selectedSection == i;
                      return ListTile(
                        dense: true,
                        leading: Icon(s.icon, size: 18, color: isSelected ? cs.primary : cs.onSurfaceVariant),
                        title: Text(s.name, style: TextStyle(
                          fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? cs.primary : cs.onSurface)),
                        selected: isSelected,
                        selectedTileColor: cs.primary.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        onTap: () => setState(() => _selectedSection = i),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search settings...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [_buildSection(_sections[_selectedSection].name, cs)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String name, ColorScheme cs) {
    switch (name) {
      case 'Editor': return _editorSettings(cs);
      case 'Terminal': return _terminalSettings(cs);
      case 'Git': return _gitSettings(cs);
      case 'Extensions': return _extensionsSettings(cs);
      case 'AI': return _aiSettings(cs);
      case 'Appearance': return _appearanceSettings(cs);
      case 'Keybindings': return _keybindingsSettings(cs);
      case 'About': return _aboutSection(cs);
      default: return const SizedBox.shrink();
    }
  }

  Widget _tile(String title, String subtitle, Widget trailing) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      trailing: trailing,
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // EDITOR SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _editorSettings(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Editor'),
        _tile('Font Size', 'Size of the editor font', _NumberStepper(
          initial: _s.editorFontSize, min: 10, max: 32,
          onChanged: (v) => setState(() => _s.editorFontSize = v),
        )),
        _tile('Tab Size', 'Number of spaces per tab', _NumberStepper(
          initial: _s.editorTabSize, min: 1, max: 8,
          onChanged: (v) => setState(() => _s.editorTabSize = v),
        )),
        _tile('Word Wrap', 'Wrap long lines', Switch(
          value: _s.editorWordWrap,
          onChanged: (v) => setState(() => _s.editorWordWrap = v),
        )),
        _tile('Show Indent Guides', 'Display vertical indent lines', Switch(
          value: _s.editorIndentGuides,
          onChanged: (v) => setState(() => _s.editorIndentGuides = v),
        )),
        _tile('Bracket Colorization', 'Color matching brackets', Switch(
          value: _s.editorBracketColorization,
          onChanged: (v) => setState(() => _s.editorBracketColorization = v),
        )),
        _tile('Show Minimap', 'Display code overview', Switch(
          value: _s.editorMinimap,
          onChanged: (v) => setState(() => _s.editorMinimap = v),
        )),
        _tile('Sticky Scroll', 'Keep scope headers visible', Switch(
          value: _s.editorStickyScroll,
          onChanged: (v) => setState(() => _s.editorStickyScroll = v),
        )),
        _tile('Render Whitespace', 'Show whitespace characters', Switch(
          value: _s.editorRenderWhitespace,
          onChanged: (v) => setState(() => _s.editorRenderWhitespace = v),
        )),
        _tile('Highlight Active Line', 'Highlight the current line', Switch(
          value: _s.editorHighlightActiveLine,
          onChanged: (v) => setState(() => _s.editorHighlightActiveLine = v),
        )),
        _tile('Smooth Scrolling', 'Animated scroll', Switch(
          value: _s.editorSmoothScrolling,
          onChanged: (v) => setState(() => _s.editorSmoothScrolling = v),
        )),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TERMINAL SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _terminalSettings(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Terminal'),
        _tile('Default Shell', 'Terminal shell', DropdownButton<String>(
          value: _s.terminalShell,
          items: const [
            DropdownMenuItem(value: 'bash', child: Text('bash')),
            DropdownMenuItem(value: 'zsh', child: Text('zsh')),
            DropdownMenuItem(value: 'sh', child: Text('sh')),
          ],
          onChanged: (v) { if (v != null) setState(() => _s.terminalShell = v); },
        )),
        _tile('Font Size', 'Terminal font size', _NumberStepper(
          initial: _s.terminalFontSize, min: 10, max: 24,
          onChanged: (v) => setState(() => _s.terminalFontSize = v),
        )),
        _tile('Cursor Style', 'Terminal cursor style', DropdownButton<String>(
          value: _s.terminalCursorStyle,
          items: const [
            DropdownMenuItem(value: 'block', child: Text('Block')),
            DropdownMenuItem(value: 'underline', child: Text('Underline')),
            DropdownMenuItem(value: 'bar', child: Text('Bar')),
          ],
          onChanged: (v) { if (v != null) setState(() => _s.terminalCursorStyle = v); },
        )),
        _tile('Scroll Back', 'Lines to keep in history', _NumberStepper(
          initial: _s.terminalScrollback, min: 100, max: 10000, step: 100,
          onChanged: (v) => setState(() => _s.terminalScrollback = v),
        )),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GIT SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _gitSettings(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Git'),
        _tile('Auto Fetch', 'Fetch changes automatically', Switch(
          value: _s.gitAutoFetch,
          onChanged: (v) => setState(() => _s.gitAutoFetch = v),
        )),
        _tile('Show Inline Blame', 'Show author in editor gutter', Switch(
          value: _s.gitInlineBlame,
          onChanged: (v) => setState(() => _s.gitInlineBlame = v),
        )),
        _tile('Confirm Push', 'Ask before pushing', Switch(
          value: _s.gitConfirmPush,
          onChanged: (v) => setState(() => _s.gitConfirmPush = v),
        )),
        _tile('Default Branch', 'Default branch name', Text(_s.gitDefaultBranch,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'))),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXTENSIONS SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _extensionsSettings(ColorScheme cs) {
    final count = ExtensionRegistry.instance.all.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Extensions'),
        Text('$count extension(s) installed', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (count > 0)
          ...ExtensionRegistry.instance.all.map((ext) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.extension, color: cs.primary),
            title: Text(ext.manifest.displayName ?? ext.manifest.name, style: const TextStyle(fontSize: 13)),
            subtitle: Text('v${ext.manifest.version}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            trailing: TextButton(onPressed: () {}, child: const Text('Manage')),
          )),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AI SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _aiSettings(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('AI Gateway'),
        _tile('Default Provider', 'AI provider for chat', DropdownButton<String>(
          value: _s.aiDefaultProvider,
          items: const [
            DropdownMenuItem(value: 'chatgpt', child: Text('ChatGPT')),
            DropdownMenuItem(value: 'claude', child: Text('Claude')),
            DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
            DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
            DropdownMenuItem(value: 'grok', child: Text('Grok')),
            DropdownMenuItem(value: 'mistral', child: Text('Mistral')),
            DropdownMenuItem(value: 'qwen', child: Text('Qwen')),
            DropdownMenuItem(value: 'kimi', child: Text('Kimi')),
          ],
          onChanged: (v) { if (v != null) setState(() => _s.aiDefaultProvider = v); },
        )),
        _tile('Gateway URL', 'Panda AI Gateway endpoint', Text('http://localhost:8000', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'))),
        _tile('API Token', 'Authentication token', const Text('pnd_•••••••••••', style: TextStyle(fontSize: 11, fontFamily: 'monospace'))),
        _tile('Enable Inline Completions', 'AI-powered code suggestions', Switch(
          value: _s.aiInlineCompletions,
          onChanged: (v) => setState(() => _s.aiInlineCompletions = v),
        )),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APPEARANCE SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _appearanceSettings(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Appearance'),
        _tile('Theme', 'Color theme', DropdownButton<String>(
          value: _s.workbenchColorTheme,
          items: const [
            DropdownMenuItem(value: 'dark', child: Text('Dark')),
            DropdownMenuItem(value: 'light', child: Text('Light')),
            DropdownMenuItem(value: 'system', child: Text('System')),
          ],
          onChanged: (v) { if (v != null) setState(() => _s.workbenchColorTheme = v); },
        )),
        _tile('Icon Theme', 'File icons', const Text('Default', style: TextStyle(fontSize: 13))),
        _tile('Font Family', 'Editor font', Text(_s.editorFontFamily, style: const TextStyle(fontSize: 13, fontFamily: 'monospace'))),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // KEYBINDINGS SETTINGS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _keybindingsSettings(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Keyboard Shortcuts'),
        Text('Press a key combination to search.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        _keybindingRow('Ctrl+P', 'Quick Open'),
        _keybindingRow('Ctrl+Shift+O', 'Go to Symbol'),
        _keybindingRow('Ctrl+D', 'Add Cursor at Next Occurrence'),
        _keybindingRow('Ctrl+Shift+L', 'Select All Occurrences'),
        _keybindingRow('Ctrl+`', 'Toggle Terminal'),
        _keybindingRow('Ctrl+B', 'Toggle Sidebar'),
        _keybindingRow('Ctrl+S', 'Save'),
        _keybindingRow('Ctrl+G', 'Go to Line'),
        _keybindingRow('Ctrl+F', 'Find in File'),
        _keybindingRow('Ctrl+Shift+F', 'Find in Files'),
        _keybindingRow('Alt+Z', 'Toggle Word Wrap'),
        _keybindingRow('F5', 'Run / Debug'),
        _keybindingRow('Ctrl+Shift+P', 'Command Palette'),
      ],
    );
  }

  Widget _keybindingRow(String key, String action) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
            child: Text(key, style: TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: cs.onSurface)),
          ),
          const SizedBox(width: 12),
          Text(action, style: TextStyle(fontSize: 13, color: cs.onSurface)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ABOUT SECTION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _aboutSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('About Panda IDE'),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.code, size: 32, color: cs.primary)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Panda IDE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
                Text('v2.3.3', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                Text('A mobile-first IDE with AI', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _tile('Repository', 'github.com/ferelking242/panda-ide', Icon(Icons.open_in_new, size: 16, color: cs.primary)),
        _tile('License', 'GPL-3.0', Icon(Icons.gavel, size: 16, color: cs.primary)),
        _tile('Runtime', 'Alpine Linux + Node.js', Icon(Icons.dns, size: 16, color: cs.primary)),
        _tile('Providers', '8 AI providers (ChatGPT, Claude, Gemini...)', Icon(Icons.smart_toy, size: 16, color: cs.primary)),
        _tile('Extensions', '${ExtensionRegistry.instance.all.length} VS Code extensions', Icon(Icons.extension, size: 16, color: cs.primary)),
      ],
    );
  }
}

class _Section {
  final String name;
  final IconData icon;
  const _Section(this.name, this.icon);
}

/// Numeric stepper with + / − buttons. Persists via onChanged callback.
class _NumberStepper extends StatelessWidget {
  final int initial;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int>? onChanged;

  const _NumberStepper({
    required this.initial,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: initial > min
              ? () => onChanged?.call(initial - step)
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text('$initial', style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          onPressed: initial < max
              ? () => onChanged?.call(initial + step)
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}
