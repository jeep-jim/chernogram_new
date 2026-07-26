import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Основа бесплатных аудио- и видеозвонков Чернограма.
///
/// WebRTC не требует платного API. Для связи между разными сетями позже
/// подключается собственная сигнализация и open-source STUN/TURN (coturn).
class ChernogramCallScreen extends StatefulWidget {
  final String tunnelName;
  final bool video;
  final bool ru;

  const ChernogramCallScreen({
    super.key,
    required this.tunnelName,
    required this.video,
    required this.ru,
  });

  @override
  State<ChernogramCallScreen> createState() => _ChernogramCallScreenState();
}

class _ChernogramCallScreenState extends State<ChernogramCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _peer;
  bool _muted = false;
  bool _cameraOff = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _localRenderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      final peer = await createPeerConnection({
        // В локальной сети WebRTC может договориться напрямую. Интернет-маршрут
        // будет добавлен после подключения собственной сигнализации/coturn.
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      });
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
      if (!mounted) {
        await stream.dispose();
        await peer.close();
        return;
      }
      setState(() {
        _localStream = stream;
        _peer = peer;
        _localRenderer.srcObject = stream;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    setState(() {
      _muted = !_muted;
      for (final track in tracks) {
        track.enabled = !_muted;
      }
    });
  }

  void _toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    setState(() {
      _cameraOff = !_cameraOff;
      for (final track in tracks) {
        track.enabled = !_cameraOff;
      }
    });
  }

  @override
  void dispose() {
    unawaited(_peer?.close());
    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    unawaited(_localStream?.dispose());
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ru = widget.ru;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.tunnelName),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          ru
                              ? 'Не удалось открыть камеру или микрофон. Проверьте разрешения.\n\n$_error'
                              : 'Could not open camera or microphone. Check permissions.\n\n$_error',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : widget.video
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 58,
                            child: Icon(Icons.graphic_eq_rounded, size: 58),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            ru ? 'Аудиозвонок' : 'Audio call',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                ru
                    ? 'Камера и микрофон уже работают через WebRTC. Соединение с собеседником включится после сетевого слоя туннелей.'
                    : 'Camera and microphone already run through WebRTC. Peer connection will activate with the tunnel network layer.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.filledTonal(
                    onPressed: _toggleMute,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                  ),
                  if (widget.video)
                    IconButton.filledTonal(
                      onPressed: _toggleCamera,
                      icon: Icon(_cameraOff ? Icons.videocam_off : Icons.videocam),
                    ),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
