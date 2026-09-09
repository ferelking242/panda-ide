import "dart:convert";
import "package:http/http.dart" as http;

class OllamaModelInfo {
  final String name;
  final int size;
  final String modifiedAt;

  OllamaModelInfo({
    required this.name,
    required this.size,
    required this.modifiedAt,
  });

  factory OllamaModelInfo.fromJson(Map<String, dynamic> json) => OllamaModelInfo(
        name: json["name"] as String? ?? "",
        size: json["size"] as int? ?? 0,
        modifiedAt: json["modified_at"] as String? ?? "",
      );
}

class OllamaService {
  static Future<List<OllamaModelInfo>> discoverLocalModels({
    String baseUrl = "http://localhost:11434",
  }) async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/api/tags")).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final models = body["models"] as List?;
        if (models != null) {
          return models.map((m) => OllamaModelInfo.fromJson(Map<String, dynamic>.from(m as Map))).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static String formatToolCallGrammar(List<Map<String, dynamic>> tools) {
    // Generate GBNF JSON schema or system prompt function instructions for LLaMA/Ollama
    final buffer = StringBuffer();
    buffer.writeln("You have access to the following tools:");
    for (final t in tools) {
      final fn = t["function"] as Map? ?? {};
      buffer.writeln("- ${fn["name"]}: ${fn["description"]}");
      buffer.writeln("  Parameters: ${jsonEncode(fn["parameters"] ?? {})}");
    }
    buffer.writeln("\nTo call a tool, respond ONLY with a JSON block:\n```json\n{\"tool\": \"tool_name\", \"args\": {...}}\n```");
    return buffer.toString();
  }
}
