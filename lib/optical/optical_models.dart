import 'dart:convert';
import 'dart:math';

String opticalRandomId([int byteCount = 12]) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

class OpticalProfile {
  final String id;
  final String nickname;

  const OpticalProfile({required this.id, required this.nickname});

  OpticalProfile copyWith({String? nickname}) => OpticalProfile(
        id: id,
        nickname: nickname ?? this.nickname,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nickname': nickname,
      };

  factory OpticalProfile.fromJson(Map<String, dynamic> json) => OpticalProfile(
        id: json['id']?.toString() ?? opticalRandomId(),
        nickname: json['nickname']?.toString() ?? 'Устройство',
      );
}

class OpticalMessage {
  final String id;
  final String senderId;
  final String senderName;
  final DateTime sentAt;
  final String kind;
  final String text;
  final String? fileName;
  final String? filePath;
  final int fileSize;
  final String state;

  const OpticalMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.sentAt,
    required this.kind,
    this.text = '',
    this.fileName,
    this.filePath,
    this.fileSize = 0,
    this.state = 'local',
  });

  bool get isFile => kind == 'file';

  OpticalMessage copyWith({
    String? filePath,
    String? state,
  }) =>
      OpticalMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        sentAt: sentAt,
        kind: kind,
        text: text,
        fileName: fileName,
        filePath: filePath ?? this.filePath,
        fileSize: fileSize,
        state: state ?? this.state,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'kind': kind,
        'text': text,
        'fileName': fileName,
        'filePath': filePath,
        'fileSize': fileSize,
        'state': state,
      };

  factory OpticalMessage.fromJson(Map<String, dynamic> json) => OpticalMessage(
        id: json['id']?.toString() ?? opticalRandomId(),
        senderId: json['senderId']?.toString() ?? '',
        senderName: json['senderName']?.toString() ?? 'Устройство',
        sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        kind: json['kind']?.toString() ?? 'text',
        text: json['text']?.toString() ?? '',
        fileName: json['fileName']?.toString(),
        filePath: json['filePath']?.toString(),
        fileSize: int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
        state: json['state']?.toString() ?? 'local',
      );
}

class OpticalRoom {
  final String id;
  final String name;
  final String secretBase64;
  final DateTime createdAt;
  final List<OpticalMessage> messages;

  const OpticalRoom({
    required this.id,
    required this.name,
    required this.secretBase64,
    required this.createdAt,
    required this.messages,
  });

  DateTime get lastActivity =>
      messages.isEmpty ? createdAt : messages.last.sentAt;

  OpticalRoom copyWith({
    String? name,
    List<OpticalMessage>? messages,
  }) =>
      OpticalRoom(
        id: id,
        name: name ?? this.name,
        secretBase64: secretBase64,
        createdAt: createdAt,
        messages: messages ?? this.messages,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'secretBase64': secretBase64,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory OpticalRoom.fromJson(Map<String, dynamic> json) => OpticalRoom(
        id: json['id']?.toString() ?? opticalRandomId(),
        name: json['name']?.toString() ?? 'Оптическая комната',
        secretBase64: json['secretBase64']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        messages: ((json['messages'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (value) => OpticalMessage.fromJson(
                Map<String, dynamic>.from(value),
              ),
            )
            .toList(),
      );
}

class OpticalReceivedPayload {
  final OpticalMessage message;
  final List<int> fileBytes;

  const OpticalReceivedPayload({
    required this.message,
    this.fileBytes = const <int>[],
  });
}
