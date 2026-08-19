import 'dart:convert';

/// Base abstract class for all typed agent output blocks.
sealed class AgentBlock {
  const AgentBlock();

  Map<String, dynamic> toJson();

  static AgentBlock fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'text';
    switch (type) {
      case 'thinking':
        return ThinkingBlock.fromJson(json);
      case 'toolCall':
        return ToolCallBlock.fromJson(json);
      case 'text':
      default:
        return TextBlock.fromJson(json);
    }
  }
}

/// Represents a model thinking / reasoning phase (<think>...</think> or reasoning_content).
class ThinkingBlock extends AgentBlock {
  String content;
  bool isStreaming;
  bool isCollapsed;
  final DateTime timestamp;

  ThinkingBlock({
    this.content = '',
    this.isStreaming = false,
    this.isCollapsed = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  Map<String, dynamic> toJson() => {
        'type': 'thinking',
        'thinking': content,
        'isStreaming': isStreaming,
        'isCollapsed': isCollapsed,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ThinkingBlock.fromJson(Map<String, dynamic> json) => ThinkingBlock(
        content: json['thinking'] as String? ?? json['content'] as String? ?? '',
        isStreaming: json['isStreaming'] as bool? ?? false,
        isCollapsed: json['isCollapsed'] as bool? ?? true,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String)
            : null,
      );
}

/// Represents a tool invocation with name, parameters, result and lifecycle status.
class ToolCallBlock extends AgentBlock {
  final String toolName;
  final Map<String, dynamic> args;
  String? result;
  String status; // 'running', 'done', 'error', 'pending_approval'
  final DateTime timestamp;

  ToolCallBlock({
    required this.toolName,
    this.args = const {},
    this.result,
    this.status = 'running',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  Map<String, dynamic> toJson() => {
        'type': 'toolCall',
        'name': toolName,
        'args': args,
        'result': result,
        'status': status,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ToolCallBlock.fromJson(Map<String, dynamic> json) => ToolCallBlock(
        toolName: json['name'] as String? ?? json['toolName'] as String? ?? '',
        args: (json['args'] as Map?)?.cast<String, dynamic>() ?? {},
        result: json['result'] as String?,
        status: json['status'] as String? ?? 'done',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String)
            : null,
      );
}

/// Represents final markdown textual output from the assistant.
class TextBlock extends AgentBlock {
  String text;
  bool isStreaming;
  final DateTime timestamp;

  TextBlock({
    this.text = '',
    this.isStreaming = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'text': text,
        'isStreaming': isStreaming,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TextBlock.fromJson(Map<String, dynamic> json) => TextBlock(
        text: json['text'] as String? ?? '',
        isStreaming: json['isStreaming'] as bool? ?? false,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String)
            : null,
      );
}
