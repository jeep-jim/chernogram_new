from pathlib import Path
import re


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise RuntimeError(f'{label}: expected source block was not found')
    return source.replace(old, new, 1)


path = Path('lib/internet_core.dart')
source = path.read_text(encoding='utf-8')
original = source

source = replace_once(
    source,
    "import 'package:http/http.dart' as http;\n",
    "import 'package:http/http.dart' as http;\nimport 'package:path_provider/path_provider.dart';\n",
    'path_provider import',
)

source = replace_once(
    source,
    '''class _PendingEnvelope {
  final String kind;
  final Map<String, dynamic> data;

  const _PendingEnvelope(this.kind, this.data);
}
''',
    '''class _PendingEnvelope {
  final String id;
  final String kind;
  final String encrypted;
  final String? uniqueId;
  final DateTime createdAt;
  int attempts;

  _PendingEnvelope({
    required this.id,
    required this.kind,
    required this.encrypted,
    required this.uniqueId,
    required this.createdAt,
    this.attempts = 0,
  });

  factory _PendingEnvelope.fromJson(Map<String, dynamic> json) =>
      _PendingEnvelope(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        encrypted: json['encrypted']?.toString() ?? '',
        uniqueId: json['uniqueId']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'encrypted': encrypted,
        if (uniqueId != null) 'uniqueId': uniqueId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
      };
}
''',
    'pending envelope model',
)

source = replace_once(
    source,
    "  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];\n",
    "  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];\n"
    "  bool _outboxLoaded = false;\n"
    "  bool _flushingOutbox = false;\n"
    "  File? _outboxFile;\n",
    'outbox fields',
)

source = replace_once(
    source,
    "      await _prepareCryptoAndTopic();\n      final connectHosts",
    "      await _prepareCryptoAndTopic();\n      await _loadOutbox();\n      final connectHosts",
    'load outbox during connect',
)

source = replace_once(
    source,
    '''    if (kind == 'signal' &&
        sentAt != null &&
        DateTime.now().toUtc().difference(sentAt.toUtc()).inSeconds.abs() > 120) {
      return;
    }
''',
    '''    final ageSeconds = sentAt == null
        ? 0
        : DateTime.now()
            .toUtc()
            .difference(sentAt.toUtc())
            .inSeconds
            .abs();
    if (kind == 'signal' && ageSeconds > 45) return;
    if (kind == 'presence' && ageSeconds > 35) return;
''',
    'stale realtime packet filter',
)

start = source.index('  Future<void> _sendEnvelope(\n')
end = source.index('  Future<String?> _publishSignalFast(\n', start)
replacement = r'''  Future<void> _sendEnvelope(
    String kind,
    Map<String, dynamic> data, {
    bool queueOnFailure = true,
  }) async {
    if (_closed) return;
    await _prepareCryptoAndTopic();
    await _loadOutbox();
    if (!connected) unawaited(connect());

    final uniqueId = _uniqueIdFor(kind, data);
    final packetId = uniqueId == null
        ? CgIds.random(24)
        : '${kind}_${uniqueId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    final body = <String, dynamic>{
      'v': 8,
      'packetId': packetId,
      'from': profileId,
      'name': nickname,
      'kind': kind,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    };
    final encrypted = await _encrypt(body);
    final successfulHost = await _publishEnvelope(kind, encrypted);

    if (successfulHost != null) {
      _emit('delivery', <String, dynamic>{
        'state': 'sent',
        'kind': kind,
        'packetId': packetId,
        if (uniqueId != null) 'uniqueId': uniqueId,
        'relayHost': successfulHost,
      });
      return;
    }

    final canQueue = queueOnFailure && (kind == 'message' || kind == 'control');
    if (canQueue) {
      await _enqueuePending(
        _PendingEnvelope(
          id: packetId,
          kind: kind,
          encrypted: encrypted,
          uniqueId: uniqueId,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      _emit('status', <String, dynamic>{
        'state': 'queued',
        'code': 'relay_unavailable',
        'kind': kind,
        'packetId': packetId,
        if (uniqueId != null) 'uniqueId': uniqueId,
      });
    } else {
      _emit('status', <String, dynamic>{
        'state': 'offline',
        'code': 'relay_unavailable',
        'kind': kind,
        'packetId': packetId,
      });
    }
    _scheduleGlobalReconnect();
  }

  String? _uniqueIdFor(String kind, Map<String, dynamic> data) {
    if (kind == 'message') {
      final rawMessage = data['message'];
      if (rawMessage is Map) {
        final id = rawMessage['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) return id;
      }
    }
    if (kind == 'control') {
      final id = data['operationId']?.toString().trim() ?? '';
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  Future<String?> _publishEnvelope(String kind, String encrypted) async {
    final orderedHosts = <String>[
      ..._sockets.keys,
      ...relayHosts.where((host) => !_sockets.containsKey(host)),
    ];
    if (kind == 'signal') {
      return _publishSignalFast(orderedHosts, encrypted);
    }

    for (final host in orderedHosts) {
      try {
        await _publishEncrypted(
          host,
          encrypted,
          cache: kind != 'presence',
          priority: kind == 'control' ? 'high' : 'default',
          timeout: kind == 'presence'
              ? const Duration(milliseconds: 1600)
              : const Duration(milliseconds: 4200),
        );
        return host;
      } catch (_) {
        _scheduleHostReconnect(host);
      }
    }
    return null;
  }

  Future<void> _enqueuePending(_PendingEnvelope item) async {
    final duplicateIndex = _outbox.indexWhere(
      (existing) => existing.kind == item.kind &&
          ((item.uniqueId != null && existing.uniqueId == item.uniqueId) ||
              existing.id == item.id),
    );
    if (duplicateIndex >= 0) {
      _outbox[duplicateIndex] = item;
    } else {
      _outbox.add(item);
    }
    if (_outbox.length > 500) {
      _outbox.removeRange(0, _outbox.length - 500);
    }
    await _persistOutbox();
  }

'''
source = source[:start] + replacement + source[end:]

