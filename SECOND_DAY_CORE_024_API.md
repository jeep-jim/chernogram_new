# Second-day core API comparison

Historical commit: d696e470cb96e61a0e5cc29c9e335b5da5a8f69b

## Historical internet core public surface
```text
10:class InternetEvent {
17:class _PendingEnvelope {
24:class InternetTunnelSession {
54:  String? _topic;
55:  bool _closed = false;
56:  bool _connecting = false;
57:  int _reconnectAttempt = 0;
59:  InternetTunnelSession({
66:  Stream<InternetEvent> get events => _events.stream;
67:  bool get connected => _sockets.isNotEmpty;
68:  int get onlinePeers => _peers.length + 1;
69:  List<Map<String, dynamic>> get members => <Map<String, dynamic>>[
86:  Future<void> connect() async {
121:  Future<void> _connectHost(String host) async {
161:  Future<void> _prepareCryptoAndTopic() async {
169:  Future<void> _handleSocketMessage(String host, dynamic raw) async {
201:  void _onHostDisconnected(String host, String reason) {
216:  Future<void> _handleEncryptedPacket(
306:  Future<void> sendMessage(Map<String, dynamic> message) async {
311:  Future<void> sendControl(Map<String, dynamic> control) async {
315:  Future<void> sendSignal(Map<String, dynamic> signal) async {
319:  Future<void> sendHistory() async {
326:  void replaceHistory(List<Map<String, dynamic>> messages) {
333:  Future<void> _publishPresence() async {
344:  Future<void> _sendEnvelope(
427:  Future<void> _publishEncrypted(
455:  Future<void> _flushOutbox() async {
464:  Future<String> _encrypt(Map<String, dynamic> body) async {
480:  Future<Map<String, dynamic>?> _decrypt(String value) async {
502:  bool _rememberMessage(Map<String, dynamic> message) {
517:  void _startTimers() {
536:  void _emitPresence() {
543:  void _scheduleHostReconnect(String host) {
551:  void _scheduleGlobalReconnect() {
566:  void _emit(String type, [Map<String, dynamic> data = const {}]) {
570:  Future<void> close() async {
592:class InternetRelay {
596:  static InternetTunnelSession? session(String tunnelId) =>
599:  static Future<InternetTunnelSession> open({
626:  static Future<void> close(String tunnelId) async {
```

## Current internet core public surface
```text
10:class InternetEvent {
17:class _PendingEnvelope {
24:class InternetTunnelSession {
57:  String? _topic;
58:  bool _closed = false;
59:  bool _connecting = false;
60:  int _reconnectAttempt = 0;
62:  InternetTunnelSession({
69:  Stream<InternetEvent> get events => _events.stream;
70:  bool get connected => _sockets.isNotEmpty;
71:  int get onlinePeers => _peers.length + 1;
72:  List<Map<String, dynamic>> get members => <Map<String, dynamic>>[
89:  Future<void> connect() async {
140:  Future<bool> waitUntilConnected([Duration timeout = const Duration(seconds: 4)]) async {
151:  Future<bool> _connectHost(String host) async {
193:  Future<void> _prepareCryptoAndTopic() async {
201:  Future<void> _handleSocketMessage(String host, dynamic raw) async {
231:  void _onHostDisconnected(String host, String reason) {
252:  Future<void> _handleEncryptedPacket(
346:  Future<void> sendMessage(Map<String, dynamic> message) async {
351:  Future<void> sendControl(Map<String, dynamic> control) async {
355:  Future<void> sendSignal(Map<String, dynamic> signal) async {
359:  List<Map<String, dynamic>> replaySignals(String callId) {
369:  Future<void> sendHistory() async {
377:  void replaceHistory(List<Map<String, dynamic>> messages) {
384:  Map<String, dynamic> _sanitizeMessage(Map<String, dynamic> message) {
397:  Future<void> _publishPresence() async {
408:  Future<void> _sendEnvelope(
518:  Future<String?> _publishSignalFast(
551:  Future<void> _publishEncrypted(
581:  Future<void> _flushOutbox() async {
590:  Future<String> _encrypt(Map<String, dynamic> body) async {
606:  Future<Map<String, dynamic>?> _decrypt(String value) async {
628:  bool _rememberMessage(Map<String, dynamic> message) {
643:  void _startTimers() {
662:  void _emitPresence() {
669:  void _scheduleHostReconnect(String host) {
678:  void _scheduleGlobalReconnect() {
688:  void _emit(String type, [Map<String, dynamic> data = const <String, dynamic>{}]) {
692:  Future<void> close() async {
715:class InternetRelay {
719:  static InternetTunnelSession? session(String tunnelId) => _sessions[tunnelId];
721:  static Future<InternetTunnelSession> open({
748:  static Future<void> close(String tunnelId) async {
```

