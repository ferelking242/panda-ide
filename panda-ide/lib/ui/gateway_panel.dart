import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/broken_icons.dart';
import '../gateway/gateway_installer.dart';
import '../gateway/gateway_manager.dart';
import '../gateway/gateway_webview_bridge.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg      = Color(0xff131720);
const _kBgL     = Color(0xfff4f6fb);
const _kSurface = Color(0xff1c2130);
const _kSurfaceL= Color(0xffffffff);
const _kBorder  = Color(0xff2a3145);
const _kBorderL = Color(0xffe2e6ef);
const _kAccent  = Color(0xff5090c8);
const _kGreen   = Color(0xff34c77b);
const _kRed     = Color(0xffef5350);
const _kAmber   = Color(0xffffa726);
const _kMuted   = Color(0xff6b7a99);
const _kPanda   = Color(0xff5090c8);

/// GatewayPanel — interface complète pour panda-browser-gateway.
///
/// Sections :
///  • En-tête avec état Python + actions install/start
///  • Sélection du provider : ChatGPT / Claude / Panda Open Gateway
///  • Token input (Panda Open Gateway)
///  • WebView (dashboard)
///  • Console de logs
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

  // Install state
  bool _installing = false;
  String _installLog = '';
  String? _installDir;
  bool _installed = false;

  // Python detection
  String? _pythonBin;
  bool _checkingPython = false;

  // Token for Panda Open Gateway
  final _tokenCtrl = TextEditingController();
  bool _tokenVisible = false;

  @override
  void initState() {
    super.initState();
    _manager = GatewayManager();
    _bridge  = GatewayWebViewBridge();
    _tabCtrl = TabController(length: 2, vsync: this);
    _bridge.onCommand = _handleBridgeCommand;
    _initPanel();
  }

  Future<void> _initPanel() async {
    _installDir = await GatewayInstaller.getInstallDir();
    _installed  = await GatewayInstaller.isInstalled();
    try { await _bridge.start(); } catch (_) {}
    await _detectPython();
    if (mounted) setState(() {});
  }

  Future<void> _detectPython() async {
    if (_checkingPython) return;
    setState(() => _checkingPython = true);
    _pythonBin = await _manager.findPython();
    setState(() => _checkingPython = false);
  }

  // ── Bridge handler ────────────────────────────────────────────────────────
  Future<dynamic> _handleBridgeCommand(Map<String, dynamic> cmd) async {
    final ctrl = _webController;
    if (ctrl == null) throw Exception('WebView not ready');
    final action = cmd['action'] as String;
    if (action == 'navigate') {
      await ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(cmd['url'] as String)));
      return 'ok';
    }
    if (action == 'eval') {
      return await ctrl.evaluateJavascript(source: cmd['script'] as String);
    }
    throw Exception('Unknown bridge action: $action');
  }

  // ── Install ───────────────────────────────────────────────────────────────
  Future<void> _install({bool force = false}) async {
    if (_installing) return;
    setState(() { _installing = true; _installLog = ''; });

    await GatewayInstaller.install(
      forceReinstall: force,
      onProgress: (msg) => setState(() => _installLog += '$msg\n'),
    );

    _installed = await GatewayInstaller.isInstalled();
    setState(() => _installing = false);
  }

  // ── Start / Stop ─────────────────────────────────────────────────────────
  Future<void> _toggleServer() async {
    if (_manager.isRunning) {
      await _manager.stop();
    } else {
      if (_installDir == null) return;
      // Save token if Panda Open Gateway is selected
      if (_manager.provider == 'pandagateway') {
        _manager.setToken(_tokenCtrl.text.trim());
      }
      await _manager.start(_installDir!);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _manager,
      builder: (ctx, _) => _buildBody(ctx, isDark),
    );
  }

  Widget _buildBody(BuildContext ctx, bool dark) {
    final bg = dark ? _kBg : _kBgL;
    return Container(
      color: bg,
      child: Column(
        children: [
          _buildHeader(dark),
          _buildProviderBar(dark),
          if (_manager.provider == 'pandagateway') _buildTokenRow(dark),
          _buildStatusStrip(dark),
          _buildTabBar(dark),
          Expanded(child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildWebViewTab(dark),
              _buildLogsTab(dark),
            ],
          )),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool dark) {
    final surface = dark ? _kSurface : _kSurfaceL;
    final border  = dark ? _kBorder  : _kBorderL;
    final fg      = dark ? Colors.grey[200]! : Colors.grey[900]!;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ────────────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.router_rounded, size: 16, color: _kAccent),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Panda Browser Gateway',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
              Text('Serveur Python OpenAI-compatible',
                  style: TextStyle(fontSize: 11, color: _kMuted)),
            ]),
            const Spacer(),
            _PythonBadge(
              bin: _pythonBin,
              checking: _checkingPython,
              onRefresh: _detectPython,
            ),
          ]),

          const SizedBox(height: 12),

          // ── Action buttons ────────────────────────────────────────────────
          Wrap(spacing: 8, runSpacing: 6, children: [
            // Install
            _GwButton(
              icon: Icons.download_rounded,
              label: _installing ? 'Installation…' : (_installed ? 'Réinstaller' : 'Installer'),
              color: _kAccent,
              loading: _installing,
              enabled: !_installing && !_manager.isRunning,
              onTap: () => _install(force: _installed),
            ),

            // Start / Stop — disabled if python not found or not installed
            _GwButton(
              icon: _manager.isRunning
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              label: _manager.status == GatewayStatus.starting
                  ? 'Démarrage…'
                  : _manager.isRunning ? 'Arrêter' : 'Démarrer',
              color: _manager.isRunning ? _kRed : _kGreen,
              loading: _manager.status == GatewayStatus.starting ||
                  _manager.status == GatewayStatus.stopping,
              enabled: !_installing &&
                  _installed &&
                  _pythonBin != null &&
                  _manager.status != GatewayStatus.starting &&
                  _manager.status != GatewayStatus.stopping,
              onTap: _toggleServer,
            ),

            // Open client tab
            if (_manager.isRunning)
              _GwButton(
                icon: Icons.open_in_browser_rounded,
                label: 'Interface',
                color: _kMuted,
                enabled: true,
                onTap: () {
                  _webController?.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri('http://127.0.0.1:${_manager.apiPort}/client'),
                    ),
                  );
                  _tabCtrl.animateTo(0);
                },
              ),
          ]),

          // ── Install log ───────────────────────────────────────────────────
          if (_installing && _installLog.isNotEmpty) ...[
            const SizedBox(height: 10),
            _LogBox(text: _installLog, dark: dark, maxHeight: 100),
          ],

          // ── No python warning ─────────────────────────────────────────────
          if (!_checkingPython && _pythonBin == null && !_manager.isRunning) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              icon: Icons.warning_amber_rounded,
              color: _kAmber,
              dark: dark,
              text: 'Python introuvable. Installez Python via le '
                  'Gestionnaire de paquets puis relancez.',
              action: TextButton(
                onPressed: _detectPython,
                child: const Text('Détecter', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],

          // ── Not installed hint ────────────────────────────────────────────
          if (!_installed && !_installing) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              icon: Icons.info_outline_rounded,
              color: _kAccent,
              dark: dark,
              text: 'Appuyez sur "Installer" pour télécharger panda-browser-gateway.',
            ),
          ],
        ],
      ),
    );
  }

  // ── Provider bar ─────────────────────────────────────────────────────────
  Widget _buildProviderBar(bool dark) {
    final surface = dark ? const Color(0xff1a2035) : const Color(0xfff8f9fd);
    final border  = dark ? _kBorder : _kBorderL;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROVIDER', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.0, color: _kMuted)),
          const SizedBox(height: 8),
          Row(children: [
            _ProviderChip(
              label: 'ChatGPT',
              icon: Icons.chat_bubble_outline_rounded,
              color: const Color(0xff10a37f),
              selected: _manager.provider == 'chatgpt',
              onTap: () { _manager.setProvider('chatgpt'); setState(() {}); },
            ),
            const SizedBox(width: 8),
            _ProviderChip(
              label: 'Claude',
              icon: Icons.psychology_outlined,
              color: const Color(0xffb87333),
              selected: _manager.provider == 'claude',
              onTap: () { _manager.setProvider('claude'); setState(() {}); },
            ),
            const SizedBox(width: 8),
            _ProviderChip(
              label: 'Panda Gateway',
              icon: Icons.router_rounded,
              color: _kPanda,
              selected: _manager.provider == 'pandagateway',
              onTap: () { _manager.setProvider('pandagateway'); setState(() {}); },
            ),
          ]),
        ],
      ),
    );
  }

  // ── Token row (Panda Open Gateway) ────────────────────────────────────────
  Widget _buildTokenRow(bool dark) {
    final surface = dark ? const Color(0xff1a2035) : const Color(0xfff8f9fd);
    final border  = dark ? _kBorder : _kBorderL;
    final fg      = dark ? Colors.grey[300]! : Colors.grey[800]!;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOKEN PANDA OPEN GATEWAY', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.0, color: _kMuted)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xff131720) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: TextField(
                  controller: _tokenCtrl,
                  obscureText: !_tokenVisible,
                  style: TextStyle(fontSize: 13, color: fg,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'Collez votre token ici…',
                    hintStyle: TextStyle(fontSize: 12, color: _kMuted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _tokenVisible ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16, color: _kMuted),
                      onPressed: () =>
                          setState(() => _tokenVisible = !_tokenVisible),
                    ),
                  ),
                  onChanged: (_) => _manager.setToken(_tokenCtrl.text.trim()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _GwIconBtn(
              icon: Icons.copy_all_rounded,
              tooltip: 'Copier',
              color: _kMuted,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _tokenCtrl.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Token copié'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ]),
        ],
      ),
    );
  }

  // ── Status strip ─────────────────────────────────────────────────────────
  Widget _buildStatusStrip(bool dark) {
    Color dotColor;
    switch (_manager.status) {
      case GatewayStatus.running:  dotColor = _kGreen; break;
      case GatewayStatus.error:    dotColor = _kRed;   break;
      case GatewayStatus.starting:
      case GatewayStatus.stopping: dotColor = _kAmber; break;
      default:                     dotColor = _kMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: dark ? const Color(0xff0f1422) : const Color(0xffeef0f6),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: _manager.isRunning
                ? [BoxShadow(color: dotColor.withOpacity(0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _manager.statusMessage,
            style: TextStyle(
                fontSize: 11,
                color: dark ? Colors.grey[400] : Colors.grey[600]),
          ),
        ),
        if (_manager.isRunning)
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: 'http://127.0.0.1:${_manager.apiPort}/v1'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URL copiée'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _kAccent.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  ':${_manager.apiPort}/v1',
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace', color: _kAccent),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.copy_outlined, size: 10, color: _kAccent),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────
  Widget _buildTabBar(bool dark) {
    final surface = dark ? _kSurface : _kSurfaceL;
    final border  = dark ? _kBorder  : _kBorderL;
    final fg      = dark ? Colors.grey[300]! : Colors.grey[800]!;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelColor: _kAccent,
        unselectedLabelColor: _kMuted,
        indicatorColor: _kAccent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.web_rounded, size: 14),
              const SizedBox(width: 5),
              const Text('INTERFACE'),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.terminal_rounded, size: 14),
              const SizedBox(width: 5),
              Text('LOGS (${_manager.logs.length})'),
            ]),
          ),
        ],
      ),
    );
  }

  // ── WebView tab ───────────────────────────────────────────────────────────
  Widget _buildWebViewTab(bool dark) {
    if (!_manager.isRunning) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.router_outlined, size: 56,
              color: dark ? Colors.grey[700] : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Démarrez le gateway pour voir l\'interface.',
            style: TextStyle(
                fontSize: 13,
                color: dark ? Colors.grey[500] : Colors.grey[500]),
          ),
          const SizedBox(height: 6),
          Text(
            'API compatible OpenAI sur :${_manager.apiPort}/v1',
            style: const TextStyle(fontSize: 11, color: _kAccent),
          ),
          const SizedBox(height: 20),
          if (!_installed)
            TextButton.icon(
              onPressed: _install,
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('Installer le gateway'),
              style: TextButton.styleFrom(foregroundColor: _kAccent),
            )
          else if (_pythonBin == null)
            Text(
              'Python requis — installez-le via le gestionnaire de paquets.',
              style: TextStyle(fontSize: 11, color: _kAmber),
            ),
        ]),
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('http://127.0.0.1:${_manager.apiPort}/client'),
      ),
      onWebViewCreated: (ctrl) => _webController = ctrl,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
      ),
    );
  }

  // ── Logs tab ──────────────────────────────────────────────────────────────
  Widget _buildLogsTab(bool dark) {
    final fg   = dark ? Colors.grey[300]! : Colors.grey[800]!;
    final bg   = dark ? _kBg : _kBgL;
    final hdr  = dark ? _kSurface : _kSurfaceL;

    return Column(children: [
      // Toolbar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: hdr,
        child: Row(children: [
          Icon(Icons.circle, size: 8, color: _kGreen.withOpacity(
              _manager.isRunning ? 1 : 0.3)),
          const SizedBox(width: 6),
          Text(
            '${_manager.logs.length} entrées',
            style: TextStyle(fontSize: 11, color: _kMuted),
          ),
          const Spacer(),
          _GwIconBtn(
            icon: Icons.delete_sweep_rounded,
            tooltip: 'Effacer',
            color: _kMuted,
            onTap: _manager.clearLogs,
          ),
        ]),
      ),

      // Log lines
      Expanded(
        child: _manager.logs.isEmpty
            ? Center(
                child: Text('Aucun log pour l\'instant.',
                    style: TextStyle(fontSize: 12, color: _kMuted)),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: _manager.logs.length,
                itemBuilder: (_, i) {
                  final line =
                      _manager.logs[_manager.logs.length - 1 - i];
                  final Color lineColor;
                  if (line.contains('✗') ||
                      line.contains('Error') ||
                      line.contains('error') ||
                      line.contains('CRITICAL')) {
                    lineColor = _kRed;
                  } else if (line.contains('✓') ||
                      line.contains('startup complete') ||
                      line.contains('running') ||
                      line.contains('ready')) {
                    lineColor = _kGreen;
                  } else if (line.contains('⚠') ||
                      line.contains('WARNING') ||
                      line.contains('warn')) {
                    lineColor = _kAmber;
                  } else if (line.contains('▶') ||
                      line.contains('■') ||
                      line.contains('PID')) {
                    lineColor = _kAccent;
                  } else {
                    lineColor = dark ? Colors.grey[400]! : Colors.grey[700]!;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: lineColor,
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  @override
  void dispose() {
    _bridge.stop();
    _manager.stop();
    _manager.dispose();
    _tabCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _PythonBadge extends StatelessWidget {
  final String? bin;
  final bool checking;
  final VoidCallback onRefresh;
  const _PythonBadge({required this.bin, required this.checking, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: _kMuted),
      );
    }
    final ok = bin != null;
    return GestureDetector(
      onTap: onRefresh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (ok ? _kGreen : _kRed).withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: (ok ? _kGreen : _kRed).withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            ok ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 12,
            color: ok ? _kGreen : _kRed,
          ),
          const SizedBox(width: 4),
          Text(
            ok ? 'Python ✓' : 'Python ?',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: ok ? _kGreen : _kRed,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ProviderChip({
    required this.label, required this.icon, required this.color,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : _kMuted.withOpacity(0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: selected ? color : _kMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              color: selected ? color : _kMuted,
            ),
          ),
        ]),
      ),
    );
  }
}

class _GwButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const _GwButton({
    required this.icon, required this.label, required this.color,
    required this.enabled, required this.onTap, this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.38,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.45)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              SizedBox(
                width: 13, height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: color),
              )
            else
              Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ]),
        ),
      ),
    );
  }
}

class _GwIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _GwIconBtn({required this.icon, required this.tooltip,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool dark;
  final String text;
  final Widget? action;
  const _InfoBanner({required this.icon, required this.color,
      required this.dark, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.9))),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

class _LogBox extends StatelessWidget {
  final String text;
  final bool dark;
  final double maxHeight;
  const _LogBox({required this.text, required this.dark, required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff0f1422) : const Color(0xfff0f0f0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: dark ? _kBorder : _kBorderL),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          text,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 11, color: _kGreen),
        ),
      ),
    );
  }
}
