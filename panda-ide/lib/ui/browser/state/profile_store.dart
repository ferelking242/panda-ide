import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/browser_profile.dart';

const _kProfilesKey         = 'browser_profiles';
const _kDefaultProfileIdKey = 'browser_default_profile_id';
const _kSearchEngineKey     = 'browser_search_engine';
const _kHomeUrlKey          = 'browser_home_url';
const _kMaxProfilesKey      = 'browser_max_profiles';

/// Persistence des profils et préférences navigateur via SharedPreferences.
class ProfileStore {
  static const _uuid = Uuid();

  // ── Profils ────────────────────────────────────────────────────────────

  static Future<List<BrowserProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProfilesKey);
    if (raw == null || raw.isEmpty) return _defaultProfiles();
    try {
      final list = jsonDecode(raw) as List;
      final profiles = list
          .map((e) => BrowserProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      return profiles.isEmpty ? _defaultProfiles() : profiles;
    } catch (_) {
      return _defaultProfiles();
    }
  }

  static Future<void> saveProfiles(List<BrowserProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kProfilesKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  // ── Profil par défaut ──────────────────────────────────────────────────

  static Future<String?> loadDefaultProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDefaultProfileIdKey);
  }

  static Future<void> saveDefaultProfileId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultProfileIdKey, id);
  }

  // ── Moteur de recherche ────────────────────────────────────────────────

  static Future<String> loadSearchEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSearchEngineKey) ??
        'https://www.google.com/search?q=%s';
  }

  static Future<void> saveSearchEngine(String engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSearchEngineKey, engine);
  }

  // ── URL d'accueil ──────────────────────────────────────────────────────

  static Future<String> loadHomeUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHomeUrlKey) ?? 'https://www.google.com';
  }

  static Future<void> saveHomeUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHomeUrlKey, url);
  }

  // ── Nombre max de profils ──────────────────────────────────────────────

  static Future<int> loadMaxProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kMaxProfilesKey) ?? 3;
  }

  static Future<void> saveMaxProfiles(int max) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxProfilesKey, max);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static String generateId() => _uuid.v4();

  static List<BrowserProfile> _defaultProfiles() => [
        BrowserProfile(
          id: _uuid.v4(),
          name: 'Personnel',
          color: kProfileColors[0],
          searchEngine: 'https://www.google.com/search?q=%s',
        ),
        BrowserProfile(
          id: _uuid.v4(),
          name: 'Travail',
          color: kProfileColors[1],
          searchEngine: 'https://www.google.com/search?q=%s',
        ),
      ];
}
