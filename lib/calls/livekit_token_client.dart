import 'dart:convert';

import 'package:http/http.dart' as http;

import 'livekit_call_config.dart';

class CgLiveKitCredentials {
  final Uri serverUri;
  final String participantToken;
  final String roomName;
  final String callId;
  final bool video;
  final DateTime expiresAt;

  const CgLiveKitCredentials({
    required this.serverUri,
    required this.participantToken,
    required this.roomName,
    required this.callId,
    required this.video,
    required this.expiresAt,
  });

  factory CgLiveKitCredentials.fromJson(Map<String, dynamic> json) {
    final serverUri = Uri.parse(json['server_url']?.toString() ?? '');
    final token = json['participant_token']?.toString() ?? '';
    final roomName = json['room_name']?.toString() ?? '';
    final callId = json['call_id']?.toString() ?? '';
    if (!serverUri.hasAuthority ||
        (serverUri.scheme != 'wss' && serverUri.scheme != 'ws') ||
        token.isEmpty ||
        roomName.isEmpty ||
        callId.isEmpty) {
      throw const FormatException('Invalid LiveKit credentials response');
    }
    final expiresSeconds =
        int.tryParse(json['expires_at']?.toString() ?? '') ?? 0;
    return CgLiveKitCredentials(
      serverUri: serverUri,
      participantToken: token,
      roomName: roomName,
      callId: callId,
      video: json['video'] == true,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresSeconds * 1000,
        isUtc: true,
      ),
    );
  }
}

class CgLiveKitTokenClient {
  final CgLiveKitCallConfig config;
  final Future<String> Function() accessTokenProvider;
  final http.Client _client;

  CgLiveKitTokenClient({
    required this.config,
    required this.accessTokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<CgLiveKitCredentials> join({
    required String callTicket,
    required String profileId,
    required String displayName,
    Map<String, dynamic> participantMetadata = const <String, dynamic>{},
  }) async {
    final broker = config.brokerUri;
    if (!config.enabled || broker == null) {
      throw StateError('livekit_calls_disabled');
    }
    final accessToken = await accessTokenProvider();
    if (accessToken.trim().isEmpty) {
      throw StateError('missing_cernogram_access_token');
    }
    final uri = broker.resolve('/v1/calls/token');
    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer ${accessToken.trim()}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'call_ticket': callTicket,
            'profile_id': profileId,
            'device_id': config.deviceId,
            'display_name': displayName,
            'participant_metadata': participantMetadata,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      throw StateError(
        'calls_token_http_${response.statusCode}:'
        '${body.length <= 220 ? body : body.substring(0, 220)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Calls token response must be a JSON object');
    }
    return CgLiveKitCredentials.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<bool> test() async {
    final broker = config.brokerUri;
    if (broker == null) return false;
    try {
      final response = await _client
          .get(broker.resolve('/healthz'))
          .timeout(const Duration(seconds: 6));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
