import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'brand.dart';
import 'call_service.dart';
import 'core_models.dart';
import 'internet_core.dart';

class ChernogramGroupCallScreen extends StatefulWidget {
  final String tunnelName;
  final String tunnelId;
  final String secret;
  final String profileId;
  final String nickname;
  final String callId;
  final bool isHost;
  final bool video;
  final bool ru;
  final String? myAvatarBase64;

  const ChernogramGroupCallScreen({
    super.key,
    required this.tunnelName,
    required this.tunnelId,
    required this.secret,
    required this.profileId,
    required this.nickname,
    required this.callId,
    required this.isHost,
    required this.video,
    required this.ru,
    this.myAvatarBase64,
  });

  @override
  State<ChernogramGroupCallScreen> createState() =>
      _ChernogramGroupCallScreenState();
}

class _GroupPeer {
  final String id;
  String name;
  final RTCPeerConnection connection;
  final RTCVideoRenderer renderer;
  final List<RTCIceCandidate> queuedCandidates = <RTCIceCandidate>[];
  bool remoteDescriptionSet = false;
  bool offerSent = false;
  bool connected = false;
  bool recovering = false;
  DateTime lastSeenAt = DateTime.now();
  DateTime lastOfferAt = DateTime.fromMillisecondsSinceEpoch(0);
  RTCSessionDescription? localOffer;
  RTCSessionDescription? localAnswer;
  final Set<String> seenCandidates = <String>{};

  _GroupPeer({
    required this.id,
    required this.name,
    required this.connection,
    required this.renderer,
  });

  Future<void> dispose() async {
    renderer.srcObject = null;
    await connection.close();
    await renderer.dispose();
  }
}

