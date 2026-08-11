import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AgentSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<Map<String, dynamic>> messages;
  final String agentMode;
  final String modelName;

  AgentSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.agentMode = 'agent',
    this.modelName = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages,
        'agentMode': agentMode,
        'modelName': modelName,
      };

  factory AgentSession.fromJson(Map<String, dynamic> json) => AgentSession(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Nouvelle discussion',
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        messages: (json['messages'] as List?)
                ?.map((m) => Map<String, dynamic>.from(m as Map))
                .toList() ??
            [],
        agentMode: json['agentMode'] as String? ?? 'agent',
        modelName: json['modelName'] as String? ?? '',
      );
}

class AgentHistoryService {
  static const String _keyPrefix = 'panda_agent_sessions_v1';
  static const int _maxSessions = 50;

  static Future<List<AgentSession>> loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyPrefix);
      if (raw == null || raw.isEmpty) return [];
      final List decoded = jsonDecode(raw) as List;
      final sessions = decoded
          .map((item) => AgentSession.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSession(AgentSession session) async {
    try {
      final sessions = await loadSessions();
      final index = sessions.indexWhere((s) => s.id == session.id);
      if (index >= 0) {
        sessions[index] = session;
      } else {
        sessions.insert(0, session);
      }

      if (sessions.length > _maxSessions) {
        sessions.removeRange(_maxSessions, sessions.length);
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_keyPrefix, raw);
    } catch (_) {}
  }

  static Future<void> deleteSession(String id) async {
    try {
      final sessions = await loadSessions();
      sessions.removeWhere((s) => s.id == id);
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_keyPrefix, raw);
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPrefix);
    } catch (_) {}
  }
}
