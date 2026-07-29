/// Routeur central pour tous les appels vscode.* venant des extensions (Node.js → Flutter).
///
/// Chaque namespace est délégué à un handler spécialisé.
/// Ce routeur est enregistré dans ExtensionHostManager.apiCallHandler.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'extension_host_manager.dart';
import 'models/extension_message.dart';
import 'ui/output_channel_panel.dart';
import 'ui/progress_overlay.dart';
import 'ui/status_bar_manager.dart';
import 'ui/window_api_handler.dart';

/// Route un appel vscode.* reçu d'une extension vers le handler Flutter approprié.
///
/// [extensionId] : ID de l'extension qui fait l'appel (ex: "esbenp.prettier-vscode")
/// [msg]         : message IPC reçu (type: apiCall)
/// [context]     : BuildContext Flutter pour afficher des UI — peut être null si
///                 l'appel ne nécessite pas de UI (ex: workspace.fs.stat)
///
/// Retourne le résultat à renvoyer à l'extension via apiReturn.
class ExtensionApiRouter {
  static final ExtensionApiRouter instance = ExtensionApiRouter._();
  ExtensionApiRouter._();

  /// BuildContext global fourni par le widget racine.
  /// Mis à jour à chaque rebuild de l'app (via GlobalKey ou NavigatorObserver).
  BuildContext? _context;

  void setContext(BuildContext ctx) => _context = ctx;

  // ── Point d'entrée principal ─────────────────────────────────────────────

  Future<dynamic> route(String extensionId, IpcMessage msg) async {
    final method = msg.method;
    final params = msg.params;

    // Dispatcher par namespace
    if (method.startsWith('vscode.window.')) {
      return _routeWindow(extensionId, method, params);
    }
    if (method.startsWith('vscode.workspace.')) {
      return _routeWorkspace(extensionId, method, params);
    }
    if (method.startsWith('vscode.languages.')) {
      return _routeLanguages(extensionId, method, params);
    }
    if (method.startsWith('vscode.commands.')) {
      return _routeCommands(extensionId, method, params);
    }
    if (method.startsWith('vscode.env.')) {
      return _routeEnv(extensionId, method, params);
    }
    if (method.startsWith('vscode.extensions.')) {
      return _routeExtensions(extensionId, method, params);
    }
    if (method.startsWith('vscode.authentication.')) {
      return _routeAuthentication(extensionId, method, params);
    }

    // Appel inconnu → log + retour null sûr
    debugPrint('[ExtApiRouter] Unrouted: $method (ext: $extensionId)');
    return null;
  }

  // ── vscode.window.* ──────────────────────────────────────────────────────

  Future<dynamic> _routeWindow(
      String extId, String method, List<dynamic> params) async {
    final ctx = _context;

    switch (method) {
      // ── Messages ──────────────────────────────────────────────────────────
      case 'vscode.window.showInformationMessage':
        if (ctx == null || !ctx.mounted) return null;
        return WindowApiHandler.showMessage(
            ctx, WindowMessageType.information, params);

      case 'vscode.window.showWarningMessage':
        if (ctx == null || !ctx.mounted) return null;
        return WindowApiHandler.showMessage(
            ctx, WindowMessageType.warning, params);

      case 'vscode.window.showErrorMessage':
        if (ctx == null || !ctx.mounted) return null;
        return WindowApiHandler.showMessage(
            ctx, WindowMessageType.error, params);

      // ── Input ─────────────────────────────────────────────────────────────
      case 'vscode.window.showInputBox':
        if (ctx == null || !ctx.mounted) return null;
        final options =
            params.isNotEmpty ? params[0] as Map<String, dynamic>? : null;
        return WindowApiHandler.showInputBox(ctx, options ?? {});

      case 'vscode.window.showQuickPick':
        if (ctx == null || !ctx.mounted) return null;
        final items = (params.isNotEmpty ? params[0] : null);
        final options =
            params.length > 1 ? params[1] as Map<String, dynamic>? : null;
        return WindowApiHandler.showQuickPick(
            ctx, items as List? ?? [], options ?? {});

      // ── Output channels ───────────────────────────────────────────────────
      case 'vscode.window.outputChannel.create':
        final name = params.isNotEmpty ? params[0] as String? : null;
        if (name != null) OutputChannelManager.instance.create(name);
        return null;

      case 'vscode.window.outputChannel.append':
        if (params.length >= 2) {
          OutputChannelManager.instance
              .append(params[0] as String, params[1] as String);
        }
        return null;

      case 'vscode.window.outputChannel.appendLine':
        if (params.length >= 2) {
          OutputChannelManager.instance
              .appendLine(params[0] as String, params[1] as String);
        }
        return null;

      case 'vscode.window.outputChannel.clear':
        if (params.isNotEmpty) {
          OutputChannelManager.instance.clear(params[0] as String);
        }
        return null;

      case 'vscode.window.outputChannel.show':
        if (params.isNotEmpty && ctx != null && ctx.mounted) {
          final name = params[0] as String;
          final preserveFocus =
              params.length > 1 ? params[1] as bool? ?? false : false;
          OutputChannelManager.instance.show(ctx, name,
              preserveFocus: preserveFocus);
        }
        return null;

      case 'vscode.window.outputChannel.hide':
      case 'vscode.window.outputChannel.dispose':
        if (params.isNotEmpty) {
          OutputChannelManager.instance.dispose(params[0] as String);
        }
        return null;

      // ── Status bar ────────────────────────────────────────────────────────
      case 'vscode.window.statusBarItem.create':
        if (params.length >= 3) {
          StatusBarManager.instance.create(
            id: params[0] as String,
            alignment: (params[1] as num).toInt(),
            priority: (params[2] as num).toInt(),
          );
        }
        return null;

      case 'vscode.window.statusBarItem.update':
        if (params.isNotEmpty && params[0] is Map) {
          StatusBarManager.instance
              .update(params[0] as Map<String, dynamic>);
        }
        return null;

      case 'vscode.window.statusBarItem.dispose':
        if (params.isNotEmpty) {
          StatusBarManager.instance.dispose(params[0] as String);
        }
        return null;

      // ── Progress ──────────────────────────────────────────────────────────
      case 'vscode.window.withProgress.start':
        if (ctx == null || !ctx.mounted) return null;
        final options =
            params.isNotEmpty ? params[0] as Map<String, dynamic>? : null;
        ProgressOverlayManager.instance.start(ctx, options ?? {});
        return null;

      case 'vscode.window.withProgress.report':
        if (params.isNotEmpty && params[0] is Map) {
          ProgressOverlayManager.instance
              .report(params[0] as Map<String, dynamic>);
        }
        return null;

      case 'vscode.window.withProgress.end':
        ProgressOverlayManager.instance.end();
        return null;

      // ── Terminal ──────────────────────────────────────────────────────────
      case 'vscode.window.terminal.create':
        // Phase 11 — stub pour l'instant
        return null;
      case 'vscode.window.terminal.sendText':
      case 'vscode.window.terminal.show':
      case 'vscode.window.terminal.hide':
      case 'vscode.window.terminal.dispose':
        return null;

      default:
        debugPrint('[ExtApiRouter] Unknown window method: $method');
        return null;
    }
  }

