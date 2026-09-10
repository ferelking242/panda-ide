import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

/// Lightweight project preview with two transports:
/// - WebView: render a local dashboard or app directly in Panda IDE.
/// - DevTools: discover pages exposed by Chrome's remote debugging endpoint
///   and open a selected target in the same WebView.
class PreviewPanel extends StatefulWidget {
  final String initialUrl;

  const PreviewPanel({
    super.key,
    this.initialUrl = 'http://127.0.0.1:5000',
  });

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

enum _PreviewMode { webView, devTools }

class _PreviewPanelState extends State<PreviewPanel> {
  static const _accent = Color(0xff5090c8);
  static const _borderDark = Color(0xff2a3145);
  static const _borderLight = Color(0xffe2e6ef);

  late final TextEditingController _urlController;
  final _cdpController = TextEditingController(
    text: 'http://127.0.0.1:9222',
  );

  InAppWebViewController? _webController;
  _PreviewMode _mode = _PreviewMode.webView;
  late String _currentUrl;
  List<Map<String, dynamic>> _targets = const [];
  bool _discovering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _cdpController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final value = _urlController.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      setState(() => _error = 'URL de preview invalide.');
      return;
    }
    setState(() {
      _error = null;
      _currentUrl = value;
      _mode = _PreviewMode.webView;
    });
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(value)),
    );
  }

  Future<void> _discoverTargets() async {
    final base = _cdpController.text.trim().replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.tryParse('$base/json/list');
    if (uri == null || !uri.hasScheme) {
      setState(() => _error = 'URL DevTools Protocol invalide.');
      return;
    }

    setState(() {
      _discovering = true;
      _error = null;
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException('Réponse inattendue');
      final pages = decoded
          .whereType<Map>()
          .map((target) => Map<String, dynamic>.from(target))
          .where((target) => (target['url'] ?? '').toString().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _targets = pages);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _targets = const [];
        _error =
            'Impossible de joindre $base. Lancez Chrome avec '
            '--remote-debugging-port=9222.';
      });
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _openTarget(Map<String, dynamic> target) async {
    final url = (target['url'] ?? '').toString();
    if (url.isEmpty) return;
    _urlController.text = url;
    setState(() {
      _currentUrl = url;
      _mode = _PreviewMode.webView;
    });
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xff131720) : const Color(0xfff4f6fb);
    final surface = dark ? const Color(0xff1c2130) : Colors.white;
    final foreground = dark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted = dark ? Colors.grey[500]! : Colors.grey[600]!;

    return ColoredBox(
      color: background,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: BoxDecoration(
              color: surface,
              border: Border(bottom: BorderSide(
                color: dark ? _borderDark : _borderLight,
              )),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.preview_outlined, color: _accent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Preview',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    ChoiceChip(
                      label: const Text('WebView'),
                      selected: _mode == _PreviewMode.webView,
                      onSelected: (_) => setState(
                        () => _mode = _PreviewMode.webView,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('DevTools'),
                      selected: _mode == _PreviewMode.devTools,
                      onSelected: (_) {
                        setState(() => _mode = _PreviewMode.devTools);
                        _discoverTargets();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_mode == _PreviewMode.webView)
                  _addressBar(foreground, muted, dark)
                else
                  _devToolsBar(foreground, muted, dark),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _mode == _PreviewMode.webView
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_currentUrl),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      supportZoom: true,
                      displayZoomControls: false,
                    ),
                    onWebViewCreated: (controller) {
                      _webController = controller;
                    },
                  )
                : _buildTargets(foreground, muted, surface),
          ),
        ],
      ),
    );
  }

  Widget _addressBar(Color foreground, Color muted, bool dark) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            style: TextStyle(fontSize: 12, color: foreground),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _loadPreview(),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.link, size: 15, color: muted),
              hintText: 'http://127.0.0.1:5000',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _loadPreview,
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Charger'),
        ),
      ],
    );
  }

  Widget _devToolsBar(Color foreground, Color muted, bool dark) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _cdpController,
            style: TextStyle(fontSize: 12, color: foreground),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _discoverTargets(),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.developer_mode, size: 15, color: muted),
              hintText: 'http://127.0.0.1:9222',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _discovering ? null : _discoverTargets,
          icon: _discovering
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.radar, size: 15),
          label: const Text('Détecter'),
        ),
      ],
    );
  }

  Widget _buildTargets(Color foreground, Color muted, Color surface) {
    if (_targets.isEmpty && !_discovering) {
      return Center(
        child: Text(
          'Aucune cible DevTools détectée.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _targets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final target = _targets[index];
        final title = (target['title'] ?? 'Page sans titre').toString();
        final url = (target['url'] ?? '').toString();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.web, color: _accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    )),
                    const SizedBox(height: 3),
                    Text(url, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 11)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openTarget(target),
                child: const Text('Ouvrir'),
              ),
            ],
          ),
        );
      },
    );
  }
}