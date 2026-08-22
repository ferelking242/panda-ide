/// Panda IDE Extension SDK
///
/// This package provides the API for building native Dart extensions
/// for Panda IDE. Extensions import this package and extend [PandaExtension].
///
/// ```dart
/// import 'package:panda_sdk/panda_sdk.dart';
///
/// class MyExtension extends PandaExtension {
///   @override
///   String get id => 'com.example.myext';
///
///   @override
///   String get name => 'My Extension';
///
///   @override
///   Future<void> onActivate(ExtensionContext context) async {
///     context.commands.register('my.hello', (args) async {
///       await context.window.showInformation('Hello!');
///     });
///   }
/// }
/// ```
library panda_sdk;

import 'dart:async';

// ═══════════════════════════════════════════════════════════════
// BASE CLASS
// ═══════════════════════════════════════════════════════════════

/// Abstract class that ALL native extensions must extend.
abstract class PandaExtension {
  /// Unique ID (reverse DNS format: com.author.name)
  String get id;

  /// Display name
  String get name;

  /// Semver version
  String get version => '0.0.0';

  /// Called when the extension is activated.
  Future<void> onActivate(ExtensionContext context);

  /// Called when the extension is deactivated.
  Future<void> onDeactivate() async {}
}

// ═══════════════════════════════════════════════════════════════
// EXTENSION CONTEXT
// ═══════════════════════════════════════════════════════════════

/// Context provided to extensions on activation.
/// This is the gateway to all Panda IDE APIs.
class ExtensionContext {
  final CommandRegistry commands;
  final EventRegistry events;
  final WindowAPI window;
  final EditorAPI editor;
  final FileSystemAPI fs;
  final PandaLogger logger;
  final ThemeAPI theme;
  final StorageAPI storage;
  final NetworkAPI network;
  final TerminalAPI terminal;

  ExtensionContext({
    required this.commands,
    required this.events,
    required this.window,
    required this.editor,
    required this.fs,
    required this.logger,
    required this.theme,
    required this.storage,
    required this.network,
    required this.terminal,
  });
}

// ═══════════════════════════════════════════════════════════════
// COMMANDS API
// ═══════════════════════════════════════════════════════════════

/// Command handler type.
typedef CommandHandler = Future<void> Function(Map<String, dynamic> args);

/// Registry for registering and executing commands.
abstract class CommandRegistry {
  void register(String id, CommandHandler handler);
  Future<void> execute(String id, {Map<String, dynamic> args = const {}});
  List<CommandInfo> list();
}

class CommandInfo {
  final String id;
  final String title;
  final String category;

  const CommandInfo({
    required this.id,
    required this.title,
    this.category = '',
  });
}

// ═══════════════════════════════════════════════════════════════
// EDITOR API
// ═══════════════════════════════════════════════════════════════

/// API for interacting with the code editor.
abstract class EditorAPI {
  Future<EditorDocument?> getActiveDocument();
  Future<String?> getSelection();
  Future<void> replaceSelection(String text);
  Future<void> insertText(String text);
  Future<List<CursorPosition>> getCursors();
  Stream<EditorChangeEvent> get onDidChange;
}

class EditorDocument {
  final String filePath;
  final String language;
  final String content;
  final int version;

  const EditorDocument({
    required this.filePath,
    required this.language,
    required this.content,
    required this.version,
  });
}

class CursorPosition {
  final int line;
  final int character;

  const CursorPosition({required this.line, required this.character});
}

class EditorChangeEvent {
  final String filePath;
  final String oldContent;
  final String newContent;
}

// ═══════════════════════════════════════════════════════════════
// WINDOW API
// ═══════════════════════════════════════════════════════════════

/// API for creating panels, dialogs, notifications.
abstract class WindowAPI {
  Future<void> showInformation(String message, {List<String>? actions});
  Future<void> showWarning(String message, {List<String>? actions});
  Future<void> showError(String message, {List<String>? actions});
  Future<bool> showConfirmation(String message, {String? title});
  Future<String?> showInputBox(InputBoxOptions options);
  Future<QuickPickResult?> showQuickPick(List<QuickPickItem> items);
  Future<void> openSettings({required String extensionId});
  Future<WebviewPanel> createWebview(WebviewOptions options);
  Future<void> openFile(String filePath, {bool preview = true});
  Future<void> createTreeView(String treeId, TreeDataProvider provider);
  Future<T> withProgress<T>(ProgressOptions options,
      Future<T> Function(Progress progress, CancellationToken token) task);
}

class InputBoxOptions {
  final String prompt;
  final String? title;
  final String? placeHolder;
  final String? defaultValue;
  final bool password;

  const InputBoxOptions({
    required this.prompt,
    this.title,
    this.placeHolder,
    this.defaultValue,
    this.password = false,
  });
}

class QuickPickItem {
  final String label;
  final String? description;
  final dynamic value;

