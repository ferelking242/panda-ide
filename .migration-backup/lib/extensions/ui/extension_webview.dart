/// WebView panels pour les extensions VSCode — Phase 9.
///
/// Implémente vscode.window.createWebviewPanel() côté Flutter.
/// Utilise flutter_inappwebview pour le rendu HTML.
/// Le bridge postMessage est bidirectionnel :
///   Extension → WebView : panel.webview.postMessage(data)
///   WebView → Extension : window.vscode.postMessage(data) → event 'webview.message.<panelId>'
///
/// Usage :
///   WebviewPanelManager.instance.createPanel(id, viewType, title, html, options)
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// ── Modèle WebviewPanel ───────────────────────────────────────────────────────

class WebviewPanel {
  final String panelId;
  final String viewType;
  final String title;
  final Map<String, dynamic> options;

  String _html = '';
  InAppWebViewController? _controller;
  bool _visible = false;
  bool _disposed = false;

  // Callbacks vers l'extension (via IpcBridge)
  final void Function(String panelId, dynamic message)? onMessage;
  final void Function(String panelId)? onDidDispose;
  final void Function(String panelId, bool active)? onDidChangeViewState;

  WebviewPanel({
    required this.panelId,
    required this.viewType,
    required this.title,
    required this.options,
    this.onMessage,
    this.onDidDispose,
    this.onDidChangeViewState,
  });

  bool get isDisposed => _disposed;
  bool get isVisible => _visible;

  /// Met à jour le HTML affiché dans le WebView.
  Future<void> setHtml(String html) async {
    _html = html;
    await _controller?.loadData(
      data: _wrapHtml(html),
      mimeType: 'text/html',
      encoding: 'utf-8',
    );
  }

  /// Envoie un message de l'extension vers le WebView.
  Future<void> postMessage(dynamic data) async {
    final json = jsonEncode(data);
    await _controller?.evaluateJavascript(source:
      "window.__pandaPostMessage && window.__pandaPostMessage($json);");
  }

