import 'dart:convert';

import 'package:crypto/crypto.dart';

class GatewayIdentity {
  final String profileId;
  final String deviceId;
  final Set<String> allowedRooms;
  final DateTime expiresAt;

  const GatewayIdentity({
    required this.profileId,
    required this.deviceId,
    required this.allowedRooms,
    required this.expiresAt,
  });

  bool canAccess(String roomId) =>
      allowedRooms.contains('*') || allowedRooms.contains(roomId);
}

class GatewayTokenCodec {
  final List<int> _secret;

  GatewayTokenCodec(String secret) : _secret = utf8.encode(secret);

  String issue({
    required String profileId,
    required String deviceId,
    required Iterable<String> rooms,
    Duration lifetime = const Duration(hours: 12),
  }) {
    final payload = <String, dynamic>{
      'sub': profileId,
      'deviceId': deviceId,
      'rooms': rooms.toSet().toList()..sort(),
      'iat': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().toUtc().add(lifetime).millisecondsSinceEpoch ~/ 1000,
    };
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final signature = Hmac(sha256, _secret).convert(payloadBytes).bytes;
    return '${_encode(payloadBytes)}.${_encode(signature)}';
  }

  GatewayIdentity verify(String token) {
    final parts = token.split('.');
    if (parts.length != 2) {
      throw const FormatException('invalid_token_format');
    }
    final payloadBytes = _decode(parts[0]);
    final actualSignature = _decode(parts[1]);
    final expectedSignature = Hmac(sha256, _secret).convert(payloadBytes).bytes;
    if (!_constantTimeEquals(actualSignature, expectedSignature)) {
      throw const FormatException('invalid_token_signature');
    }

    final decoded = jsonDecode(utf8.decode(payloadBytes));
    if (decoded is! Map) throw const FormatException('invalid_token_payload');
    final payload = Map<String, dynamic>.from(decoded);
    final profileId = payload['sub']?.toString().trim() ?? '';
    final deviceId = payload['deviceId']?.toString().trim() ?? '';
    final exp = int.tryParse(payload['exp']?.toString() ?? '') ?? 0;
    final rooms = ((payload['rooms'] as List?) ?? const <dynamic>[])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (profileId.isEmpty || deviceId.isEmpty || rooms.isEmpty || exp <= 0) {
      throw const FormatException('incomplete_token_payload');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    if (!expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('token_expired');
    }
    return GatewayIdentity(
      profileId: profileId,
      deviceId: deviceId,
      allowedRooms: rooms,
      expiresAt: expiresAt,
    );
  }

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decode(String value) {
    final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(normalized);
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
