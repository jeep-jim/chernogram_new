import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cernogram_realtime_gateway/src/gateway.dart';
import 'package:test/test.dart';

void main() {
  test(
    'delivers live events and replays offline events after the saved cursor',
    () async {
      final temporary =
          await Directory.systemTemp.createTemp('cernogram-gateway-integration-');
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final gateway = CernogramGateway(
        GatewayConfig(
          address: InternetAddress.loopbackIPv4,
          port: port,
          dataDirectory: temporary,
          signingSecret: '',
          allowAnonymousDevelopment: true,
        ),
      );
      await gateway.start();

      _Inbox? alice;
      _Inbox? bob;
      _Inbox? bobReconnected;
      try {
        alice = await _connect(port);
        bob = await _connect(port);
        _sendHello(alice.socket, profileId: 'alice', deviceId: 'android-a');
        _sendHello(bob.socket, profileId: 'bob', deviceId: 'windows-b');
        await alice.nextType('hello_ack');
        await bob.nextType('hello_ack');
        await alice.nextType('replay_complete');
        await bob.nextType('replay_complete');

        alice.socket.add(
          jsonEncode(<String, dynamic>{
            'type': 'event',
            'protocol': 1,
            'requestId': 'request-live-1',
            'packetId': 'packet-live-1',
            'roomId': 'room-test',
            'kind': 'message',
            'priority': 'normal',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'ttlSeconds': 3600,
            'crypto': const <String, dynamic>{
              'algorithm': 'AES-256-GCM',
              'nonce': 'nonce-live',
              'ciphertext': 'cipher-live',
              'mac': 'mac-live',
            },
          }),
        );
        final liveAck = await alice.nextType('event_ack');
        final liveEvent = await bob.nextType('event');
        expect(liveAck['duplicate'], isFalse);
        expect(liveEvent['packetId'], 'packet-live-1');
        expect(liveEvent['replay'], isFalse);
        final liveRoomSeq = liveEvent['roomSeq'] as int;
        bob.socket.add(
          jsonEncode(<String, dynamic>{
            'type': 'ack',
            'protocol': 1,
            'roomId': 'room-test',
            'roomSeq': liveRoomSeq,
          }),
        );

        await bob.close();
        bob = null;
        await Future<void>.delayed(const Duration(milliseconds: 80));

        alice.socket.add(
          jsonEncode(<String, dynamic>{
            'type': 'event',
            'protocol': 1,
            'requestId': 'request-offline-2',
            'packetId': 'packet-offline-2',
            'roomId': 'room-test',
            'kind': 'message',
            'priority': 'normal',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'ttlSeconds': 3600,
            'crypto': const <String, dynamic>{
              'algorithm': 'AES-256-GCM',
              'nonce': 'nonce-offline',
              'ciphertext': 'cipher-offline',
              'mac': 'mac-offline',
            },
          }),
        );
        await alice.nextType('event_ack');

        bobReconnected = await _connect(port);
        _sendHello(
          bobReconnected.socket,
          profileId: 'bob',
          deviceId: 'windows-b',
          lastRoomSeq: 0,
        );
        await bobReconnected.nextType('hello_ack');
        final replay = await bobReconnected.nextType('event');
        expect(replay['packetId'], 'packet-offline-2');
        expect(replay['replay'], isTrue);
        expect(replay['roomSeq'], liveRoomSeq + 1);
        final replayComplete = await bobReconnected.nextType('replay_complete');
        expect(replayComplete['events'], 1);
      } finally {
        await bobReconnected?.close();
        await bob?.close();
        await alice?.close();
        await gateway.stop();
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

Future<_Inbox> _connect(int port) async {
  final socket = await WebSocket.connect('ws://127.0.0.1:$port/v1/realtime');
  return _Inbox(socket);
}

void _sendHello(
  WebSocket socket, {
  required String profileId,
  required String deviceId,
  int lastRoomSeq = 0,
}) {
  socket.add(
    jsonEncode(<String, dynamic>{
      'type': 'hello',
      'protocol': 1,
      'requestId': 'hello-$profileId-$deviceId',
      'profileId': profileId,
      'deviceId': deviceId,
      'rooms': <Map<String, dynamic>>[
        <String, dynamic>{
          'roomId': 'room-test',
          'lastRoomSeq': lastRoomSeq,
        },
      ],
    }),
  );
}

class _Inbox {
  final WebSocket socket;
  late final StreamIterator<dynamic> _iterator = StreamIterator<dynamic>(socket);

  _Inbox(this.socket);

  Future<Map<String, dynamic>> nextType(String type) async {
    while (await _iterator.moveNext()) {
      final raw = _iterator.current;
      if (raw is! String) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final frame = Map<String, dynamic>.from(decoded);
      if (frame['type']?.toString() == 'error') {
        throw StateError('Gateway error: $frame');
      }
      if (frame['type']?.toString() == type) return frame;
    }
    throw StateError('Socket closed before frame type $type');
  }

  Future<void> close() async {
    await _iterator.cancel();
    await socket.close();
  }
}
