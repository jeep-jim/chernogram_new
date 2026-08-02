import 'dart:math';

import 'package:chernogram/optical/optical_codec.dart';
import 'package:chernogram/optical/optical_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text survives encrypted optical frames in shuffled order', () async {
    final room = OpticalInviteCodec.createRoom('Test room');
    const profile = OpticalProfile(id: 'device-a', nickname: 'Phone A');
    final message = OpticalMessage(
      id: 'message-1',
      senderId: profile.id,
      senderName: profile.nickname,
      sentAt: DateTime.utc(2026, 8, 2, 8),
      kind: 'text',
      text: 'Привет через экран',
    );
    final transfer = await OpticalTransferCodec.encodeText(
      room: room,
      profile: profile,
      message: message,
    );
    final shuffled = [...transfer.frames]..shuffle(Random(42));
    final accumulator = OpticalFrameAccumulator(expectedRoomId: room.id);
    for (final frame in shuffled) {
      accumulator.add(frame);
    }
    final packed = await accumulator.assembleAndVerify();
    final decoded = await OpticalTransferCodec.decode(
      room: room,
      packedBytes: packed,
    );
    expect(decoded.message.text, message.text);
    expect(decoded.message.senderId, profile.id);
    expect(decoded.message.kind, 'text');
  });

  test('binary file survives optical frames', () async {
    final room = OpticalInviteCodec.createRoom('Files');
    const profile = OpticalProfile(id: 'device-b', nickname: 'Phone B');
    final bytes = List<int>.generate(4096, (index) => index % 251);
    final message = OpticalMessage(
      id: 'file-1',
      senderId: profile.id,
      senderName: profile.nickname,
      sentAt: DateTime.utc(2026, 8, 2, 9),
      kind: 'file',
      fileName: 'sample.bin',
      fileSize: bytes.length,
    );
    final transfer = await OpticalTransferCodec.encodeFile(
      room: room,
      profile: profile,
      message: message,
      fileBytes: bytes,
    );
    final accumulator = OpticalFrameAccumulator(expectedRoomId: room.id);
    for (final frame in transfer.frames.reversed) {
      accumulator.add(frame);
    }
    final packed = await accumulator.assembleAndVerify();
    final decoded = await OpticalTransferCodec.decode(
      room: room,
      packedBytes: packed,
    );
    expect(decoded.message.fileName, 'sample.bin');
    expect(decoded.fileBytes, bytes);
  });
}
