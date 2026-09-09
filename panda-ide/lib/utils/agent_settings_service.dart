library;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';



class AgentSettingsService {
  static const _kCustomPromptKey = 'panda_agent_custom_prompt';
  static const _kCustomRulesKey  = 'panda_agent_custom_rules';
  static const _kSecretsKey       = 'panda_agent_secrets_json';
  static const _kSkillsKey        = 'panda_agent_skills_json';

  static Future<String> getCustomPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCustomPromptKey) ?? '';
  }

  static Future<void> setCustomPrompt(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomPromptKey, value);
  }

  static Future<String> getCustomRules() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCustomRulesKey) ?? '';
  }

  static Future<void> setCustomRules(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomRulesKey, value);
  }

  static Future<Map<String, String>> getSecrets() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kSecretsKey);
    if (str == null || str.isEmpty) return {};
    try {
      final decoded = jsonDecode(str);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  static Future<void> setSecrets(Map<String, String> secrets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSecretsKey, jsonEncode(secrets));
  }

  static Future<List<String>> getSkills() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kSkillsKey);
    if (str == null || str.isEmpty) {
      return ['Code Analysis', 'Shell Runner', 'File Manager', 'Git Helper'];
    }
    try {
      final decoded = jsonDecode(str);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return ['Code Analysis', 'Shell Runner', 'File Manager', 'Git Helper'];
  }

  static Future<void> setSkills(List<String> skills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkillsKey, jsonEncode(skills));
  }
}