  // ── vscode.workspace.* ───────────────────────────────────────────────────
  // Phase 3 — stubs propres pour l'instant

  Future<dynamic> _routeWorkspace(
      String extId, String method, List<dynamic> params) async {
    switch (method) {
      case 'vscode.workspace.openTextDocument':
        return null; // Phase 3

      case 'vscode.workspace.saveAll':
        return false; // Phase 3

      case 'vscode.workspace.applyEdit':
        return false; // Phase 3

      case 'vscode.workspace.findFiles':
        return []; // Phase 3

      case 'vscode.workspace.configuration.update':
        return null; // Phase 3 — config store

      case 'vscode.workspace.fileWatcher.create':
      case 'vscode.workspace.fileWatcher.dispose':
        return null;

      // FileSystem API
      case 'vscode.workspace.fs.stat':
        return null;
      case 'vscode.workspace.fs.readDirectory':
        return [];
      case 'vscode.workspace.fs.createDirectory':
        return null;
      case 'vscode.workspace.fs.readFile':
        return null;
      case 'vscode.workspace.fs.writeFile':
        return null;
      case 'vscode.workspace.fs.delete':
        return null;
      case 'vscode.workspace.fs.rename':
        return null;
      case 'vscode.workspace.fs.copy':
        return null;
      case 'vscode.workspace.fs.isWritable':
        return true;

      default:
        debugPrint('[ExtApiRouter] Unknown workspace method: $method');
        return null;
    }
  }

  // ── vscode.languages.* ───────────────────────────────────────────────────
  // Phase 4 — stubs propres pour l'instant

  Future<dynamic> _routeLanguages(
      String extId, String method, List<dynamic> params) async {
    switch (method) {
      case 'vscode.languages.getLanguages':
        return <String>[];

      case 'vscode.languages.setLanguageConfiguration':
        return null;

      case 'vscode.languages.diagnostics.set':
      case 'vscode.languages.diagnostics.clear':
        return null; // Phase 4

      default:
        // Enregistrements de providers (completionItemProvider.register, etc.)
        if (method.endsWith('.register') || method.endsWith('.unregister')) {
          return null; // Phase 4
        }
        debugPrint('[ExtApiRouter] Unknown languages method: $method');
        return null;
    }
  }

  // ── vscode.commands.* ────────────────────────────────────────────────────
  // Phase 5

  Future<dynamic> _routeCommands(
      String extId, String method, List<dynamic> params) async {
    switch (method) {
      case 'vscode.commands.register':
      case 'vscode.commands.unregister':
        return null;
      case 'vscode.commands.execute':
        return null;
      case 'vscode.commands.getAll':
        return <String>[];
      default:
        return null;
    }
  }

  // ── vscode.env.* ─────────────────────────────────────────────────────────
  // Phase 7

  Future<dynamic> _routeEnv(
      String extId, String method, List<dynamic> params) async {
    switch (method) {
      case 'vscode.env.clipboard.read':
        // Utilise flutter_secure_storage ou Clipboard Flutter
        return '';
      case 'vscode.env.clipboard.write':
        return null;
      case 'vscode.env.openExternal':
        return false;
      default:
        return null;
    }
  }

  // ── vscode.extensions.* ──────────────────────────────────────────────────

  Future<dynamic> _routeExtensions(
      String extId, String method, List<dynamic> params) async {
    switch (method) {
      case 'vscode.extensions.get':
        return null;
      default:
        return null;
    }
  }

  // ── vscode.authentication.* ──────────────────────────────────────────────

  Future<dynamic> _routeAuthentication(
      String extId, String method, List<dynamic> params) async {
    return null;
  }

  // ── Setup ────────────────────────────────────────────────────────────────

  /// À appeler depuis main.dart après avoir configuré ExtensionHostManager.
  void attachToManager() {
    ExtensionHostManager.instance.apiCallHandler = route;
  }
}
