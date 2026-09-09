import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One API key profile registered for a provider.
class KeyProfile {
  final String id;
  String label;
  String key;
  bool enabled;

  KeyProfile({
    required this.id,
    required this.label,
    required this.key,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'key': key, 'enabled': enabled};

  static KeyProfile fromJson(Map<String, dynamic> j) => KeyProfile(
        id: j['id']?.toString() ?? '',
        label: j['label']?.toString() ?? 'Clé',
        key: j['key']?.toString() ?? '',
        enabled: j['enabled'] != false,
      );

  String get masked {
    final k = key.trim();
    if (k.length <= 10) return '${k.substring(0, (k.length / 2).ceil())}••••';
    return '${k.substring(0, 6)}••••••${k.substring(k.length - 4)}';
  }
}

/// Live statistics the rotation brain keeps for a single key.
class KeyStats {
  int requests = 0;
  int errors = 0;
  int consecutiveErrors = 0;
  DateTime? lastUsedAt;
  DateTime? lastErrorAt;
  DateTime? cooldownUntil;
  DateTime? quotaResetAt;
  String lastStatus = 'ok';

  KeyStats();

  Map<String, dynamic> toJson() => {
        'requests': requests,
        'errors': errors,
        'consecutiveErrors': consecutiveErrors,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
        if (lastErrorAt != null) 'lastErrorAt': lastErrorAt!.toIso8601String(),
        if (cooldownUntil != null) 'cooldownUntil': cooldownUntil!.toIso8601String(),
        if (quotaResetAt != null) 'quotaResetAt': quotaResetAt!.toIso8601String(),
        'lastStatus': lastStatus,
      };

  static KeyStats fromJson(Map<String, dynamic> j) {
    final s = KeyStats();
    s.requests = (j['requests'] as num?)?.toInt() ?? 0;
    s.errors = (j['errors'] as num?)?.toInt() ?? 0;
    s.consecutiveErrors = (j['consecutiveErrors'] as num?)?.toInt() ?? 0;
    DateTime? parse(String? v) => v == null || v.isEmpty ? null : DateTime.tryParse(v);
    s.lastUsedAt = parse(j['lastUsedAt']);
    s.lastErrorAt = parse(j['lastErrorAt']);
    s.cooldownUntil = parse(j['cooldownUntil']);
    s.quotaResetAt = parse(j['quotaResetAt']);
    s.lastStatus = j['lastStatus']?.toString() ?? 'ok';
    return s;
  }

  bool get isCoolingDown =>
      (cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now())) ||
      (quotaResetAt != null && quotaResetAt!.isAfter(DateTime.now()));

  /// Human readable remaining cooldown ("2m 14s") or empty.
  String get cooldownRemaining {
    final now = DateTime.now();
    DateTime? until;
    if (cooldownUntil != null && cooldownUntil!.isAfter(now)) until = cooldownUntil;
    if (quotaResetAt != null && quotaResetAt!.isAfter(now)) {
      until = (until == null || quotaResetAt!.isAfter(until)) ? quotaResetAt : until;
    }
    if (until == null) return '';
    final d = until.difference(now);
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  /// When the quota/cooldown resets, formatted short ("00:00" or "12 mars 03:00").
  String get quotaResetLabel {
    final until = (quotaResetAt != null && quotaResetAt!.isAfter(DateTime.now()))
        ? quotaResetAt
        : (cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now()) ? cooldownUntil : null);
    if (until == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(until.hour)}:${two(until.minute)}';
    if (until.day != DateTime.now().day) return '${until.day}/${until.month} $hm';
    return hm;
  }
}

class _ProviderBrain {
  final List<KeyProfile> profiles = [];
  final Map<String, KeyStats> stats = {};
  bool autoRotate = true;
  String activeKeyId = '';
}

/// KeyRotationBrain — central "cerveau" that manages every API key profile of
/// every provider: it monitors usage, errors, rate-limit cooldowns and quota
/// resets, and always picks the healthiest available key.
class KeyRotationBrain extends ChangeNotifier {
  KeyRotationBrain._();
  static final KeyRotationBrain instance = KeyRotationBrain._();

  static const _prefsKey = 'panda_key_rotation_brain_v1';