class _ChernogramGroupCallScreenState
    extends State<ChernogramGroupCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, _GroupPeer> _peers = <String, _GroupPeer>{};

  InternetTunnelSession? _session;
  StreamSubscription<InternetEvent>? _subscription;
  MediaStream? _localStream;
  Timer? _durationTimer;
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;
  DateTime? _connectedAt;
  int _elapsedSeconds = 0;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = true;
  bool _ended = false;
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.ru
        ? 'Подключаем групповую комнату…'
        : 'Connecting group room…';
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await _localRenderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googEchoCancellation2': true,
          'googNoiseSuppression': true,
          'googNoiseSuppression2': true,
          'googAutoGainControl': true,
          'googHighpassFilter': true,
          'channelCount': 1,
          'sampleRate': 48000,
        },
        'video': widget.video
            ? <String, dynamic>{
                'facingMode': 'user',
                'width': <String, dynamic>{'ideal': 640, 'max': 960},
                'height': <String, dynamic>{'ideal': 360, 'max': 540},
                'frameRate': <String, dynamic>{'ideal': 20, 'max': 24},
              }
            : false,
      });
      _localRenderer.srcObject = stream;
      _localStream = stream;

      final session = InternetRelay.session(widget.tunnelId) ??
          await InternetRelay.open(
            tunnelId: widget.tunnelId,
            secret: widget.secret,
            profileId: widget.profileId,
            nickname: widget.nickname,
            history: const <Map<String, dynamic>>[],
          );
      _session = session;
      _subscription = session.events.listen(_onRelayEvent);
      for (final signal in session.replaySignals(widget.callId)) {
        _onRelayEvent(InternetEvent('signal', signal));
      }

      if (widget.isHost) {
        await _send({
          'action': 'group_call_invite',
          'fromName': widget.nickname,
          'avatarBase64': widget.myAvatarBase64,
          'video': widget.video,
          'maxParticipants': 6,
        });
      }
      await _send({
        'action': 'group_join',
        'fromName': widget.nickname,
        'video': widget.video,
      });
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (_ended) return;
        unawaited(_send({
          'action': 'group_join',
          'fromName': widget.nickname,
          'video': widget.video,
        }));
      });
      _recoveryTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!_ended) unawaited(_recoverPeers());
      });

      if (mounted) {
        setState(() {
          _status = widget.ru
              ? 'Ожидаем участников…'
              : 'Waiting for participants…';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = widget.ru ? 'Ошибка группового звонка' : 'Group call error';
        });
      }
    }
  }

  void _onRelayEvent(InternetEvent event) {
    if (event.type != 'signal') return;
    final data = event.data;
    if (data['callId']?.toString() != widget.callId) return;
    final target = data['target']?.toString();
    if (target != null &&
        target.isNotEmpty &&
        target != widget.profileId) {
      return;
    }
    final remoteId =
        data['from']?.toString() ?? data['relaySender']?.toString() ?? '';
    if (remoteId.isEmpty || remoteId == widget.profileId) return;
    final remoteName = data['fromName']?.toString() ??
        data['relaySenderName']?.toString() ??
        'user';
    final action = data['action']?.toString() ?? '';
    final knownPeer = _peers[remoteId];
    if (knownPeer != null) knownPeer.lastSeenAt = DateTime.now();

    switch (action) {
      case 'group_join':
        unawaited(_handleJoin(remoteId, remoteName));
        break;
      case 'group_hello':
        unawaited(_handleHello(remoteId, remoteName));
        break;
      case 'group_offer':
        unawaited(_handleOffer(remoteId, remoteName, data));
        break;
      case 'group_answer':
        unawaited(_handleAnswer(remoteId, remoteName, data));
        break;
      case 'group_ice':
        unawaited(_handleIce(remoteId, remoteName, data));
        break;
      case 'group_leave':
        unawaited(_removePeer(remoteId));
        break;
      case 'group_full':
        if (mounted) {
          setState(() {
            _status = widget.ru
                ? 'В комнате уже шесть участников'
                : 'The room already has six participants';
          });
        }
        break;
    }
  }

  Future<void> _handleJoin(String remoteId, String remoteName) async {
    if (!_peers.containsKey(remoteId) && _peers.length >= 5) {
      await _send({
        'action': 'group_full',
        'target': remoteId,
      });
      return;
    }
    await _ensurePeer(remoteId, remoteName);
    await _send({
      'action': 'group_hello',
      'target': remoteId,
      'fromName': widget.nickname,
    });
    await _maybeOffer(remoteId);
  }

  Future<void> _handleHello(String remoteId, String remoteName) async {
    if (!_peers.containsKey(remoteId) && _peers.length >= 5) return;
    await _ensurePeer(remoteId, remoteName);
    await _maybeOffer(remoteId);
  }

  Future<_GroupPeer> _ensurePeer(String id, String name) async {
    final existing = _peers[id];
    if (existing != null) {
      existing.name = name;
      existing.lastSeenAt = DateTime.now();
      return existing;
    }

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final connection = await createPeerConnection({
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
      'iceCandidatePoolSize': 6,
      'continualGatheringPolicy': 'gather_continually',
    });
    final peer = _GroupPeer(
      id: id,
      name: name,
      connection: connection,
      renderer: renderer,
    );
    _peers[id] = peer;

    connection.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      unawaited(_send({
        'action': 'group_ice',
        'target': id,
        'candidate': value,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
    };
    connection.onTrack = (event) {
      if (event.streams.isEmpty) return;
      renderer.srcObject = event.streams.first;
      peer.connected = true;
      _markConnected();
      if (mounted) setState(() {});
    };
    connection.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        peer.connected = true;
        peer.recovering = false;
        peer.lastSeenAt = DateTime.now();
        _markConnected();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        peer.connected = false;
        unawaited(_recoverPeer(peer));
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        peer.connected = false;
      }
      setState(() {});
    };

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await connection.addTrack(track, stream);
      }
    }
    if (mounted) setState(() {});
    return peer;
  }

  Future<void> _maybeOffer(
    String remoteId, {
    bool iceRestart = false,
  }) async {
    final peer = _peers[remoteId];
    if (peer == null) return;
    if (widget.profileId.compareTo(remoteId) >= 0) return;
    final now = DateTime.now();
    if (!iceRestart &&
        peer.offerSent &&
        now.difference(peer.lastOfferAt) < const Duration(seconds: 3)) {
      final cached = peer.localOffer;
      if (cached != null) {
        await _send({
          'action': 'group_offer',
          'target': remoteId,
          'sdp': cached.sdp,
          'sdpType': cached.type,
        });
      }
      return;
    }
    peer.offerSent = true;
    peer.lastOfferAt = now;
    final offer = await peer.connection.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
      'iceRestart': iceRestart,
    });
    await peer.connection.setLocalDescription(offer);
    peer.localOffer = offer;
    await _send({
      'action': 'group_offer',
      'target': remoteId,
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }

  Future<void> _handleOffer(
    String remoteId,
    String remoteName,
    Map<String, dynamic> data,
  ) async {
    final peer = await _ensurePeer(remoteId, remoteName);
    final sdp = data['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) return;
    final current = await peer.connection.getRemoteDescription();
    if (current?.sdp != sdp) {
      await peer.connection.setRemoteDescription(
        RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'offer'),
      );
      peer.remoteDescriptionSet = true;
      peer.localAnswer = null;
      await _flushCandidates(peer);
    }
    var answer = peer.localAnswer;
    if (answer == null) {
      answer = await peer.connection.createAnswer(<String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
      });
      await peer.connection.setLocalDescription(answer);
      peer.localAnswer = answer;
    }
    await _send({
      'action': 'group_answer',
      'target': remoteId,
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
  }

  Future<void> _handleAnswer(
    String remoteId,
    String remoteName,
    Map<String, dynamic> data,
  ) async {
    final peer = await _ensurePeer(remoteId, remoteName);
    final sdp = data['sdp']?.toString();
    if (sdp == null || sdp.isEmpty) return;
    final current = await peer.connection.getRemoteDescription();
    if (current?.sdp == sdp) return;
    await peer.connection.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'answer'),
    );
    peer.remoteDescriptionSet = true;
    peer.recovering = false;
    await _flushCandidates(peer);
  }

  Future<void> _handleIce(
    String remoteId,
    String remoteName,
    Map<String, dynamic> data,
  ) async {
    final peer = await _ensurePeer(remoteId, remoteName);
    final value = data['candidate']?.toString();
    if (value == null || value.isEmpty) return;
    final signature =
        '$value|${data['sdpMid']}|${data['sdpMLineIndex']}';
    if (!peer.seenCandidates.add(signature)) return;
    final candidate = RTCIceCandidate(
      value,
      data['sdpMid']?.toString(),
      int.tryParse(data['sdpMLineIndex']?.toString() ?? ''),
    );
    if (!peer.remoteDescriptionSet) {
      peer.queuedCandidates.add(candidate);
      return;
    }
    try {
      await peer.connection.addCandidate(candidate);
    } catch (_) {
      peer.queuedCandidates.add(candidate);
    }
  }

  Future<void> _flushCandidates(_GroupPeer peer) async {
    for (final candidate in peer.queuedCandidates.toList()) {
      try {
        await peer.connection.addCandidate(candidate);
        peer.queuedCandidates.remove(candidate);
      } catch (_) {}
    }
  }

  Future<void> _recoverPeer(_GroupPeer peer) async {
    if (_ended || peer.recovering) return;
    peer.recovering = true;
    try {
      await _send({
        'action': 'group_hello',
        'target': peer.id,
        'fromName': widget.nickname,
      });
      if (widget.profileId.compareTo(peer.id) < 0) {
        await _maybeOffer(peer.id, iceRestart: true);
      }
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      peer.recovering = false;
    }
  }

  Future<void> _recoverPeers() async {
    final now = DateTime.now();
    for (final peer in _peers.values.toList()) {
      if (now.difference(peer.lastSeenAt) > const Duration(seconds: 35)) {
        await _removePeer(peer.id);
        continue;
      }
      if (!peer.connected) await _recoverPeer(peer);
    }
  }

  void _markConnected() {
    _connectedAt ??= DateTime.now();
    _status = widget.ru
        ? 'В звонке • ${_peers.length + 1} участников'
        : 'In call • ${_peers.length + 1} participants';
    _durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() {
        _elapsedSeconds = DateTime.now().difference(_connectedAt!).inSeconds;
        _status = widget.ru
            ? 'В звонке • ${_peers.length + 1} участников'
            : 'In call • ${_peers.length + 1} participants';
      });
    });
  }

  Future<void> _removePeer(String id) async {
    final peer = _peers.remove(id);
    if (peer != null) await peer.dispose();
    if (mounted) {
      setState(() {
        _status = widget.ru
            ? 'В звонке • ${_peers.length + 1} участников'
            : 'In call • ${_peers.length + 1} participants';
      });
    }
  }

  Future<void> _send(Map<String, dynamic> data) async {
    final session = _session;
    if (session == null) return;
    await session.sendSignal({
      ...data,
      'callId': widget.callId,
      'from': widget.profileId,
      'fromName': widget.nickname,
      'video': widget.video,
      'group': true,
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
    unawaited(
      _send({'action': 'group_leave'})
          .timeout(const Duration(milliseconds: 700))
          .catchError((_) {}),
    );
    _finish();
  }

  void _finish() {
    if (_ended || !mounted) return;
    _ended = true;
    final seconds = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;
    Navigator.pop(
      context,
      CgCallOutcome(
        status: _connectedAt == null ? 'cancelled' : 'completed',
        durationSeconds: seconds,
        connected: _connectedAt != null,
        video: widget.video,
      ),
    );
  }

  String get _duration {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _ended = true;
    _durationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    unawaited(_subscription?.cancel());
    for (final peer in _peers.values) {
      unawaited(peer.dispose());
    }
    _peers.clear();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    unawaited(_localStream?.dispose());
    _localRenderer.srcObject = null;
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <_VideoTileData>[
      _VideoTileData(
        name: widget.nickname,
        renderer: _localRenderer,
        local: true,
        videoEnabled: widget.video && !_cameraOff,
        connected: true,
      ),
      ..._peers.values.map(
        (peer) => _VideoTileData(
          name: peer.name,
          renderer: peer.renderer,
          local: false,
          videoEnabled: widget.video && peer.renderer.srcObject != null,
          connected: peer.connected,
        ),
      ),
    ].take(6).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_hangUp());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050711),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.tunnelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '$_status${_connectedAt == null ? '' : ' • $_duration'}',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${tiles.length}/6',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth > constraints.maxHeight ? 3 : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: .78,
                      ),
                      itemCount: tiles.length,
                      itemBuilder: (context, index) =>
                          _GroupVideoTile(data: tiles[index]),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: GlassPanel(
                  color: const Color(0xAA111725),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _GroupCallButton(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        active: _muted,
                        onTap: _toggleMute,
                      ),
                      _GroupCallButton(
                        icon: _speaker ? Icons.volume_up : Icons.hearing,
                        active: _speaker,
                        onTap: _toggleSpeaker,
                      ),
                      if (widget.video)
                        _GroupCallButton(
                          icon: _cameraOff
                              ? Icons.videocam_off
                              : Icons.videocam,
                          active: _cameraOff,
                          onTap: _toggleCamera,
                        ),
                      if (widget.video)
                        _GroupCallButton(
                          icon: Icons.cameraswitch,
                          onTap: _switchCamera,
                        ),
                      _GroupCallButton(
                        icon: Icons.call_end,
                        danger: true,
                        onTap: _hangUp,
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoTileData {
  final String name;
  final RTCVideoRenderer renderer;
  final bool local;
  final bool videoEnabled;
  final bool connected;

  const _VideoTileData({
    required this.name,
    required this.renderer,
    required this.local,
    required this.videoEnabled,
    required this.connected,
  });
}

class _GroupVideoTile extends StatelessWidget {
  final _VideoTileData data;

  const _GroupVideoTile({required this.data});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF151C32),
              child: data.videoEnabled
                  ? RTCVideoView(
                      data.renderer,
                      mirror: data.local,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: CircleAvatar(
                        radius: 34,
                        backgroundColor: const Color(0xFF7C5CFF),
                        child: Text(
                          data.name.isEmpty
                              ? '?'
                              : data.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.local ? '${data.name} • вы' : data.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Icon(
                      data.connected
                          ? Icons.graphic_eq_rounded
                          : Icons.hourglass_bottom_rounded,
                      color: data.connected
                          ? ChernogramColors.success
                          : Colors.white54,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _GroupCallButton extends StatelessWidget {
  final IconData icon;
  final FutureOr<void> Function() onTap;
  final bool active;
  final bool danger;

  const _GroupCallButton({
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
            width: 50,
            height: 50,
            child: Icon(
              icon,
              color: active ? const Color(0xFF111725) : Colors.white,
            ),
          ),
        ),
      );
}
