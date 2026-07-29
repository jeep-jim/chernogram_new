import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chernogram/realtime_gateway_models.dart';
import 'package:chernogram/realtime_gateway_outbox.dart';

void main() {
  group('CgGatewayOutboxStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cg_gateway_outbox_');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    CgGatewayOutboxRecord record(int index) {
      final now = DateTime.now().toUtc();
      return CgGatewayOutboxRecord(
        packetId: 'packet-$index',
        requestId: 'request-$index',
        roomId: 'room-a',
        kind: 'message',
        priority: 'normal',
        createdAt: now.add(Duration(milliseconds: index)),
        ttlSeconds: const Duration(days: 7).inSeconds,
        crypto: <String, dynamic>{
          'algorithm': 'AES-256-GCM',
          'nonce': 'nonce-$index',
          'ciphertext': 'cipher-$index',
          'mac': 'mac-$index',
        },
        nextAttemptAt: now.subtract(const Duration(seconds: 1)),
      );
    }

    test('persists and restores records with the same packetId', () async {
      final first = CgGatewayOutboxStore(directoryOverride: directory);
      await first.put(record(1));
      await first.put(record(2));

      final restored = CgGatewayOutboxStore(directoryOverride: directory);
      final values = await restored.all();

      expect(values.map((item) => item.packetId), <String>[
        'packet-1',
        'packet-2',
      ]);
    });

    test('removes acknowledged records', () async {
      final store = CgGatewayOutboxStore(directoryOverride: directory);
      await store.put(record(1));
      await store.remove('packet-1');

      final restored = CgGatewayOutboxStore(directoryOverride: directory);
      expect(await restored.all(), isEmpty);
    });

    test('keeps at most 500 newest pending records', () async {
      final store = CgGatewayOutboxStore(directoryOverride: directory);
      for (var index = 0; index < 510; index++) {
        await store.put(record(index));
      }

      final values = await store.all();
      expect(values, hasLength(CgGatewayOutboxStore.maxRecords));
      expect(values.first.packetId, 'packet-10');
      expect(values.last.packetId, 'packet-509');
    });

    test('delays records after a failed attempt', () async {
      final store = CgGatewayOutboxStore(directoryOverride: directory);
      await store.put(record(1));
      await store.markAttempt(
        'packet-1',
        attempts: 3,
        nextAttemptAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );

      expect(await store.pending(), isEmpty);
      final all = await store.all();
      expect(all.single.attempts, 3);
    });
  });
}
