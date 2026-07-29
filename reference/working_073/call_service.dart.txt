import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'brand.dart';
import 'core_models.dart';
import 'internet_core.dart';

class ChernogramCallScreen extends StatefulWidget {
  final String tunnelName;
  final bool video;
  final bool ru;
  final String? tunnelId;
  final String? secret;
  final String? profileId;
  final String? nickname;
  final String? callId;
  final bool isCaller;
  final String? peerName;

  const ChernogramCallScreen({
    super.key,
    required this.tunnelName,
    required this.video,
    required this.ru,
    this.tunnelId,
    this.secret,
    this.profileId,
    this.nickname,
    this.callId,
    this.isCaller = true,
    this.peerName,
  });

  @override
  State<ChernogramCallScreen> createState() => _ChernogramCallScreenState();
}

class _ChernogramCallScreenState extends State<ChernogramCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _queuedCandidates = <RTCIceCandidate>[];

  StreamSubscription<InternetEvent>? _signalSubscription;
  MediaStream? _localStream;
  RTCPeerConnection? _peer;
  InternetTunnelSession? _session;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = true;
  bool _remoteDescriptionSet = false;
  bool _offerSent = false;
  bool _ended = false;
  bool _remoteVideoReady = false;
  String _status = '';
  String? _error;

  String get _callId => widget.callId ?? CgIds.random(20);
  String get _profileId => widget.profileId ?? '';

  @override
  void initState() {
    super.initState();
    _status = widget.ru ? 'Подключаем защищённый звонок…' : 'Connecting secure call…';
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 30},
              }
            : false,
      });
      final peer = await createPeerConnection({
        'iceServers': <Map<String, dynamic>>[
          {
            'urls': <String>[
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
              'stun:openrelay.metered.ca:80',
            ],
          },
          {
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
        unawaited(_sendSignal({
          'action': 'ice',
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }));
      };
      peer.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams.first;
          if (mounted) {
            setState(() {
              _remoteVideoReady = true;
              _status = widget.ru ? 'Соединено' : 'Connected';
            });
          }
        }
      };
      peer.onConnectionState = (state) {
        if (!mounted) return;
        setState(() {
          switch (state) {
            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              _status = widget.ru ? 'Соединено' : 'Connected';
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
              _status = widget.ru ? 'Устанавливаем канал…' : 'Establishing channel…';
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
              _status = widget.ru ? 'Не удалось соединить. Повторите звонок.' : 'Connection failed. Try again.';
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
              _status = widget.ru ? 'Связь прервана…' : 'Connection interrupted…';
              break;
            default:
              break;
          }
        });
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

      final tunnelId = widget.tunnelId;
      final secret = widget.secret;
      if (tunnelId == null || secret == null || _profileId.isEmpty) {
        setState(() {
          _error = widget.ru
              ? 'Эта старая версия экрана звонка не привязана к интернет-туннелю.'
              : 'This legacy call screen is not attached to an internet tunnel.';
        });
        return;
      }
      final session = InternetRelay.session(tunnelId) ??
          await InternetRelay.open(
            tunnelId: tunnelId,
            secret: secret,
            profileId: _profileId,
            nickname: widget.nickname ?? 'user',
            history: const <Map<String, dynamic>>[],
          );
      _session = session;
      _signalSubscription = session.events.listen(_onRelayEvent);

      if (widget.isCaller) {
        await _sendSignal({
          'action': 'call_invite',
          'video': widget.video,
          'fromName': widget.nickname,
        });
        if (mounted) {
          setState(() {
            _status = widget.ru ? 'Звоним…' : 'Calling…';
          });
        }
      } else {
        await _sendSignal({
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
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = widget.ru ? 'Ошибка звонка' : 'Call error';
        });
      }
    }
  }

  void _onRelayEvent(InternetEvent event) {
    if (event.type != 'signal') return;
    final data = event.data;
    if (data['callId']?.toString() != _callId) return;
    final target = data['target']?.toString();
    if (target != null && target.isNotEmpty && target != _profileId) return;
    final action = data['action']?.toString() ?? '';
    switch (action) {
      case 'call_accept':
      case 'call_ready':
        if (widget.isCaller) unawaited(_makeOffer());
        break;
      case 'call_decline':
        if (mounted) {
          setState(() {
            _status = widget.ru ? 'Звонок отклонён' : 'Call declined';
          });
          Future<void>.delayed(const Duration(milliseconds: 850), () {
            if (mounted) Navigator.pop(context);
          });
        }
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
        if (mounted) {
          setState(() {
            _status = widget.ru ? 'Звонок завершён' : 'Call ended';
          });
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.pop(context);
          });
        }
        break;
    }
  }

  Future<void> _makeOffer() async {
    if (_offerSent || _peer == null) return;
    _offerSent = true;
    final offer = await _peer!.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
    });
    await _peer!.setLocalDescription(offer);
    await _sendSignal({
      'action': 'offer',
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    final peer = _peer;
    final sdp = data['sdp']?.toString();
    if (peer == null || sdp == null || sdp.isEmpty) return;
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
    await _sendSignal({
      'action': 'answer',
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final peer = _peer;
    final sdp = data['sdp']?.toString();
    if (peer == null || sdp == null || sdp.isEmpty) return;
    await peer.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'answer'),
    );
    _remoteDescriptionSet = true;
    await _flushQueuedCandidates();
  }

  Future<void> _handleIce(Map<String, dynamic> data) async {
    final candidateValue = data['candidate']?.toString();
    if (candidateValue == null || candidateValue.isEmpty) return;
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
    await session.sendSignal({
      ...data,
      'callId': _callId,
      'from': _profileId,
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
    if (_ended) return;
    _ended = true;
    await _sendSignal({'action': 'call_end'});
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ended = true;
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
                    colors: [Color(0xFF283061), Color(0xFF050711)],
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
                    _CallButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      active: _muted,
                      onTap: _toggleMute,
                    ),
                    _CallButton(
                      icon: _speaker ? Icons.volume_up : Icons.hearing,
                      active: _speaker,
                      onTap: _toggleSpeaker,
                    ),
                    if (widget.video)
                      _CallButton(
                        icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                        active: _cameraOff,
                        onTap: _toggleCamera,
                      ),
                    if (widget.video)
                      _CallButton(
                        icon: Icons.cameraswitch,
                        onTap: _switchCamera,
                      ),
                    _CallButton(
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
                child: GlassPanel(
                  color: const Color(0xCC4B1020),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final FutureOr<void> Function() onTap;
  final bool active;
  final bool danger;

  const _CallButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: danger
            ? ChernogramColors.danger
            : active
                ? Colors.white
                : Colors.white.withValues(alpha: .12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onTap(),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              icon,
              color: active ? const Color(0xFF111725) : Colors.white,
            ),
          ),
        ),
      );
}
