import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/broken_icons.dart';
import '../gateway/gateway_installer.dart';
import '../gateway/gateway_manager.dart';
import '../gateway/gateway_webview_bridge.dart';

// ── Couleurs VSCode ───────────────────────────────────────────────────────────
const _kBg     = Color(0xff1e1e1e);
const _kBgL    = Color(0xfffafafa);
const _kHdr    = Color(0xff252526);
const _kHdrL   = Color(0xffececec);
const _kBorder = Color(0xff3a3a3a);
const _kBorderL= Color(0xffdddddd);
const _kAccent = Color(0xff5090c8);
const _kGreen  = Color(0xff4ec9b0);
const _kRed    = Color(0xfff44747);
const _kMuted  = Color(0xff6a9955);

/// GatewayPanel — onglet complet d'interface pour panda-browser-gateway.
///
/// Fournit :
///   - Installation depuis GitHub (ou assets embarqués)
///   - Sélection du provider (ChatGPT / Claude)
///   - Démarrage / arrêt du serveur Python
///   - WebView intégré (dashboard http://127.0.0.1:8000/client)
///   - Console de logs
class GatewayPanel extends StatefulWidget {
  const GatewayPanel({super.key});

  @override
  State<GatewayPanel> createState() => _GatewayPanelState();
}

