# 01 — Settings Persistence (Phase 0 — CRITIQUE)

## Objectif
Les Switches/Steppers dans `lib/ui/settings_page.dart` sont purement visuels.
Aucun setting ne persiste. Les toggle font `onChanged: (_) {}` — vide.
Il faut un `SettingsService` qui sauvegarde via `shared_preferences`
et un `Provider`/`Bloc` qui distribue les valeurs à l'éditeur, terminal, etc.

## Fichiers à modifier

| Fichier | Action |
|---|---|
| `lib/utils/settings_service.dart` | **CRÉER** — SettingsService singleton |
| `lib/ui/settings_page.dart` | **MODIFIER** — Brancher tous les Switches au SettingsService |
| `lib/ui/editor_page.dart` | **MODIFIER** — Lire les settings au démarrage |
| `lib/terminal/terminal.dart` | **MODIFIER** — Lire shell/fontSize/cursor du SettingsService |
| `lib/main.dart` | **MODIFIER** — Initialiser SettingsService au démarrage |
| `pubspec.yaml` | **MODIFIER** — Ajouter `shared_preferences` |

## Code à créer : SettingsService

```dart
// lib/utils/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static SettingsService? _instance;
  late SharedPreferences _prefs;

  static Future<SettingsService> instance() async {
    _instance ??= SettingsService._();
    await _instance!._init();
    return _instance!;
  }

  SettingsService._();

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Editor ──
  int get fontSize => _prefs.getInt('editor.fontSize') ?? 14;
  set fontSize(int v) => _prefs.setInt('editor.fontSize', v);

  int get tabSize => _prefs.getInt('editor.tabSize') ?? 2;
  set tabSize(int v) => _prefs.setInt('editor.tabSize', v);

  bool get wordWrap => _prefs.getBool('editor.wordWrap') ?? true;
  set wordWrap(bool v) => _prefs.setBool('editor.wordWrap', v);

  bool get indentGuides => _prefs.getBool('editor.indentGuides') ?? true;
  set indentGuides(bool v) => _prefs.setBool('editor.indentGuides', v);

  bool get bracketColorization => _prefs.getBool('editor.bracketColorization') ?? true;
  set bracketColorization(bool v) => _prefs.setBool('editor.bracketColorization', v);

  bool get minimap => _prefs.getBool('editor.minimap') ?? false;
  set minimap(bool v) => _prefs.setBool('editor.minimap', v);

  bool get stickyScroll => _prefs.getBool('editor.stickyScroll') ?? false;
  set stickyScroll(bool v) => _prefs.setBool('editor.stickyScroll', v);

  bool get renderWhitespace => _prefs.getBool('editor.renderWhitespace') ?? false;
  set renderWhitespace(bool v) => _prefs.setBool('editor.renderWhitespace', v);

  bool get highlightActiveLine => _prefs.getBool('editor.highlightActiveLine') ?? true;
  set highlightActiveLine(bool v) => _prefs.setBool('editor.highlightActiveLine', v);

  bool get smoothScrolling => _prefs.getBool('editor.smoothScrolling') ?? true;
  set smoothScrolling(bool v) => _prefs.setBool('editor.smoothScrolling', v);

  // ── Terminal ──
  String get terminalShell => _prefs.getString('terminal.shell') ?? 'bash';
  set terminalShell(String v) => _prefs.setString('terminal.shell', v);

  int get terminalFontSize => _prefs.getInt('terminal.fontSize') ?? 14;
  set terminalFontSize(int v) => _prefs.setInt('terminal.fontSize', v);

  String get terminalCursorStyle => _prefs.getString('terminal.cursorStyle') ?? 'block';
  set terminalCursorStyle(String v) => _prefs.setString('terminal.cursorStyle', v);

  int get terminalScrollback => _prefs.getInt('terminal.scrollback') ?? 1000;
  set terminalScrollback(int v) => _prefs.setInt('terminal.scrollback', v);

  // ── Git ──
  bool get gitAutoFetch => _prefs.getBool('git.autoFetch') ?? true;
  set gitAutoFetch(bool v) => _prefs.setBool('git.autoFetch', v);

  bool get gitInlineBlame => _prefs.getBool('git.inlineBlame') ?? false;
  set gitInlineBlame(bool v) => _prefs.setBool('git.inlineBlame', v);

  bool get gitConfirmPush => _prefs.getBool('git.confirmPush') ?? true;
  set gitConfirmPush(bool v) => _prefs.setBool('git.confirmPush', v);

  // ── Appearance ──
  String get theme => _prefs.getString('workbench.colorTheme') ?? 'dark';
  set theme(String v) => _prefs.setString('workbench.colorTheme', v);

  String get fontFamily => _prefs.getString('editor.fontFamily') ?? 'JetBrains Mono';
  set fontFamily(String v) => _prefs.setString('editor.fontFamily', v);
}
```

## Code à modifier : settings_page.dart

Chaque Switch/Stepper doit lire et écrire via SettingsService :

```dart
// AVANT (non branché):
_tile('Font Size', 'Size of the editor font', const _NumberStepper(initial: 14, min: 10, max: 32)),
_tile('Word Wrap', 'Wrap long lines', Switch(value: true, onChanged: (_) {})),

// APRÈS (branché):
_tile('Font Size', 'Size of the editor font', _NumberStepper(
  initial: SettingsService.instance.fontSize,
  min: 10, max: 32,
  onChanged: (v) => SettingsService.instance.fontSize = v,
)),
_tile('Word Wrap', 'Wrap long lines', Switch(
  value: SettingsService.instance.wordWrap,
  onChanged: (v) => setState(() => SettingsService.instance.wordWrap = v),
)),
```

## Priorité
**P0 — CRITIQUE** — Sans ça, la page Settings est un trompe-l'œil.

## Effort
6h (SettingsService + brancher ~20 Switches + initialisation + imports)

## Vérification
1. `flutter pub get` passe
2. Toggle un switch → fermer/réouvrir → le switch est toujours dans le même état
3. Le setting est appliqué à l'éditeur (font size change réellement)
