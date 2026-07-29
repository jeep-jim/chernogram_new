import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CgAgentMessage {
  final String id;
  final String role;
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
    'role': role,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'failed': failed,
  };

  factory CgAgentMessage.fromJson(Map<String, dynamic> json) => CgAgentMessage(
    id: json['id']?.toString() ?? '',
    role: json['role']?.toString() ?? 'user',
    text: json['text']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    failed: json['failed'] == true,
  );
}

class CgAgentConfig {
  final String baseUrl;
  final String apiToken;
  final String chatModel;
  final String transcriptionModel;
  final String speechModel;
  final String voice;
  final bool speakReplies;
  final bool memoryEnabled;
  final bool allowContacts;
  final bool allowFiles;
  final bool allowSearch;

  const CgAgentConfig({
    this.baseUrl = '',
    this.apiToken = '',
    this.chatModel = 'gpt-oss:20b',
    this.transcriptionModel = 'whisper-1',
    this.speechModel = 'tts-1',
    this.voice = 'alloy',
    this.speakReplies = true,
    this.memoryEnabled = true,
    this.allowContacts = false,
    this.allowFiles = false,
    this.allowSearch = false,
  });

  bool get configured {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        chatModel.trim().isNotEmpty;
  }

  CgAgentConfig copyWith({
    String? baseUrl,
    String? apiToken,
    String? chatModel,
    String? transcriptionModel,
    String? speechModel,
    String? voice,
    bool? speakReplies,
    bool? memoryEnabled,
    bool? allowContacts,
    bool? allowFiles,
    bool? allowSearch,
  }) => CgAgentConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    apiToken: apiToken ?? this.apiToken,
    chatModel: chatModel ?? this.chatModel,
    transcriptionModel: transcriptionModel ?? this.transcriptionModel,
    speechModel: speechModel ?? this.speechModel,
    voice: voice ?? this.voice,
    speakReplies: speakReplies ?? this.speakReplies,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    allowContacts: allowContacts ?? this.allowContacts,
    allowFiles: allowFiles ?? this.allowFiles,
    allowSearch: allowSearch ?? this.allowSearch,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseUrl': baseUrl,
    'apiToken': apiToken,
    'chatModel': chatModel,
    'transcriptionModel': transcriptionModel,
    'speechModel': speechModel,
    'voice': voice,
    'speakReplies': speakReplies,
    'memoryEnabled': memoryEnabled,
    'allowContacts': allowContacts,
    'allowFiles': allowFiles,
    'allowSearch': allowSearch,
  };

  factory CgAgentConfig.fromJson(Map<String, dynamic> json) => CgAgentConfig(
    baseUrl: json['baseUrl']?.toString() ?? '',
    apiToken: json['apiToken']?.toString() ?? '',
    chatModel: json['chatModel']?.toString() ?? 'gpt-oss:20b',
    transcriptionModel: json['transcriptionModel']?.toString() ?? 'whisper-1',
    speechModel: json['speechModel']?.toString() ?? 'tts-1',
    voice: json['voice']?.toString() ?? 'alloy',
    speakReplies: json['speakReplies'] != false,
    memoryEnabled: json['memoryEnabled'] != false,
    allowContacts: json['allowContacts'] == true,
    allowFiles: json['allowFiles'] == true,
    allowSearch: json['allowSearch'] == true,
  );
}

class CgAgentStore {
  static const String _configKey = 'cg_agent_config_v1';
  static const String _historyKey = 'cg_agent_history_v1';

  static Future<CgAgentConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return const CgAgentConfig();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? CgAgentConfig.fromJson(Map<String, dynamic>.from(decoded))
          : const CgAgentConfig();
    } catch (_) {
      return const CgAgentConfig();
    }
  }

  static Future<void> saveConfig(CgAgentConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  static Future<List<CgAgentMessage>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const <CgAgentMessage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CgAgentMessage>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => CgAgentMessage.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((message) => message.id.isNotEmpty && message.text.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <CgAgentMessage>[];
    }
  }

  static Future<void> saveHistory(List<CgAgentMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final start = messages.length > 120 ? messages.length - 120 : 0;
    await prefs.setString(
      _historyKey,
      jsonEncode(
        messages.skip(start).map((message) => message.toJson()).toList(),
      ),
    );
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}

