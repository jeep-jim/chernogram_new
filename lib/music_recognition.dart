import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'music_player.dart';

class CgMusicRecognitionConfig {
  static const String _urlKey = 'cg_music_recognition_url_v1';
  final String baseUrl;

  const CgMusicRecognitionConfig({this.baseUrl = ''});

  bool get configured {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<CgMusicRecognitionConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CgMusicRecognitionConfig(
      baseUrl: prefs.getString(_urlKey)?.trim() ?? '',
    );
  }

  static Future<void> save(String value) async {
    final url = value.trim().replaceAll(RegExp(r'/+$'), '');
    final config = CgMusicRecognitionConfig(baseUrl: url);
    if (url.isNotEmpty && !config.configured) {
      throw const FormatException('Use http:// or https://');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
  }
}

class CgMusicRecognitionResult {
  final bool found;
  final double score;
  final String assetId;
  final String title;
  final String artist;
  final String ownerId;
  final String ownerName;
  final String publicUrl;
  final bool downloadAllowed;
  final bool saveAllowed;
  final double duration;

  const CgMusicRecognitionResult({
    required this.found,
    required this.score,
    this.assetId = '',
    this.title = '',
    this.artist = '',
    this.ownerId = '',
    this.ownerName = '',
    this.publicUrl = '',
    this.downloadAllowed = false,
    this.saveAllowed = false,
    this.duration = 0,
  });

  factory CgMusicRecognitionResult.fromJson(Map<String, dynamic> json) =>
      CgMusicRecognitionResult(
        found: json['found'] == true,
        score: double.tryParse(json['score']?.toString() ?? '') ?? 0,
        assetId: json['asset_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        ownerId: json['owner_id']?.toString() ?? '',
        ownerName: json['owner_name']?.toString() ?? '',
        publicUrl: json['public_url']?.toString() ?? '',
        downloadAllowed: json['download_allowed'] == true,
        saveAllowed: json['save_allowed'] == true,
        duration: double.tryParse(json['duration']?.toString() ?? '') ?? 0,
      );
}

class CgMusicRecognitionClient {
  final CgMusicRecognitionConfig config;
  final http.Client _client;

  CgMusicRecognitionClient(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Uri _endpoint(String path) => Uri.parse(
        '${config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}$path',
      );

  Future<CgMusicRecognitionResult> recognize(File sample) async {
    if (!config.configured) throw StateError('music_recognition_not_configured');
    if (!await sample.exists()) throw StateError('sample_missing');
    final request = http.MultipartRequest(
      'POST',
      _endpoint('/v1/music/recognize'),
    )..files.add(await http.MultipartFile.fromPath('file', sample.path));
    final response = await _client.send(request).timeout(
          const Duration(minutes: 1),
        );
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'recognition_http_${response.statusCode}:${body.replaceAll(RegExp(r'\s+'), ' ').trim()}',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Invalid recognition result');
    return CgMusicRecognitionResult.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<bool> test() async {
    if (!config.configured) return false;
    try {
      final response = await _client
          .get(_endpoint('/healthz'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}

class CgMusicRecognitionScreen extends StatefulWidget {
  final bool ru;
  final Future<void> Function(CgMusicRecognitionResult result)? onAdd;

  const CgMusicRecognitionScreen({
    super.key,
    required this.ru,
    this.onAdd,
  });

  @override
  State<CgMusicRecognitionScreen> createState() =>
      _CgMusicRecognitionScreenState();
}

class _CgMusicRecognitionScreenState extends State<CgMusicRecognitionScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  CgMusicRecognitionConfig _config = const CgMusicRecognitionConfig();
  CgMusicRecognitionClient? _client;
  CgMusicRecognitionResult? _result;
  bool _loading = true;
  bool _recording = false;
  bool _recognizing = false;
  bool _testing = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  DateTime? _startedAt;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final config = await CgMusicRecognitionConfig.load();
    if (!mounted) return;
    _client?.close();
    setState(() {
      _config = config;
      _client = CgMusicRecognitionClient(config);
      _loading = false;
    });
  }

  Future<void> _configure() async {
    final controller = TextEditingController(text: _config.baseUrl);
    var feedback = '';
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.ru ? 'Сервер распознавания' : 'Recognition server',
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.ru
                      ? 'Аудио отправляется только на ваш Cernogram Music Gateway, преобразуется в Chromaprint и удаляется после анализа.'
                      : 'Audio is sent only to your Cernogram Music Gateway, converted to a Chromaprint fingerprint and deleted after analysis.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://music.example.com',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                if (feedback.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      feedback,
                      style: TextStyle(
                        color: feedback.startsWith('✓')
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
                                final value = controller.text.trim();
                                final candidate = CgMusicRecognitionConfig(baseUrl: value);
                                setSheetState(() {
                                  _testing = true;
                                  feedback = '';
                                });
                                final client = CgMusicRecognitionClient(candidate);
                                final ok = await client.test();
                                client.close();
                                setSheetState(() {
                                  _testing = false;
                                  feedback = ok
                                      ? '✓ ${widget.ru ? 'Сервер отвечает' : 'Server responded'}'
                                      : '✕ ${widget.ru ? 'Нет соединения' : 'Connection failed'}';
                                });
                              },
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text(widget.ru ? 'Проверить' : 'Test'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          try {
                            await CgMusicRecognitionConfig.save(controller.text);
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                            await _load();
                          } catch (_) {
                            setSheetState(() {
                              feedback = widget.ru
                                  ? '✕ Нужен адрес http:// или https://'
                                  : '✕ Use an http:// or https:// address';
                            });
                          }
                        },
                        icon: const Icon(Icons.save_rounded),
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
    controller.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _finishRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_config.configured) {
      await _configure();
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}${Platform.pathSeparator}'
        'music_recognition_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
        numChannels: 1,
        echoCancel: false,
        noiseSuppress: false,
        autoGain: false,
      ),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _path = path;
      _recording = true;
      _recognizing = false;
      _result = null;
      _error = null;
      _elapsed = Duration.zero;
      _startedAt = DateTime.now();
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _startedAt == null) return;
      final elapsed = DateTime.now().difference(_startedAt!);
      setState(() => _elapsed = elapsed);
      if (elapsed >= const Duration(seconds: 15)) unawaited(_finishRecording());
    });
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _timer?.cancel();
    _timer = null;
    final path = await _recorder.stop() ?? _path;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recognizing = true;
    });
    if (path == null) return;
    final sample = File(path);
    try {
      final result = await (_client ?? CgMusicRecognitionClient(_config))
          .recognize(sample);
      if (!mounted) return;
      setState(() {
        _result = result;
        _recognizing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = widget.ru
            ? 'Не удалось распознать трек. Проверьте сервер и попробуйте ещё раз.'
            : 'Could not recognize the track. Check the server and try again.';
      });
    } finally {
      try {
        if (await sample.exists()) await sample.delete();
      } catch (_) {}
    }
  }