source = source.replace(
    ".timeout(const Duration(seconds: 6));",
    ".timeout(timeout);",
    1,
)

old_flush = '''  Future<void> _flushOutbox() async {
    if (_outbox.isEmpty || !connected) return;
    final pending = List<_PendingEnvelope>.from(_outbox);
    _outbox.clear();
    for (final item in pending) {
      await _sendEnvelope(item.kind, item.data);
    }
  }
'''
new_flush = r'''  Future<void> _flushOutbox() async {
    await _loadOutbox();
    if (_flushingOutbox || _outbox.isEmpty || !connected) return;
    _flushingOutbox = true;
    try {
      for (final item in List<_PendingEnvelope>.from(_outbox)) {
        if (_closed || !connected) break;
        final successfulHost = await _publishEnvelope(item.kind, item.encrypted);
        if (successfulHost == null) {
          item.attempts++;
          await _persistOutbox();
          break;
        }
        _outbox.removeWhere((existing) => existing.id == item.id);
        await _persistOutbox();
        _emit('delivery', <String, dynamic>{
          'state': 'sent',
          'kind': item.kind,
          'packetId': item.id,
          if (item.uniqueId != null) 'uniqueId': item.uniqueId,
          'relayHost': successfulHost,
          'fromOutbox': true,
        });
      }
    } finally {
      _flushingOutbox = false;
    }
  }

  Future<void> _loadOutbox() async {
    if (_outboxLoaded) return;
    _outboxLoaded = true;
    try {
      final file = await _resolveOutboxFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
      for (final raw in decoded.whereType<Map>()) {
        final item = _PendingEnvelope.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (item.id.isEmpty ||
            item.kind.isEmpty ||
            item.encrypted.isEmpty ||
            item.createdAt.toUtc().isBefore(cutoff)) {
          continue;
        }
        if (_outbox.any((existing) => existing.id == item.id)) continue;
        _outbox.add(item);
      }
    } catch (_) {
      // Corrupted local queue must never prevent the app from starting.
    }
  }

  Future<File> _resolveOutboxFile() async {
    final cached = _outboxFile;
    if (cached != null) return cached;
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}realtime_outbox',
    );
    await directory.create(recursive: true);
    final hash = await Sha256().hash(utf8.encode('$profileId:$tunnelId'));
    final name = base64Url.encode(hash.bytes).replaceAll('=', '');
    final file = File(
      '${directory.path}${Platform.pathSeparator}$name.json',
    );
    _outboxFile = file;
    return file;
  }

  Future<void> _persistOutbox() async {
    if (!_outboxLoaded) return;
    try {
      final file = await _resolveOutboxFile();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode(_outbox.map((item) => item.toJson()).toList()),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      // Delivery continues in memory even if the filesystem is temporarily busy.
    }
  }
'''
source = replace_once(source, old_flush, new_flush, 'persistent outbox methods')

source = replace_once(
    source,
    "    _sockets.clear();\n    _http.close();\n",
    "    _sockets.clear();\n    await _persistOutbox();\n    _http.close();\n",
    'persist outbox on close',
)

if source == original:
    raise RuntimeError('internet_core.dart was not changed')
path.write_text(source, encoding='utf-8')

pubspec = Path('pubspec.yaml')
pub = pubspec.read_text(encoding='utf-8')
pub = re.sub(
    r'^version:\s*0\.16\.10\+41\s*$',
    'version: 0.16.11+42',
    pub,
    count=1,
    flags=re.M,
)
pubspec.write_text(pub, encoding='utf-8')

workflow = Path('.github/workflows/build.yml')
w = workflow.read_text(encoding='utf-8')
w = w.replace(
    'Диагностическая foreground-сборка: отключён второй Android isolate, сокращено число публичных relay, устранена четырёхкратная отправка и исправлено игнорирование сетевого timeout. Иконка не изменялась.',
    'Recovery 0.16.11: добавлена зашифрованная дисковая очередь исходящих сообщений, один packetId сохраняется при повторе, обычные сообщения больше не дублируются по двум relay, исправлен фактический timeout. Иконка не изменялась.',
)
w = w.replace(
    'Diagnostic foreground recovery build with the second Android isolate disabled, reduced public relay fan-out, duplicate publishing removed, and network timeout handling fixed. Branding is unchanged.',
    'Recovery 0.16.11 adds an encrypted persistent message outbox, stable packet IDs across retries, single-path normal message delivery, and correct network timeout handling. Branding is unchanged.',
)
workflow.write_text(w, encoding='utf-8')

print('Applied persistent encrypted realtime outbox and 0.16.11 metadata')