class CgAgentBackendException implements Exception {
  final String message;

  const CgAgentBackendException(this.message);

  @override
  String toString() => message;
}

class CgAgentBackend {
  final CgAgentConfig config;
  final http.Client _client;

  CgAgentBackend(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  Uri _endpoint(String path) {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalized');
  }

  Map<String, String> _headers({bool json = true}) => <String, String>{
    if (json) 'Content-Type': 'application/json',
    'Accept': json ? 'text/event-stream, application/json' : '*/*',
    if (config.apiToken.trim().isNotEmpty)
      'Authorization': 'Bearer ${config.apiToken.trim()}',
  };

  Stream<String> streamReply({
    required List<CgAgentMessage> messages,
    required bool ru,
  }) async* {
    if (!config.configured) {
      throw const CgAgentBackendException('agent_not_configured');
    }
    final request = http.Request('POST', _endpoint('/v1/chat/completions'))
      ..headers.addAll(_headers())
      ..body = jsonEncode(<String, dynamic>{
        'model': config.chatModel.trim(),
        'stream': true,
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': ru
                ? 'Ты цифровой агент Cernogram. Отвечай полезно и прямо. Не утверждай, что имеешь доступ к контактам, файлам или интернету, если соответствующее разрешение и инструмент не были переданы сервером.'
                : 'You are the Cernogram digital agent. Be useful and direct. Never claim access to contacts, files or web search unless the server explicitly provided that tool and permission.',
          },
          ...messages.map(
            (message) => <String, String>{
              'role': message.role == 'assistant' ? 'assistant' : 'user',
              'content': message.text,
            },
          ),
        ],
      });
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw CgAgentBackendException(
        'chat_http_${response.statusCode}:${_compact(body)}',
      );
    }

    var emitted = false;
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload == '[DONE]') break;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final json = Map<String, dynamic>.from(decoded);
        final choices = json['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map) {
          continue;
        }
        final choice = Map<String, dynamic>.from(choices.first as Map);
        final delta = choice['delta'];
        final message = choice['message'];
        String text = '';
        if (delta is Map) {
          text = delta['content']?.toString() ?? '';
        } else if (message is Map) {
          text = message['content']?.toString() ?? '';
        }
        if (text.isNotEmpty) {
          emitted = true;
          yield text;
        }
      } catch (_) {
        // Ignore malformed keepalive or provider-specific metadata frames.
      }
    }
    if (!emitted) {
      throw const CgAgentBackendException('empty_agent_response');
    }
  }

  Future<String> transcribe(File audioFile) async {
    if (!config.configured) {
      throw const CgAgentBackendException('agent_not_configured');
    }
    if (!await audioFile.exists()) {
      throw const CgAgentBackendException('audio_file_missing');
    }
    final request =
        http.MultipartRequest('POST', _endpoint('/v1/audio/transcriptions'))
          ..headers.addAll(_headers(json: false))
          ..fields['model'] = config.transcriptionModel.trim()
          ..files.add(
            await http.MultipartFile.fromPath('file', audioFile.path),
          );
    final response = await _client
        .send(request)
        .timeout(const Duration(minutes: 2));
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CgAgentBackendException(
        'transcription_http_${response.statusCode}:${_compact(body)}',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = decoded['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
    } catch (_) {
      if (body.trim().isNotEmpty) return body.trim();
    }
    throw const CgAgentBackendException('empty_transcription');
  }

  Future<File> synthesize(String text) async {
    if (!config.configured) {
      throw const CgAgentBackendException('agent_not_configured');
    }
    final response = await _client
        .post(
          _endpoint('/v1/audio/speech'),
          headers: _headers(),
          body: jsonEncode(<String, dynamic>{
            'model': config.speechModel.trim(),
            'voice': config.voice.trim(),
            'input': text,
            'response_format': 'mp3',
          }),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CgAgentBackendException(
        'speech_http_${response.statusCode}:${_compact(response.body)}',
      );
    }
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'cernogram_agent_${DateTime.now().microsecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  Future<bool> testConnection() async {
    if (!config.configured) return false;
    try {
      final response = await _client
          .get(_endpoint('/v1/models'), headers: _headers(json: false))
          .timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();

  String _compact(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 240 ? normalized : normalized.substring(0, 240);
  }
}
