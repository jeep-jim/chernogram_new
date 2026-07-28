import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core_models.dart';

enum CgAgentRole { user, assistant, system }

class CgAgentMessage {
  final String id;
  final CgAgentRole role;
  final String text;
  final DateTime createdAt;
  final bool failed;

  const CgAgentMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.failed = false,
  });

  CgAgentMessage copyWith({String? text, bool? failed}) => CgAgentMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        createdAt: createdAt,
        failed: failed ?? this.failed,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.name,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (failed) 'failed': true,
      };

  factory CgAgentMessage.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role']?.toString();
    return CgAgentMessage(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString()
          : CgIds.random(20),
      role: CgAgentRole.values.firstWhere(
        (item) => item.name == rawRole,
        orElse: () => CgAgentRole.user,
      ),
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      failed: json['failed'] == true,
    );
  }
}

class CgAgentSettings {
  final String endpoint;
  final String model;
  final bool rememberConversation;
  final bool autoSpeak;
  final bool allowChatContext;
  final bool allowFiles;
  final bool allowContacts;
  final bool allowWebSearch;
  final double voiceRate;

  const CgAgentSettings({
    this.endpoint = '',
    this.model = 'qwen2.5:3b',
    this.rememberConversation = true,
    this.autoSpeak = false,
    this.allowChatContext = false,
    this.allowFiles = false,
    this.allowContacts = false,
    this.allowWebSearch = false,
    this.voiceRate = .46,
  });

  CgAgentSettings copyWith({
    String? endpoint,
    String? model,
    bool? rememberConversation,
    bool? autoSpeak,
    bool? allowChatContext,
    bool? allowFiles,
    bool? allowContacts,
    bool? allowWebSearch,
    double? voiceRate,
  }) =>
      CgAgentSettings(
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
        rememberConversation:
            rememberConversation ?? this.rememberConversation,
        autoSpeak: autoSpeak ?? this.autoSpeak,
        allowChatContext: allowChatContext ?? this.allowChatContext,
        allowFiles: allowFiles ?? this.allowFiles,
        allowContacts: allowContacts ?? this.allowContacts,
        allowWebSearch: allowWebSearch ?? this.allowWebSearch,
        voiceRate: voiceRate ?? this.voiceRate,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'endpoint': endpoint,
        'model': model,
        'rememberConversation': rememberConversation,
        'autoSpeak': autoSpeak,
        'allowChatContext': allowChatContext,
        'allowFiles': allowFiles,
        'allowContacts': allowContacts,
        'allowWebSearch': allowWebSearch,
        'voiceRate': voiceRate,
      };

  factory CgAgentSettings.fromJson(Map<String, dynamic> json) =>
      CgAgentSettings(
        endpoint: json['endpoint']?.toString() ?? '',
        model: json['model']?.toString().trim().isNotEmpty == true
            ? json['model'].toString()
            : 'qwen2.5:3b',
        rememberConversation: json['rememberConversation'] != false,
        autoSpeak: json['autoSpeak'] == true,
        allowChatContext: json['allowChatContext'] == true,
        allowFiles: json['allowFiles'] == true,
        allowContacts: json['allowContacts'] == true,
        allowWebSearch: json['allowWebSearch'] == true,
        voiceRate:
            (double.tryParse(json['voiceRate']?.toString() ?? '') ?? .46)
                .clamp(.25, .75)
                .toDouble(),
      );
}

class CgAgentStore {
  static const _messagesKey = 'cg_agent_messages_v1';
  static const _settingsKey = 'cg_agent_settings_v1';

  static Future<List<CgAgentMessage>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_messagesKey);
    if (raw == null || raw.isEmpty) return <CgAgentMessage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CgAgentMessage>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => CgAgentMessage.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.text.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return <CgAgentMessage>[];
    }
  }

  static Future<void> saveMessages(List<CgAgentMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final tail = messages.length > 300
        ? messages.sublist(messages.length - 300)
        : messages;
    await prefs.setString(
      _messagesKey,
      jsonEncode(tail.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesKey);
  }

  static Future<CgAgentSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const CgAgentSettings();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? CgAgentSettings.fromJson(Map<String, dynamic>.from(decoded))
          : const CgAgentSettings();
    } catch (_) {
      return const CgAgentSettings();
    }
  }

  static Future<void> saveSettings(CgAgentSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}

abstract class CgAgentProvider {
  Stream<String> streamReply({
    required List<CgAgentMessage> messages,
    required CgAgentSettings settings,
    required bool ru,
    String? sessionToken,
  });

  Future<void> close();
}

