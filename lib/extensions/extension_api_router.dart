/// Routeur central pour tous les appels vscode.* venant des extensions (Node.js → Flutter).
///
/// Chaque namespace est délégué à un handler spécialisé.
/// Ce routeur est enregistré dans ExtensionHostManager.apiCallHandler.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'command_registry.dart';
import 'config_store.dart';
import 'debug_bridge.dart';
import 'extension_exports_registry.dart';
import 'extension_host_manager.dart';
import 'fs_bridge.dart';
import 'language_feature_router.dart';
import 'models/extension_message.dart';
import 'scm_bridge.dart';
import 'tasks_bridge.dart';
import 'ui/extension_webview.dart';
import 'ui/output_channel_panel.dart';
import 'ui/progress_overlay.dart';
import 'ui/status_bar_manager.dart';
import 'ui/window_api_handler.dart';
import 'workspace_bridge.dart';

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
    if (method.startsWith('vscode.webview.')) {
      return _routeWebview(extensionId, method, params);
    }
    if (method.startsWith('vscode.scm.')) {
      return _routeScm(extensionId, method, params);
    }
    if (method.startsWith('vscode.tasks.')) {
      return _routeTasks(extensionId, method, params);
    }
    if (method.startsWith('vscode.debug.')) {
      return _routeDebug(extensionId, method, params);
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
  // Phase 3 — implémentation complète via WorkspaceBridge + FsBridge

  Future<dynamic> _routeWorkspace(
      String extId, String method, List<dynamic> params) async {
    final wb = WorkspaceBridge.instance;
    final fb = FsBridge.instance;

    switch (method) {
      // ── Documents ──────────────────────────────────────────────────────────
      case 'vscode.workspace.openTextDocument':
        return wb.openTextDocument(params.isNotEmpty ? params[0] : null);

      case 'vscode.workspace.saveAll':
        return wb.saveAll(params.isNotEmpty ? params[0] as bool? ?? false : false);

      case 'vscode.workspace.applyEdit':
        final edits = params.isNotEmpty ? params[0] : null;
        if (edits is List) return wb.applyEdit(edits);
        return false;

      case 'vscode.workspace.findFiles':
        final include   = params.isNotEmpty  ? params[0] as String? ?? '' : '';
        final exclude   = params.length > 1  ? params[1] as String?       : null;
        final maxRes    = params.length > 2  ? (params[2] as num?)?.toInt() : null;
        return wb.findFiles(include, exclude, maxRes);

      // ── Configuration ──────────────────────────────────────────────────────
      case 'vscode.workspace.configuration.get':
        final section = params.isNotEmpty ? params[0] as String? : null;
        return wb.getConfiguration(section);

      case 'vscode.workspace.configuration.update':
        final section = params.isNotEmpty  ? params[0] as String? : null;
        final key     = params.length > 1  ? params[1] as String? ?? '' : '';
        final value   = params.length > 2  ? params[2] : null;
        final target  = params.length > 3  ? (params[3] as num?)?.toInt() : null;
        await wb.updateConfiguration(section, key, value, target);
        return null;

      // ── Workspace folders ──────────────────────────────────────────────────
      case 'vscode.workspace.workspaceFolders.get':
        return wb.workspaceFolders;

      // ── File watchers (Phase 13 — stubs propres) ───────────────────────────
      case 'vscode.workspace.fileWatcher.create':
      case 'vscode.workspace.fileWatcher.dispose':
        return null;

      // ── FileSystem API ─────────────────────────────────────────────────────
      case 'vscode.workspace.fs.stat':
      case 'vscode.workspace.fs.readDirectory':
      case 'vscode.workspace.fs.createDirectory':
      case 'vscode.workspace.fs.readFile':
      case 'vscode.workspace.fs.writeFile':
      case 'vscode.workspace.fs.delete':
      case 'vscode.workspace.fs.rename':
      case 'vscode.workspace.fs.copy':
        // Extraire le nom de l'opération (ex: 'vscode.workspace.fs.stat' → 'fs.stat')
        final op = method.substring('vscode.workspace.'.length);
        return fb.dispatch(op, params);

      case 'vscode.workspace.fs.isWritable':
        return true; // Tous les schémas file:// sont writables sur Android

      default:
        debugPrint('[ExtApiRouter] Unknown workspace method: $method');
        return null;
    }
  }

  // ── vscode.languages.* ───────────────────────────────────────────────────
  // Phase 4 — implémentation complète via LanguageFeatureRouter

  Future<dynamic> _routeLanguages(
      String extId, String method, List<dynamic> params) async {
    final lr = LanguageFeatureRouter.instance;

    // ── Provider registration ──────────────────────────────────────────────
    // Méthodes: 'vscode.languages.<type>.register' / '.unregister'
    // params[0] = providerId  params[1] = selector  params[2+] = extras

    if (method.endsWith('.register') && method.startsWith('vscode.languages.')) {
      final apiMethod  = method.substring('vscode.languages.'.length, method.length - '.register'.length);
      final providerId = params.isNotEmpty ? params[0] as String? ?? '' : '';
      final rawSel     = params.length > 1 ? params[1] : null;
      final selector   = rawSel is List ? rawSel : (rawSel != null ? [rawSel] : <dynamic>[]);

      // Mapper apiMethod → type interne du LanguageFeatureRouter
      final type = _apiMethodToProviderType(apiMethod);
      if (type != null && providerId.isNotEmpty) {
        lr.registerProvider(
          type:        type,
          extensionId: extId,
          providerId:  providerId,
          selector:    selector,
        );
      }
      return providerId;
    }

    if (method.endsWith('.unregister') && method.startsWith('vscode.languages.')) {
      final providerId = params.isNotEmpty ? params[0] as String? ?? '' : '';
      if (providerId.isNotEmpty) lr.unregisterProvider(providerId);
      return null;
    }

    switch (method) {
      // ── Diagnostics (push model) ───────────────────────────────────────────
      case 'vscode.languages.diagnostics.set':
        final fsPath      = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final diagnostics = params.length > 1 ? (params[1] as List<dynamic>?) ?? [] : [];
        lr.setDiagnostics(fsPath, diagnostics);
        return null;

      case 'vscode.languages.diagnostics.clear':
        lr.clearDiagnostics(extId);
        return null;

      // ── Query ──────────────────────────────────────────────────────────────
      case 'vscode.languages.getLanguages':
        return <String>[
          'plaintext', 'dart', 'javascript', 'typescript', 'javascriptreact',
          'typescriptreact', 'python', 'rust', 'go', 'java', 'kotlin', 'swift',
          'c', 'cpp', 'csharp', 'php', 'ruby', 'html', 'css', 'scss', 'json',
          'yaml', 'xml', 'markdown', 'shellscript', 'dockerfile', 'sql',
        ];

      case 'vscode.languages.setLanguageConfiguration':
        return null; // Phase 13 (grammars)

      case 'vscode.languages.getDiagnostics':
        final uri = params.isNotEmpty ? params[0] : null;
        if (uri is Map<String, dynamic>) {
          final fp = uri['fsPath'] as String? ?? uri['path'] as String?;
          if (fp != null) return lr.getDiagnosticsForFile(fp);
        }
        // null = retourne toutes les diags (toutes les clés)
        return lr.allDiagnostics.entries
            .map((e) => {'uri': e.key, 'diagnostics': e.value})
            .toList();

      default:
        debugPrint('[ExtApiRouter] Unknown languages method: $method');
        return null;
    }
  }

  /// Convertit le nom d'apiMethod vscode.js → type interne LanguageFeatureRouter.
  static String? _apiMethodToProviderType(String apiMethod) {
    return const {
      'completionItemProvider':    'completion',
      'hoverProvider':             'hover',
      'definitionProvider':        'definition',
      'declarationProvider':       'definition',
      'referenceProvider':         'references',
      'formattingProvider':        'format',
      'rangeFormattingProvider':   'format',
      'onTypeFormattingProvider':  'format',
      'codeActionsProvider':       'codeAction',
      'renameProvider':            'rename',
      'signatureHelpProvider':     'signature',
      'documentSymbolProvider':    'symbol',
      'workspaceSymbolProvider':   'symbol',
      'codeLensProvider':          'codeAction',
      'implementationProvider':    'definition',
      'typeDefinitionProvider':    'definition',
      'documentHighlightProvider': 'hover',
      'inlayHintsProvider':        'hover',
      'foldingRangeProvider':      'symbol',
      'selectionRangeProvider':    'symbol',
      'callHierarchyProvider':     'symbol',
      'linkedEditingRangeProvider':'symbol',
    }[apiMethod];
  }

  // ── vscode.commands.* ────────────────────────────────────────────────────
  // Phase 5 — implémentation complète via CommandRegistry

  Future<dynamic> _routeCommands(
      String extId, String method, List<dynamic> params) async {
    final cr = CommandRegistry.instance;

    switch (method) {
      case 'vscode.commands.register':
        // params[0] = commandId   params[1] = title (optionnel)
        final command  = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final title    = params.length > 1 ? params[1] as String? : null;
        if (command.isNotEmpty) {
          cr.register(
            command:     command,
            extensionId: extId,
            title:       title ?? command,
          );
        }
        return null;

      case 'vscode.commands.unregister':
        final command = params.isNotEmpty ? params[0] as String? ?? '' : '';
        if (command.isNotEmpty) cr.unregister(command);
        return null;

      case 'vscode.commands.execute':
        // params[0] = commandId  params[1+] = args
        final command = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final args    = params.length > 1 ? params.sublist(1) : <dynamic>[];
        if (command.isNotEmpty) return cr.execute(command, args);
        return null;

      case 'vscode.commands.getAll':
        return cr.commandIds;

      default:
        return null;
    }
  }

  // ── vscode.env.* ─────────────────────────────────────────────────────────
  // Phase 7 — Clipboard Flutter + url_launcher

  Future<dynamic> _routeEnv(
      String extId, String method, List<dynamic> params) async {
    switch (method) {
      case 'vscode.env.clipboard.read':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text ?? '';

      case 'vscode.env.clipboard.write':
        final text = params.isNotEmpty ? params[0] as String? ?? '' : '';
        await Clipboard.setData(ClipboardData(text: text));
        return null;

      case 'vscode.env.openExternal':
        final uriArg = params.isNotEmpty ? params[0] : null;
        String? uriStr;
        if (uriArg is Map<String, dynamic>) {
          uriStr = uriArg['toString'] as String? ??
              uriArg['path'] as String?;
        } else if (uriArg is String) {
          uriStr = uriArg;
        }
        if (uriStr == null) return false;
        try {
          final uri = Uri.parse(uriStr);
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          return false;
        }

      default:
        return null;
    }
  }

  // ── vscode.extensions.* ──────────────────────────────────────────────────
  // Phase 6 — implémentation via ExtensionExportsRegistry

  Future<dynamic> _routeExtensions(
      String extId, String method, List<dynamic> params) async {
    final er = ExtensionExportsRegistry.instance;

    switch (method) {
      case 'vscode.extensions.get':
        final id = params.isNotEmpty ? params[0] as String? : null;
        if (id == null) return null;
        return er.getExtensionJson(id);

      case 'vscode.extensions.getAll':
        return er.getAll();

      case 'vscode.extensions.exports.register':
        // Appelé par host.js après activate() — enregistre les exports
        final exports = params.isNotEmpty ? params[0] : null;
        final host    = ExtensionHostManager.instance.getHost(extId);
        if (host != null) {
          er.register(
            extensionId:   extId,
            version:       host.manifest.version,
            extensionPath: host.extension.installPath,
            exports:       exports,
          );
          // Met à jour le packageJSON si disponible
          if (host.manifest.raw.isNotEmpty) {
            er.setPackageJson(extId, host.manifest.raw);
          }
        }
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

  // ── vscode.webview.* ─────────────────────────────────────────────────────
  // Phase 9 — WebView Panels via flutter_inappwebview

  Future<dynamic> _routeWebview(
      String extId, String method, List<dynamic> params) async {
    final wm = WebviewPanelManager.instance;

    switch (method) {
      case 'vscode.webview.create':
        // params[0] = { panelId, viewType, title, showOptions, options }
        final config = params.isNotEmpty ? params[0] as Map<String, dynamic>? : null;
        if (config == null) return null;
        wm.createPanel(
          extensionId: extId,
          panelId: config['panelId'] as String,
          viewType: config['viewType'] as String? ?? '',
          title: config['title'] as String? ?? '',
          options: (config['options'] as Map<String, dynamic>?) ?? {},
        );
        return null;

      case 'vscode.webview.setHtml':
        final panelId = params.isNotEmpty ? params[0] as String? : null;
        final html    = params.length > 1 ? params[1] as String? ?? '' : '';
        if (panelId != null) {
          await wm.getPanel(panelId)?.setHtml(html);
        }
        return null;

      case 'vscode.webview.postMessage':
        final panelId = params.isNotEmpty ? params[0] as String? : null;
        final data    = params.length > 1 ? params[1] : null;
        if (panelId != null) {
          await wm.getPanel(panelId)?.postMessage(data);
        }
        return null;

      case 'vscode.webview.setTitle':
        // Panel title updates — handled via panel proxy
        return null;

      case 'vscode.webview.reveal':
        // Bring panel to front — no-op if already visible
        return null;

      case 'vscode.webview.dispose':
        final panelId = params.isNotEmpty ? params[0] as String? : null;
        if (panelId != null) wm.disposePanel(panelId);
        return null;

      default:
        debugPrint('[ExtApiRouter] Unknown webview method: $method');
        return null;
    }
  }

  // ── vscode.scm.* ─────────────────────────────────────────────────────────
  // Phase 10 — Source Control Management

  Future<dynamic> _routeScm(
      String extId, String method, List<dynamic> params) async {
    final scm = ScmBridge.instance;

    switch (method) {
      case 'vscode.scm.create':
        final config = params.isNotEmpty ? params[0] as Map<String, dynamic>? : null;
        if (config == null) return null;
        return scm.createSourceControl(
          extensionId: extId,
          id: config['id'] as String? ?? '',
          label: config['label'] as String? ?? '',
          rootUri: config['rootUri'] as String?,
        );

      case 'vscode.scm.createResourceGroup':
        final scmId   = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final groupId = params.length > 1 ? params[1] as String? ?? '' : '';
        final label   = params.length > 2 ? params[2] as String? ?? '' : '';
        return scm.createResourceGroup(scmId: scmId, groupId: groupId, label: label);

      case 'vscode.scm.setResourceStates':
        final scmId   = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final groupId = params.length > 1 ? params[1] as String? ?? '' : '';
        final resources = params.length > 2 ? params[2] as List<dynamic>? ?? [] : [];
        scm.setResourceGroupStates(scmId: scmId, groupId: groupId, resources: resources);
        return null;

      case 'vscode.scm.setInputBoxValue':
        final scmId = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final value = params.length > 1 ? params[1] as String? ?? '' : '';
        scm.setInputBoxValue(scmId, value);
        return null;

      case 'vscode.scm.setInputBoxPlaceholder':
        final scmId = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final ph    = params.length > 1 ? params[1] as String? ?? '' : '';
        scm.setInputBoxPlaceholder(scmId, ph);
        return null;

      case 'vscode.scm.update':
      case 'vscode.scm.updateGroup':
        return null; // handled client-side by ScmBridge notifyListeners

      case 'vscode.scm.disposeGroup':
        return null;

      case 'vscode.scm.dispose':
        final scmId = params.isNotEmpty ? params[0] as String? ?? '' : '';
        scm.disposeSourceControl(scmId);
        return null;

      default:
        debugPrint('[ExtApiRouter] Unknown scm method: $method');
        return null;
    }
  }

  // ── vscode.tasks.* ───────────────────────────────────────────────────────
  // Phase 11 — Task providers + execution

  Future<dynamic> _routeTasks(
      String extId, String method, List<dynamic> params) async {
    final tb = TasksBridge.instance;

    switch (method) {
      case 'vscode.tasks.registerProvider':
        final type = params.isNotEmpty ? params[0] as String? ?? '' : '';
        tb.registerTaskProvider(extId, type);
        return null;

      case 'vscode.tasks.unregisterProvider':
        tb.unregisterProvider(extId);
        return null;

      case 'vscode.tasks.providerResult':
        final type  = params.isNotEmpty ? params[0] as String? ?? '' : '';
        final tasks = params.length > 1 ? params[1] as List<dynamic>? ?? [] : [];
        tb.setProviderTasks(extId, tasks);
        return null;

      case 'vscode.tasks.fetchAll':
        final filter = params.isNotEmpty ? params[0] as Map<String, dynamic>? : null;
        final type   = filter?['type'] as String?;
        return (await tb.fetchTasks(type: type))
            .map((t) => {
              'name': t.name,
              'type': t.type,
              'detail': t.detail,
              '_taskId': t.taskId,
            })
            .toList();

      case 'vscode.tasks.execute':
        final taskJson = params.isNotEmpty ? params[0] as Map<String, dynamic>? : null;
        if (taskJson == null) return null;
        return tb.executeTask(taskJson, extId);

      case 'vscode.tasks.terminate':
        // Terminal termination — handled by flutter_pty
        return null;

      default:
        debugPrint('[ExtApiRouter] Unknown tasks method: $method');
        return null;
    }
  }

  // ── vscode.debug.* ───────────────────────────────────────────────────────
  // Phase 12 — Debug Adapter Protocol

  Future<dynamic> _routeDebug(
      String extId, String method, List<dynamic> params) async {
    final db = DebugBridge.instance;

    switch (method) {
      case 'vscode.debug.start':
        final config = params.length > 1 ? params[1] as Map<String, dynamic>? : null;
        if (config == null) return null;
        return db.startDebugging(extensionId: extId, config: config);

      case 'vscode.debug.stop':
        final sessionId = params.isNotEmpty ? params[0] as String? : null;
        await db.stopDebugging(sessionId);
        return null;

      case 'vscode.debug.customRequest':
        final sessionId = params.isNotEmpty ? params[0] as String? : null;
        final command   = params.length > 1 ? params[1] as String? : null;
        final args      = params.length > 2 ? params[2] : null;
        if (sessionId == null || command == null) return null;
        final session = db.getSession(sessionId);
        if (session == null) return null;
        final r = await session.send(command, args);
        return r.body;

      case 'vscode.debug.addBreakpoints':
        // Forward to active session
        final breakpoints = params.isNotEmpty ? params[0] as List<dynamic>? ?? [] : [];
        final active = db.activeSession;
        if (active == null) return null;
        // Extract file/line pairs and set them via DAP
        for (final bp in breakpoints) {
          if (bp is Map<String, dynamic>) {
            final loc = bp['location'] as Map<String, dynamic>?;
            final uri = loc?['uri']?['fsPath'] as String? ??
                        loc?['uri']?['path'] as String?;
            final line = (loc?['range']?['start']?['line'] as num?)?.toInt() ?? 0;
            if (uri != null) {
              await active.setBreakpoints(uri, [line + 1]); // DAP is 1-based
            }
          }
        }
        return null;

      case 'vscode.debug.removeBreakpoints':
        return null;

      case 'vscode.debug.console.append':
      case 'vscode.debug.console.appendLine':
        // Route to debug console output channel
        final text = params.isNotEmpty ? params[0] as String? ?? '' : '';
        OutputChannelManager.instance.appendLine('Debug Console', text);
        return null;

      case 'vscode.debug.getBreakpoint':
        return null;

      default:
        debugPrint('[ExtApiRouter] Unknown debug method: $method');
        return null;
    }
  }

  // ── Setup ────────────────────────────────────────────────────────────────

  /// À appeler depuis main.dart après avoir configuré ExtensionHostManager.
  void attachToManager() {
    ExtensionHostManager.instance.apiCallHandler = route;
    // Wire le bridge lookup pour que LanguageFeatureRouter puisse appeler les providers
    LanguageFeatureRouter.instance.bridgeLookup =
        ExtensionHostManager.instance.getBridge;
    // Wire the fireEvent callback for WebView panels → extension IPC events
    WebviewPanelManager.instance.fireEvent =
        ExtensionHostManager.instance.sendEvent;
    // Wire DebugBridge → IPC events
    DebugBridge.instance.fireEvent = ExtensionHostManager.instance.sendEvent;
  }
}