  final Map<String, _ProviderBrain> _brains = {};
  Timer? _ticker; // periodic notify so cooldown labels stay fresh
  bool _loaded = false;

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((provider, value) {
            if (value is! Map) return;
            final brain = _ProviderBrain();
            brain.autoRotate = value['autoRotate'] != false;
            brain.activeKeyId = value['activeKeyId']?.toString() ?? '';
            if (value['profiles'] is List) {
              for (final p in (value['profiles'] as List)) {
                if (p is Map) brain.profiles.add(KeyProfile.fromJson(Map<String, dynamic>.from(p)));
              }
            }
            if (value['stats'] is Map) {
              (value['stats'] as Map).forEach((k, v) {
                if (v is Map) brain.stats[k.toString()] = KeyStats.fromJson(Map<String, dynamic>.from(v));
              });
            }
            _brains[provider.toString()] = brain;
          });
        }
      }
    } catch (_) {}
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (hasListeners) notifyListeners();
    });
    if (hasListeners) notifyListeners();
  }

  /// Snapshot synchrone (après chargement) pour l'UI.
  Map<String, List<KeyProfile>> snapshotSync() {
    final out = <String, List<KeyProfile>>{};
    _brains.forEach((provider, brain) {
      if (brain.profiles.isNotEmpty) {
        out[provider] = List<KeyProfile>.from(brain.profiles);
      }
    });
    return out;
  }

  /// État auto-rotation lu de façon synchrone (défaut true).
  bool autoRotateSync(String provider) => _brains[provider]?.autoRotate ?? true;

  KeyStats? statsSync(String provider, String keyId) =>
      _brains[provider]?.stats[keyId];

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      _brains.forEach((provider, brain) {
        out[provider] = {
          'autoRotate': brain.autoRotate,
          'activeKeyId': brain.activeKeyId,
          'profiles': brain.profiles.map((p) => p.toJson()).toList(),
          'stats': brain.stats.map((k, v) => MapEntry(k, v.toJson())),
        };
      });
      await prefs.setString(_prefsKey, jsonEncode(out));
    } catch (_) {}
  }

  _ProviderBrain _brainFor(String provider) => _brains.putIfAbsent(provider, () => _ProviderBrain());

  // ── Profile management ────────────────────────────────────────────────────

  Future<List<KeyProfile>> getProfiles(String provider) async {
    await _ensureLoaded();
    return List<KeyProfile>.from(_brainFor(provider).profiles);
  }

  Future<KeyProfile> addProfile(String provider, String label, String key) async {
    await _ensureLoaded();
    final brain = _brainFor(provider);
    // Re-adding an existing key just updates its label.
    final existing = brain.profiles.where((p) => p.key.trim() == key.trim()).toList();
    if (existing.isNotEmpty) {
      existing.first.label = label.trim().isEmpty ? existing.first.label : label.trim();
      await _persist();
      notifyListeners();
      return existing.first;
    }
    final profile = KeyProfile(
      id: 'kp_${DateTime.now().millisecondsSinceEpoch}_${brain.profiles.length}',
      label: label.trim().isEmpty ? 'Clé ${brain.profiles.length + 1}' : label.trim(),
      key: key.trim(),
    );
    brain.profiles.add(profile);
    if (brain.activeKeyId.isEmpty) brain.activeKeyId = profile.id;
    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> removeProfile(String provider, String profileId) async {
    await _ensureLoaded();
    final brain = _brainFor(provider);
    brain.profiles.removeWhere((p) => p.id == profileId);
    brain.stats.remove(profileId);
    if (brain.activeKeyId == profileId) {
      brain.activeKeyId = brain.profiles.isNotEmpty ? brain.profiles.first.id : '';
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setProfileEnabled(String provider, String profileId, bool enabled) async {
    await _ensureLoaded();
    final brain = _brainFor(provider);
    for (final p in brain.profiles) {
      if (p.id == profileId) p.enabled = enabled;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setActiveProfile(String provider, String profileId) async {
    await _ensureLoaded();
    final brain = _brainFor(provider);
    brain.activeKeyId = profileId;
    brain.autoRotate = false;
    await _persist();
    notifyListeners();
  }

  Future<void> setAutoRotate(String provider, bool value) async {
    await _ensureLoaded();
    _brainFor(provider).autoRotate = value;
    await _persist();
    notifyListeners();
  }

  Future<bool> isAutoRotate(String provider) async {
    await _ensureLoaded();
    return _brainFor(provider).autoRotate;
  }

  // ── Key selection ─────────────────────────────────────────────────────────

  /// Picks the best key for [provider]:
  ///  • skips disabled / cooling-down keys (unless none are eligible);
  ///  • with autoRotate ON → least-recently-used eligible key (spreads load);
  ///  • with autoRotate OFF → the manually selected active key.
  Future<String?> pickKey(String provider) async {
    await _ensureLoaded();
    final brain = _brainFor(provider);
    if (brain.profiles.isEmpty) return null;

    KeyStats statsFor(String id) => brain.stats.putIfAbsent(id, () => KeyStats());

    if (!brain.autoRotate) {
      final active = brain.profiles.where((p) => p.id == brain.activeKeyId).firstOrNull;
      final chosen = (active != null && active.enabled) ? active : brain.profiles.firstWhere((p) => p.enabled, orElse: () => brain.profiles.first);
      statsFor(chosen.id).lastUsedAt = DateTime.now();
      return chosen.key;
    }

    final now = DateTime.now();
    final eligible = brain.profiles.where((p) {
      if (!p.enabled) return false;
      final s = statsFor(p.id);
      final cooling = (s.cooldownUntil != null && s.cooldownUntil!.isAfter(now)) ||
          (s.quotaResetAt != null && s.quotaResetAt!.isAfter(now));
      return !cooling;
    }).toList();

    final pool = eligible.isNotEmpty ? eligible : brain.profiles.where((p) => p.enabled).toList();
    if (pool.isEmpty) pool.addAll(brain.profiles);
    if (pool.isEmpty) return null;

    pool.sort((a, b) {
      final sa = statsFor(a.id);
      final sb = statsFor(b.id);
      final la = sa.lastUsedAt?.millisecondsSinceEpoch ?? 0;
      final lb = sb.lastUsedAt?.millisecondsSinceEpoch ?? 0;
      return la.compareTo(lb); // least recently used first
    });
    final picked = pool.first;
    statsFor(picked.id).lastUsedAt = DateTime.now();
    await _persist();
    notifyListeners();
    return picked.key;
  }

  /// Id of the profile matching [key], for reporting results.
  String? profileIdForKey(String provider, String key) {
    final brain = _brains[provider];
    if (brain == null) return null;
    for (final p in brain.profiles) {
      if (p.key.trim() == key.trim()) return p.id;
    }
    return null;
  }

  // ── Result reporting ──────────────────────────────────────────────────────

  Future<void> reportSuccess(String provider, String? keyId) async {
    if (keyId == null) return;
    await _ensureLoaded();
    final brain = _brainFor(provider);
    final s = brain.stats.putIfAbsent(keyId, () => KeyStats());
    s.requests += 1;
    s.consecutiveErrors = 0;
    s.lastStatus = 'ok';
    s.lastUsedAt = DateTime.now();
    s.cooldownUntil = null;
    s.quotaResetAt = null;
    await _persist();
    notifyListeners();
  }

  /// Reports an HTTP failure and applies the matching cooldown policy:
  ///  • 429 rate-limit   → short cooldown (Retry-After aware, default 60 s)
  ///  • 402 payment/quota → until next UTC midnight (daily quota reset)
  ///  • 401/403 auth     → 30 min cooldown (key probably revoked)
  ///  • 5xx              → 15 s (provider hiccup)
  Future<void> reportFailure(String provider, String? keyId, int statusCode, {Duration? retryAfter}) async {
    await _ensureLoaded();
    final brain = _brainFor(provider);
    final id = keyId ?? brain.activeKeyId;
    if (id.isEmpty) return;
    final s = brain.stats.putIfAbsent(id, () => KeyStats());
    final now = DateTime.now();
    s.requests += 1;
    s.errors += 1;
    s.consecutiveErrors += 1;
    s.lastErrorAt = now;

    switch (statusCode) {
      case 429:
        s.lastStatus = 'rate_limited';
        s.cooldownUntil = now.add(retryAfter ?? const Duration(seconds: 60));
        break;
      case 402:
        s.lastStatus = 'quota_exhausted';
        final utc = DateTime.now().toUtc();
        s.quotaResetAt = DateTime.utc(utc.year, utc.month, utc.day + 1); // next UTC midnight
        break;
      case 401:
      case 403:
        s.lastStatus = 'auth_error';
        s.cooldownUntil = now.add(const Duration(minutes: 30));
        break;
      default:
        if (statusCode >= 500) {
          s.lastStatus = 'server_error';
          s.cooldownUntil = now.add(const Duration(seconds: 15));
        } else {
          s.lastStatus = 'error';
        }
    }
    await _persist();
    notifyListeners();
  }

  KeyStats? statsFor(String provider, String keyId) {
    final brain = _brains[provider];
    if (brain == null) return null;
    return brain.stats[keyId];
  }

  String activeProfileId(String provider) => _brainFor(provider).activeKeyId;

  bool hasProfiles(String provider) => _brains[provider]?.profiles.isNotEmpty ?? false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
