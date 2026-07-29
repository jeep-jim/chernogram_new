import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'agent_service.dart';
import 'brand.dart';
import 'core_models.dart';

enum _AgentEntityState { idle, listening, thinking, speaking, error }

class CgAgentScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final bool privacyLens;
  final VoidCallback onCreateTunnel;
  final VoidCallback onTogglePrivacy;

  const CgAgentScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.privacyLens,
    required this.onCreateTunnel,
    required this.onTogglePrivacy,
  });

  @override
  State<CgAgentScreen> createState() => _CgAgentScreenState();
}

class _CgAgentScreenState extends State<CgAgentScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'agent-composer');
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _voicePlayer = AudioPlayer();

  List<CgAgentMessage> _messages = const <CgAgentMessage>[];
  CgAgentConfig _config = const CgAgentConfig();
  CgAgentBackend? _backend;
  _AgentEntityState _entityState = _AgentEntityState.idle;
  bool _loading = true;
  bool _sending = false;
  bool _recording = false;
  bool _testing = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;
  String? _recordingPath;
  StreamSubscription<PlayerState>? _voiceStateSubscription;

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
    _voiceStateSubscription = _voicePlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _entityState = _AgentEntityState.idle);
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final config = await CgAgentStore.loadConfig();
    final history = config.memoryEnabled
        ? await CgAgentStore.loadHistory()
        : const <CgAgentMessage>[];
    if (!mounted) return;
    _backend?.close();
    setState(() {
      _config = config;
      _messages = history;
      _backend = CgAgentBackend(config);
      _loading = false;
    });
    _scrollToBottom();
  }

  void _onComposerChanged() {
    if (!mounted || _sending || _recording) return;
    final next = _composer.text.trim().isEmpty
        ? _AgentEntityState.idle
        : _AgentEntityState.listening;
    if (_entityState != next) setState(() => _entityState = next);
  }

  Future<void> _persistHistory() async {
    if (_config.memoryEnabled) {
      await CgAgentStore.saveHistory(_messages);
    }
  }

  Future<void> _send({String? explicitText}) async {
    final text = (explicitText ?? _composer.text).trim();
    if (text.isEmpty || _sending) return;
    if (!_config.configured) {
      await _showSettings(firstRun: true);
      return;
    }
    await _stopVoice();
    _composer.clear();
    final user = CgAgentMessage(
      id: CgIds.random(20),
      role: 'user',
      text: text,
      createdAt: DateTime.now().toUtc(),
    );
    final assistant = CgAgentMessage(
      id: CgIds.random(20),
      role: 'assistant',
      text: '',
      createdAt: DateTime.now().toUtc(),
    );
    setState(() {
      _messages = <CgAgentMessage>[..._messages, user, assistant];
      _sending = true;
      _entityState = _AgentEntityState.thinking;
    });
    _scrollToBottom();
    await _persistHistory();

    final contextMessages = _config.memoryEnabled
        ? _messages.where((message) => message.id != assistant.id).toList()
        : <CgAgentMessage>[user];
    final buffer = StringBuffer();
    try {
      final backend = _backend ?? CgAgentBackend(_config);
      _backend = backend;
      await for (final chunk in backend.streamReply(
        messages: contextMessages,
        ru: widget.ru,
      )) {
        buffer.write(chunk);
        if (!mounted) return;
        final index = _messages.indexWhere(
          (message) => message.id == assistant.id,
        );
        if (index < 0) return;
        final updated = List<CgAgentMessage>.from(_messages);
        updated[index] = updated[index].copyWith(text: buffer.toString());
        setState(() {
          _messages = updated;
          _entityState = _AgentEntityState.thinking;
        });
        _scrollToBottom();
      }
      final answer = buffer.toString().trim();
      if (answer.isEmpty) throw const CgAgentBackendException('empty_response');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _entityState = _AgentEntityState.idle;
      });
      await _persistHistory();
      if (_config.speakReplies) await _speak(answer);
    } catch (error) {
      if (!mounted) return;
      final index = _messages.indexWhere(
        (message) => message.id == assistant.id,
      );
      final updated = List<CgAgentMessage>.from(_messages);
      if (index >= 0) {
        updated[index] = updated[index].copyWith(
          text: buffer.isEmpty
              ? _friendlyError(error)
              : '${buffer.toString()}\n\n${_friendlyError(error)}',
          failed: true,
        );
      }
      setState(() {
        _messages = updated;
        _sending = false;
        _entityState = _AgentEntityState.error;
      });
      await _persistHistory();
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('agent_not_configured')) {
      return widget.ru
          ? 'Backend агента не настроен. Откройте настройки справа вверху.'
          : 'The agent backend is not configured. Open settings in the top right.';
    }
    if (raw.contains('SocketException') || raw.contains('connect_failed')) {
      return widget.ru
          ? 'Нет соединения с сервером агента. Проверьте адрес и сеть.'
          : 'Could not connect to the agent server. Check the endpoint and network.';
    }
    return widget.ru
        ? 'Ответ прерван. Проверьте настройки backend и повторите.'
        : 'The response was interrupted. Check the backend settings and retry.';
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _finishRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_sending || !_config.configured) {
      if (!_config.configured) await _showSettings(firstRun: true);
      return;
    }
    await _stopVoice();
    if (!await _recorder.hasPermission()) return;
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}'
        'agent_input_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordingPath = path;
      _recordingStartedAt = DateTime.now();
      _recordingElapsed = Duration.zero;
      _entityState = _AgentEntityState.listening;
    });
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _recordingStartedAt == null) return;
      final elapsed = DateTime.now().difference(_recordingStartedAt!);
      setState(() => _recordingElapsed = elapsed);
      if (elapsed >= const Duration(minutes: 3)) unawaited(_finishRecording());
    });
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final path = await _recorder.stop() ?? _recordingPath;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _entityState = _AgentEntityState.thinking;
    });
    if (path == null) return;
    final file = File(path);
    if (!await file.exists() || await file.length() < 1000) {
      if (mounted) setState(() => _entityState = _AgentEntityState.idle);
      return;
    }
    try {
      final text = await (_backend ?? CgAgentBackend(_config)).transcribe(file);
      try {
        await file.delete();
      } catch (_) {}
      if (!mounted) return;
      _composer.text = text;
      _composer.selection = TextSelection.collapsed(offset: text.length);
      await _send(explicitText: text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _entityState = _AgentEntityState.error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty || !_config.speakReplies) return;
    try {
      setState(() => _entityState = _AgentEntityState.speaking);
      final file = await (_backend ?? CgAgentBackend(_config)).synthesize(text);
      await _voicePlayer.setFilePath(file.path);
      await _voicePlayer.play();
    } catch (_) {
      if (mounted) setState(() => _entityState = _AgentEntityState.idle);
    }
  }

  Future<void> _stopVoice() async {
    if (_voicePlayer.playing) await _voicePlayer.stop();
    if (mounted && _entityState == _AgentEntityState.speaking) {
      setState(() => _entityState = _AgentEntityState.idle);
    }
  }

  Future<void> _clearHistory() async {
    await _stopVoice();
    await CgAgentStore.clearHistory();
    if (mounted) setState(() => _messages = const <CgAgentMessage>[]);
  }

  Future<void> _showSettings({bool firstRun = false}) async {
    final baseUrl = TextEditingController(text: _config.baseUrl);
    final token = TextEditingController(text: _config.apiToken);
    final model = TextEditingController(text: _config.chatModel);
    final stt = TextEditingController(text: _config.transcriptionModel);
    final tts = TextEditingController(text: _config.speechModel);
    final voice = TextEditingController(text: _config.voice);
    var draft = _config;
    var testResult = '';
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.ru ? 'Настройки агента' : 'Agent settings',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.ru
                      ? 'Поддерживается OpenAI‑совместимый API, включая локальный сервер. Секрет не зашит в приложение и сохраняется только на этом устройстве.'
                      : 'An OpenAI-compatible API is supported, including a local server. No secret is embedded in the app; the token stays on this device.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: baseUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'http://192.168.1.10:11434',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: token,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.ru
                        ? 'Токен (необязательно)'
                        : 'Token (optional)',
                    prefixIcon: const Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: model,
                  decoration: InputDecoration(
                    labelText: widget.ru ? 'Модель чата' : 'Chat model',
                    prefixIcon: const Icon(Icons.psychology_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stt,
                        decoration: const InputDecoration(
                          labelText: 'STT model',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tts,
                        decoration: const InputDecoration(
                          labelText: 'TTS model',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: voice,
                  decoration: InputDecoration(
                    labelText: widget.ru ? 'Голос' : 'Voice',
                    prefixIcon: const Icon(Icons.record_voice_over_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: draft.speakReplies,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(speakReplies: value),
                  ),
                  title: Text(
                    widget.ru ? 'Озвучивать ответы' : 'Speak replies',
                  ),
                ),
                SwitchListTile(
                  value: draft.memoryEnabled,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(memoryEnabled: value),
                  ),
                  title: Text(
                    widget.ru ? 'Память диалога' : 'Conversation memory',
                  ),
                ),
                const Divider(),
                Text(
                  widget.ru ? 'Разрешения инструментов' : 'Tool permissions',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                SwitchListTile(
                  value: draft.allowSearch,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowSearch: value),
                  ),
                  title: Text(widget.ru ? 'Интернет‑поиск' : 'Web search'),
                  subtitle: Text(
                    widget.ru
                        ? 'Разрешение само по себе не даёт доступ: инструмент должен быть подключён на backend.'
                        : 'Permission alone grants no access: the backend must expose the tool.',
                  ),
                ),
                SwitchListTile(
                  value: draft.allowFiles,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowFiles: value),
                  ),
                  title: Text(widget.ru ? 'Файлы' : 'Files'),
                ),
                SwitchListTile(
                  value: draft.allowContacts,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowContacts: value),
                  ),
                  title: Text(widget.ru ? 'Контакты' : 'Contacts'),
                ),
                if (testResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      testResult,
                      style: TextStyle(
                        color: testResult.startsWith('✓')
                            ? ChernogramColors.success
                            : ChernogramColors.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing
                            ? null
                            : () async {
                                final candidate = draft.copyWith(
                                  baseUrl: baseUrl.text.trim(),
                                  apiToken: token.text,
                                  chatModel: model.text.trim(),
                                  transcriptionModel: stt.text.trim(),
                                  speechModel: tts.text.trim(),
                                  voice: voice.text.trim(),
                                );
                                setSheetState(() {
                                  _testing = true;
                                  testResult = '';
                                });
                                final ok = await CgAgentBackend(
                                  candidate,
                                ).testConnection();
                                setSheetState(() {
                                  _testing = false;
                                  testResult = ok
                                      ? '✓ ${widget.ru ? 'Сервер отвечает' : 'Server responded'}'
                                      : '✕ ${widget.ru ? 'Нет соединения' : 'Connection failed'}';
                                });
                              },
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text(widget.ru ? 'Проверить' : 'Test'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          final candidate = draft.copyWith(
                            baseUrl: baseUrl.text.trim(),
                            apiToken: token.text,
                            chatModel: model.text.trim(),
                            transcriptionModel: stt.text.trim(),
                            speechModel: tts.text.trim(),
                            voice: voice.text.trim(),
                          );
                          await CgAgentStore.saveConfig(candidate);
                          if (!candidate.memoryEnabled) {
                            await CgAgentStore.clearHistory();
                          }
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          _backend?.close();
                          if (mounted) {
                            setState(() {
                              _config = candidate;
                              _backend = CgAgentBackend(candidate);
                              if (!candidate.memoryEnabled) {
                                _messages = const <CgAgentMessage>[];
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: Text(widget.ru ? 'Сохранить' : 'Save'),
                      ),
                    ),
                  ],
                ),
                if (!firstRun) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () async {
                        await _clearHistory();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(
                        widget.ru ? 'Очистить историю' : 'Clear history',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    baseUrl.dispose();
    token.dispose();
    model.dispose();
    stt.dispose();
    tts.dispose();
    voice.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    unawaited(_recorder.dispose());
    unawaited(_voiceStateSubscription?.cancel());
    unawaited(_voicePlayer.dispose());
    _backend?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 4),
            child: Row(
              children: [
                _AgentEntity(state: _entityState, size: 54),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ru ? 'Цифровой агент' : 'Digital agent',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _config.configured
                            ? (widget.ru ? 'Готов к диалогу' : 'Ready to talk')
                            : (widget.ru
                                  ? 'Нужно подключить интеллект'
                                  : 'Connect an intelligence backend'),
                        style: TextStyle(
                          fontSize: 11,
                          color: _config.configured
                              ? ChernogramColors.success
                              : scheme.onSurface.withValues(alpha: .48),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: widget.privacyLens
                      ? (widget.ru ? 'Показать' : 'Show')
                      : (widget.ru ? 'Скрыть' : 'Hide'),
                  onPressed: widget.onTogglePrivacy,
                  icon: Icon(
                    widget.privacyLens
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
                IconButton(
                  tooltip: widget.ru ? 'Настройки агента' : 'Agent settings',
                  onPressed: _showSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? _AgentWelcome(
                    ru: widget.ru,
                    configured: _config.configured,
                    onConfigure: () => _showSettings(firstRun: true),
                    entityState: _entityState,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _AgentBubble(
                      message: _messages[index],
                      mine: _messages[index].role == 'user',
                      privacyLens: widget.privacyLens,
                      profile: widget.profile,
                    ),
                  ),
          ),
          if (_recording)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded, color: ChernogramColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.ru ? 'Слушаю' : 'Listening'} • '
                      '${_recordingElapsed.inMinutes.toString().padLeft(2, '0')}:'
                      '${(_recordingElapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: _finishRecording,
                    child: Text(widget.ru ? 'Отправить' : 'Send'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: GlassPanel(
              blur: 10,
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
              borderRadius: BorderRadius.circular(22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _recording
                        ? (widget.ru ? 'Остановить запись' : 'Stop recording')
                        : (widget.ru ? 'Голосовой вопрос' : 'Voice question'),
                    onPressed: _sending ? null : _toggleRecording,
                    color: _recording ? ChernogramColors.danger : null,
                    icon: Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending && !_recording,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: widget.ru
                            ? 'Напишите агенту…'
                            : 'Message the agent…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: widget.ru ? 'Отправить' : 'Send',
                    onPressed: _sending || _recording ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentWelcome extends StatelessWidget {
  final bool ru;
  final bool configured;
  final VoidCallback onConfigure;
  final _AgentEntityState entityState;

  const _AgentWelcome({
    required this.ru,
    required this.configured,
    required this.onConfigure,
    required this.entityState,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AgentEntity(state: entityState, size: 150),
          const SizedBox(height: 18),
          Text(
            configured
                ? (ru ? 'Я на связи' : 'I am ready')
                : (ru ? 'Подключите интеллект' : 'Connect intelligence'),
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            configured
                ? (ru
                      ? 'Пишите или нажмите микрофон. Ответ появляется по мере генерации и может быть озвучен.'
                      : 'Type or tap the microphone. Replies stream as they are generated and can be spoken aloud.')
                : (ru
                      ? 'Укажите OpenAI‑совместимый сервер: локальный Ollama, собственную модель или ваш защищённый AI‑gateway.'
                      : 'Provide an OpenAI-compatible server: local Ollama, your own model or a secure AI gateway.'),
            textAlign: TextAlign.center,
          ),
          if (!configured) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onConfigure,
              icon: const Icon(Icons.link_rounded),
              label: Text(ru ? 'Подключить backend' : 'Connect backend'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _AgentBubble extends StatelessWidget {
  final CgAgentMessage message;
  final bool mine;
  final bool privacyLens;
  final CgProfile profile;

  const _AgentBubble({
    required this.message,
    required this.mine,
    required this.privacyLens,
    required this.profile,
  });

  Widget _avatar(BuildContext context) {
    if (!mine) return const ChernogramLogo(size: 30);
    final raw = profile.avatarBase64;
    if (raw != null && raw.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 15,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: 15,
      child: Text(
        profile.nickname.trim().isEmpty
            ? '?'
            : profile.nickname.trim().characters.first.toUpperCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = privacyLens ? '••••••••••••' : message.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!mine) ...[_avatar(context), const SizedBox(width: 7)],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 680),
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
              decoration: BoxDecoration(
                color: mine
                    ? scheme.primary.withValues(alpha: .20)
                    : message.failed
                    ? scheme.errorContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 5),
                  bottomRight: Radius.circular(mine ? 5 : 18),
                ),
              ),
              child: SelectableText(
                text.isEmpty ? '…' : text,
                style: TextStyle(
                  height: 1.35,
                  color: message.failed ? scheme.onErrorContainer : null,
                ),
              ),
            ),
          ),
          if (mine) ...[const SizedBox(width: 7), _avatar(context)],
        ],
      ),
    );
  }
}

class _AgentEntity extends StatefulWidget {
  final _AgentEntityState state;
  final double size;

  const _AgentEntity({required this.state, required this.size});

  @override
  State<_AgentEntity> createState() => _AgentEntityWidgetState();
}

class _AgentEntityWidgetState extends State<_AgentEntity>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 130),
  );
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 1800 + DateTime.now().millisecond * 3),
      () async {
        if (!mounted) return;
        await _blink.forward();
        await _blink.reverse();
        _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _pulse.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_pulse, _blink]),
      builder: (context, _) {
        final active = widget.state != _AgentEntityState.idle;
        final scale = active ? .98 + _pulse.value * .05 : 1.0;
        final glow = switch (widget.state) {
          _AgentEntityState.listening => ChernogramColors.danger,
          _AgentEntityState.thinking => scheme.primary,
          _AgentEntityState.speaking => scheme.secondary,
          _AgentEntityState.error => scheme.error,
          _ => scheme.primary,
        };
        return Transform.scale(
          scale: scale,
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: widget.size * .82,
                  height: widget.size * .82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: glow.withValues(
                          alpha: active ? .20 + _pulse.value * .15 : .08,
                        ),
                        blurRadius: widget.size * (.18 + _pulse.value * .10),
                        spreadRadius: widget.size * .01,
                      ),
                    ],
                  ),
                ),
                ChernogramLogo(size: widget.size),
                Positioned(
                  top: widget.size * .39,
                  child: Transform.scale(
                    scaleY: 1 - _blink.value * .92,
                    child: Row(
                      children: [
                        _eye(widget.size, glow),
                        SizedBox(width: widget.size * .12),
                        _eye(widget.size, glow),
                      ],
                    ),
                  ),
                ),
                if (widget.state == _AgentEntityState.speaking)
                  Positioned(
                    top: widget.size * .58,
                    child: SizedBox(
                      width: widget.size * .30,
                      height: widget.size * .12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List<Widget>.generate(5, (index) {
                          final phase = (_pulse.value + index * .19) % 1;
                          return Container(
                            width: widget.size * .025,
                            height: widget.size * (.035 + phase * .07),
                            decoration: BoxDecoration(
                              color: glow,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _eye(double size, Color color) => Container(
    width: size * .11,
    height: mathMax(2, size * .018),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
  );

  double mathMax(num left, num right) =>
      left > right ? left.toDouble() : right.toDouble();
}
