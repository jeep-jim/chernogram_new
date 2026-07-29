import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';

class CgLiveKitTestScreen extends StatefulWidget {
  final bool ru;
  final String initialIdentity;
  final String initialDisplayName;

  const CgLiveKitTestScreen({
    super.key,
    required this.ru,
    required this.initialIdentity,
    required this.initialDisplayName,
  });

  @override
  State<CgLiveKitTestScreen> createState() => _CgLiveKitTestScreenState();
}

class _CgLiveKitTestScreenState extends State<CgLiveKitTestScreen> {
  static const _brokerUrlKey = 'cg_livekit_broker_url_v1';
  static const _brokerSecretKey = 'cg_livekit_broker_secret_v1';
  static const _roomKey = 'cg_livekit_room_v1';

  late final lk.Room _room;
  late final TextEditingController _brokerController;
  late final TextEditingController _secretController;
  late final TextEditingController _roomController;
  late final TextEditingController _identityController;
  late final TextEditingController _displayNameController;

  bool _busy = false;
  bool _connected = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = false;
  String? _error;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _room = lk.Room();
    _room.addListener(_onRoomChanged);
    _brokerController = TextEditingController(text: 'http://127.0.0.1:8090');
    _secretController = TextEditingController();
    _roomController = TextEditingController(text: 'android-windows-test');
    _identityController = TextEditingController(text: widget.initialIdentity);
    _displayNameController = TextEditingController(
      text: widget.initialDisplayName,
    );
    _status = widget.ru ? 'Не подключено' : 'Not connected';
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _brokerController.text =
        prefs.getString(_brokerUrlKey) ?? _brokerController.text;
    _secretController.text = prefs.getString(_brokerSecretKey) ?? '';
    _roomController.text = prefs.getString(_roomKey) ?? _roomController.text;
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait<void>([
      prefs.setString(_brokerUrlKey, _brokerController.text.trim()),
      prefs.setString(_brokerSecretKey, _secretController.text.trim()),
      prefs.setString(_roomKey, _roomController.text.trim()),
    ]);
  }

  void _onRoomChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _connect() async {
    if (_busy || _connected) return;
    FocusScope.of(context).unfocus();
    final brokerBase = _brokerController.text.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final roomName = _roomController.text.trim();
    final identity = _identityController.text.trim();
    final displayName = _displayNameController.text.trim();
    if (brokerBase.isEmpty || roomName.isEmpty || identity.isEmpty) {
      setState(() {
        _error = widget.ru
            ? 'Заполните адрес broker, комнату и identity.'
            : 'Enter broker URL, room and identity.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = widget.ru ? 'Получаем временный токен…' : 'Getting token…';
    });

    try {
      await _saveSettings();
      final headers = <String, String>{'Content-Type': 'application/json'};
      final brokerSecret = _secretController.text.trim();
      if (brokerSecret.isNotEmpty) {
        headers['X-Cernogram-Broker-Key'] = brokerSecret;
      }
      final response = await http
          .post(
            Uri.parse('$brokerBase/v1/token'),
            headers: headers,
            body: jsonEncode(<String, String>{
              'room': roomName,
              'identity': identity,
              'displayName': displayName,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError(
          'Broker HTTP ${response.statusCode}: ${response.body}',
        );
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Broker returned invalid JSON');
      }
      final url = payload['url']?.toString() ?? '';
      final token = payload['token']?.toString() ?? '';
      if (url.isEmpty || token.isEmpty) {
        throw const FormatException('Broker response has no URL or token');
      }

      if (!mounted) return;
      setState(
        () => _status = widget.ru
            ? 'Подключаем медиаканал…'
            : 'Connecting media…',
      );
      const roomOptions = lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      );
      await _room.prepareConnection(url, token);
      await _room.connect(url, token, roomOptions: roomOptions);
      final local = _room.localParticipant;
      if (local == null) {
        throw StateError('LiveKit did not create a local participant');
      }
      await local.setMicrophoneEnabled(_microphoneEnabled);
      if (_cameraEnabled) await local.setCameraEnabled(true);

      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = widget.ru ? 'Связь установлена' : 'Connected';
      });
    } catch (error) {
      await _room.disconnect();
      if (!mounted) return;
      setState(() {
        _connected = false;
        _error = error.toString();
        _status = widget.ru ? 'Ошибка подключения' : 'Connection error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMicrophone() async {
    final local = _room.localParticipant;
    if (!_connected || local == null || _busy) return;
    final next = !_microphoneEnabled;
    setState(() => _busy = true);
    try {
      await local.setMicrophoneEnabled(next);
      if (mounted) setState(() => _microphoneEnabled = next);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleCamera() async {
    final local = _room.localParticipant;
    if (!_connected || local == null || _busy) return;
    final next = !_cameraEnabled;
    setState(() => _busy = true);
    try {
      await local.setCameraEnabled(next);
      if (mounted) setState(() => _cameraEnabled = next);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hangUp() async {
    if (_busy && !_connected) return;
    setState(() {
      _busy = true;
      _status = widget.ru ? 'Завершаем звонок…' : 'Ending call…';
    });
    try {
      await _room.disconnect();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _connected = false;
          _microphoneEnabled = true;
          _cameraEnabled = false;
          _status = widget.ru ? 'Звонок завершён' : 'Call ended';
        });
      }
    }
  }

  List<lk.Participant> get _participants {
    final result = <lk.Participant>[];
    final local = _room.localParticipant;
    if (local != null) result.add(local);
    result.addAll(_room.remoteParticipants.values);
    return result;
  }

  lk.VideoTrack? _firstVideoTrack(lk.Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track != null && !publication.muted) return track;
    }
    return null;
  }

  Widget _participantCard(lk.Participant participant) {
    final track = _firstVideoTrack(participant);
    final local = participant is lk.LocalParticipant;
    final title = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: participant.isSpeaking
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  )
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track != null)
                lk.VideoTrackRenderer(track)
              else
                Center(
                  child: Icon(
                    local ? Icons.person_rounded : Icons.person_outline_rounded,
                    size: 64,
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$title${local ? (widget.ru ? ' · вы' : ' · you') : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (participant.isSpeaking)
                        const Icon(
                          Icons.graphic_eq_rounded,
                          color: Colors.white,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _configurationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.ru ? 'Тест Android ↔ Windows' : 'Android ↔ Windows test',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              widget.ru
                  ? 'На обоих устройствах укажите одинаковую комнату, но разные identity.'
                  : 'Use the same room and different identities on both devices.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _brokerController,
              enabled: !_connected && !_busy,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: widget.ru ? 'Адрес Python broker' : 'Python broker URL',
                hintText: 'http://192.168.1.20:8090',
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              enabled: !_connected && !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.ru ? 'Ключ broker' : 'Broker key',
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roomController,
              enabled: !_connected && !_busy,
              decoration: InputDecoration(
                labelText: widget.ru ? 'Комната' : 'Room',
                prefixIcon: const Icon(Icons.meeting_room_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _identityController,
                    enabled: !_connected && !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Identity',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _displayNameController,
                    enabled: !_connected && !_busy,
                    decoration: InputDecoration(
                      labelText: widget.ru ? 'Имя' : 'Name',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _connected ? null : _connect,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_rounded),
              label: Text(widget.ru ? 'Подключиться' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final participants = _participants;
    return Scaffold(
      appBar: AppBar(
        title: BrandHeader(
          ru: widget.ru,
          subtitle: widget.ru ? 'LiveKit Core' : 'LiveKit Core',
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final content = ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, _connected ? 108 : 24),
              children: [
                if (!_connected) _configurationCard(),
                Card(
                  child: ListTile(
                    leading: Icon(
                      _connected
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                    ),
                    title: Text(_status),
                    subtitle: Text(
                      widget.ru
                          ? '${participants.length} участник(а) в комнате'
                          : '${participants.length} participant(s) in room',
                    ),
                    trailing: _busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: SelectableText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_connected) ...[
                  const SizedBox(height: 12),
                  if (participants.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.ru
                            ? 'Ожидаем второго участника…'
                            : 'Waiting for another participant…',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: wide ? 2 : 1,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 16 / 10,
                      ),
                      itemCount: participants.length,
                      itemBuilder: (context, index) =>
                          _participantCard(participants[index]),
                    ),
                ],
              ],
            );
            return content;
          },
        ),
      ),
      bottomNavigationBar: !_connected
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'livekit-mic',
                    onPressed: _busy ? null : _toggleMicrophone,
                    tooltip: _microphoneEnabled
                        ? (widget.ru ? 'Выключить микрофон' : 'Mute')
                        : (widget.ru ? 'Включить микрофон' : 'Unmute'),
                    child: Icon(
                      _microphoneEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                    ),
                  ),
                  const SizedBox(width: 18),
                  FloatingActionButton.small(
                    heroTag: 'livekit-camera',
                    onPressed: _busy ? null : _toggleCamera,
                    tooltip: _cameraEnabled
                        ? (widget.ru ? 'Выключить камеру' : 'Disable camera')
                        : (widget.ru ? 'Включить камеру' : 'Enable camera'),
                    child: Icon(
                      _cameraEnabled
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                    ),
                  ),
                  const SizedBox(width: 18),
                  FloatingActionButton(
                    heroTag: 'livekit-hangup',
                    onPressed: _hangUp,
                    tooltip: widget.ru ? 'Завершить' : 'Hang up',
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    child: const Icon(Icons.call_end_rounded),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _room.removeListener(_onRoomChanged);
    unawaited(_room.disconnect().whenComplete(_room.dispose));
    _brokerController.dispose();
    _secretController.dispose();
    _roomController.dispose();
    _identityController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }
}
