import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:uuid/uuid.dart';
import '../models/browser_profile.dart';
import '../models/browser_tab.dart';
import 'profile_store.dart';

/// Contrôleur central du navigateur (ChangeNotifier).
/// Gère les onglets, les profils et leur état.
class BrowserController extends ChangeNotifier {
  static const _uuid = Uuid();

  List<BrowserProfile> _profiles = [];
  final List<BrowserTab>  _tabs   = [];
  int _activeTabIndex = 0;
  bool _initialized   = false;

  // ── WebView controllers ────────────────────────────────────────────────
  /// Clé = tab.id → InAppWebViewController natif
  final Map<String, InAppWebViewController> webControllers = {};

  /// Clé = tab.id → TextEditingController pour la barre d'adresse
  final Map<String, TextEditingController> urlControllers = {};

  // ── Getters ────────────────────────────────────────────────────────────

  List<BrowserProfile> get profiles  => _profiles;
  List<BrowserTab>     get tabs      => _tabs;
  int                  get activeTabIndex => _activeTabIndex;

  BrowserTab? get activeTab {
    if (_tabs.isEmpty) return null;
    return _tabs[_activeTabIndex.clamp(0, _tabs.length - 1)];
  }

  BrowserProfile profileForId(String id) => _profiles.firstWhere(
        (p) => p.id == id,
        orElse: () => _profiles.first,
      );

  BrowserProfile? get activeProfile {
    final tab = activeTab;
    if (tab == null || _profiles.isEmpty) return null;
    return profileForId(tab.profileId);
  }

  String _searchEngine = 'https://www.google.com/search?q=%s';
  String _homeUrl      = 'https://www.google.com';

  String get searchEngine => _searchEngine;
  String get homeUrl      => _homeUrl;

  // ── Init ───────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _profiles     = await ProfileStore.loadProfiles();
    _searchEngine = await ProfileStore.loadSearchEngine();
    _homeUrl      = await ProfileStore.loadHomeUrl();

    if (_profiles.isEmpty) {
      _profiles = [
        BrowserProfile(
          id: ProfileStore.generateId(),
          name: 'Personnel',
          color: kProfileColors[0],
          searchEngine: _searchEngine,
        ),
      ];
      await ProfileStore.saveProfiles(_profiles);
    }

