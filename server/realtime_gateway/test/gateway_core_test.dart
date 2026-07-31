import 'dart:io';

import 'package:test/test.dart';

import '../bin/server.dart' as gateway;

void main() {
  test('development token is accepted only in explicit development mode', () async {
    final verifier = gateway.AccessTokenVerifier(
      secret: '',
      allowInsecureDevelopmentToken: true,
    );
    final claims = await verifier.verify('dev');
    expect(claims, isNotNull);
    expect(claims!.profileId, '*');
    expect(claims.deviceId, '*');
  });

  test('event store persists, deduplicates and replays by room cursor', () async {
    final directory = await Directory.systemTemp.createTemp('cg-gateway-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = gateway.EventStore(directory);
    await store.initialize();

    final first = await store.append(
      packetId: 'packet-1',
      roomId: 'room-1',
      kind: 'message',
      priority: 'normal',
      fromProfileId: 'profile-a',
      fromDeviceId: 'android-a',
      createdAt: DateTime.now().toUtc(),
      ttl: const Duration(days: 1),
      crypto: const <String, dynamic>{'ciphertext': 'encrypted'},
    );
    expect(first.duplicate, isFalse);
    expect(first.event.roomSeq, 1);

    final duplicate = await store.append(
      packetId: 'packet-1',
      roomId: 'room-1',
      kind: 'message',
      priority: 'normal',
      fromProfileId: 'profile-a',
      fromDeviceId: 'android-a',
      createdAt: DateTime.now().toUtc(),
      ttl: const Duration(days: 1),
      crypto: const <String, dynamic>{'ciphertext': 'encrypted'},
    );
    expect(duplicate.duplicate, isTrue);
    expect(duplicate.event.roomSeq, 1);

    final second = await store.append(
      packetId: 'packet-2',
      roomId: 'room-1',
      kind: 'file_chunk',
      priority: 'bulk',
      fromProfileId: 'profile-a',
      fromDeviceId: 'android-a',
      createdAt: DateTime.now().toUtc(),
      ttl: const Duration(days: 1),
      crypto: const <String, dynamic>{'ciphertext': 'encrypted-chunk'},
    );
    expect(second.event.roomSeq, 2);

    final replay = store.eventsAfter('room-1', 1);
    expect(replay, hasLength(1));
    expect(replay.single.packetId, 'packet-2');

    final restored = gateway.EventStore(directory);
    await restored.initialize();
    expect(restored.eventsAfter('room-1', 0), hasLength(2));
  });
}
