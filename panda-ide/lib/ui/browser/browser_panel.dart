import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'models/browser_profile.dart';
import 'models/browser_tab.dart';
import 'state/browser_controller.dart';
import 'widgets/browser_tab_bar.dart';
import 'widgets/browser_address_bar.dart';

/// Point d'entrée du navigateur — fournit [BrowserController] et
/// affiche la pile d'onglets isolés.
class BrowserPanel extends StatelessWidget {
  const BrowserPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BrowserController()..init(),
      child: const _BrowserPanelContent(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BrowserPanelContent extends StatelessWidget {
  const _BrowserPanelContent();

  @override
  Widget build(BuildContext context) {
    final ctrl    = context.watch<BrowserController>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);

    if (ctrl.tabs.isEmpty) {
      return Container(
        color: bg,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final activeProfile = ctrl.activeProfile;
    final borderColor   = activeProfile?.color ?? const Color(0xff5090c8);

    return Container(
      color: bg,
      child: Column(
        children: [
          // ── Barre d'onglets ────────────────────────────────────────
          const BrowserTabBar(),

          // ── Barre d'adresse ────────────────────────────────────────
          const BrowserAddressBar(),

          // ── Zone WebView avec bordure couleur profil ───────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: borderColor, width: 2),
                ),
              ),
              child: IndexedStack(
                index: ctrl.activeTabIndex.clamp(0, ctrl.tabs.length - 1),
                children: ctrl.tabs.map((tab) {
                  final profile = ctrl.profileForId(tab.profileId);
                  return _IsolatedWebView(
                    key:        ValueKey('wv_${tab.id}'),
                    tab:        tab,
                    profile:    profile,
                    controller: ctrl,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// WebView isolé par profil.
///
/// Chaque [BrowserTab] a un `id` unique → [ValueKey] distinct →
/// Flutter recrée le widget (et donc le WebView natif) si le profil change.
class _IsolatedWebView extends StatefulWidget {
  final BrowserTab      tab;
  final BrowserProfile  profile;
  final BrowserController controller;

  const _IsolatedWebView({
    super.key,
    required this.tab,
    required this.profile,
    required this.controller,
  });

  @override
  State<_IsolatedWebView> createState() => _IsolatedWebViewState();
}

class _IsolatedWebViewState extends State<_IsolatedWebView> {
  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled:               true,
        domStorageEnabled:               true,
        databaseEnabled:                 true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback:       true,
        useOnDownloadStart:              true,
        safeBrowsingEnabled:             false,
        supportZoom:                     true,
        builtInZoomControls:             true,
        displayZoomControls:             false,
        // ── User-Agent personnalisé si défini ────────────────────────
        userAgent: widget.profile.userAgent,
      ),

      // ── Enregistrement du contrôleur natif ──────────────────────────
      onWebViewCreated: (wvc) {
        widget.controller.webControllers[widget.tab.id] = wvc;
      },

      // ── Suivi URL ────────────────────────────────────────────────────
      onLoadStart: (_, url) {
        widget.controller.updateTabUrl(widget.tab.id, url?.toString() ?? '');
        widget.controller.updateTabLoading(widget.tab.id, loading: true);
      },
      onLoadStop: (_, url) {
        widget.controller.updateTabUrl(widget.tab.id, url?.toString() ?? '');
        widget.controller.updateTabLoading(widget.tab.id, loading: false);
      },
      onLoadError: (_, __, ___, ____) {
        widget.controller.updateTabLoading(widget.tab.id, loading: false);
      },

      // ── Titre de la page ─────────────────────────────────────────────
      onTitleChanged: (_, title) {
        if (title != null && title.isNotEmpty) {
          widget.controller.updateTabTitle(widget.tab.id, title);
        }
      },

      // ── Historique (mise à jour URL lors de navigation JS) ───────────
      onUpdateVisitedHistory: (_, url, __) {
        final s = url?.toString() ?? '';
        if (s.isNotEmpty) {
          widget.controller.updateTabUrl(widget.tab.id, s);
        }
      },
    );
  }

  @override
  void dispose() {
    widget.controller.webControllers.remove(widget.tab.id);
    super.dispose();
  }
}