class CgLocalAgentProvider implements CgAgentProvider {
  @override
  Stream<String> streamReply({
    required List<CgAgentMessage> messages,
    required CgAgentSettings settings,
    required bool ru,
    String? sessionToken,
  }) async* {
    final request = messages.lastOrNull?.text.toLowerCase() ?? '';
    final answer = request.contains('привет') || request.contains('hello')
        ? (ru
            ? 'Привет. Я Агент Cernogram. Сейчас я работаю в локальном режиме. Открой мои настройки и выбери Ollama или укажи OpenAI-compatible сервер — после этого ответы станут полноценными и потоковыми.'
            : 'Hello. I am the Cernogram Agent. I am currently in local mode. Open my settings and select Ollama or enter an OpenAI-compatible server for full streaming replies.')
        : (ru
            ? 'Локальный режим активен. Я сохранил запрос, но для полноценного ответа нужна модель. В настройках можно выбрать «Ollama на этом компьютере» или указать адрес своего OpenAI-compatible сервера. Ключ в приложение не зашивается.'
            : 'Local mode is active. I saved the request, but a model is required for a full answer. In settings, select Ollama on this computer or enter your OpenAI-compatible server. No key is embedded in the app.');
    for (final part in answer.split(RegExp(r'(?<=\s)'))) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      yield part;
    }
  }

  @override
  Future<void> close() async {}
}

class CgOpenAiCompatibleProvider implements CgAgentProvider {
  final http.Client _client = http.Client();

  @override
  Stream<String> streamReply({
    required List<CgAgentMessage> messages,
    required CgAgentSettings settings,
    required bool ru,
    String? sessionToken,
  }) async* {
    final endpoint = _normalizeEndpoint(settings.endpoint);
    if (endpoint == null) {
      throw const FormatException('Agent endpoint is empty');
    }
    final request = http.Request('POST', endpoint)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream, application/json';
    final token = sessionToken?.trim() ?? '';
    if (token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.body = jsonEncode(<String, dynamic>{
      'model': settings.model,
      'stream': true,
      'temperature': .65,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'system',
          'content': _systemPrompt(settings, ru),
        },
        ...messages
            .where((item) => item.role != CgAgentRole.system)
            .map(
              (item) => <String, String>{
                'role': item.role == CgAgentRole.assistant
                    ? 'assistant'
                    : 'user',
                'content': item.text,
              },
            ),
      ],
    });

    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw http.ClientException(
        'Agent server ${response.statusCode}: ${body.length > 300 ? body.substring(0, 300) : body}',
        endpoint,
      );
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body);
      final text = _extractFullText(decoded);
      if (text.isNotEmpty) yield text;
      return;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') {
        if (payload == '[DONE]') break;
        continue;
      }
      try {
        final decoded = jsonDecode(payload);
        final chunk = _extractDelta(decoded);
        if (chunk.isNotEmpty) yield chunk;
      } catch (_) {
        // Ignore keep-alive or vendor-specific frames.
      }
    }
  }

  Uri? _normalizeEndpoint(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'http://$value';
    var uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') path = '/v1/chat/completions';
    if (path.endsWith('/v1')) path = '$path/chat/completions';
    if (!path.contains('chat/completions')) {
      path = '${path.endsWith('/') ? path.substring(0, path.length - 1) : path}/chat/completions';
    }
    uri = uri.replace(path: path);
    return uri;
  }

  String _systemPrompt(CgAgentSettings settings, bool ru) {
    final permissions = <String>[
      if (settings.allowChatContext) 'chat-context',
      if (settings.allowFiles) 'files',
      if (settings.allowContacts) 'contacts',
      if (settings.allowWebSearch) 'web-search',
    ];
    return ru
        ? 'Ты цифровой Агент внутри Cernogram. Отвечай по-русски ясно и по делу. Не утверждай, что выполнил действие, если клиент не передал результат инструмента. Доступы пользователя: ${permissions.isEmpty ? 'никаких' : permissions.join(', ')}.'
        : 'You are the digital Agent inside Cernogram. Be clear and practical. Never claim an action succeeded unless the client supplied a tool result. User permissions: ${permissions.isEmpty ? 'none' : permissions.join(', ')}.';
  }

  String _extractDelta(dynamic decoded) {
    if (decoded is! Map) return '';
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = choices.first as Map;
      final delta = choice['delta'];
      if (delta is Map) return delta['content']?.toString() ?? '';
      final message = choice['message'];
      if (message is Map) return message['content']?.toString() ?? '';
      return choice['text']?.toString() ?? '';
    }
    return decoded['response']?.toString() ??
        decoded['content']?.toString() ??
        '';
  }

  String _extractFullText(dynamic decoded) => _extractDelta(decoded);

  @override
  Future<void> close() async => _client.close();
}

extension _AgentIterableExtension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
