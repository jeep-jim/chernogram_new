import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'brand.dart';
import 'core_models.dart';
import 'internet_core_v08.dart';

class CgCallResult {
  final String status;
  final int durationSeconds;

  const CgCallResult({
    required this.status,
    required this.durationSeconds,
  });
}

class ChernogramCallScreenV08 extends StatefulWidget {
  final String tunnelName;
  final bool video;
  final bool ru;
  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;
  final String callId;
  final bool isCaller;
  final String? peerName;

  const ChernogramCallScreenV08({
    super.key,
    required this.tunnelName,
    required this.video,
    required this.ru,
    required this.tunnelId,
    required this.secret,
    required this.profileId,
    required this.nickname,
    required this.callId,
    required this.isCaller,
    this.peerName,
  });

  @override
  State<ChernogramCallScreenV08> createState() =>
      _ChernogramCallScreenV08State();
}

class _ChernogramCallScreenV08State
    extends State<ChernogramCallScreenV08> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _queuedCandidates = <RTCIceCandidate>[];

  StreamSubscription<InternetEventV08>? _signalSubscription;
  MediaStream? _localStream;
  RTCPeerConnection? _peer;
  InternetTunnelSessionV08? _session;
  Timer? _ringTimer;
  DateTime? _connectedAt;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = true;
  bool _remoteDescriptionSet = false;
  bool _offerSent = false;
  bool _finished = false;
  bool _remoteVideoReady = false;
  bool _accepted = false;
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.ru
        ? 'Подключаем защищённый звонок…'
        : 'Connecting secure call…';
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': widget.video
            ? <String, dynamic>{
                'facingMode': 'user',
                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
                'frameRate': <String, dynamic>{'ideal': 30},
              }
            : false,
      });
      final peer = await createPeerConnection(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[
          <String, dynamic>{
            'urls': <String>[
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
              'stun:openrelay.metered.ca:80',
            ],
          },
          <String, dynamic>{
            'urls': <String>[
              'turn:openrelay.metered.ca:80',
              'turn:openrelay.metered.ca:443',
              'turn:openrelay.metered.ca:443?transport=tcp',
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
      });

      peer.onIceCandidate = (candidate) {
        final value = candidate.candidate;
        if (value == null || value.isEmpty) return;
        unawaited(_sendSignal(<String, dynamic>{
          'action': 'ice',
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }));
      };
      peer.onTrack = (event) {
        if (event.streams.isEmpty) return;
        _remoteRenderer.srcObject = event.streams.first;
        if (!mounted) return;
        setState(() {
          _remoteVideoReady = true;
          _status = widget.ru ? 'Соединено' : 'Connected';
        });
      };
      peer.onConnectionState = (state) {
        if (!mounted || _finished) return;
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _connectedAt ??= DateTime.now();
            _ringTimer?.cancel();
            setState(() => _status = widget.ru ? 'Соединено' : 'Connected');
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
            setState(() {
              _status = widget.ru
                  ? 'Устанавливаем канал…'
                  : 'Establishing channel…';
            });
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            setState(() {
              _status = widget.ru
                  ? 'Не удалось соединить'
                  : 'Connection failed';
            });
            unawaited(_finish('failed', notifyPeer: true, delay: 700));
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            setState(() {
              _status = widget.ru ? 'Связь прервана…' : 'Connection interrupted…';
            });
            break;
          default:
            break;
        }
      };
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }

      if (!mounted) {
        await peer.close();
        await stream.dispose();
        return;
      }
      setState(() {
        _peer = peer;
        _localStream = stream;
        _localRenderer.srcObject = stream;
      });

      final session = InternetRelayV08.session(widget.tunnelId) ??
          await InternetRelayV08.open(
            tunnelId: widget.tunnelId,
            secret: widget.secret,
            profileId: widget.profileId,
            nickname: widget.nickname,
            history: const <Map<String, dynamic>>[],
          );
      _session = session;
      _signalSubscription = session.events.listen(_onRelayEvent);
      unawaited(session.connect());

      if (widget.isCaller) {
        await _sendSignal(<String, dynamic>{
          'action': 'call_invite',
          'video': widget.video,
          'fromName': widget.nickname,
        });
        if (mounted) setState(() => _status = widget.ru ? 'Звоним…' : 'Calling…');
        _ringTimer = Timer(const Duration(seconds: 35), () {
          if (!_accepted && _connectedAt == null) {
            unawaited(_finish('missed', notifyPeer: true));
          }
        });
      } else {
        _accepted = true;
        await _sendSignal(<String, dynamic>{
          'action': 'call_ready',
          'video': widget.video,
          'fromName': widget.nickname,
        });
        if (mounted) {
          setState(() {
            _status = widget.ru ? 'Принимаем звонок…' : 'Answering…';
          });
        }
      }
    } catch (error) {
      if (!mounted || _finished) return;
      setState(() {
        _error = error.toString();
        _status = widget.ru ? 'Ошибка звонка' : 'Call error';
      });
      unawaited(_finish('failed', notifyPeer: true, delay: 900));
    }
  }

  void _onRelayEvent(InternetEventV08 event) {
    if (event.type != 'signal' || _finished) return;
    final data = event.data;
    if (data['callId']?.toString() != widget.callId) return;
    final target = data['target']?.toString();
    if (target != null && target.isNotEmpty && target != widget.profileId) {
      return;
    }
    final action = data['action']?.toString() ?? '';
    switch (action) {
      case 'call_accept':
      case 'call_ready':
        _accepted = true;
        _ringTimer?.cancel();
        if (widget.isCaller) unawaited(_makeOffer());
        break;
      case 'call_decline':
        if (mounted) {
          setState(() {
            _status = widget.ru ? 'Звонок отклонён' : 'Call declined';
          });
        }
        unawaited(_finish('declined', delay: 650));
        break;
      case 'offer':
        unawaited(_handleOffer(data));
        break;
      case 'answer':
        unawaited(_handleAnswer(data));
        break;
      case 'ice':
        unawaited(_handleIce(data));
        break;
      case 'call_end':
        final result = _connectedAt == null ? 'missed' : 'completed';
        if (mounted) {
          setState(() {
            _status = widget.ru ? 'Звонок завершён' : 'Call ended';
          });
        }
        unawaited(_finish(result, delay: 350));
        break;
    }
  }

  Future<void> _makeOffer() async {
    if (_offerSent || _peer == null || _finished) return;
    _offerSent = true;
    final offer = await _peer!.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
    });
    await _peer!.setLocalDescription(offer);
    await _sendSignal(<String, dynamic>{
      'action': 'offer',
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    final peer = _peer;
    final sdp = data['sdp']?.toString();
    if (peer == null || sdp == null || sdp.isEmpty || _finished) return;
    await peer.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'offer'),
    );
    _remoteDescriptionSet = true;
    await _flushQueuedCandidates();
    final answer = await peer.createAnswer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
    });
    await peer.setLocalDescription(answer);
    await _sendSignal(<String, dynamic>{
      'action': 'answer',
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final peer = _peer;
    final sdp = data['sdp']?.toString();
    if (peer == null || sdp == null || sdp.isEmpty || _finished) return;
    await peer.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'answer'),
    );
    _remoteDescriptionSet = true;
    await _flushQueuedCandidates();
  }

  Future<void> _handleIce(Map<String, dynamic> data) async {
    final candidateValue = data['candidate']?.toString();
    if (candidateValue == null || candidateValue.isEmpty || _finished) return;
    final candidate = RTCIceCandidate(
      candidateValue,
      data['sdpMid']?.toString(),
      int.tryParse(data['sdpMLineIndex']?.toString() ?? ''),
    );
    if (!_remoteDescriptionSet || _peer == null) {
      _queuedCandidates.add(candidate);
      return;
    }
    await _peer!.addCandidate(candidate);
  }

  Future<void> _flushQueuedCandidates() async {
    final peer = _peer;
    if (peer == null) return;
    for (final candidate in _queuedCandidates.toList()) {
      await peer.addCandidate(candidate);
    }
    _queuedCandidates.clear();
  }

  Future<void> _sendSignal(Map<String, dynamic> data) async {
    final session = _session;
    if (session == null) return;
    await session.sendSignal(<String, dynamic>{
      ...data,
      'callId': widget.callId,
      'from': widget.profileId,
      'video': widget.video,
    });
  }

  void _toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    setState(() {
      _muted = !_muted;
      for (final track in tracks) {
        track.enabled = !_muted;
      }
    });
  }

  void _toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    setState(() {
      _cameraOff = !_cameraOff;
      for (final track in tracks) {
        track.enabled = !_cameraOff;
      }
    });
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> _toggleSpeaker() async {
    _speaker = !_speaker;
    await Helper.setSpeakerphoneOn(_speaker);
    if (mounted) setState(() {});
  }

  Future<void> _hangUp() async {
    final result = _connectedAt == null ? 'cancelled' : 'completed';
    await _finish(result, notifyPeer: true);
  }

  int get _durationSeconds {
    final connected = _connectedAt;
    if (connected == null) return 0;
    return DateTime.now().difference(connected).inSeconds.clamp(0, 86400);
  }

  Future<void> _finish(
    String status, {
    bool notifyPeer = false,
    int delay = 0,
  }) async {
    if (_finished) return;
    _finished = true;
    _ringTimer?.cancel();
    if (notifyPeer) {
      await _sendSignal(<String, dynamic>{'action': 'call_end'});
    }
    if (delay > 0) {
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      CgCallResult(status: status, durationSeconds: _durationSeconds),
    );
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    unawaited(_signalSubscription?.cancel());
    unawaited(_peer?.close());
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    unawaited(_localStream?.dispose());
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    unawaited(_localRenderer.dispose());
    unawaited(_remoteRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteLabel = widget.peerName?.trim().isNotEmpty == true
        ? widget.peerName!
        : widget.tunnelName;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_hangUp());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050711),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.video && _remoteVideoReady)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -.2),
                    radius: 1.1,
                    colors: <Color>[Color(0xFF283061), Color(0xFF050711)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ChernogramLogo(size: 112, withPlate: true),
                      const SizedBox(height: 22),
                      Text(
                        remoteLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.video && _localStream != null)
              Positioned(
                right: 16,
                top: MediaQuery.paddingOf(context).top + 16,
                width: 112,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              child: GlassPanel(
                color: const Color(0xAA111725),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CallButtonV08(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      active: _muted,
                      onTap: _toggleMute,
                    ),
                    _CallButtonV08(
                      icon: _speaker ? Icons.volume_up : Icons.hearing,
                      active: _speaker,
                      onTap: _toggleSpeaker,
                    ),
                    if (widget.video)
                      _CallButtonV08(
                        icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                        active: _cameraOff,
                        onTap: _toggleCamera,
                      ),
                    if (widget.video)
                      _CallButtonV08(
                        icon: Icons.cameraswitch,
                        onTap: _switchCamera,
                      ),
                    _CallButtonV08(
                      icon: Icons.call_end,
                      danger: true,
                      onTap: _hangUp,
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Positioned(
                left: 18,
                right: 18,
                top: MediaQuery.paddingOf(context).top + 20,
                child: Material(
                  color: ChernogramColors.danger.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.ru
                          ? 'Не удалось запустить камеру или микрофон.'
                          : 'Camera or microphone could not be started.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallButtonV08 extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool danger;
  final FutureOr<void> Function() onTap;

  const _CallButtonV08({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: danger
              ? ChernogramColors.danger
              : active
                  ? ChernogramColors.orange
                  : Colors.white12,
          foregroundColor: Colors.white,
          minimumSize: const Size(50, 50),
        ),
        onPressed: () => onTap(),
        icon: Icon(icon),
      );
}
