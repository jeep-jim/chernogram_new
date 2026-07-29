import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'brand.dart';
import 'core_models.dart';
import 'internet_core.dart';

class CgCallOutcome {
  final String status;
  final int durationSeconds;
  final bool connected;
  final bool video;

  const CgCallOutcome({
    required this.status,
    required this.durationSeconds,
    required this.connected,
    required this.video,
  });
}

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
  final String? peerId;
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
    this.peerId,
    this.peerName,
  });

  @override
  State<ChernogramCallScreen> createState() => _ChernogramCallScreenState();
}

class _ChernogramCallScreenState extends State<ChernogramCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _queuedRemoteCandidates = <RTCIceCandidate>[];
  final List<Map<String, dynamic>> _queuedLocalCandidates =
      <Map<String, dynamic>>[];

  StreamSubscription<InternetEvent>? _signalSubscription;
  MediaStream? _localStream;
  RTCPeerConnection? _peer;
  InternetTunnelSession? _session;
  Timer? _durationTimer;
  Timer? _inviteTimer;
  Timer? _readyTimer;
  Timer? _offerTimer;
  Timer? _watchdog;
  RTCSessionDescription? _localOffer;
  RTCSessionDescription? _localAnswer;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = true;
  bool _remoteDescriptionSet = false;
  bool _ended = false;
  bool _remoteVideoReady = false;
  bool _preparing = true;
  String _status = '';
  String? _error;
  DateTime? _connectedAt;
  int _elapsedSeconds = 0;
  late final String _resolvedCallId;
  String? _peerId;

  String get _callId => _resolvedCallId;
  String get _profileId => widget.profileId ?? '';

  @override
  void initState() {
    super.initState();
    _resolvedCallId = widget.callId ?? CgIds.random(20);
    _peerId = widget.peerId;
    _status = widget.ru
        ? 'Подключаем защищённый звонок…'
        : 'Connecting secure call…';
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      final tunnelId = widget.tunnelId;
      final secret = widget.secret;
      if (tunnelId == null || secret == null || _profileId.isEmpty) {
        throw StateError(
          widget.ru
              ? 'Звонок не привязан к интернет-туннелю.'
              : 'This call is not attached to an internet tunnel.',
        );
      }

      final session =
          InternetRelay.session(tunnelId) ??
          await InternetRelay.open(
            tunnelId: tunnelId,
            secret: secret,
            profileId: _profileId,
            nickname: widget.nickname ?? 'user',
            history: const <Map<String, dynamic>>[],
          );
      _session = session;
      _signalSubscription = session.events.listen(_onRelayEvent);

      final stream = await navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'channelCount': 1,
          },
          'video': widget.video
              ? <String, dynamic>{
                  'facingMode': 'user',
                  'width': <String, dynamic>{'ideal': 640},
                  'height': <String, dynamic>{'ideal': 480},
                  'frameRate': <String, dynamic>{'ideal': 24, 'max': 24},
                }
              : false,
        },
      ).timeout(const Duration(seconds: 9));

      final peer = await createPeerConnection(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[
          <String, dynamic>{
            'urls': <String>[
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
              'stun:stun.cloudflare.com:3478',
              'stun:openrelay.metered.ca:80',
            ],
          },
          <String, dynamic>{
            'urls': <String>[
              'turn:openrelay.metered.ca:80',
              'turn:openrelay.metered.ca:80?transport=tcp',
              'turn:openrelay.metered.ca:443',
              'turn:openrelay.metered.ca:443?transport=tcp',
              'turns:openrelay.metered.ca:443?transport=tcp',
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceTransportPolicy': 'all',
      });

      peer.onIceCandidate = (candidate) {
        final value = candidate.candidate;
        if (value == null || value.isEmpty) return;
        final signal = <String, dynamic>{
          'action': 'ice',
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        };
        if (_peerId == null || _peerId!.isEmpty) {
          _queuedLocalCandidates.add(signal);
        } else {
          unawaited(_sendSignal(signal));
        }
      };
      peer.onTrack = (event) {
        if (event.streams.isEmpty) return;
        _remoteRenderer.srcObject = event.streams.first;
        if (mounted) {
          setState(() {
            _remoteVideoReady = true;
            _markConnected();
          });
        }
      };
      peer.onConnectionState = (state) {
        if (!mounted || _ended) return;
        setState(() {
          switch (state) {
            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              _markConnected();
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
              _status = widget.ru
                  ? 'Устанавливаем прямой канал…'
                  : 'Establishing direct channel…';
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
              _status = widget.ru
                  ? 'Перезапускаем соединение…'
                  : 'Restarting connection…';
              unawaited(_recoverConnection());
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
              _status = widget.ru
                  ? 'Восстанавливаем связь…'
                  : 'Restoring connection…';
              unawaited(_recoverConnection());
              break;
            default:
              break;
          }
        });
      };

      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
      await Helper.setSpeakerphoneOn(true).timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );

      if (!mounted) {
        await peer.close();
        await stream.dispose();
        return;
      }
      setState(() {
        _peer = peer;
        _localStream = stream;
        _localRenderer.srcObject = stream;
        _preparing = false;
      });

      for (final signal in session.replaySignals(_callId)) {
        _handleSignal(signal);
      }

      if (widget.isCaller) {
        await _sendInvite();
        _inviteTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (_connectedAt == null && _peerId == null && !_ended) {
            unawaited(_sendInvite());
          }
        });
        if (mounted)
          setState(() => _status = widget.ru ? 'Звоним…' : 'Calling…');
      } else {
        await _sendReady();
        _readyTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (!_remoteDescriptionSet && !_ended) unawaited(_sendReady());
        });
        if (mounted) {
          setState(
            () => _status = widget.ru ? 'Принимаем звонок…' : 'Answering…',
          );
        }
      }

      _watchdog = Timer.periodic(const Duration(seconds: 12), (_) {
        if (_ended || _connectedAt != null) return;
        if (widget.isCaller && _peerId != null) {
          unawaited(_makeOffer(iceRestart: _localOffer != null));
        } else if (!widget.isCaller) {
          unawaited(_sendReady());
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _error = error.toString();
          _status = widget.ru ? 'Ошибка звонка' : 'Call error';
        });
      }
    }
  }

  Future<void> _sendInvite() => _sendSignal(<String, dynamic>{
    'action': 'call_invite',
    'video': widget.video,
    'fromName': widget.nickname,
  });

  Future<void> _sendReady() => _sendSignal(<String, dynamic>{
    'action': 'call_ready',
    'video': widget.video,
    'fromName': widget.nickname,
  });

  void _onRelayEvent(InternetEvent event) {
    if (event.type != 'signal') return;
    _handleSignal(event.data);
  }

  void _handleSignal(Map<String, dynamic> data) {
    if (data['callId']?.toString() != _callId) return;
    final target = data['target']?.toString();
    if (target != null && target.isNotEmpty && target != _profileId) return;
    final sender =
        data['from']?.toString() ?? data['relaySender']?.toString() ?? '';
    if (sender.isEmpty || sender == _profileId) return;
    if (_peerId != null && _peerId!.isNotEmpty && _peerId != sender) return;
    _adoptPeer(sender);
    final action = data['action']?.toString() ?? '';
    switch (action) {
      case 'call_accept':
      case 'call_ready':
        if (widget.isCaller) unawaited(_makeOffer());
        break;
      case 'call_decline':
        if (mounted) {
          setState(
            () => _status = widget.ru ? 'Звонок отклонён' : 'Call declined',
          );
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _finish('declined');
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
          setState(
            () => _status = widget.ru ? 'Звонок завершён' : 'Call ended',
          );
          Future<void>.delayed(const Duration(milliseconds: 250), () {
            if (mounted) _finish(_connectedAt == null ? 'missed' : 'completed');
          });
        }
        break;
    }
  }

  void _adoptPeer(String sender) {
    if (_peerId != null && _peerId!.isNotEmpty && _peerId != sender) return;
    if (_peerId == sender) return;
    _peerId = sender;
    _inviteTimer?.cancel();
    final queued = List<Map<String, dynamic>>.from(_queuedLocalCandidates);
    _queuedLocalCandidates.clear();
    for (final candidate in queued) {
      unawaited(_sendSignal(candidate));
    }
  }

  Future<void> _makeOffer({bool iceRestart = false}) async {
    final peer = _peer;
    if (peer == null || _peerId == null || _ended) return;
    try {
      final offer = await peer.createOffer(<String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
        'iceRestart': iceRestart,
      });
      await peer.setLocalDescription(offer);
      _localOffer = offer;
      await _sendOffer(offer);
      _offerTimer ??= Timer.periodic(const Duration(milliseconds: 2500), (_) {
        final cached = _localOffer;
        if (_connectedAt == null && cached != null && !_ended) {
          unawaited(_sendOffer(cached));
        }
      });
      if (mounted) {
        setState(
          () => _status = widget.ru
              ? 'Согласовываем защищённый канал…'
              : 'Negotiating secure channel…',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = widget.ru
              ? 'Повторяем подключение…'
              : 'Retrying connection…',
        );
      }
    }
  }

  Future<void> _sendOffer(RTCSessionDescription offer) =>
      _sendSignal(<String, dynamic>{
        'action': 'offer',
        'sdp': offer.sdp,
        'sdpType': offer.type,
      });

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    final peer = _peer;
    final sdp = data['sdp']?.toString();
    if (peer == null || sdp == null || sdp.isEmpty || _ended) return;
    try {
      final current = await peer.getRemoteDescription();
      if (current?.sdp != sdp) {
        await peer.setRemoteDescription(
          RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'offer'),
        );
        _remoteDescriptionSet = true;
        await _flushQueuedRemoteCandidates();
      }
      var answer = _localAnswer;
      if (answer == null || current?.sdp != sdp) {
        answer = await peer.createAnswer(<String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': widget.video,
        });
        await peer.setLocalDescription(answer);
        _localAnswer = answer;
      }
      _readyTimer?.cancel();
      await _sendSignal(<String, dynamic>{
        'action': 'answer',
        'sdp': answer.sdp,
        'sdpType': answer.type,
      });
    } catch (_) {
      await _sendReady();
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final peer = _peer;
    final sdp = data['sdp']?.toString();
    if (peer == null || sdp == null || sdp.isEmpty || _ended) return;
    try {
      final current = await peer.getRemoteDescription();
      if (current?.sdp == sdp) return;
      await peer.setRemoteDescription(
        RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'answer'),
      );
      _remoteDescriptionSet = true;
      _offerTimer?.cancel();
      await _flushQueuedRemoteCandidates();
    } catch (_) {}
  }

  Future<void> _handleIce(Map<String, dynamic> data) async {
    final candidateValue = data['candidate']?.toString();
    if (candidateValue == null || candidateValue.isEmpty || _ended) return;
    final candidate = RTCIceCandidate(
      candidateValue,
      data['sdpMid']?.toString(),
      int.tryParse(data['sdpMLineIndex']?.toString() ?? ''),
    );
    if (!_remoteDescriptionSet || _peer == null) {
      _queuedRemoteCandidates.add(candidate);
      return;
    }
    try {
      await _peer!.addCandidate(candidate);
    } catch (_) {
      _queuedRemoteCandidates.add(candidate);
    }
  }

  Future<void> _flushQueuedRemoteCandidates() async {
    final peer = _peer;
    if (peer == null) return;
    for (final candidate in _queuedRemoteCandidates.toList()) {
      try {
        await peer.addCandidate(candidate);
        _queuedRemoteCandidates.remove(candidate);
      } catch (_) {}
    }
  }

  Future<void> _recoverConnection() async {
    if (_ended || _connectedAt == null && _peerId == null) return;
    if (widget.isCaller) {
      await _makeOffer(iceRestart: true);
    } else {
      await _sendReady();
    }
  }

  Future<void> _sendSignal(Map<String, dynamic> data) async {
    final session = _session;
    if (session == null || _ended) return;
    await session
        .sendSignal(<String, dynamic>{
          ...data,
          'callId': _callId,
          'from': _profileId,
          'video': widget.video,
          if (_peerId != null && _peerId!.isNotEmpty) 'target': _peerId,
        })
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  void _markConnected() {
    _connectedAt ??= DateTime.now();
    _inviteTimer?.cancel();
    _readyTimer?.cancel();
    _offerTimer?.cancel();
    _status = widget.ru ? 'Соединено' : 'Connected';
    _durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() {
        _elapsedSeconds = DateTime.now().difference(_connectedAt!).inSeconds;
      });
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
    unawaited(_sendSignal(<String, dynamic>{'action': 'call_end'}));
    _finish(_connectedAt == null ? 'cancelled' : 'completed');
  }

  void _finish(String status) {
    if (_ended || !mounted) return;
    _ended = true;
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;
    Navigator.pop(
      context,
      CgCallOutcome(
        status: status,
        durationSeconds: duration,
        connected: _connectedAt != null,
        video: widget.video,
      ),
    );
  }

  String get _durationLabel {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _ended = true;
    _durationTimer?.cancel();
    _inviteTimer?.cancel();
    _readyTimer?.cancel();
    _offerTimer?.cancel();
    _watchdog?.cancel();
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
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_connectedAt != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          _durationLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                      if (!_preparing && _connectedAt == null) ...[
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: _recoverConnection,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            widget.ru
                                ? 'Повторить соединение'
                                : 'Retry connection',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (widget.video && _localStream != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 18,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 112,
                    height: 158,
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
              bottom: 30 + MediaQuery.paddingOf(context).bottom,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallControl(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    active: !_muted,
                    onPressed: _toggleMute,
                  ),
                  if (widget.video)
                    _CallControl(
                      icon: _cameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      active: !_cameraOff,
                      onPressed: _toggleCamera,
                    ),
                  if (widget.video)
                    _CallControl(
                      icon: Icons.cameraswitch_rounded,
                      active: true,
                      onPressed: _switchCamera,
                    ),
                  _CallControl(
                    icon: _speaker
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    active: _speaker,
                    onPressed: _toggleSpeaker,
                  ),
                  _CallControl(
                    icon: Icons.call_end_rounded,
                    active: false,
                    danger: true,
                    onPressed: _hangUp,
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

class _CallControl extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool danger;
  final FutureOr<void> Function() onPressed;

  const _CallControl({
    required this.icon,
    required this.active,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => IconButton.filled(
    style: IconButton.styleFrom(
      backgroundColor: danger
          ? ChernogramColors.danger
          : active
          ? Colors.white
          : Colors.white24,
      foregroundColor: danger
          ? Colors.white
          : active
          ? const Color(0xFF10142A)
          : Colors.white,
      minimumSize: const Size(54, 54),
    ),
    onPressed: () => onPressed(),
    icon: Icon(icon),
  );
}
