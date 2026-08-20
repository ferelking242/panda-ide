import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:panda/logging/panda_log_event.dart';
import 'package:panda/logging/panda_log_level.dart';

void main() {
  group('PandaLogEvent', () {
    test('creates event with required fields', () {
      final event = PandaLogEvent(
        id: 'test-001',
        timestamp: DateTime(2026, 8, 20, 14, 30, 0, 500),
        level: PandaLogLevel.info,
        category: PandaLogCategory.agent,
        message: 'Agent started',
      );

      expect(event.id, 'test-001');
      expect(event.level, PandaLogLevel.info);
      expect(event.category, PandaLogCategory.agent);
      expect(event.message, 'Agent started');
      expect(event.sessionId, isNull);
      expect(event.agentRunId, isNull);
    });

    test('serializes to JSON with all fields', () {
      final event = PandaLogEvent(
        id: 'test-002',
        timestamp: DateTime(2026, 8, 20, 14, 30, 0, 500),
        level: PandaLogLevel.error,
        category: PandaLogCategory.terminal,
        message: 'Command failed',
        sessionId: 'sess-123',
        agentRunId: 'run-456',
        toolCallId: 'tool-789',
        source: 'terminal_native.dart:100',
        durationMs: 1500,
        projectPath: '/data/data/com.panda.ide',
        filePath: 'lib/main.dart',
        line: 42,
        column: 5,
        command: 'flutter analyze',
        cwd: '/data/data/com.panda.ide/projects/myapp',
        exitCode: 1,
        metadata: {'flutter_version': '3.12.0', 'errors': 3},
        error: 'Compilation failed',
        stackTrace: '#0 main\n#1 runApp',
      );

      final json = event.toJson();
      expect(json['id'], 'test-002');
      expect(json['level'], 'ERROR');
      expect(json['cat'], 'TERMINAL');
      expect(json['msg'], 'Command failed');
      expect(json['sid'], 'sess-123');
      expect(json['run'], 'run-456');
      expect(json['tool'], 'tool-789');
      expect(json['src'], 'terminal_native.dart:100');
      expect(json['dur'], 1500);
      expect(json['file'], 'lib/main.dart');
      expect(json['line'], 42);
      expect(json['col'], 5);
      expect(json['cmd'], 'flutter analyze');
      expect(json['exit'], 1);
      expect(json['meta'], {'flutter_version': '3.12.0', 'errors': 3});
      expect(json['err'], 'Compilation failed');
      expect(json['stack'], '#0 main\n#1 runApp');
    });

    test('omits null fields from JSON', () {
      final event = PandaLogEvent(
        id: 'test-003',
        timestamp: DateTime.now(),
        level: PandaLogLevel.info,
        category: PandaLogCategory.app,
        message: 'Simple message',
      );

      final json = event.toJson();
      expect(json.containsKey('sid'), false);
      expect(json.containsKey('run'), false);
      expect(json.containsKey('tool'), false);
      expect(json.containsKey('src'), false);
      expect(json.containsKey('dur'), false);
      expect(json.containsKey('file'), false);
      expect(json.containsKey('err'), false);
      expect(json.containsKey('stack'), false);
    });

    test('serializes to JSON line', () {
      final event = PandaLogEvent(
        id: 'test-004',
        timestamp: DateTime(2026, 8, 20, 14, 30, 0),
        level: PandaLogLevel.info,
        category: PandaLogCategory.app,
        message: 'Test message',
      );

      final jsonLine = event.toJsonLine();
      expect(jsonLine, isA<String>());

      // Should be valid JSON
      final parsed = jsonDecode(jsonLine) as Map<String, dynamic>;
      expect(parsed['id'], 'test-004');
      expect(parsed['msg'], 'Test message');
    });

    test('deserializes from JSON map', () {
      final json = {
        'id': 'test-005',
        'ts': '2026-08-20T14:30:00.500',
        'level': 'INFO',
        'cat': 'AGENT',
        'msg': 'Agent started',
        'run': 'run-abc',
        'dur': 2000,
      };

      final event = PandaLogEvent.fromJson(json);
      expect(event.id, 'test-005');
      expect(event.level, PandaLogLevel.info);
      expect(event.category, PandaLogCategory.agent);
      expect(event.message, 'Agent started');
      expect(event.agentRunId, 'run-abc');
      expect(event.durationMs, 2000);
    });

    test('deserializes from JSON line', () {
      final event = PandaLogEvent(
        id: 'test-006',
        timestamp: DateTime(2026, 8, 20, 14, 30, 0),
        level: PandaLogLevel.warning,
        category: PandaLogCategory.network,
        message: 'Slow request',
        durationMs: 5000,
      );

      final line = event.toJsonLine();
      final parsed = PandaLogEvent.fromJsonLine(line);

      expect(parsed, isNotNull);
      expect(parsed!.id, 'test-006');
      expect(parsed.level, PandaLogLevel.warning);
      expect(parsed.category, PandaLogCategory.network);
      expect(parsed.durationMs, 5000);
    });

    test('returns null for invalid JSON line', () {
      final parsed = PandaLogEvent.fromJsonLine('not valid json');
      expect(parsed, isNull);
    });

    test('handles missing fields gracefully', () {
      final json = {
        'msg': 'Partial event',
      };

      final event = PandaLogEvent.fromJson(json);
      expect(event.message, 'Partial event');
      expect(event.id, '');
      expect(event.level, PandaLogLevel.info); // default
      expect(event.category, PandaLogCategory.app); // default
    });

    test('toString includes prefix and message', () {
      final event = PandaLogEvent(
        id: 'test-007',
        timestamp: DateTime.now(),
        level: PandaLogLevel.error,
        category: PandaLogCategory.terminal,
        message: 'Something went wrong',
      );

      expect(event.toString(), '[E][TERMINAL] Something went wrong');
    });
  });

  group('PandaLogLevel', () {
    test('label returns correct string', () {
      expect(PandaLogLevel.debug.label, 'DEBUG');
      expect(PandaLogLevel.info.label, 'INFO');
      expect(PandaLogLevel.success.label, 'SUCCESS');
      expect(PandaLogLevel.warning.label, 'WARNING');
      expect(PandaLogLevel.error.label, 'ERROR');
      expect(PandaLogLevel.fatal.label, 'FATAL');
    });

    test('prefix returns correct short string', () {
      expect(PandaLogLevel.debug.prefix, 'D');
      expect(PandaLogLevel.info.prefix, 'I');
      expect(PandaLogLevel.error.prefix, 'E');
      expect(PandaLogLevel.fatal.prefix, 'F');
    });

    test('levels are ordered correctly', () {
      expect(PandaLogLevel.debug.index, lessThan(PandaLogLevel.info.index));
      expect(PandaLogLevel.info.index, lessThan(PandaLogLevel.warning.index));
      expect(PandaLogLevel.warning.index, lessThan(PandaLogLevel.error.index));
      expect(PandaLogLevel.error.index, lessThan(PandaLogLevel.fatal.index));
    });
  });

  group('PandaLogCategory', () {
    test('label returns correct string', () {
      expect(PandaLogCategory.app.label, 'APP');
      expect(PandaLogCategory.agent.label, 'AGENT');
      expect(PandaLogCategory.terminal.label, 'TERMINAL');
      expect(PandaLogCategory.git.label, 'GIT');
      expect(PandaLogCategory.build.label, 'BUILD');
      expect(PandaLogCategory.network.label, 'NETWORK');
      expect(PandaLogCategory.crash.label, 'CRASH');
    });

    test('fromString resolves correctly', () {
      expect(PandaLogCategory.fromString('AGENT'), PandaLogCategory.agent);
      expect(PandaLogCategory.fromString('terminal'), PandaLogCategory.terminal);
      expect(PandaLogCategory.fromString('unknown'), PandaLogCategory.app); // default
    });

    test('all categories have labels', () {
      for (final cat in PandaLogCategory.values) {
        expect(cat.label.isNotEmpty, true, reason: '${cat.name} has empty label');
      }
    });
  });

  group('JSON Lines roundtrip', () {
    test('event survives serialize -> deserialize', () {
      final original = PandaLogEvent(
        id: 'roundtrip-001',
        timestamp: DateTime(2026, 8, 20, 14, 30, 0, 123),
        level: PandaLogLevel.error,
        category: PandaLogCategory.tool,
        message: 'Tool failed',
        agentRunId: 'run-xyz',
        toolCallId: 'call-123',
        command: 'read_file lib/main.dart',
        exitCode: 1,
        metadata: {'key': 'value'},
        error: 'File not found',
      );

      final line = original.toJsonLine();
      final restored = PandaLogEvent.fromJsonLine(line);

      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.level, original.level);
      expect(restored.category, original.category);
      expect(restored.message, original.message);
      expect(restored.agentRunId, original.agentRunId);
      expect(restored.toolCallId, original.toolCallId);
      expect(restored.command, original.command);
      expect(restored.exitCode, original.exitCode);
      expect(restored.error, original.error);
    });
  });
}
