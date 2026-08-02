import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'optical_models.dart';

class OpticalInviteCodec {
  static OpticalRoom createRoom(String name) {
    final random = Random.secure();
    final secret = List<int>.generate(32, (_) => random.nextInt(256));
    return OpticalRoom(
      id: opticalRandomId(12),
      name: name.trim().isEmpty ? 'Оптическая комната' : name.trim(),
      secretBase64: base64UrlEncode(secret),
      createdAt: DateTime.now(),
      messages: const <OpticalMessage>[],
    );
  }

  static String encodeRoom(OpticalRoom room) => jsonEncode(<String, dynamic>{
    'v': 1,
    'k': 'room',
    'r': room.id,
    'n': room.name,
    's': room.secretBase64,
  });

  static OpticalRoom? decodeRoom(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['v'] != 1 || map['k'] != 'room') return null;
      final id = map['r']?.toString() ?? '';
      final name = map['n']?.toString() ?? '';
      final secret = map['s']?.toString() ?? '';
      final key = base64Url.decode(secret);
      if (id.isEmpty || name.isEmpty || key.length != 32) return null;
      return OpticalRoom(
        id: id,
        name: name,
        secretBase64: secret,
        createdAt: DateTime.now(),
        messages: const <OpticalMessage>[],
      );
    } catch (_) {
      return null;
    }
  }
}

class OpticalEncodedTransfer {
  final String transferId;
  final String roomId;
  final String kind;
  final int clearBytes;
  final int packedBytes;
  final String sha256;
  final List<String> frames;

  const OpticalEncodedTransfer({
    required this.transferId,
    required this.roomId,
    required this.kind,
    required this.clearBytes,
    required this.packedBytes,
    required this.sha256,
    required this.frames,
  });

  Duration estimateAt(double framesPerSecond) {
    if (frames.isEmpty || framesPerSecond <= 0) return Duration.zero;
    final seconds = frames.length / framesPerSecond;
    return Duration(milliseconds: (seconds * 1000).ceil());
  }
}

class OpticalFrameProgress {
  final bool accepted;
  final bool complete;
  final int received;
  final int total;
  final String? transferId;
  final String? error;

  const OpticalFrameProgress({
    required this.accepted,
    required this.complete,
    required this.received,
    required this.total,
    this.transferId,
    this.error,
  });

  double get ratio => total <= 0 ? 0 : received / total;
}

class OpticalTransferCodec {
  static const int frameChunkBytes = 620;
  static final Cipher _cipher = Chacha20.poly1305Aead();
  static final HashAlgorithm _hash = Sha256();

  static Future<OpticalEncodedTransfer> encodeText({
    required OpticalRoom room,
    required OpticalProfile profile,
    required OpticalMessage message,
  }) async {
    final header = <String, dynamic>{
      'v': 1,
      'kind': 'text',
      'messageId': message.id,
      'senderId': profile.id,
      'senderName': profile.nickname,
      'sentAt': message.sentAt.toUtc().toIso8601String(),
      'text': message.text,
      'fileName': null,
      'fileSize': 0,
    };
    return _encode(room: room, kind: 'text', header: header);
  }

  static Future<OpticalEncodedTransfer> encodeFile({
    required OpticalRoom room,
    required OpticalProfile profile,
    required OpticalMessage message,
    required List<int> fileBytes,
  }) async {
    final header = <String, dynamic>{
      'v': 1,
      'kind': 'file',
      'messageId': message.id,
      'senderId': profile.id,
      'senderName': profile.nickname,
      'sentAt': message.sentAt.toUtc().toIso8601String(),
      'text': '',
      'fileName': message.fileName ?? 'file.bin',
      'fileSize': fileBytes.length,
    };
    return _encode(room: room, kind: 'file', header: header, body: fileBytes);
  }

  static Future<OpticalEncodedTransfer> _encode({
    required OpticalRoom room,
    required String kind,
    required Map<String, dynamic> header,
    List<int> body = const <int>[],
  }) async {
    final headerBytes = utf8.encode(jsonEncode(header));
    final headerLength = ByteData(4)
      ..setUint32(0, headerBytes.length, Endian.big);
    final clearBuilder = BytesBuilder(copy: false)
      ..add(headerLength.buffer.asUint8List())
      ..add(headerBytes)
      ..add(body);
    final clear = clearBuilder.takeBytes();

    final secret = SecretKey(base64Url.decode(room.secretBase64));
    final box = await _cipher.encrypt(clear, secretKey: secret);
    final packedBuilder = BytesBuilder(copy: false)
      ..addByte(box.nonce.length)
      ..add(box.nonce)
      ..addByte(box.mac.bytes.length)
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    final packed = packedBuilder.takeBytes();
    final digest = await _hash.hash(packed);
    final hashHex = _hex(digest.bytes);
    final transferId = opticalRandomId(10);
    final count = (packed.length / frameChunkBytes)
        .ceil()
        .clamp(1, 1 << 30)
        .toInt();
    final frames = <String>[];
    for (var index = 0; index < count; index++) {
      final start = index * frameChunkBytes;
      final end = min(start + frameChunkBytes, packed.length);
      final chunk = packed.sublist(start, end);
      frames.add(
        jsonEncode(<String, dynamic>{
          'v': 1,
          'k': 'data',
          'r': room.id,
          't': transferId,
          'i': index,
          'n': count,
          'h': hashHex,
          'd': base64UrlEncode(chunk),
        }),
      );
    }
    return OpticalEncodedTransfer(
      transferId: transferId,
      roomId: room.id,
      kind: kind,
      clearBytes: clear.length,
      packedBytes: packed.length,
      sha256: hashHex,
      frames: frames,
    );
  }