    _addTabInternal(url: _homeUrl, profileId: _profiles.first.id);
    notifyListeners();
  }

  // ── Tabs ───────────────────────────────────────────────────────────────

  void addTab({String? url, String? profileId}) {
    final pid = profileId ?? activeTab?.profileId ?? _profiles.first.id;
    _addTabInternal(url: url ?? _homeUrl, profileId: pid);
    _activeTabIndex = _tabs.length - 1;
    notifyListeners();
  }

  void _addTabInternal({required String url, required String profileId}) {
    final id = _uuid.v4();
    _tabs.add(BrowserTab(id: id, url: url, profileId: profileId));
    urlControllers[id] = TextEditingController(text: url);
  }

  void closeTab(String tabId) {
    final idx = _tabs.indexWhere((t) => t.id == tabId);
    if (idx < 0) return;
    _tabs.removeAt(idx);
    urlControllers.remove(tabId)?.dispose();
    webControllers.remove(tabId);

    if (_tabs.isEmpty) {
      _addTabInternal(url: _homeUrl, profileId: _profiles.first.id);
    }
    _activeTabIndex =
        (_activeTabIndex >= _tabs.length ? _tabs.length - 1 : _activeTabIndex)
            .clamp(0, _tabs.length - 1);
    notifyListeners();
  }

  void setActiveTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_activeTabIndex == index) return;
    _activeTabIndex = index;
    notifyListeners();
  }

  /// Change le profil d'un onglet.
  /// Crée un nouveau tab ID pour forcer la recréation du WebView
  /// avec le bon dataDirectoryIdentifier.
  void changeTabProfile(String tabId, String newProfileId) {
    final idx = _tabs.indexWhere((t) => t.id == tabId);
    if (idx < 0) return;
    final old = _tabs[idx];
    if (old.profileId == newProfileId) return;

    // Nouveau tab ID → nouveau WebView → bonne isolation
    final newId = _uuid.v4();
    webControllers.remove(old.id);
    urlControllers.remove(old.id)?.dispose();
    urlControllers[newId] = TextEditingController(text: old.url);

    _tabs[idx] = BrowserTab(
      id:        newId,
      url:       old.url,
      profileId: newProfileId,
      title:     old.title,
    );
    notifyListeners();
  }

  // ── Mises à jour depuis WebView callbacks ──────────────────────────────

  void updateTabUrl(String tabId, String url) {
    final idx = _tabs.indexWhere((t) => t.id == tabId);
    if (idx < 0) return;
    _tabs[idx].url = url;
    final ctrl = urlControllers[tabId];
    if (ctrl != null && ctrl.text != url) ctrl.text = url;
    notifyListeners();
  }

  void updateTabTitle(String tabId, String title) {
    final idx = _tabs.indexWhere((t) => t.id == tabId);
    if (idx < 0 || _tabs[idx].title == title) return;
    _tabs[idx].title = title;
    notifyListeners();
  }

  void updateTabLoading(String tabId, {required bool loading}) {
    final idx = _tabs.indexWhere((t) => t.id == tabId);
    if (idx < 0 || _tabs[idx].isLoading == loading) return;
    _tabs[idx].isLoading = loading;
    notifyListeners();
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void navigateTo(String tabId, String rawInput) {
    final url = _resolveUrl(rawInput);
    webControllers[tabId]
        ?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    updateTabUrl(tabId, url);
  }

  String _resolveUrl(String input) {
    final s = input.trim();
    if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('file://')) {
      return s;
    }
    // Looks like a domain (no spaces, has a dot)
    if (!s.contains(' ') && RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}').hasMatch(s)) {
      return 'https://$s';
    }
    return _searchEngine.replaceAll('%s', Uri.encodeQueryComponent(s));
  }

  // ── Profils ────────────────────────────────────────────────────────────

  Future<void> createProfile({
    required String name,
    required Color  color,
    String? ua,
    String? engine,
  }) async {
    final p = BrowserProfile(
      id:           ProfileStore.generateId(),
      name:         name,
      color:        color,
      userAgent:    ua,
      searchEngine: engine ?? _searchEngine,
    );
    _profiles.add(p);
    await ProfileStore.saveProfiles(_profiles);
    notifyListeners();
  }

  Future<void> updateProfile(BrowserProfile updated) async {
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return;
    _profiles[idx] = updated;
    await ProfileStore.saveProfiles(_profiles);
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return; // garder au moins un profil
    _profiles.removeWhere((p) => p.id == id);
    // Réassigner les onglets orphelins
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].profileId == id) {
        final newId = _uuid.v4();
        urlControllers[newId] = TextEditingController(text: _tabs[i].url);
        urlControllers.remove(_tabs[i].id)?.dispose();
        webControllers.remove(_tabs[i].id);
        _tabs[i] = BrowserTab(
          id:        newId,
          url:       _tabs[i].url,
          profileId: _profiles.first.id,
          title:     _tabs[i].title,
        );
      }
    }
    await ProfileStore.saveProfiles(_profiles);
    notifyListeners();
  }

  Future<void> updateSearchEngine(String engine) async {
    _searchEngine = engine;
    await ProfileStore.saveSearchEngine(engine);
    notifyListeners();
  }

  Future<void> updateHomeUrl(String url) async {
    _homeUrl = url;
    await ProfileStore.saveHomeUrl(url);
    notifyListeners();
  }

  // ── Nettoyage cache ────────────────────────────────────────────────────

  Future<void> clearCookiesForProfile(String profileId) async {
    // Phase 1 : suppression globale des cookies (pas encore d'isolation par profil)
    await CookieManager.instance().deleteAllCookies();
  }

  // ── Dispose ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    for (final c in urlControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