  Future<void> _openResult() async {
    final url = _result?.publicUrl.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:'
      '${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recorder.dispose());
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Распознать музыку' : 'Recognize music'),
        actions: [
          IconButton(
            tooltip: widget.ru ? 'Настроить сервер' : 'Configure server',
            onPressed: _configure,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: .08),
                        boxShadow: _recording || _recognizing
                            ? [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: .25),
                                  blurRadius: 45,
                                  spreadRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: _recording || _recognizing
                            ? CgPlayingBars(active: true, size: 105)
                            : const ChernogramLogo(size: 122),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      _recording
                          ? (widget.ru ? 'Слушаю музыку…' : 'Listening…')
                          : _recognizing
                              ? (widget.ru ? 'Сравниваю отпечаток…' : 'Matching fingerprint…')
                              : result?.found == true
                                  ? (widget.ru ? 'Трек найден' : 'Track found')
                                  : (widget.ru ? 'Что сейчас играет?' : 'What is playing?'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _recording
                          ? '${_time(_elapsed)} / 00:15'
                          : widget.ru
                              ? 'Запишите 10–15 секунд. Исходный звук удаляется сразу после создания fingerprint.'
                              : 'Record 10–15 seconds. The original audio is deleted immediately after fingerprinting.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (result?.found == true)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Icon(Icons.music_note_rounded, size: 42),
                              const SizedBox(height: 8),
                              Text(
                                result!.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (result.artist.isNotEmpty)
                                Text(result.artist, textAlign: TextAlign.center),
                              const SizedBox(height: 5),
                              Text(
                                '${widget.ru ? 'Совпадение' : 'Match'}: '
                                '${(result.score * 100).toStringAsFixed(1)}%',
                              ),
                              if (result.ownerName.isNotEmpty)
                                Text(
                                  '${widget.ru ? 'Опубликовал' : 'Published by'}: '
                                  '${result.ownerName}',
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (result.publicUrl.isNotEmpty)
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _openResult,
                                        icon: const Icon(Icons.open_in_new_rounded),
                                        label: Text(widget.ru ? 'Открыть' : 'Open'),
                                      ),
                                    ),
                                  if (result.publicUrl.isNotEmpty &&
                                      result.saveAllowed &&
                                      widget.onAdd != null)
                                    const SizedBox(width: 8),
                                  if (result.saveAllowed && widget.onAdd != null)
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => widget.onAdd!(result),
                                        icon: const Icon(Icons.bookmark_add_rounded),
                                        label: Text(widget.ru ? 'Добавить к себе' : 'Add to library'),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (result != null && !result.found)
                      Text(
                        widget.ru
                            ? 'В опубликованном каталоге Cernogram совпадение не найдено.'
                            : 'No match was found in the published Cernogram catalog.',
                        textAlign: TextAlign.center,
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _recognizing ? null : _toggle,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(220, 54),
                        backgroundColor:
                            _recording ? ChernogramColors.danger : null,
                      ),
                      icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                      label: Text(
                        _recording
                            ? (widget.ru ? 'Остановить' : 'Stop')
                            : (widget.ru ? 'Распознать' : 'Recognize'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