  static Future<OpticalReceivedPayload> decode({
    required OpticalRoom room,
    required List<int> packedBytes,
  }) async {
    if (packedBytes.length < 32) {
      throw const FormatException('Оптический пакет слишком короткий');
    }
    var offset = 0;
    final nonceLength = packedBytes[offset++];
    if (nonceLength <= 0 || offset + nonceLength >= packedBytes.length) {
      throw const FormatException('Повреждён nonce');
    }
    final nonce = packedBytes.sublist(offset, offset + nonceLength);
    offset += nonceLength;
    final macLength = packedBytes[offset++];
    if (macLength <= 0 || offset + macLength >= packedBytes.length) {
      throw const FormatException('Повреждён MAC');
    }
    final mac = packedBytes.sublist(offset, offset + macLength);
    offset += macLength;
    final cipherText = packedBytes.sublist(offset);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(base64Url.decode(room.secretBase64)),
    );
    if (clear.length < 4) {
      throw const FormatException('Повреждён заголовок');
    }
    final headerLength = ByteData.sublistView(
      Uint8List.fromList(clear.sublist(0, 4)),
    ).getUint32(0, Endian.big);
    if (headerLength <= 0 || 4 + headerLength > clear.length) {
      throw const FormatException('Некорректная длина заголовка');
    }
    final header = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(clear.sublist(4, 4 + headerLength))) as Map,
    );
    final kind = header['kind']?.toString() ?? 'text';
    final body = clear.sublist(4 + headerLength);
    final declaredSize =
        int.tryParse(header['fileSize']?.toString() ?? '') ?? 0;
    if (kind == 'file' && declaredSize != body.length) {
      throw FormatException(
        'Размер файла не совпал: ожидалось $declaredSize, получено ${body.length}',
      );
    }
    final message = OpticalMessage(
      id: header['messageId']?.toString() ?? opticalRandomId(),
      senderId: header['senderId']?.toString() ?? '',
      senderName: header['senderName']?.toString() ?? 'Устройство',
      sentAt:
          DateTime.tryParse(header['sentAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      kind: kind,
      text: header['text']?.toString() ?? '',
      fileName: header['fileName']?.toString(),
      fileSize: declaredSize,
      state: 'received',
    );
    return OpticalReceivedPayload(message: message, fileBytes: body);
  }

  static Future<String> sha256Hex(List<int> bytes) async =>
      _hex((await _hash.hash(bytes)).bytes);

  static String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

class OpticalFrameAccumulator {
  final String expectedRoomId;

  String? _transferId;
  String? _expectedHash;
  int _total = 0;
  final Map<int, Uint8List> _chunks = <int, Uint8List>{};
  bool _verified = false;

  OpticalFrameAccumulator({required this.expectedRoomId});

  OpticalFrameProgress add(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _ignored();
      final frame = Map<String, dynamic>.from(decoded);
      if (frame['v'] != 1 || frame['k'] != 'data') return _ignored();
      if (frame['r']?.toString() != expectedRoomId) {
        return OpticalFrameProgress(
          accepted: false,
          complete: false,
          received: _chunks.length,
          total: _total,
          transferId: _transferId,
          error: 'Кадр относится к другой комнате',
        );
      }
      final transferId = frame['t']?.toString() ?? '';
      final index = int.tryParse(frame['i']?.toString() ?? '') ?? -1;
      final total = int.tryParse(frame['n']?.toString() ?? '') ?? 0;
      final hash = frame['h']?.toString() ?? '';
      final data = frame['d']?.toString() ?? '';
      if (transferId.isEmpty ||
          index < 0 ||
          total <= 0 ||
          index >= total ||
          hash.length != 64 ||
          data.isEmpty) {
        return _ignored();
      }
      if (_transferId == null) {
        _transferId = transferId;
        _expectedHash = hash;
        _total = total;
      }
      if (_transferId != transferId ||
          _expectedHash != hash ||
          _total != total) {
        return OpticalFrameProgress(
          accepted: false,
          complete: false,
          received: _chunks.length,
          total: _total,
          transferId: _transferId,
          error: 'Уже принимается другой пакет',
        );
      }
      _chunks.putIfAbsent(
        index,
        () => Uint8List.fromList(base64Url.decode(data)),
      );
      return OpticalFrameProgress(
        accepted: true,
        complete: _chunks.length == _total,
        received: _chunks.length,
        total: _total,
        transferId: _transferId,
      );
    } catch (_) {
      return _ignored();
    }
  }

  OpticalFrameProgress _ignored() => OpticalFrameProgress(
    accepted: false,
    complete: false,
    received: _chunks.length,
    total: _total,
    transferId: _transferId,
  );

  Future<List<int>> assembleAndVerify() async {
    if (_total <= 0 || _chunks.length != _total || _expectedHash == null) {
      throw StateError('Не все кадры получены');
    }
    final builder = BytesBuilder(copy: false);
    for (var index = 0; index < _total; index++) {
      final chunk = _chunks[index];
      if (chunk == null) throw StateError('Отсутствует кадр $index');
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final actual = await OpticalTransferCodec.sha256Hex(bytes);
    if (actual != _expectedHash) {
      throw const FormatException('Контрольная сумма не совпала');
    }
    _verified = true;
    return bytes;
  }

  bool get verified => _verified;
}
