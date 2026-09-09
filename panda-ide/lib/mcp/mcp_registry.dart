import "dart:convert";
import "package:shared_preferences/shared_preferences.dart";
import "mcp_client.dart";

class McpRegistry {
  static const String _key = "panda_mcp_servers_v1";

  static Future<List<McpServerConfig>> loadServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final List decoded = jsonDecode(raw);
      return decoded.map((s) => McpServerConfig.fromJson(Map<String, dynamic>.from(s))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveServers(List<McpServerConfig> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(servers.map((s) => s.toJson()).toList());
      await prefs.setString(_key, raw);
    } catch (_) {}
  }
}
