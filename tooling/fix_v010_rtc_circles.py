from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    # ------------------------------------------------------------------
    # 1-to-1 WebRTC: conservative media profile + continuous recovery.
    # ------------------------------------------------------------------
    replace(
        'lib/call_service.dart',
        """  String? _peerId;

  String get _callId => _resolvedCallId;
""",
        """  String? _peerId;
  bool _transportConnected = false;
  DateTime _lastRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);

  String get _callId => _resolvedCallId;
""",
    )
    replace(
        'lib/call_service.dart',
        """        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 1,
        },
""",
        """        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googEchoCancellation2': true,
          'googNoiseSuppression': true,
          'googNoiseSuppression2': true,
          'googAutoGainControl': true,
          'googAutoGainControl2': true,
          'googHighpassFilter': true,
          'googTypingNoiseDetection': true,
          'channelCount': 1,
          'sampleRate': 48000,
          'sampleSize': 16,
        },
""",
    )
    replace(
        'lib/call_service.dart',
        """                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
                'frameRate': <String, dynamic>{'ideal': 30, 'max': 30},
""",
        """                'width': <String, dynamic>{'ideal': 960, 'max': 1280},
                'height': <String, dynamic>{'ideal': 540, 'max': 720},
                'frameRate': <String, dynamic>{'ideal': 24, 'max': 30},
""",
    )
    replace(
        'lib/call_service.dart',
        """        'iceTransportPolicy': 'all',
      });
""",
        """        'iceTransportPolicy': 'all',
        'iceCandidatePoolSize': 8,
        'continualGatheringPolicy': 'gather_continually',
      });
""",
    )
    replace(
        'lib/call_service.dart',
        """            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              _markConnected();
              break;
""",
        """            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              _transportConnected = true;
              _markConnected();
              break;
""",
    )
    replace(
        'lib/call_service.dart',
        """            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
              _status = widget.ru
""",
        """            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
              _transportConnected = false;
              _status = widget.ru
""",
    )
    replace(
        'lib/call_service.dart',
        """            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
              _status = widget.ru
""",
        """            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
              _transportConnected = false;
              _status = widget.ru
""",
    )
    replace(
        'lib/call_service.dart',
        """      _watchdog = Timer.periodic(const Duration(seconds: 12), (_) {
        if (_ended || _connectedAt != null) return;
        if (widget.isCaller && _peerId != null) {
          unawaited(_makeOffer(iceRestart: _localOffer != null));
        } else if (!widget.isCaller) {
          unawaited(_sendReady());
        }
      });
""",
        """      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_ended) return;
        if (_peerId == null || _peerId!.isEmpty) {
          if (widget.isCaller) {
            unawaited(_sendInvite());
          } else {
            unawaited(_sendReady());
          }
          return;
        }
        if (!_transportConnected) unawaited(_recoverConnection());
      });
""",
    )
    replace(
        'lib/call_service.dart',
        """  Future<void> _recoverConnection() async {
    if (_ended || _connectedAt == null && _peerId == null) return;
    if (widget.isCaller) {
      await _makeOffer(iceRestart: true);
    } else {
      await _sendReady();
    }
  }
""",
        """  Future<void> _recoverConnection() async {
    if (_ended || _peerId == null || _peerId!.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastRecoveryAt) < const Duration(seconds: 3)) return;
    _lastRecoveryAt = now;
    if (mounted) {
      setState(() {
        _status = widget.ru
            ? 'Восстанавливаем медиаканал…'
            : 'Restoring media channel…';
      });
    }
    if (widget.isCaller) {
      await _makeOffer(iceRestart: true);
    } else {
      await _sendReady();
    }
  }
""",
    )
    replace(
        'lib/call_service.dart',
        """  void _markConnected() {
    _connectedAt ??= DateTime.now();
""",
        """  void _markConnected() {
    _transportConnected = true;
    _connectedAt ??= DateTime.now();
""",
    )

    # ------------------------------------------------------------------
    # Group WebRTC mesh: replay signalling, heartbeat, ICE restarts,
    # candidate deduplication and a bandwidth-safe six-person profile.
    # ------------------------------------------------------------------
    replace(
        'lib/group_call_service.dart',
        """  bool offerSent = false;
  bool connected = false;
""",
        """  bool offerSent = false;
  bool connected = false;
  bool recovering = false;
  DateTime lastSeenAt = DateTime.now();
  DateTime lastOfferAt = DateTime.fromMillisecondsSinceEpoch(0);
  RTCSessionDescription? localOffer;
  RTCSessionDescription? localAnswer;
  final Set<String> seenCandidates = <String>{};
""",
    )
    replace(
        'lib/group_call_service.dart',
        """  Timer? _durationTimer;
  DateTime? _connectedAt;
""",
        """  Timer? _durationTimer;
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;
  DateTime? _connectedAt;
""",
    )
    replace(
        'lib/group_call_service.dart',
        """      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 960},
                'height': {'ideal': 540},
                'frameRate': {'ideal': 24},
              }
            : false,
      });
""",
        """      final stream = await navigator.mediaDevices.getUserMedia({
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
""",
    )
    replace(
        'lib/group_call_service.dart',
        """      _session = session;
      _subscription = session.events.listen(_onRelayEvent);

      if (widget.isHost) {
""",
        """      _session = session;
      _subscription = session.events.listen(_onRelayEvent);
      for (final signal in session.replaySignals(widget.callId)) {
        _onRelayEvent(InternetEvent('signal', signal));
      }

      if (widget.isHost) {
""",
    )
    replace(
        'lib/group_call_service.dart',
        """      await _send({
        'action': 'group_join',
        'fromName': widget.nickname,
        'video': widget.video,
      });

      if (mounted) {
""",
        """      await _send({
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
""",
    )
    replace(
        'lib/group_call_service.dart',
        """    final action = data['action']?.toString() ?? '';

    switch (action) {
""",
        """    final action = data['action']?.toString() ?? '';
    final knownPeer = _peers[remoteId];
    if (knownPeer != null) knownPeer.lastSeenAt = DateTime.now();

    switch (action) {
""",
    )
    replace(
        'lib/group_call_service.dart',
        """    if (existing != null) {
      existing.name = name;
      return existing;
    }
""",
        """    if (existing != null) {
      existing.name = name;
      existing.lastSeenAt = DateTime.now();
      return existing;
    }
""",
    )
    replace(
        'lib/group_call_service.dart',
        """      'iceServers': <Map<String, dynamic>>[
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
""",
        """      'iceServers': <Map<String, dynamic>>[
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
""",
    )
    replace(
        'lib/group_call_service.dart',
        """      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        peer.connected = true;
        _markConnected();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        peer.connected = false;
      }
""",
        """      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
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
""",
    )

    old_offer = """  Future<void> _maybeOffer(String remoteId) async {
    final peer = _peers[remoteId];
    if (peer == null || peer.offerSent) return;
    if (widget.profileId.compareTo(remoteId) >= 0) return;
    peer.offerSent = true;
    final offer = await peer.connection.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
    });
    await peer.connection.setLocalDescription(offer);
    await _send({
      'action': 'group_offer',
      'target': remoteId,
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }
"""
    new_offer = """  Future<void> _maybeOffer(
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
"""
    replace('lib/group_call_service.dart', old_offer, new_offer)

    replace(
        'lib/group_call_service.dart',
        """    await peer.connection.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'offer'),
    );
    peer.remoteDescriptionSet = true;
    await _flushCandidates(peer);
    final answer = await peer.connection.createAnswer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
    });
    await peer.connection.setLocalDescription(answer);
    await _send({
      'action': 'group_answer',
      'target': remoteId,
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
""",
        """    final current = await peer.connection.getRemoteDescription();
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
""",
    )
    replace(
        'lib/group_call_service.dart',
        """    await peer.connection.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'answer'),
    );
    peer.remoteDescriptionSet = true;
    await _flushCandidates(peer);
""",
        """    final current = await peer.connection.getRemoteDescription();
    if (current?.sdp == sdp) return;
    await peer.connection.setRemoteDescription(
      RTCSessionDescription(sdp, data['sdpType']?.toString() ?? 'answer'),
    );
    peer.remoteDescriptionSet = true;
    peer.recovering = false;
    await _flushCandidates(peer);
""",
    )
    replace(
        'lib/group_call_service.dart',
        """    final candidate = RTCIceCandidate(
      value,
      data['sdpMid']?.toString(),
      int.tryParse(data['sdpMLineIndex']?.toString() ?? ''),
    );
    if (!peer.remoteDescriptionSet) {
      peer.queuedCandidates.add(candidate);
      return;
    }
    await peer.connection.addCandidate(candidate);
""",
        """    final signature =
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
""",
    )
    replace(
        'lib/group_call_service.dart',
        """  Future<void> _flushCandidates(_GroupPeer peer) async {
    for (final candidate in peer.queuedCandidates.toList()) {
      await peer.connection.addCandidate(candidate);
    }
    peer.queuedCandidates.clear();
  }

  void _markConnected() {
""",
        """  Future<void> _flushCandidates(_GroupPeer peer) async {
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
""",
    )
    replace(
        'lib/group_call_service.dart',
        """    _durationTimer?.cancel();
    unawaited(_subscription?.cancel());
""",
        """    _durationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    unawaited(_subscription?.cancel());
""",
    )

    # ------------------------------------------------------------------
    # Video circles: real circular bubble in chat + 60-second progress ring.
    # ------------------------------------------------------------------
    replace(
        'lib/chat_media.dart',
        """    final attachment = widget.attachment;
    final bytes = _bytes;
    if (attachment.kind == 'image' && bytes != null) {
""",
        """    final attachment = widget.attachment;
    final bytes = _bytes;
    if (attachment.kind == 'circle') {
      return _CgInlineCircleAttachment(attachment: attachment);
    }
    if (attachment.kind == 'image' && bytes != null) {
""",
    )

    circle_widget = r'''
class _CgInlineCircleAttachment extends StatefulWidget {
  final CgAttachment attachment;

  const _CgInlineCircleAttachment({required this.attachment});

  @override
  State<_CgInlineCircleAttachment> createState() =>
      _CgInlineCircleAttachmentState();
}

class _CgInlineCircleAttachmentState
    extends State<_CgInlineCircleAttachment> {
  VideoPlayerController? _controller;
  File? _file;
  bool _ready = false;
  bool _sound = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final file = await CgMediaStore.ensureFile(widget.attachment);
    if (file == null || !mounted) return;
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(0);
    controller.addListener(_refresh);
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _file = file;
      _controller = controller;
      _ready = true;
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying && _sound) {
      await controller.pause();
      return;
    }
    _sound = true;
    await controller.setVolume(1);
    await controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final file = _file;
    if (file == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgVideoPlayerScreen(
          file: file,
          circle: true,
          title: widget.attachment.name,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_refresh);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final duration = controller?.value.duration ?? Duration.zero;
    final position = controller?.value.position ?? Duration.zero;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    const size = 224.0;
    return GestureDetector(
      onTap: _toggle,
      onLongPress: _open,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: size - 8,
                child: !_ready || controller == null
                    ? Container(
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      )
                    : FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 4,
                backgroundColor: Colors.white24,
              ),
            ),
            if (controller != null && !controller.value.isPlaying)
              const CircleAvatar(
                radius: 25,
                backgroundColor: Colors.black54,
                child: Icon(Icons.play_arrow_rounded, color: Colors.white),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: Colors.black54,
                child: Icon(
                  _sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
    media = Path('lib/chat_media.dart')
    media_source = media.read_text(encoding='utf-8')
    if 'class _CgInlineCircleAttachment extends StatefulWidget' not in media_source:
        replace(
            'lib/chat_media.dart',
            'class CgMediaLibraryScreen extends StatefulWidget {',
            circle_widget + 'class CgMediaLibraryScreen extends StatefulWidget {',
        )

    replace(
        'lib/chat_media.dart',
        """                        ClipOval(
                          child: SizedBox.square(
                            dimension: math.min(
                              MediaQuery.sizeOf(context).width - 36,
                              420.0,
                            ).toDouble(),
                            child: CameraPreview(_controller!),
                          ),
                        ),
""",
        """                        Builder(
                          builder: (context) {
                            final diameter = math.min(
                              MediaQuery.sizeOf(context).width - 48,
                              410.0,
                            ).toDouble();
                            final progress = (_elapsed.inMilliseconds / 60000)
                                .clamp(0.0, 1.0);
                            return SizedBox.square(
                              dimension: diameter + 14,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ClipOval(
                                    child: SizedBox.square(
                                      dimension: diameter,
                                      child: CameraPreview(_controller!),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CircularProgressIndicator(
                                      value: _recording ? progress : 0,
                                      strokeWidth: 7,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                  if (_recording)
                                    Positioned(
                                      bottom: 18,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${60 - _elapsed.inSeconds} сек',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
""",
    )

    print('Applied Chernogram 0.10 adaptive RTC and circular video UX')


if __name__ == '__main__':
    main()
