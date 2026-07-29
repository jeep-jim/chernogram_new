import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'livekit_call_config.dart';
import 'livekit_token_client.dart';

enum CgLiveKitCallState {
  idle,
  requestingToken,
  preparing,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  disconnected,
  failed,
}

class CgLiveKitCallSnapshot {
  final CgLiveKitCallState state;
  final String? code;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool speakerEnabled;
  final int remoteParticipants;
  final DateTime at;

  const CgLiveKitCallSnapshot({
    required this.state,
    this.code,
    required this.microphoneEnabled,
    required this.cameraEnabled,
    required this.speakerEnabled,
    required this.remoteParticipants,
    required this.at,
  });
}

class CgLiveKitCallClient {
  final CgLiveKitCallConfig config;
  final CgLiveKitTokenClient tokenClient;
  final ValueNotifier<CgLiveKitCallSnapshot> snapshot =
      ValueNotifier<CgLiveKitCallSnapshot>(
    CgLiveKitCallSnapshot(
      state: CgLiveKitCallState.idle,
      microphoneEnabled: false,
      cameraEnabled: false,
      speakerEnabled: true,
      remoteParticipants: 0,
      at: DateTime.now().toUtc(),
    ),
  );

  Room? _room;
  CgLiveKitCredentials? _credentials;
  Timer? _healthTimer;
  bool _closed = false;
  bool _microphoneEnabled = false;
  bool _cameraEnabled = false;
  bool _speakerEnabled = true;

  CgLiveKitCallClient({
    required this.config,
    required this.tokenClient,
  });

  Room? get room => _room;
  CgLiveKitCredentials? get credentials => _credentials;
  bool get connected =>
      snapshot.value.state == CgLiveKitCallState.connected ||
      snapshot.value.state == CgLiveKitCallState.reconnecting;

  Future<bool> connect({
    required String callTicket,
    required String profileId,
    required String displayName,
    required bool video,
    Map<String, dynamic> participantMetadata = const <String, dynamic>{},
  }) async {
    if (_closed || !config.enabled || config.brokerUri == null) return false;
    if (connected) return true;
    _emit(CgLiveKitCallState.requestingToken);
    try {
      final credentials = await tokenClient.join(
        callTicket: callTicket,
        profileId: profileId,
        displayName: displayName,
        participantMetadata: <String, dynamic>{
          ...participantMetadata,
          'requestedVideo': video,
        },
      );
      if (_closed) return false;
      _credentials = credentials;
      _emit(CgLiveKitCallState.preparing);

      final room = Room();
      _room = room;
      room.addListener(_syncRoomState);
      final options = RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: const AudioPublishOptions(
          dtx: true,
          red: true,
        ),
        defaultVideoPublishOptions: const VideoPublishOptions(
          simulcast: true,
        ),
      );
      await room.prepareConnection(
        credentials.serverUri.toString(),
        credentials.participantToken,
      );
      if (_closed) {
        await room.dispose();
        return false;
      }
      _emit(CgLiveKitCallState.connecting);
      await room.connect(
        credentials.serverUri.toString(),
        credentials.participantToken,
        roomOptions: options,
      );
      if (_closed) {
        await room.disconnect();
        await room.dispose();
        return false;
      }
      await room.localParticipant?.setMicrophoneEnabled(true);
      _microphoneEnabled = true;
      if (video && credentials.video) {
        await room.localParticipant?.setCameraEnabled(true);
        _cameraEnabled = true;
      }
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
        _speakerEnabled = true;
      } catch (_) {
        // Desktop and some Android audio routes do not expose this switch.
      }
      _startHealthTimer();
      _emit(CgLiveKitCallState.connected);
      return true;
    } catch (error) {
      _emit(
        CgLiveKitCallState.failed,
        code: 'livekit_connect_${error.runtimeType}',
      );
      await _disposeRoom();
      return false;
    }
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      await participant.setMicrophoneEnabled(enabled);
      _microphoneEnabled = enabled;
      _syncRoomState();
    } catch (error) {
      _emit(snapshot.value.state, code: 'microphone_${error.runtimeType}');
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      await participant.setCameraEnabled(enabled);
      _cameraEnabled = enabled;
      _syncRoomState();
    } catch (error) {
      _emit(snapshot.value.state, code: 'camera_${error.runtimeType}');
    }
  }

  Future<void> setSpeakerEnabled(bool enabled) async {
    try {
      await Hardware.instance.setSpeakerphoneOn(enabled);
      _speakerEnabled = enabled;
      _syncRoomState();
    } catch (error) {
      _emit(snapshot.value.state, code: 'speaker_${error.runtimeType}');
    }
  }

  Future<void> switchCamera() async {
    final participant = _room?.localParticipant;
    if (participant == null || !_cameraEnabled) return;
    final publication = participant.videoTrackPublications
        .where((item) => !item.isScreenShare)
        .firstOrNull;
    final track = publication?.track;
    if (track is LocalVideoTrack) {
      try {
        await track.setCameraPosition(
          track.currentOptions.cameraPosition == CameraPosition.front
              ? CameraPosition.back
              : CameraPosition.front,
        );
      } catch (error) {
        _emit(snapshot.value.state, code: 'switch_camera_${error.runtimeType}');
      }
    }
  }

  Future<void> disconnect({String code = 'local_hangup'}) async {
    if (_closed && _room == null) return;
    _emit(CgLiveKitCallState.disconnecting, code: code);
    _healthTimer?.cancel();
    final room = _room;
    _room = null;
    if (room != null) {
      room.removeListener(_syncRoomState);
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
    _microphoneEnabled = false;
    _cameraEnabled = false;
    _credentials = null;
    _emit(CgLiveKitCallState.disconnected, code: code);
  }

  void _syncRoomState() {
    final room = _room;
    if (room == null) return;
    final rawState = room.connectionState.toString().toLowerCase();
    final state = rawState.contains('reconnect')
        ? CgLiveKitCallState.reconnecting
        : rawState.contains('connect')
            ? CgLiveKitCallState.connected
            : rawState.contains('disconnect')
                ? CgLiveKitCallState.disconnected
                : snapshot.value.state;
    _emit(state);
  }

  void _startHealthTimer() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_room == null) return;
      _syncRoomState();
    });
  }

  void _emit(CgLiveKitCallState state, {String? code}) {
    if (_closed && state != CgLiveKitCallState.disconnected) return;
    snapshot.value = CgLiveKitCallSnapshot(
      state: state,
      code: code,
      microphoneEnabled: _microphoneEnabled,
      cameraEnabled: _cameraEnabled,
      speakerEnabled: _speakerEnabled,
      remoteParticipants: _room?.remoteParticipants.length ?? 0,
      at: DateTime.now().toUtc(),
    );
  }

  Future<void> _disposeRoom() async {
    final room = _room;
    _room = null;
    if (room == null) return;
    room.removeListener(_syncRoomState);
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _healthTimer?.cancel();
    await _disposeRoom();
    tokenClient.close();
    snapshot.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
