
import 'package:flutter_test/flutter_test.dart';
import 'package:panda/logging/panda_log_event.dart';
import 'package:panda/logging/panda_log_level.dart';
import 'package:panda/logging/panda_log_store.dart';

void main() {
  group('PandaLogStore', () {
    late PandaLogStore store;

    setUp(() async {
      store = PandaLogStore();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('initializes without error', () async {
      await store.init();
      expect(store.recentEvents, isEmpty);
    });

    test('writes events to memory', () async {
      await store.init();

      final event = PandaLogEvent(
        id: 'test-mem-001',
        timestamp: DateTime.now(),
        level: PandaLogLevel.info,
        category: PandaLogCategory.app,
        message: 'Test event',
      );

      store.write(event);
      expect(store.recentEvents, isNotEmpty);
      expect(store.recentEvents.last.message, 'Test event');
    });

    test('keeps events in ring buffer', () async {
      await store.init();

      for (var i = 0; i < 5; i++) {
        store.write(PandaLogEvent(
          id: 'ring-$i',
          timestamp: DateTime.now(),
          level: PandaLogLevel.info,
          category: PandaLogCategory.app,
          message: 'Event $i',
        ));
      }

      expect(store.ringBuffer.length, 5);
    });

    test('limits ring buffer to 100', () async {
      await store.init();

      for (var i = 0; i < 150; i++) {
        store.write(PandaLogEvent(
          id: 'overflow-$i',
          timestamp: DateTime.now(),
          level: PandaLogLevel.info,
          category: PandaLogCategory.app,
          message: 'Event $i',
        ));
      }

      expect(store.ringBuffer.length, 100);
      expect(store.ringBuffer.first.message, 'Event 50'); // oldest kept
    });

    test('limits memory events to max', () async {
      await store.init();

      for (var i = 0; i < 2100; i++) {
        store.write(PandaLogEvent(
          id: 'mem-$i',
          timestamp: DateTime.now(),
          level: PandaLogLevel.info,
          category: PandaLogCategory.app,
          message: 'Event $i',
        ));
      }

      // Memory limit is 2000, should keep newest
      expect(store.recentEvents.length, 2000);
    });

    test('live stream emits events', () async {
      await store.init();

      final received = <PandaLogEvent>[];
      final sub = store.liveStream.listen((e) => received.add(e));

      store.write(PandaLogEvent(
        id: 'live-001',
        timestamp: DateTime.now(),
        level: PandaLogLevel.info,
        category: PandaLogCategory.app,
        message: 'Live event',
      ));

      await Future.delayed(Duration.zero); // let stream propagate
      expect(received.length, 1);
      expect(received.first.message, 'Live event');

      await sub.cancel();
    });

    test('level filtering respects config', () async {
      final config = PandaLogConfig(
        fileMinLevel: PandaLogLevel.warning, // only warning+ to file
      );
      await store.init(config: config);

      store.write(PandaLogEvent(
        id: 'filtered-001',
        timestamp: DateTime.now(),
        level: PandaLogLevel.debug,
        category: PandaLogCategory.app,
        message: 'Debug event',
      ));

      // Still in memory (not filtered)
      expect(store.recentEvents.last.message, 'Debug event');
    });

    test('flush does not crash when no buffer', () async {
      await store.init();
      await store.flush(); // Should not throw
    });

    test('clearAll empties everything', () async {
      await store.init();

      store.write(PandaLogEvent(
        id: 'clear-001',
        timestamp: DateTime.now(),
        level: PandaLogLevel.info,
        category: PandaLogCategory.app,
        message: 'To be cleared',
      ));

      expect(store.recentEvents, isNotEmpty);
      await store.clearAll();
      expect(store.recentEvents, isEmpty);
      expect(store.ringBuffer, isEmpty);
    });
  });

  group('PandaLogConfig', () {
    test('default config values are reasonable', () {
      const config = PandaLogConfig.defaultConfig;
      expect(config.maxFileSizeBytes, 10 * 1024 * 1024); // 10MB
      expect(config.retentionDays, 30);
      expect(config.crashRetentionDays, 90);
      expect(config.maxBufferSize, 200);
    });

    test('diagnostic config is more verbose', () {
      const config = PandaLogConfig.diagnosticConfig;
      expect(config.maxBufferSize, 500);
    });
  });
}
