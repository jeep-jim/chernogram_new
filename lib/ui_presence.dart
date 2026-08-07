import 'dart:async';

class CgPeerArrival {
  final String tunnelId;
  final String peerId;
  final String peerName;

  const CgPeerArrival({
    required this.tunnelId,
    required this.peerId,
    required this.peerName,
  });
}

class CgUiPresence {
  static bool _foreground = true;
  static String? _activeTunnelId;
  static final Map<String, Set<String>> _peers = <String, Set<String>>{};
  static final StreamController<CgPeerArrival> _peerEvents =
      StreamController<CgPeerArrival>.broadcast(sync: true);

  static bool get foreground => _foreground;
  static String? get activeTunnelId => _activeTunnelId;
  static Stream<CgPeerArrival> get peerEvents => _peerEvents.stream;

  static void setForeground(bool value) {
    _foreground = value;
  }

  static void enterTunnel(String tunnelId) {
    _activeTunnelId = tunnelId;
  }

  static void leaveTunnel(String tunnelId) {
    if (_activeTunnelId == tunnelId) _activeTunnelId = null;
  }

  static bool isTunnelOpen(String tunnelId) =>
      _foreground && _activeTunnelId == tunnelId;

  static void markPeer(String tunnelId, String peerId, String peerName) {
    if (tunnelId.isEmpty || peerId.isEmpty) return;
    final peers = _peers.putIfAbsent(tunnelId, () => <String>{});
    final fresh = peers.add(peerId);
    if (fresh) {
      _peerEvents.add(
        CgPeerArrival(
          tunnelId: tunnelId,
          peerId: peerId,
          peerName: peerName,
        ),
      );
    }
  }

  static bool hasRemotePeer(String tunnelId) =>
      _peers[tunnelId]?.isNotEmpty == true;
}
