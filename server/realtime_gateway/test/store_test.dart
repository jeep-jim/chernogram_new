import 'dart:convert';
import 'dart:io';

import 'package:cernogram_realtime_gateway/src/store.dart';
import 'package:cernogram_realtime_gateway/src/token.dart';
import 'package:test/test.dart';

void main() {
  group('GatewayTokenCodec', () {
    test('issues and verifies a room-scoped token', () {
      final codec =
          GatewayTokenCodec('a-secure-test-secret-with-more-than-32-chars');
      final token = codec.issue(
        profileId: 'profile-a',
        deviceId: 'android-main',
        rooms: const <String>['room-1', 'room-2'],
      );
      final identity = codec.verify(token);
      expect(identity.profileId, 'profile-a');
      expect(identity.deviceId, 'android-main');
      expect(identity.canAccess('room-1'), isTrue);
      expect(identity.canAccess('room-3'), isFalse);
    });
  });

  group('GatewayJsonStore', () {
    late Directory temporary;
    late GatewayJsonStore store;

    setUp(() async {
      temporary =
          await Directory.systemTemp.createTemp('cernogram-gateway-test-');
      store = GatewayJsonStore(temporary);
      await store.initialize();
    });

    tearDown(() async {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('keeps stable sequence for duplicate packetId', () async {
      final first = await store.append(
        roomId: 'room-a',
        packetId: 'packet-1',
        senderProfileId: 'profile-a',
        senderDeviceId: 'device-a',
        kind: 'message',
        priority: 'normal',
        createdAt: DateTime.now().toUtc(),
        ttl: const Duration(days: 7),
        crypto: const <String, dynamic>{
          'nonce': 'n',
          'ciphertext': 'c',
          'mac': 'm',
        },
      );
      final duplicate = await store.append(
        roomId: 'room-a',
        packetId: 'packet-1',
        senderProfileId: 'profile-a',
        senderDeviceId: 'device-a',
        kind: 'message',
        priority: 'normal',
        createdAt: DateTime.now().toUtc(),
        ttl: const Duration(days: 7),
        crypto: const <String, dynamic>{
          'nonce': 'other',
          'ciphertext': 'other',
          'mac': 'other',
        },
      );
      expect(first.duplicate, isFalse);
      expect(duplicate.duplicate, isTrue);
      expect(duplicate.event.roomSeq, first.event.roomSeq);
      expect(duplicate.event.serverSeq, first.event.serverSeq);
    });

    test('splits room events into JSON chunks of at most 500 records',
        () async {
      for (var index = 0; index < 501; index++) {
        await store.append(
          roomId: 'room-chunked',
          packetId: 'packet-$index',
          senderProfileId: 'profile-a',
          senderDeviceId: 'device-a',
          kind: 'message',
          priority: 'normal',
          createdAt: DateTime.now().toUtc(),
          ttl: const Duration(days: 7),
          crypto: <String, dynamic>{
            'nonce': 'n$index',
            'ciphertext': 'c$index',
            'mac': 'm$index',
          },
        );
      }

      final chunkFiles = await Directory('${temporary.path}/rooms')
          .list(recursive: true)
          .where((entity) =>
              entity is File &&
              RegExp(r'events_\d{6}\.json$').hasMatch(entity.path))
          .cast<File>()
          .toList();
      expect(chunkFiles, hasLength(2));
      final lengths = <int>[];
      for (final file in chunkFiles) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        lengths.add(decoded.length);
      }
      lengths.sort();
      expect(lengths, <int>[1, 500]);
    });

    test('persists and restores a per-device cursor', () async {
      await store.saveCursor(
        profileId: 'profile-a',
        deviceId: 'android-main',
        roomId: 'room-a',
        roomSeq: 42,
      );
      expect(
        await store.loadCursor(
          profileId: 'profile-a',
          deviceId: 'android-main',
          roomId: 'room-a',
        ),
        42,
      );
    });
  });
}
