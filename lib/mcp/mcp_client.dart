import "dart:convert";
import "package:http/http.dart" as http;

class McpToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpToolSpec.fromJson(Map<String, dynamic> json) => McpToolSpec(
        name: json["name"] as String? ?? "",
        description: json["description"] as String? ?? "",
        inputSchema: Map<String, dynamic>.from(json["inputSchema"] as Map? ?? {}),
      );
}

class McpServerConfig {
  final String id;
  final String name;
  final String url;
  final Map<String, String> headers;
  bool isEnabled;

  McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.headers = const {},
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "url": url,
        "headers": headers,
        "isEnabled": isEnabled,
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) => McpServerConfig(
        id: json["id"] as String? ?? "",
        name: json["name"] as String? ?? "",
        url: json["url"] as String? ?? "",
        headers: Map<String, String>.from(json["headers"] as Map? ?? {}),
        isEnabled: json["isEnabled"] as bool? ?? true,
      );
}

class McpClient {
  final http.Client _client = http.Client();

  Future<List<McpToolSpec>> discoverTools(McpServerConfig config) async {
    if (!config.isEnabled || config.url.isEmpty) return [];
    try {
      final res = await _client.post(
        Uri.parse(config.url),
        headers: {"Content-Type": "application/json", ...config.headers},
        body: jsonEncode({
          "jsonrpc": "2.0",
          "id": 1,
          "method": "tools/list",
          "params": {},
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final result = body["result"] as Map?;
        final tools = result?["tools"] as List?;
        if (tools != null) {
          return tools.map((t) => McpToolSpec.fromJson(Map<String, dynamic>.from(t as Map))).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<String> callTool(McpServerConfig config, String toolName, Map<String, dynamic> args) async {
    try {
      final res = await _client.post(
        Uri.parse(config.url),
        headers: {"Content-Type": "application/json", ...config.headers},
        body: jsonEncode({
          "jsonrpc": "2.0",
          "id": DateTime.now().millisecondsSinceEpoch,
          "method": "tools/call",
          "params": {
            "name": toolName,
            "arguments": args,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final result = body["result"];
        return jsonEncode(result ?? {});
      }
      return "MCP Error ${res.statusCode}: ${res.body}";
    } catch (e) {
      return "MCP Client Exception: $e";
    }
  }
}
