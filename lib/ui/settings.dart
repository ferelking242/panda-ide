import 'package:panda/bloc/ui_bloc/ui_bloc.dart';
import 'package:panda/utils/functions.dart';
import 'package:panda/ui/adb_setup_page.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:panda/utils/themes.dart';

enum _SettingsSection {
  general,
  editor,
  terminal,
  performance,
  aiAndApi,
  about,
}

class _SettingsPillNav extends StatelessWidget {
  final _SettingsSection current;
  final ValueChanged<_SettingsSection> onTap;

  const _SettingsPillNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _SettingsSection.values.map((section) {
          final isSelected = section == current;
          String label;
          IconData icon;
          switch (section) {
            case _SettingsSection.general:
              label = 'Général';
              icon = Icons.settings;
              break;
            case _SettingsSection.editor:
              label = 'Éditeur';
              icon = Icons.code;
              break;
            case _SettingsSection.terminal:
              label = 'Terminal';
              icon = Icons.terminal;
              break;
            case _SettingsSection.performance:
              label = 'Performance';
              icon = Icons.speed;
              break;
            case _SettingsSection.aiAndApi:
              label = 'IA & API';
              icon = Icons.psychology;
              break;
            case _SettingsSection.about:
              label = 'À propos';
              icon = Icons.info_outline;
              break;
          }
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(icon, size: 18, color: isSelected ? Colors.white : null),
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => onTap(section),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class Settings extends StatefulWidget {
  final bool embedded;
  const Settings({super.key, this.embedded = false});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  _SettingsSection _selectedSection = _SettingsSection.general;
  final ScrollController scrollController = ScrollController();
  final TextEditingController apiController = TextEditingController();
  String _currentLanguage = 'Français 🇫🇷';
  double _uiScale = 1.0;
  double _ramLimitGb = 4.0;
  bool _gpuAccelerated = true;

@override
  Widget build(BuildContext context) {
    return BlocBuilder<ConfigBloc, ConfigState>(
      builder: (context, configState) {
        final theme = configState.codeForgeConfig['theme'] ?? 'vs2015';
        final fontFamily = configState.codeForgeConfig['fontFamily'] ?? 'JetBrains Mono';
        final isIndentEnabled = configState.codeForgeConfig['indentLineStatus'] ?? true;
        final lineWrap = configState.codeForgeConfig['lineWrap'] ?? true;
        final enableFolding = configState.codeForgeConfig['enableFolding'] ?? true;
        final terminalThemeId = (configState.codeForgeConfig['terminalTheme'] ?? defaultTerminalThemeId).toString();
        final selectedTerminalThemePreset = terminalThemePresetById(terminalThemeId);

        return BlocBuilder<AppThemeBloc, AppThemeState>(
          builder: (context, appThemeState) {
            final isDark = appThemeState.appTheme.isDark;
            final cs = Theme.of(context).colorScheme;

            final settingsBody = Column(
              children: [
                _SettingsPillNav(
                  current: _selectedSection,
                  onTap: (sec) => setState(() => _selectedSection = sec),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: _buildSectionContent(context, _selectedSection, configState, appThemeState, cs, isDark),
                  ),
                ),
              ],
            );

            if (widget.embedded) return settingsBody;

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'Paramètres Panda',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              body: settingsBody,
            );
          },
        );
      },
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    _SettingsSection section,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    switch (section) {
      case _SettingsSection.general:
        return _buildGeneralSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.editor:
        return _buildEditorSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.terminal:
        return _buildTerminalSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.performance:
        return _buildPerformanceSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.aiAndApi:
        return _buildAiAndApiSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.about:
        return _buildAboutSection(context, configState, appThemeState, cs, isDark);
    }
  }

  Widget _buildCardGroup({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e1e24) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          ...children,
        ],
      ),
    );
  }

  // 1. Général & Apparence
  Widget _buildGeneralSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    final languages = ['Français 🇫🇷', 'English 🇺🇸', 'Español 🇪🇸', 'Deutsch 🇩🇪', '日本語 🇯🇵', '中文 🇨🇳'];

    return Column(
      children: [
        _buildCardGroup(
          title: "Langue de l'application",
          subtitle: "Sélectionnez la langue d'affichage de Panda IDE",
          icon: Icons.language_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Langue active', style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: languages.contains(_currentLanguage) ? _currentLanguage : 'Français 🇫🇷',
                        dropdownColor: isDark ? const Color(0xff252528) : Colors.white,
                        style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                        onChanged: (val) async {
                          if (val != null) {
                            setState(() => _currentLanguage = val);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('app_language', val);
                          }
                        },
                        items: languages.map((lang) {
                          return DropdownMenuItem(value: lang, child: Text(lang));
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        _buildCardGroup(
          title: 'Thème & Apparence',
          subtitle: "Mode sombre, clair et échelle de l'interface",
          icon: Icons.dark_mode_outlined,
          isDark: isDark,
          cs: cs,
          children: [
            ListTile(
              title: const Text('Mode Sombre (Dark Theme)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Basculer entre le thème clair et sombre', style: TextStyle(fontSize: 11)),
              trailing: Switch(
                value: isDark,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  if (val) {
                    if (context.mounted) context.read<AppThemeBloc>().add(AppThemeEvent(appTheme: DarkTheme()));
                    await prefs.setString('savedAppTheme', 'dark');
                  } else {
                    if (context.mounted) context.read<AppThemeBloc>().add(AppThemeEvent(appTheme: LightTheme()));
                    await prefs.setString('savedAppTheme', 'light');
                  }
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Échelle de l'interface (Zoom UI)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${(_uiScale * 100).toInt()}%', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Slider(
                    value: _uiScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6,
                    label: '${(_uiScale * 100).toInt()}%',
                    onChanged: (val) async {
                      setState(() => _uiScale = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble('ui_scale', val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 2. Éditeur de Code
  Widget _buildEditorSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    final themeName = configState.codeForgeConfig['theme'] ?? 'vs2015';
    final lineWrap = configState.codeForgeConfig['lineWrap'] ?? true;
    final enableFolding = configState.codeForgeConfig['enableFolding'] ?? true;
    final indentStatus = configState.codeForgeConfig['indentLineStatus'] ?? true;

    return Column(
      children: [
        _buildCardGroup(
          title: 'Sauvegarde & Thème',
          subtitle: 'Auto-save et thème de coloration syntaxique',
          icon: Icons.code_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            BlocBuilder<GeneralBloc, GeneralState>(
              builder: (context, generalState) {
                final autoSave = generalState.generalSettings['autoSave'] ?? true;
                return ListTile(
                  title: const Text('Enregistrement automatique (Auto Save)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Enregistrer automatiquement les modifications', style: TextStyle(fontSize: 11)),
                  trailing: Switch(
                    value: autoSave,
                    onChanged: (val) async {
                      final prefs = await SharedPreferences.getInstance();
                      final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                      currentState['autoSave'] = val;
                      await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                      if (context.mounted) {
                        final curr = Map<String, dynamic>.from(context.read<GeneralBloc>().state.generalSettings);
                        curr['autoSave'] = val;
                        context.read<GeneralBloc>().add(GeneralEvent(generalSettings: curr));
                      }
                    },
                  ),
                );
              },
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Thème de coloration syntaxique', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Thème actuel : $themeName', style: const TextStyle(fontSize: 11)),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.palette_outlined, size: 14),
                label: const Text('Changer'),
                onPressed: () => _openEditorThemePicker(context, configState, isDark),
              ),
            ),
          ],
        ),

        _buildCardGroup(
          title: "Options d'affichage de l'éditeur",
          subtitle: "Pliage, guides d'indentation, ligne de retour",
          icon: Icons.tune_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            ListTile(
              title: const Text('Retour à la ligne automatique (Line Wrap)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: lineWrap,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                  currentState['lineWrap'] = val;
                  await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                  if (context.mounted) {
                    context.read<ConfigBloc>().add(ChangeConfigEvent(currentState));
                  }
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text("Guides d'indentation", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: indentStatus,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                  currentState['indentLineStatus'] = val;
                  await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                  if (context.mounted) {
                    context.read<ConfigBloc>().add(ChangeConfigEvent(currentState));
                  }
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Pliage de code (Code Folding)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: enableFolding,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                  currentState['enableFolding'] = val;
                  await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                  if (context.mounted) {
                    context.read<ConfigBloc>().add(ChangeConfigEvent(currentState));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 3. Terminal & Shell
  Widget _buildTerminalSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Configuration Terminal',
          subtitle: 'Aperçu interactif, police et thème',
          icon: Icons.terminal_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Container(
              height: 130,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff0d0d0f) : const Color(0xff1e1e24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.black,
                          child: const Text('user@panda-ide:~\$ echo "Panda Terminal Preview"', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)),
                        ),
              ),
            ),
            ListTile(
              title: const Text('Réseau & ADB WiFi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Appairage sans fil ADB et connexions distantes', style: TextStyle(fontSize: 11)),
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.wifi, size: 14),
                label: const Text('Ouvrir ADB'),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdbSetupPage(),
                  ));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 4. Performance & RAM
  Widget _buildPerformanceSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Allocation Mémoire & GPU',
          subtitle: 'Limites de RAM pour serveurs LSP et IA locale',
          icon: Icons.speed_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Limite RAM allouée aux LSPs & Modèles', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${_ramLimitGb.toStringAsFixed(1)} GB', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Slider(
                    value: _ramLimitGb,
                    min: 1.0,
                    max: 8.0,
                    divisions: 14,
                    label: '${_ramLimitGb.toStringAsFixed(1)} GB',
                    onChanged: (val) async {
                      setState(() => _ramLimitGb = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble('ram_limit_gb', val);
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Accélération Matérielle GPU / Vulkan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text("Utiliser le GPU pour l'affichage et le calcul IA", style: TextStyle(fontSize: 11)),
              trailing: Switch(
                value: _gpuAccelerated,
                onChanged: (val) async {
                  setState(() => _gpuAccelerated = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('gpu_accelerated', val);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 5. IA & Confidentialité
  Widget _buildAiAndApiSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Google Gemini & Copilot',
          subtitle: 'Clés API et services de génération de code',
          icon: Icons.security_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Clé API Google Gemini', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: apiController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Saisir votre clé GEMINI_API_KEY',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: const Icon(Icons.key, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('GitHub Copilot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text("Paramètres et état d'authentification Copilot", style: TextStyle(fontSize: 11)),
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.account_circle, size: 14),
                label: const Text('Gérer'),
                onPressed: () {
                  final copilotState = context.read<CopilotBloc>().state;
                  _showCopilotSettings(context, copilotState, appThemeState);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 6. À propos & Système
  Widget _buildAboutSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Panda IDE',
          subtitle: 'Version v2.5.0 (PlayStore Edition)',
          icon: Icons.info_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Image.asset('assets/icons/app-icon.png', width: 36, height: 36, errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 30)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Panda IDE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                        const Text('Build v2.5.0-release · Android arm64-v8a', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('Environnement IDE complet sans serveur externe', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Vérifier les mises à jour', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Mettre à jour'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Panda IDE est déjà à jour (v2.5.0)')),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openEditorThemePicker(BuildContext context, ConfigState configState, bool isDark) {
    final mergedThemes = getMergedHighlightThemes(configState.codeForgeConfig);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Thème de coloration syntaxique'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: mergedThemes.length,
              itemBuilder: (ctx, i) {
                final key = mergedThemes.keys.elementAt(i);
                return ListTile(
                  title: Text(key),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final curr = Map<String, dynamic>.from(configState.codeForgeConfig);
                    curr['theme'] = key;
                    await prefs.setString('codeForgeConfig', jsonEncode(curr));
                    if (context.mounted) {
                      context.read<ConfigBloc>().add(ChangeConfigEvent(curr));
                      Navigator.pop(dialogCtx);
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }


  void _showCopilotSettings(
    BuildContext context,
    CopilotState copilotState,
    AppThemeState appThemeState,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('GitHub Copilot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statut : ${copilotState.status}'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Fermer'),
              ),
            ],
          ),
        );
      },
    );
  }

}