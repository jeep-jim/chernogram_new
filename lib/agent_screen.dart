import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'agent_core.dart';
import 'brand.dart';
import 'core_models.dart';

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

class _CgAgentScreenState extends State<CgAgentScreen>
    with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<CgAgentMessage> _messages = <CgAgentMessage>[];
  CgAgentSettings _settings = const CgAgentSettings();
  String _sessionToken = '';
  bool _loading = true;
  bool _sending = false;
  bool _listening = false;
  bool _speaking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configureTts();
    unawaited(_load());
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage(widget.ru ? 'ru-RU' : 'en-US');
    await _tts.setSpeechRate(_settings.voiceRate);
    _tts.setStartHandler(() {
      if (mounted) setState(() => _speaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      CgAgentStore.loadMessages(),
      CgAgentStore.loadSettings(),
    ]);
    if (!mounted) return;
    setState(() {
      _messages = values[0] as List<CgAgentMessage>;
      _settings = values[1] as CgAgentSettings;
      _loading = false;
    });
    await _tts.setSpeechRate(_settings.voiceRate);
    _scrollToBottom(jump: true);
  }

  @override
  void didUpdateWidget(covariant CgAgentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ru != widget.ru) {
      unawaited(_tts.setLanguage(widget.ru ? 'ru-RU' : 'en-US'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _listening) {
      unawaited(_stopListening());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    unawaited(_speech.cancel());
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    await _tts.stop();

    final user = CgAgentMessage(
      id: CgIds.random(20),
      role: CgAgentRole.user,
      text: text,
      createdAt: DateTime.now().toUtc(),
    );
    final responseId = CgIds.random(20);
    final pending = CgAgentMessage(
      id: responseId,
      role: CgAgentRole.assistant,
      text: '',
      createdAt: DateTime.now().toUtc(),
    );
    setState(() {
      _messages = <CgAgentMessage>[..._messages, user, pending];
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    await _persist();

    final provider = _settings.endpoint.trim().isEmpty
        ? CgLocalAgentProvider()
        : CgOpenAiCompatibleProvider();
    var answer = '';
    try {
      await for (final chunk in provider.streamReply(
        messages: _messages.where((item) => item.id != responseId).toList(),
        settings: _settings,
        ru: widget.ru,
        sessionToken: _sessionToken,
      )) {
        answer += chunk;
        if (!mounted) break;
        _replaceMessage(responseId, pending.copyWith(text: answer));
        _scrollToBottom();
      }
      if (answer.trim().isEmpty) {
        throw StateError(
          widget.ru
              ? 'Сервер вернул пустой ответ.'
              : 'The server returned an empty response.',
        );
      }
      await _persist();
      if (_settings.autoSpeak && mounted) await _speak(answer);
    } catch (error) {
      final message = widget.ru
          ? 'Не удалось получить ответ: $error'
          : 'Could not get a reply: $error';
      if (mounted) {
        _replaceMessage(
          responseId,
          pending.copyWith(text: message, failed: true),
        );
        setState(() => _error = message);
      }
      await _persist();
    } finally {
      await provider.close();
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _replaceMessage(String id, CgAgentMessage next) {
    if (!mounted) return;
    final index = _messages.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final copy = <CgAgentMessage>[..._messages];
    copy[index] = next;
    setState(() => _messages = copy);
  }

  Future<void> _persist() async {
    if (_settings.rememberConversation) {
      await CgAgentStore.saveMessages(_messages);
    }
  }

  Future<void> _speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (_speaking) {
      await _tts.stop();
      return;
    }
    await _tts.setLanguage(widget.ru ? 'ru-RU' : 'en-US');
    await _tts.setSpeechRate(_settings.voiceRate);
    await _tts.speak(clean);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stopListening();
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        final active = status == 'listening';
        if (_listening != active) setState(() => _listening = active);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = error.errorMsg;
        });
      },
    );
    if (!available) {
      if (mounted) {
        setState(() {
          _error = widget.ru
              ? 'На устройстве недоступно распознавание речи.'
              : 'Speech recognition is unavailable on this device.';
        });
      }
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
    await _speech.listen(
      localeId: widget.ru ? 'ru_RU' : 'en_US',
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 4),
      partialResults: true,
      onResult: (result) {
        _input.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(
            offset: result.recognizedWords.length,
          ),
        );
        if (result.finalResult && mounted) setState(() => _listening = false);
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _clearMemory() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.ru ? 'Очистить память?' : 'Clear memory?'),
        content: Text(
          widget.ru
              ? 'Будет удалена только локальная история Агента.'
              : 'Only the local Agent conversation will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.ru ? 'Очистить' : 'Clear'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await CgAgentStore.clearMessages();
    if (mounted) setState(() => _messages = <CgAgentMessage>[]);
  }

  Future<void> _showSettings() async {
    final endpoint = TextEditingController(text: _settings.endpoint);
    final model = TextEditingController(text: _settings.model);
    final token = TextEditingController(text: _sessionToken);
    var draft = _settings;
    final result = await showModalBottomSheet<CgAgentSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.ru ? 'Настройки Агента' : 'Agent settings',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.ru
                      ? 'Работает с Ollama и любым OpenAI-compatible сервером. Токен хранится только до закрытия приложения.'
                      : 'Works with Ollama and any OpenAI-compatible server. The token is kept only until the app closes.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.computer_rounded, size: 18),
                      label: Text(
                        widget.ru ? 'Ollama на этом ПК' : 'Ollama on this PC',
                      ),
                      onPressed: () {
                        endpoint.text =
                            'http://127.0.0.1:11434/v1/chat/completions';
                        model.text = 'qwen2.5:3b';
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.offline_bolt_rounded, size: 18),
                      label: Text(widget.ru ? 'Локальный режим' : 'Local mode'),
                      onPressed: () => endpoint.clear(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: endpoint,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: widget.ru ? 'Адрес AI-сервера' : 'AI server URL',
                    hintText: 'http://192.168.1.10:11434/v1/chat/completions',
                    prefixIcon: const Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: model,
                  decoration: InputDecoration(
                    labelText: widget.ru ? 'Модель' : 'Model',
                    prefixIcon: const Icon(Icons.psychology_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: token,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.ru
                        ? 'Токен текущего сеанса, необязательно'
                        : 'Session token, optional',
                    prefixIcon: const Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.ru ? 'Запоминать диалог' : 'Remember conversation',
                  ),
                  value: draft.rememberConversation,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(rememberConversation: value),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.ru ? 'Озвучивать ответы' : 'Speak replies',
                  ),
                  value: draft.autoSpeak,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(autoSpeak: value),
                  ),
                ),
                Text(widget.ru ? 'Скорость голоса' : 'Voice speed'),
                Slider(
                  min: .25,
                  max: .75,
                  value: draft.voiceRate,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(voiceRate: value),
                  ),
                ),
                const Divider(height: 28),
                Text(
                  widget.ru ? 'Разрешения Агента' : 'Agent permissions',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                _permissionSwitch(
                  title: widget.ru ? 'Контекст чатов' : 'Chat context',
                  value: draft.allowChatContext,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowChatContext: value),
                  ),
                ),
                _permissionSwitch(
                  title: widget.ru ? 'Файлы' : 'Files',
                  value: draft.allowFiles,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowFiles: value),
                  ),
                ),
                _permissionSwitch(
                  title: widget.ru ? 'Контакты' : 'Contacts',
                  value: draft.allowContacts,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowContacts: value),
                  ),
                ),
                _permissionSwitch(
                  title: widget.ru ? 'Интернет-поиск' : 'Web search',
                  value: draft.allowWebSearch,
                  onChanged: (value) => setSheetState(
                    () => draft = draft.copyWith(allowWebSearch: value),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(_clearMemory());
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          widget.ru ? 'Очистить память' : 'Clear memory',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          _sessionToken = token.text.trim();
                          Navigator.pop(
                            context,
                            draft.copyWith(
                              endpoint: endpoint.text.trim(),
                              model: model.text.trim().isEmpty
                                  ? 'qwen2.5:3b'
                                  : model.text.trim(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.save_outlined),
                        label: Text(widget.ru ? 'Сохранить' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    endpoint.dispose();
    model.dispose();
    token.dispose();
    if (result == null) return;
    await CgAgentStore.saveSettings(result);
    if (!mounted) return;
    setState(() => _settings = result);
    await _tts.setSpeechRate(result.voiceRate);
  }

  Widget _permissionSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title),
    subtitle: Text(
      widget.ru
          ? 'Доступ выключен по умолчанию и включается только вами.'
          : 'Disabled by default and enabled only by you.',
      style: const TextStyle(fontSize: 11),
    ),
    value: value,
    onChanged: onChanged,
  );

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 6),
          child: Row(
            children: [
              _AgentMask(size: 48, thinking: _sending, speaking: _speaking),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.ru ? 'Агент' : 'Agent',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _speaking
                          ? (widget.ru ? 'говорит…' : 'speaking…')
                          : _listening
                          ? (widget.ru ? 'слушает…' : 'listening…')
                          : _sending
                          ? (widget.ru ? 'думает…' : 'thinking…')
                          : _settings.endpoint.trim().isEmpty
                          ? (widget.ru ? 'локальный режим' : 'local mode')
                          : '${_settings.model} · online',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: widget.ru ? 'Остановить голос' : 'Stop voice',
                onPressed: _speaking ? _tts.stop : null,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
              IconButton(
                tooltip: widget.ru ? 'Настройки Агента' : 'Agent settings',
                onPressed: _showSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? _AgentWelcome(
                  ru: widget.ru,
                  online: _settings.endpoint.trim().isNotEmpty,
                  onSettings: _showSettings,
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _AgentMessageBubble(
                      message: message,
                      profile: widget.profile,
                      ru: widget.ru,
                      speaking: _speaking && index == _messages.length - 1,
                      onSpeak:
                          message.role == CgAgentRole.assistant &&
                              message.text.trim().isNotEmpty
                          ? () => _speak(message.text)
                          : null,
                    );
                  },
                ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: scheme.errorContainer.withValues(alpha: .55),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 11),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: widget.ru ? 'Голосовой ввод' : 'Voice input',
                  onPressed: _sending ? null : _toggleListening,
                  icon: Icon(
                    _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _listening ? scheme.error : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: widget.ru
                          ? 'Напишите Агенту…'
                          : 'Message the Agent…',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: widget.ru ? 'Отправить' : 'Send',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AgentWelcome extends StatelessWidget {
  final bool ru;
  final bool online;
  final VoidCallback onSettings;

  const _AgentWelcome({
    required this.ru,
    required this.online,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _AgentMask(size: 126, thinking: false, speaking: false),
          const SizedBox(height: 18),
          Text(
            ru ? 'Цифровой Агент Cernogram' : 'Cernogram Digital Agent',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            online
                ? (ru
                      ? 'Можно писать или говорить. Ответы приходят потоком, история и доступы контролируются вами.'
                      : 'Type or speak. Replies stream in, and you control memory and permissions.')
                : (ru
                      ? 'Сейчас включён безопасный локальный режим. Подключите Ollama или свой AI-сервер в настройках.'
                      : 'Safe local mode is active. Connect Ollama or your AI server in settings.'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onSettings,
            icon: const Icon(Icons.tune_rounded),
            label: Text(ru ? 'Настроить интеллект' : 'Configure intelligence'),
          ),
        ],
      ),
    ),
  );
}

class _AgentMessageBubble extends StatelessWidget {
  final CgAgentMessage message;
  final CgProfile profile;
  final bool ru;
  final bool speaking;
  final VoidCallback? onSpeak;

  const _AgentMessageBubble({
    required this.message,
    required this.profile,
    required this.ru,
    required this.speaking,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final own = message.role == CgAgentRole.user;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!own) ...[
            _AgentMask(
              size: 34,
              thinking: message.text.isEmpty,
              speaking: speaking,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: message.text.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ru ? 'Текст скопирован' : 'Text copied',
                          ),
                        ),
                      );
                    },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 640),
                padding: const EdgeInsets.fromLTRB(13, 10, 10, 9),
                decoration: BoxDecoration(
                  color: own
                      ? scheme.primary.withValues(alpha: .92)
                      : message.failed
                      ? scheme.errorContainer
                      : scheme.surfaceContainerHighest.withValues(alpha: .80),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(own ? 18 : 5),
                    bottomRight: Radius.circular(own ? 5 : 18),
                  ),
                ),
                child: message.text.isEmpty
                    ? const _TypingDots()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            message.text,
                            style: TextStyle(
                              color: own ? Colors.white : null,
                              height: 1.34,
                            ),
                          ),
                          if (!own && onSpeak != null) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: ru ? 'Озвучить' : 'Speak',
                                onPressed: onSpeak,
                                icon: Icon(
                                  speaking
                                      ? Icons.stop_circle_outlined
                                      : Icons.volume_up_outlined,
                                  size: 19,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
          if (own) ...[
            const SizedBox(width: 7),
            _ProfileAvatar(profile: profile, size: 34),
          ],
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final CgProfile profile;
  final double size;

  const _ProfileAvatar({required this.profile, required this.size});

  @override
  Widget build(BuildContext context) {
    final raw = profile.avatarBase64;
    if (raw != null && raw.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {}
    }
    final letter = profile.nickname.trim().isEmpty
        ? '?'
        : profile.nickname.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AgentMask extends StatefulWidget {
  final double size;
  final bool thinking;
  final bool speaking;

  const _AgentMask({
    required this.size,
    required this.thinking,
    required this.speaking,
  });

  @override
  State<_AgentMask> createState() => _AgentMaskState();
}

class _AgentMaskState extends State<_AgentMask>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _AgentMask oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.thinking || widget.speaking) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final pulse = widget.thinking || widget.speaking
          ? .96 + _controller.value * .06
          : 1.0;
      return SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: pulse,
              child: ChernogramLogo(size: widget.size),
            ),
            if (widget.speaking)
              Positioned(
                bottom: widget.size * .08,
                child: _SpeakingWaves(width: widget.size * .40),
              ),
          ],
        ),
      );
    },
  );
}

class _SpeakingWaves extends StatefulWidget {
  final double width;

  const _SpeakingWaves({required this.width});

  @override
  State<_SpeakingWaves> createState() => _SpeakingWavesState();
}

class _SpeakingWavesState extends State<_SpeakingWaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List<Widget>.generate(5, (index) {
        final phase = (_controller.value + index * .17) % 1;
        final height =
            widget.width * (.06 + .12 * (1 - (phase - .5).abs() * 2));
        return Container(
          width: widget.width * .07,
          height: height,
          margin: EdgeInsets.symmetric(horizontal: widget.width * .02),
          decoration: BoxDecoration(
            color: ChernogramColors.goldLight,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    ),
  );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (index) {
        final phase = (_controller.value + index * .23) % 1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Transform.translate(
            offset: Offset(0, -3 * (1 - (phase - .5).abs() * 2)),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    ),
  );
}
