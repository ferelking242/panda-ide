import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Manages agent session persistence.
///
/// Sessions can be saved, restored, and recovered after app interruption.
class SessionManager {
  static const _prefix = 'panda_session_';
  static const _currentKey = 'panda_current_session';

  /// Save the current session.
  Future<void> save(AgentSessionData session) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(session.toJson());
    await prefs.setString('$_prefix${session.id}', json);
    await prefs.setString(_currentKey, session.id);
  }

  /// Get the current session ID.
  Future<String?> getCurrentSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentKey);
  }

  /// Restore a session by ID.
  Future<AgentSessionData?> restore(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_prefix$sessionId');
    if (json == null) return null;
    try {
      return AgentSessionData.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// Get all saved session IDs.
  Future<List<String>> listSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    return keys.map((k) => k.substring(_prefix.length)).toList();
  }

  /// Delete a session.
  Future<void> delete(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$sessionId');
  }

  /// Clear current session marker.
  Future<void> clearCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentKey);
  }
}

class AgentSessionData {
  final String id;
  final String title;
  final String mode;
  final String model;
  final List<Map<String, dynamic>> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AgentSessionData({
    required this.id,
    required this.title,
    required this.mode,
    required this.model,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'mode': mode,
        'model': model,
        'messages': messages,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgentSessionData.fromJson(Map<String, dynamic> json) =>
      AgentSessionData(
        id: json['id'] ?? '',
        title: json['title'] ?? 'Session',
        mode: json['mode'] ?? 'agent',
        model: json['model'] ?? '',
        messages: (json['messages'] as List?)
                ?.map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            [],
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      );
}