class _GatewayPanelState extends State<GatewayPanel>
    with SingleTickerProviderStateMixin {
  late final GatewayManager _manager;
  late final GatewayWebViewBridge _bridge;
  late final TabController _tabCtrl;

  InAppWebViewController? _webController;
  bool _installing = false;
  String _installLog = '';
  String? _installDir;

  @override
  void initState() {
    super.initState();
    _manager = GatewayManager();
    _bridge  = GatewayWebViewBridge();
    _tabCtrl = TabController(length: 2, vsync: this);

    // Connecter le bridge à la WebView
    _bridge.onCommand = _handleBridgeCommand;

    _initBridgeAndDir();
  }

  Future<void> _initBridgeAndDir() async {
    _installDir = await GatewayInstaller.getInstallDir();
    try {
      await _bridge.start();
    } catch (e) {
      debugPrint('[GatewayPanel] Bridge error: $e');
    }
    if (mounted) setState(() {});
  }

  // ── Bridge handler ────────────────────────────────────────────────────────

  Future<dynamic> _handleBridgeCommand(Map<String, dynamic> cmd) async {
    final action = cmd['action'] as String;
    final ctrl = _webController;
    if (ctrl == null) throw Exception('WebView not ready');

    if (action == 'navigate') {
      final url = cmd['url'] as String;
      await ctrl.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
      return 'ok';
    }

    if (action == 'eval') {
      final script = cmd['script'] as String;
      final result = await ctrl.evaluateJavascript(source: script);
      return result;
    }

    throw Exception('Unknown bridge action: $action');
  }

  // ── Installation ──────────────────────────────────────────────────────────

  Future<void> _install({bool force = false}) async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _installLog = '';
    });

    await GatewayInstaller.install(
      forceReinstall: force,
      onProgress: (msg) {
        setState(() => _installLog += '$msg\n');
      },
    );

    setState(() => _installing = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _manager,
      builder: (ctx, _) => _buildBody(ctx, _manager, isDark),
    );
  }

  Widget _buildBody(BuildContext ctx, GatewayManager mgr, bool dark) {
    final bg      = dark ? _kBg     : _kBgL;
    final hdr     = dark ? _kHdr    : _kHdrL;
    final border  = dark ? _kBorder : _kBorderL;
    final fg      = dark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted   = dark ? Colors.grey[500]! : Colors.grey[500]!;

    return Container(
      color: bg,
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _buildHeader(mgr, hdr, border, fg, muted, dark),

          // ── Status bar ────────────────────────────────────────────────────
          _buildStatusBar(mgr, dark),

          // ── Tabs ──────────────────────────────────────────────────────────
          Container(
            color: hdr,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: fg,
              unselectedLabelColor: muted,
              indicatorColor: _kAccent,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'INTERFACE'),
                Tab(text: 'LOGS'),
              ],
            ),
          ),

          // ── Tab content ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildWebViewTab(mgr, dark, bg, border),
                _buildLogsTab(mgr, dark, bg, fg, muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(GatewayManager mgr, Color hdr, Color border, Color fg, Color muted, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hdr,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.router, size: 16, color: _kAccent),
            const SizedBox(width: 8),
            Text('PANDA BROWSER GATEWAY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 1.1, color: muted)),
            const Spacer(),
            // Provider toggle
            _ProviderToggle(manager: mgr, fg: fg, muted: muted),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // Install button
            _ActionButton(
              label: _installing ? 'Installation…' : 'Installer / MàJ',
              icon: Icons.download_outlined,
              color: _kAccent,
              enabled: !_installing && !mgr.isRunning,
              onTap: _install,
            ),
            const SizedBox(width: 8),
            // Start / Stop
            _ActionButton(
              label: mgr.status == GatewayStatus.starting
                  ? 'Démarrage…'
                  : mgr.isRunning ? 'Arrêter' : 'Démarrer',
              icon: mgr.isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
              color: mgr.isRunning ? _kRed : _kGreen,
              enabled: !_installing &&
                  mgr.status != GatewayStatus.starting &&
                  mgr.status != GatewayStatus.stopping,
              onTap: () async {
                if (mgr.isRunning) {
                  await mgr.stop();
                } else {
                  if (_installDir != null) await mgr.start(_installDir!);
                }
              },
            ),
            const SizedBox(width: 8),
            // Open in browser (client test)
            if (mgr.isRunning)
              _ActionButton(
                label: 'Client Test',
                icon: Icons.language_outlined,
                color: muted,
                enabled: true,
                onTap: () {
                  _webController?.loadUrl(
                    urlRequest: URLRequest(
                        url: WebUri('http://127.0.0.1:${mgr.apiPort}/client')),
                  );
                  _tabCtrl.animateTo(0);
                },
              ),
          ]),
          if (_installing && _installLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 80),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: dark ? const Color(0xff1e1e1e) : const Color(0xfff0f0f0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _installLog,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xff4ec9b0)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  Widget _buildStatusBar(GatewayManager mgr, bool dark) {
    Color dotColor;
    switch (mgr.status) {
      case GatewayStatus.running:  dotColor = _kGreen; break;
      case GatewayStatus.error:    dotColor = _kRed;   break;
      case GatewayStatus.starting: dotColor = Colors.orange; break;
      default:                     dotColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: dark ? const Color(0xff2d2d2d) : const Color(0xfff0f0f0),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            mgr.statusMessage,
            style: TextStyle(
                fontSize: 11,
                color: dark ? Colors.grey[400] : Colors.grey[700]),
          ),
        ),
        if (mgr.isRunning)
          Text(
            'http://127.0.0.1:${mgr.apiPort}/v1',
            style: const TextStyle(
                fontSize: 11, fontFamily: 'monospace', color: _kAccent),
          ),
      ]),
    );
  }

  // ── WebView tab ───────────────────────────────────────────────────────────

  Widget _buildWebViewTab(GatewayManager mgr, bool dark, Color bg, Color border) {
    if (!mgr.isRunning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.router_outlined,
                size: 48, color: dark ? Colors.grey[700] : Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Démarrez le gateway pour accéder à l\'interface.',
              style: TextStyle(
                  fontSize: 13,
                  color: dark ? Colors.grey[500] : Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'API compatible OpenAI disponible sur :${mgr.apiPort}/v1',
              style: const TextStyle(fontSize: 11, color: _kAccent),
            ),
          ],
        ),
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('http://127.0.0.1:${mgr.apiPort}/client'),
      ),
      onWebViewCreated: (ctrl) {
        _webController = ctrl;
      },
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
      ),
    );
  }

  // ── Logs tab ──────────────────────────────────────────────────────────────

  Widget _buildLogsTab(GatewayManager mgr, bool dark, Color bg, Color fg, Color muted) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: dark ? const Color(0xff252526) : const Color(0xffececec),
          child: Row(children: [
            Text('${mgr.logs.length} lignes',
                style: TextStyle(fontSize: 11, color: muted)),
            const Spacer(),
            _IconBtn(
              icon: Icons.delete_outline,
              tooltip: 'Effacer',
              color: muted,
              onTap: mgr.clearLogs,
            ),
          ]),
        ),
        // Log list
        Expanded(
          child: mgr.logs.isEmpty
              ? Center(
                  child: Text('Aucun log.',
                      style: TextStyle(fontSize: 12, color: muted)),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: mgr.logs.length,
                  itemBuilder: (_, i) {
                    final line = mgr.logs[mgr.logs.length - 1 - i];
                    final color = line.contains('✗') || line.contains('Error') || line.contains('error')
                        ? _kRed
                        : line.contains('✓') || line.contains('ready') || line.contains('startup complete')
                            ? _kGreen
                            : dark ? Colors.grey[400]! : Colors.grey[700]!;
                    return Text(
                      line,
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 11, color: color),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _bridge.stop();
    _manager.stop();
    _manager.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _ProviderToggle extends StatelessWidget {
  final GatewayManager manager;
  final Color fg, muted;
  const _ProviderToggle({required this.manager, required this.fg, required this.muted});

  @override
  Widget build(BuildContext context) {
    final isChatGPT = manager.provider == 'chatgpt';
    return Row(children: [
      Text('Provider:', style: TextStyle(fontSize: 11, color: muted)),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: () => manager.setProvider('chatgpt'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isChatGPT ? _kAccent.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: isChatGPT ? _kAccent : Colors.grey.withOpacity(0.3)),
          ),
          child: Text('ChatGPT',
              style: TextStyle(fontSize: 11,
                  color: isChatGPT ? _kAccent : muted,
                  fontWeight: isChatGPT ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: () => manager.setProvider('claude'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: !isChatGPT ? _kAccent.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: !isChatGPT ? _kAccent : Colors.grey.withOpacity(0.3)),
          ),
          child: Text('Claude',
              style: TextStyle(fontSize: 11,
                  color: !isChatGPT ? _kAccent : muted,
                  fontWeight: !isChatGPT ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            border: Border.all(color: color.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: color,
                fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
