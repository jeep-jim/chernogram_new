import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> nextFrame(
  StreamIterator<dynamic> iterator,
  String type, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final remaining = deadline.difference(DateTime.now());
    final moved = await iterator.moveNext().timeout(remaining);
    if (!moved) throw StateError('Socket closed while waiting for $type');
    final raw = iterator.current;
    if (raw is! String) continue;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) continue;
    final frame = Map<String, dynamic>.from(decoded);
    if (frame['type'] == type) return frame;
  }
  throw TimeoutException('Timed out waiting for $type');
}

Future<(WebSocket, StreamIterator<dynamic>)> openClient(
  String profile,
  String device, {
  int lastRoomSeq = 0,
}) async {
  final socket = await WebSocket.connect(
    'ws://127.0.0.1:18080/v1/realtime',
  );
  final iterator = StreamIterator<dynamic>(socket);
  socket.add(
    jsonEncode(<String, dynamic>{
      'type': 'hello',
      'protocol': 1,
      'requestId': 'hello-$device',
      'profileId': profile,
      'deviceId': device,
      'accessToken': 'dev',
      'rooms': <Map<String, dynamic>>[
        <String, dynamic>{
          'roomId': 'smoke.room.1',
          'lastRoomSeq': lastRoomSeq,
        },
      ],
    }),
  );
  await nextFrame(iterator, 'hello_ack');
  return (socket, iterator);
}

Map<String, dynamic> event(String packetId, String kind) => <String, dynamic>{
  'type': 'event',
  'protocol': 1,
  'requestId': 'request-$packetId',
  'packetId': packetId,
  'roomId': 'smoke.room.1',
  'kind': kind,
  'priority': kind == 'signal' ? 'realtime' : 'normal',
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'ttlSeconds': 300,
  'crypto': <String, dynamic>{
    'algorithm': 'AES-256-GCM',
    'nonce': 'AA',
    'ciphertext': 'BB',
    'mac': 'CC',
  },
};

Future<void> main() async {
  final (sender, senderFrames) = await openClient('profile-a', 'android-a');
  final (receiver, receiverFrames) = await openClient('profile-b', 'windows-b');

  sender.add(jsonEncode(event('packet-message-1', 'message')));
  final ack = await nextFrame(senderFrames, 'event_ack');
  if (ack['status'] != 'stored' || ack['roomSeq'] != 1) {
    throw StateError('Unexpected first ACK: $ack');
  }
  final delivery = await nextFrame(receiverFrames, 'event');
  if (delivery['packetId'] != 'packet-message-1') {
    throw StateError('Wrong live delivery: $delivery');
  }

  await receiver.close();
  await receiverFrames.cancel();
  sender.add(jsonEncode(event('packet-offline-2', 'file_chunk')));
  final offlineAck = await nextFrame(senderFrames, 'event_ack');
  if (offlineAck['status'] != 'stored' || offlineAck['roomSeq'] != 2) {
    throw StateError('Offline event was not stored: $offlineAck');
  }

  final (resumed, resumedFrames) = await openClient(
    'profile-b',
    'windows-b',
    lastRoomSeq: 1,
  );
  final replay = await nextFrame(resumedFrames, 'event');
  if (replay['packetId'] != 'packet-offline-2' || replay['replay'] != true) {
    throw StateError('Resume replay failed: $replay');
  }

  sender.add(jsonEncode(event('packet-signal-3', 'signal')));
  await nextFrame(senderFrames, 'event_ack');
  final signal = await nextFrame(resumedFrames, 'event');
  if (signal['packetId'] != 'packet-signal-3' || signal['kind'] != 'signal') {
    throw StateError('Signal delivery failed: $signal');
  }

  await sender.close();
  await resumed.close();
  await senderFrames.cancel();
  await resumedFrames.cancel();
  stdout.writeln('gateway smoke passed: live, file_chunk, replay, signal');
}