  void _attachController(InAppWebViewController controller) {
    _controller = controller;
    if (_html.isNotEmpty) {
      controller.loadData(
        data: _wrapHtml(_html),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onDidDispose?.call(panelId);
  }

  void _setVisible(bool v) {
    _visible = v;
    onDidChangeViewState?.call(panelId, v);
  }

  /// Injecte la vscode API dans le HTML pour que le webview puisse appeler postMessage.
  static String _wrapHtml(String html) {
    const vscodeBridge = r"""
<script>
(function() {
  var handlers = [];
  window.__pandaPostMessage = function(data) {
    handlers.forEach(function(h) { try { h(data); } catch(e) {} });
  };
  window.acquireVsCodeApi = function() {
    return {
      postMessage: function(data) {
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('pandaWebviewMessage', JSON.stringify(data));
        }
      },
      getState: function() { return window.__pandaState || {}; },
      setState: function(s) { window.__pandaState = s; },
    };
  };
  // Listen for messages from extension
  window.addEventListener = (function(original) {
    return function(type, handler, options) {
      if (type === 'message') {
        handlers.push(function(data) {
          try { handler({ data: data }); } catch(e) {}
        });
      }
      return original.call(this, type, handler, options);
    };
  })(window.addEventListener);
})();
</script>
""";

    // Inject before </head> or at start
    if (html.contains('</head>')) {
      return html.replaceFirst('</head>', '$vscodeBridge</head>');
    }
    if (html.contains('<html>')) {
      return html.replaceFirst('<html>', '<html><head>$vscodeBridge</head>');
    }
    return '<head>$vscodeBridge</head>$html';
  }
}

// ── Manager singleton ─────────────────────────────────────────────────────────

class WebviewPanelManager extends ChangeNotifier {
  static final WebviewPanelManager instance = WebviewPanelManager._();
  WebviewPanelManager._();

  final Map<String, WebviewPanel> _panels = {};
  String? _activePanel;

  List<WebviewPanel> get panels => _panels.values.where((p) => !p.isDisposed).toList();
  WebviewPanel? get activePanel =>
      _activePanel != null ? _panels[_activePanel] : null;

  // Callbacks to send IPC events to extensions
  void Function(String extensionId, String event, dynamic data)? _fireEvent;
  void Function(String extensionId, String event, dynamic data)? get fireEvent => _fireEvent;
  set fireEvent(void Function(String extensionId, String event, dynamic data)? f) => _fireEvent = f;

  /// Crée un nouveau panneau WebView.
  /// Appelé depuis ExtensionApiRouter quand l'extension appelle vscode.window.createWebviewPanel.
  WebviewPanel createPanel({
    required String extensionId,
    required String panelId,
    required String viewType,
    required String title,
    required Map<String, dynamic> options,
  }) {
    final panel = WebviewPanel(
      panelId: panelId,
      viewType: viewType,
      title: title,
      options: options,
      onMessage: (id, msg) {
        // Forward message from WebView to extension via IPC event
        _fireEvent?.call(extensionId, 'webview.message.$id', msg);
      },
      onDidDispose: (id) {
        _panels.remove(id);
        if (_activePanel == id) _activePanel = _panels.keys.lastOrNull;
        notifyListeners();
        _fireEvent?.call(extensionId, 'webview.dispose.$id', null);
      },
      onDidChangeViewState: (id, active) {
        _fireEvent?.call(extensionId, 'webview.viewStateChanged.$id', {
          'active': active,
          'visible': active,
        });
      },
    );

    _panels[panelId] = panel;
    _activePanel = panelId;
    notifyListeners();
    return panel;
  }

  WebviewPanel? getPanel(String panelId) => _panels[panelId];

  void disposePanel(String panelId) {
    _panels[panelId]?.dispose();
    _panels.remove(panelId);
    if (_activePanel == panelId) _activePanel = _panels.keys.lastOrNull;
    notifyListeners();
  }
}

// ── Flutter Widget ────────────────────────────────────────────────────────────

/// Widget affichant un seul WebviewPanel.
class ExtensionWebviewWidget extends StatefulWidget {
  final WebviewPanel panel;

  const ExtensionWebviewWidget({super.key, required this.panel});

  @override
  State<ExtensionWebviewWidget> createState() => _ExtensionWebviewWidgetState();
}

class _ExtensionWebviewWidgetState extends State<ExtensionWebviewWidget> {
  InAppWebViewController? _controller;

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    javaScriptEnabled: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    mediaPlaybackRequiresUserGesture: false,
    transparentBackground: true,
  );

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.panel._attachController(controller);

        // Register handler for WebView → Extension messages
        controller.addJavaScriptHandler(
          handlerName: 'pandaWebviewMessage',
          callback: (args) {
            if (args.isNotEmpty) {
              try {
                final data = jsonDecode(args[0] as String);
                widget.panel.onMessage?.call(widget.panel.panelId, data);
              } catch (_) {
                widget.panel.onMessage?.call(widget.panel.panelId, args[0]);
              }
            }
          },
        );
      },
      onLoadStart: (controller, url) {
        widget.panel._setVisible(true);
      },
      onCloseWindow: (_) {
        widget.panel.dispose();
      },
    );
  }

  @override
  void dispose() {
    widget.panel._setVisible(false);
    super.dispose();
  }
}

// ── Tabbed WebView container ──────────────────────────────────────────────────

/// Conteneur à onglets affichant tous les panneaux WebView actifs.
/// À intégrer dans le layout principal de l'IDE (bottom panel ou tabs).
class ExtensionWebviewContainer extends StatelessWidget {
  const ExtensionWebviewContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WebviewPanelManager.instance,
      builder: (context, _) {
        final panels = WebviewPanelManager.instance.panels;
        if (panels.isEmpty) return const SizedBox.shrink();

        if (panels.length == 1) {
          return _PanelView(panel: panels.first);
        }

        return DefaultTabController(
          length: panels.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabs: panels.map((p) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.title, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => WebviewPanelManager.instance.disposePanel(p.panelId),
                        child: const Icon(Icons.close, size: 14),
                      ),
                    ],
                  ),
                )).toList(),
              ),
              Expanded(
                child: TabBarView(
                  children: panels.map((p) => _PanelView(panel: p)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PanelView extends StatelessWidget {
  final WebviewPanel panel;
  const _PanelView({required this.panel});

  @override
  Widget build(BuildContext context) {
    return ExtensionWebviewWidget(panel: panel);
  }
}
