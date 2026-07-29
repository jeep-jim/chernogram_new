class CgRealtimeRoomCursor {
  final String roomId;
  final int lastRoomSeq;

  const CgRealtimeRoomCursor({required this.roomId, this.lastRoomSeq = 0});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'lastRoomSeq': lastRoomSeq,
  };
}

class CgGatewayEvent {
  final String packetId;
  final String roomId;
  final String kind;
  final String priority;
  final int serverSeq;
  final int roomSeq;
  final String senderProfileId;
  final String senderDeviceId;
  final DateTime createdAt;
  final bool replay;
  final Map<String, dynamic> crypto;

  const CgGatewayEvent({
    required this.packetId,
    required this.roomId,
    required this.kind,
    required this.priority,
    required this.serverSeq,
    required this.roomSeq,
    required this.senderProfileId,
    required this.senderDeviceId,
    required this.createdAt,
    required this.replay,
    required this.crypto,
  });

  factory CgGatewayEvent.fromJson(Map<String, dynamic> json) => CgGatewayEvent(
    packetId: json['packetId']?.toString() ?? '',
    roomId: json['roomId']?.toString() ?? '',
    kind: json['kind']?.toString() ?? '',
    priority: json['priority']?.toString() ?? 'normal',
    serverSeq: int.tryParse(json['serverSeq']?.toString() ?? '') ?? 0,
    roomSeq: int.tryParse(json['roomSeq']?.toString() ?? '') ?? 0,
    senderProfileId:
        json['fromProfileId']?.toString() ??
        json['senderProfileId']?.toString() ??
        '',
    senderDeviceId:
        json['fromDeviceId']?.toString() ??
        json['senderDeviceId']?.toString() ??
        '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    replay: json['replay'] == true,
    crypto: json['crypto'] is Map
        ? Map<String, dynamic>.from(json['crypto'] as Map)
        : const <String, dynamic>{},
  );
}

class CgGatewayAck {
  final String packetId;
  final String roomId;
  final int serverSeq;
  final int roomSeq;
  final String status;
  final DateTime storedAt;

  const CgGatewayAck({
    required this.packetId,
    required this.roomId,
    required this.serverSeq,
    required this.roomSeq,
    required this.status,
    required this.storedAt,
  });

  factory CgGatewayAck.fromJson(Map<String, dynamic> json) => CgGatewayAck(
    packetId: json['packetId']?.toString() ?? '',
    roomId: json['roomId']?.toString() ?? '',
    serverSeq: int.tryParse(json['serverSeq']?.toString() ?? '') ?? 0,
    roomSeq: int.tryParse(json['roomSeq']?.toString() ?? '') ?? 0,
    status: json['status']?.toString() ?? 'stored',
    storedAt:
        DateTime.tryParse(json['storedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );
}

class CgGatewayPresence {
  final String roomId;
  final int onlineProfiles;
  final int onlineDevices;
  final List<Map<String, dynamic>> members;
  final DateTime at;

  const CgGatewayPresence({
    required this.roomId,
    required this.onlineProfiles,
    required this.onlineDevices,
    required this.members,
    required this.at,
  });

  factory CgGatewayPresence.fromJson(
    Map<String, dynamic> json,
  ) => CgGatewayPresence(
    roomId: json['roomId']?.toString() ?? '',
    onlineProfiles: int.tryParse(json['onlineProfiles']?.toString() ?? '') ?? 0,
    onlineDevices: int.tryParse(json['onlineDevices']?.toString() ?? '') ?? 0,
    members: ((json['members'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false),
    at:
        DateTime.tryParse(json['at']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );
}

class CgGatewayOutboxRecord {
  final String packetId;
  final String requestId;
  final String roomId;
  final String kind;
  final String priority;
  final DateTime createdAt;
  final int ttlSeconds;
  final Map<String, dynamic> crypto;
  final int attempts;
  final DateTime nextAttemptAt;

  const CgGatewayOutboxRecord({
    required this.packetId,
    required this.requestId,
    required this.roomId,
    required this.kind,
    required this.priority,
    required this.createdAt,
    required this.ttlSeconds,
    required this.crypto,
    this.attempts = 0,
    required this.nextAttemptAt,
  });

  CgGatewayOutboxRecord copyWith({int? attempts, DateTime? nextAttemptAt}) =>
      CgGatewayOutboxRecord(
        packetId: packetId,
        requestId: requestId,
        roomId: roomId,
        kind: kind,
        priority: priority,
        createdAt: createdAt,
        ttlSeconds: ttlSeconds,
        crypto: crypto,
        attempts: attempts ?? this.attempts,
        nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'packetId': packetId,
    'requestId': requestId,
    'roomId': roomId,
    'kind': kind,
    'priority': priority,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'ttlSeconds': ttlSeconds,
    'crypto': crypto,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
  };

  factory CgGatewayOutboxRecord.fromJson(
    Map<String, dynamic> json,
  ) => CgGatewayOutboxRecord(
    packetId: json['packetId']?.toString() ?? '',
    requestId: json['requestId']?.toString() ?? '',
    roomId: json['roomId']?.toString() ?? '',
    kind: json['kind']?.toString() ?? 'message',
    priority: json['priority']?.toString() ?? 'normal',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    ttlSeconds: int.tryParse(json['ttlSeconds']?.toString() ?? '') ?? 604800,
    crypto: json['crypto'] is Map
        ? Map<String, dynamic>.from(json['crypto'] as Map)
        : const <String, dynamic>{},
    attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
    nextAttemptAt:
        DateTime.tryParse(json['nextAttemptAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );

  Map<String, dynamic> toEventFrame() => <String, dynamic>{
    'type': 'event',
    'protocol': 1,
    'requestId': requestId,
    'packetId': packetId,
    'roomId': roomId,
    'kind': kind,
    'priority': priority,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'ttlSeconds': ttlSeconds,
    'crypto': crypto,
  };
}
