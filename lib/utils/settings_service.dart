import 'package:shared_preferences/shared_preferences.dart';

/// Centralized settings persistence for Panda IDE.
/// Uses SharedPreferences (key-value) to persist every toggle, stepper, and dropdown.
class SettingsService {
  static SettingsService? _instance;
  late SharedPreferences _prefs;

  static Future<SettingsService> get instance async {
    if (_instance == null) {
      _instance = SettingsService._();
      await _instance!._init();
    }
    return _instance!;
  }

  /// Synchronous accessor after init. Throws if not initialized.
  static SettingsService get I {
    assert(_instance != null, 'SettingsService not initialized. Call await SettingsService.instance first.');
    return _instance!;
  }

  SettingsService._();

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EDITOR
  // ══════════════════════════════════════════════════════════════════════════

  int get editorFontSize => _prefs.getInt('editor.fontSize') ?? 14;
  set editorFontSize(int v) => _prefs.setInt('editor.fontSize', v);

  int get editorTabSize => _prefs.getInt('editor.tabSize') ?? 2;
  set editorTabSize(int v) => _prefs.setInt('editor.tabSize', v);

  bool get editorWordWrap => _prefs.getBool('editor.wordWrap') ?? true;
  set editorWordWrap(bool v) => _prefs.setBool('editor.wordWrap', v);

  bool get editorIndentGuides => _prefs.getBool('editor.indentGuides') ?? true;
  set editorIndentGuides(bool v) => _prefs.setBool('editor.indentGuides', v);

  bool get editorBracketColorization => _prefs.getBool('editor.bracketColorization') ?? true;
  set editorBracketColorization(bool v) => _prefs.setBool('editor.bracketColorization', v);

  bool get editorMinimap => _prefs.getBool('editor.minimap') ?? false;
  set editorMinimap(bool v) => _prefs.setBool('editor.minimap', v);

  bool get editorStickyScroll => _prefs.getBool('editor.stickyScroll') ?? false;
  set editorStickyScroll(bool v) => _prefs.setBool('editor.stickyScroll', v);

  bool get editorRenderWhitespace => _prefs.getBool('editor.renderWhitespace') ?? false;
  set editorRenderWhitespace(bool v) => _prefs.setBool('editor.renderWhitespace', v);

  bool get editorHighlightActiveLine => _prefs.getBool('editor.highlightActiveLine') ?? true;
  set editorHighlightActiveLine(bool v) => _prefs.setBool('editor.highlightActiveLine', v);

  bool get editorSmoothScrolling => _prefs.getBool('editor.smoothScrolling') ?? true;
  set editorSmoothScrolling(bool v) => _prefs.setBool('editor.smoothScrolling', v);

  String get editorFontFamily => _prefs.getString('editor.fontFamily') ?? 'JetBrains Mono';
  set editorFontFamily(String v) => _prefs.setString('editor.fontFamily', v);

  // ══════════════════════════════════════════════════════════════════════════
  // TERMINAL
  // ══════════════════════════════════════════════════════════════════════════

  String get terminalShell => _prefs.getString('terminal.shell') ?? 'bash';
  set terminalShell(String v) => _prefs.setString('terminal.shell', v);

  int get terminalFontSize => _prefs.getInt('terminal.fontSize') ?? 14;
  set terminalFontSize(int v) => _prefs.setInt('terminal.fontSize', v);

  String get terminalCursorStyle => _prefs.getString('terminal.cursorStyle') ?? 'block';
  set terminalCursorStyle(String v) => _prefs.setString('terminal.cursorStyle', v);

  int get terminalScrollback => _prefs.getInt('terminal.scrollback') ?? 1000;
  set terminalScrollback(int v) => _prefs.setInt('terminal.scrollback', v);

  // ══════════════════════════════════════════════════════════════════════════
  // GIT
  // ══════════════════════════════════════════════════════════════════════════

  bool get gitAutoFetch => _prefs.getBool('git.autoFetch') ?? true;
  set gitAutoFetch(bool v) => _prefs.setBool('git.autoFetch', v);

  bool get gitInlineBlame => _prefs.getBool('git.inlineBlame') ?? false;
  set gitInlineBlame(bool v) => _prefs.setBool('git.inlineBlame', v);

  bool get gitConfirmPush => _prefs.getBool('git.confirmPush') ?? true;
  set gitConfirmPush(bool v) => _prefs.setBool('git.confirmPush', v);

  String get gitDefaultBranch => _prefs.getString('git.defaultBranch') ?? 'main';
  set gitDefaultBranch(String v) => _prefs.setString('git.defaultBranch', v);

  // ══════════════════════════════════════════════════════════════════════════
  // APPEARANCE
  // ══════════════════════════════════════════════════════════════════════════

  String get workbenchColorTheme => _prefs.getString('workbench.colorTheme') ?? 'dark';
  set workbenchColorTheme(String v) => _prefs.setString('workbench.colorTheme', v);

  // ══════════════════════════════════════════════════════════════════════════
  // AI / GATEWAY
  // ══════════════════════════════════════════════════════════════════════════

  String get aiDefaultProvider => _prefs.getString('ai.defaultProvider') ?? 'chatgpt';
  set aiDefaultProvider(String v) => _prefs.setString('ai.defaultProvider', v);

  bool get aiInlineCompletions => _prefs.getBool('ai.inlineCompletions') ?? false;
  set aiInlineCompletions(bool v) => _prefs.setBool('ai.inlineCompletions', v);
}