## Historical call service public surface
```text
10:class CgCallOutcome {
24:class ChernogramCallScreen extends StatefulWidget {
54:class _ChernogramCallScreenState extends State<ChernogramCallScreen> {
59:  StreamSubscription<InternetEvent>? _signalSubscription;
62:  InternetTunnelSession? _session;
64:  bool _muted = false;
65:  bool _cameraOff = false;
66:  bool _speaker = true;
67:  bool _remoteDescriptionSet = false;
68:  bool _offerSent = false;
69:  bool _ended = false;
70:  bool _remoteVideoReady = false;
71:  String _status = '';
72:  String? _error;
74:  int _elapsedSeconds = 0;
77:  String get _callId => _resolvedCallId;
78:  String get _profileId => widget.profileId ?? '';
81:  void initState() {
90:  Future<void> _prepare() async {
243:  void _markConnected() {
254:  void _onRelayEvent(InternetEvent event) {
300:  Future<void> _makeOffer() async {
315:  Future<void> _handleOffer(Map<String, dynamic> data) async {
336:  Future<void> _handleAnswer(Map<String, dynamic> data) async {
347:  Future<void> _handleIce(Map<String, dynamic> data) async {
362:  Future<void> _flushQueuedCandidates() async {
371:  Future<void> _sendSignal(Map<String, dynamic> data) async {
382:  void _toggleMute() {
392:  void _toggleCamera() {
402:  Future<void> _switchCamera() async {
407:  Future<void> _toggleSpeaker() async {
413:  Future<void> _hangUp() async {
419:  void _finish(String status) {
436:  String get _durationLabel {
443:  void dispose() {
612:class _CallButton extends StatelessWidget {
```

## Current call service public surface
```text
10:class CgCallOutcome {
24:class ChernogramCallScreen extends StatefulWidget {
56:class _ChernogramCallScreenState extends State<ChernogramCallScreen> {
63:  StreamSubscription<InternetEvent>? _signalSubscription;
66:  InternetTunnelSession? _session;
74:  bool _muted = false;
75:  bool _cameraOff = false;
76:  bool _speaker = true;
77:  bool _remoteDescriptionSet = false;
78:  bool _ended = false;
79:  bool _remoteVideoReady = false;
80:  bool _preparing = true;
81:  String _status = '';
82:  String? _error;
84:  int _elapsedSeconds = 0;
86:  String? _peerId;
88:  String get _callId => _resolvedCallId;
89:  String get _profileId => widget.profileId ?? '';
92:  void initState() {
102:  Future<void> _prepare() async {
295:  Future<void> _sendInvite() => _sendSignal(<String, dynamic>{
301:  Future<void> _sendReady() => _sendSignal(<String, dynamic>{
307:  void _onRelayEvent(InternetEvent event) {
312:  void _handleSignal(Map<String, dynamic> data) {
359:  void _adoptPeer(String sender) {
371:  Future<void> _makeOffer({bool iceRestart = false}) async {
407:  Future<void> _sendOffer(RTCSessionDescription offer) =>
414:  Future<void> _handleOffer(Map<String, dynamic> data) async {
447:  Future<void> _handleAnswer(Map<String, dynamic> data) async {
463:  Future<void> _handleIce(Map<String, dynamic> data) async {
482:  Future<void> _flushQueuedRemoteCandidates() async {
493:  Future<void> _recoverConnection() async {
502:  Future<void> _sendSignal(Map<String, dynamic> data) async {
516:  void _markConnected() {
530:  void _toggleMute() {
540:  void _toggleCamera() {
550:  Future<void> _switchCamera() async {
555:  Future<void> _toggleSpeaker() async {
561:  Future<void> _hangUp() async {
567:  void _finish(String status) {
584:  String get _durationLabel {
591:  void dispose() {
770:class _CallControl extends StatelessWidget {
```