  const QuickPickItem({required this.label, this.description, this.value});
}

class QuickPickResult {
  final String label;
  final dynamic value;

  const QuickPickResult({required this.label, this.value});
}

/// Panel for displaying custom Flutter widgets or HTML.
abstract class WebviewPanel {
  String get id;
  String get title;
  Future<void> updateHtml(String html);
  Stream<Map<String, dynamic>> get onMessage;
  Future<void> postMessage(Map<String, dynamic> message);
  Future<void> dispose();
}

class WebviewOptions {
  final String id;
  final String title;
  final String? icon;

  const WebviewOptions({required this.id, required this.title, this.icon});
}

/// Tree data provider for tree views.
abstract class TreeDataProvider<T> {
  Future<List<T>> getChildren(T? element);
  Future<T?> getParent(T element);
}

class ProgressOptions {
  final String title;
  final bool cancellable;

  const ProgressOptions({required this.title, this.cancellable = false});
}

abstract class Progress {
  void report(int value, {String? message});
}

abstract class CancellationToken {
  bool get isCancellationRequested;
}

// ═══════════════════════════════════════════════════════════════
// FILE SYSTEM API
// ═══════════════════════════════════════════════════════════════

/// API for reading/writing files.
abstract class FileSystemAPI {
  Future<String> readFile(String path);
  Future<void> writeFile(String path, String content);
  Future<void> createDirectory(String path);
  Future<List<FileEntry>> listDirectory(String path);
  Future<bool> exists(String path);
  Future<void> delete(String path);
  Future<void> rename(String oldPath, String newPath);
  Stream<FileChangeEvent> get onDidChange;
}

class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });
}

class FileChangeEvent {
  final String filePath;
  final FileChangeType type;
}

enum FileChangeType { created, modified, deleted }

// ═══════════════════════════════════════════════════════════════
// EVENTS API
// ═══════════════════════════════════════════════════════════════

/// Registry for event listeners.
abstract class EventRegistry {
  Stream<PandaEvent> on(String eventName);
  Future<void> emit(String eventName, {dynamic data});
}

class PandaEvent {
  final String name;
  final dynamic data;
  final DateTime timestamp;

  const PandaEvent({
    required this.name,
    this.data,
    required this.timestamp,
  });
}

// ═══════════════════════════════════════════════════════════════
// THEME API
// ═══════════════════════════════════════════════════════════════

/// API for customizing themes.
abstract class ThemeAPI {
  Future<void> registerTheme(PandaTheme theme);
  Future<void> setTheme(String themeId);
  String get currentThemeId;
}

class PandaTheme {
  final String id;
  final String name;
  final ThemeType type;
  final Map<String, String> colors;

  const PandaTheme({
    required this.id,
    required this.name,
    required this.type,
    required this.colors,
  });
}

enum ThemeType { dark, light, highContrast }

// ═══════════════════════════════════════════════════════════════
// STORAGE API
// ═══════════════════════════════════════════════════════════════

/// Persistent storage for extensions.
abstract class StorageAPI {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> remove(String key);
  Future<List<String>> keys();
  Future<void> clear();
}

// ═══════════════════════════════════════════════════════════════
// NETWORK API
// ═══════════════════════════════════════════════════════════════

/// Secure network API for extensions.
abstract class NetworkAPI {
  Future<HttpResponse> httpGet(String url, {Map<String, String>? headers});
  Future<HttpResponse> httpPost(String url,
      {String? body, Map<String, String>? headers});
}

class HttpResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const HttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });
}

// ═══════════════════════════════════════════════════════════════
// TERMINAL API
// ═══════════════════════════════════════════════════════════════

/// API for integrated terminals.
abstract class TerminalAPI {
  Future<Terminal> createTerminal({String? name, String? cwd});
  List<Terminal> get terminals;
}

abstract class Terminal {
  String get id;
  String get name;
  Future<void> sendText(String text);
  Stream<String> get onOutput;
  Future<void> dispose();
}

// ═══════════════════════════════════════════════════════════════
// LOGGER
// ═══════════════════════════════════════════════════════════════

/// Logger for extensions.
abstract class PandaLogger {
  void info(String message);
  void warning(String message);
  void error(String message, [Object? stackTrace]);
  void debug(String message);
}

// ═══════════════════════════════════════════════════════════════
// DISPOSABLE
// ═══════════════════════════════════════════════════════════════

/// Disposable resource.
class Disposable {
  final void Function() _dispose;
  Disposable(this._dispose);
  Future<void> dispose() async => _dispose();
}

/// Manages a set of disposables.
class Disposables {
  final List<Disposable> _items = [];

  void add(Disposable d) => _items.add(d);

  Future<void> disposeAll() async {
    for (final d in _items) {
      await d.dispose();
    }
    _items.clear();
  }
}
