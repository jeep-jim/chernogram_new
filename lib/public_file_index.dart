import 'dart:async';

import 'core_models.dart';
import 'internet_core.dart';

class CgPublicFileRecord {
  final String id;
  final String fileName;
  final int size;
  final String kind;
  final String ownerId;
  final String ownerName;
  final String roomId;
  final String roomName;
  final String inviteToken;
  final String messageId;
  final DateTime createdAt;

  const CgPublicFileRecord({
    required this.id,
    required this.fileName,
    required this.size,
    required this.kind,
    required this.ownerId,
    required this.ownerName,
    required this.roomId,
    required this.roomName,
    required this.inviteToken,
    required this.messageId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'fileName': fileName,
    'size': size,
    'kind': kind,
    'ownerId': ownerId,
    'ownerName': ownerName,
    'roomId': roomId,
    'roomName': roomName,
    'inviteToken': inviteToken,
    'messageId': messageId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory CgPublicFileRecord.fromJson(Map<String, dynamic> json) =>
      CgPublicFileRecord(
        id: json['id']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? 'file',
        size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        kind: json['kind']?.toString() ?? 'document',
        ownerId: json['ownerId']?.toString() ?? '',
        ownerName: json['ownerName']?.toString() ?? 'user',
        roomId: json['roomId']?.toString() ?? '',
        roomName: json['roomName']?.toString() ?? '',
        inviteToken: json['inviteToken']?.toString() ?? '',
        messageId: json['messageId']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class CgPublicFileIndex {
  static const String _roomId = 'public.files.v1';
  static const String _roomSecret =
      'cernogram-public-file-index-v1-metadata-is-intentionally-public';
  static final CgPublicFileIndex instance = CgPublicFileIndex._();

  final StreamController<List<CgPublicFileRecord>> _changes =
      StreamController<List<CgPublicFileRecord>>.broadcast(sync: true);
  final Map<String, CgPublicFileRecord> _records =
      <String, CgPublicFileRecord>{};

  InternetTunnelSession? _session;
  StreamSubscription<InternetEvent>? _subscription;
  String? _profileId;
  String? _nickname;
  bool _initializing = false;

  CgPublicFileIndex._();

  Stream<List<CgPublicFileRecord>> get changes => _changes.stream;
  List<CgPublicFileRecord> get records {
    final values = _records.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  Future<void> initialize(CgProfile profile) async {
    if (_session != null && _profileId == profile.id) return;
    if (_initializing) return;
    _initializing = true;
    try {
      await _subscription?.cancel();
      _profileId = profile.id;
      _nickname = profile.nickname;
      final session = await InternetRelay.open(
        tunnelId: _roomId,
        secret: _roomSecret,
        profileId: profile.id,
        nickname: profile.nickname,
        history: const <Map<String, dynamic>>[],
      );
      _session = session;
      _subscription = session.events.listen(_onEvent);
      unawaited(session.connect());
    } finally {
      _initializing = false;
    }
  }

  void _onEvent(InternetEvent event) {
    if (event.type != 'message' || event.data['message'] is! Map) return;
    final message = Map<String, dynamic>.from(event.data['message'] as Map);
    if (message['type']?.toString() != 'public_file_index') return;
    final rawMeta = message['meta'];
    if (rawMeta is! Map) return;
    final meta = Map<String, dynamic>.from(rawMeta);
    if (meta['action'] == 'remove') {
      final id = meta['recordId']?.toString() ?? '';
      if (id.isNotEmpty && _records.remove(id) != null) _emit();
      return;
    }
    final rawRecord = meta['record'];
    if (rawRecord is! Map) return;
    final record = CgPublicFileRecord.fromJson(
      Map<String, dynamic>.from(rawRecord),
    );
    if (record.id.isEmpty || record.inviteToken.isEmpty) return;
    _records[record.id] = record;
    if (_records.length > 10000) {
      final oldest = records.last;
      _records.remove(oldest.id);
    }
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(records);
  }

  Future<void> publish({
    required CgProfile profile,
    required CgTunnel room,
    required CgMessage message,
  }) async {
    final attachment = message.attachment;
    if (room.isPrivate || attachment == null) return;
    await initialize(profile);
    final record = CgPublicFileRecord(
      id: '${room.id}:${message.id}:${attachment.id}',
      fileName: attachment.name,
      size: attachment.size,
      kind: attachment.kind,
      ownerId: profile.id,
      ownerName: profile.nickname,
      roomId: room.id,
      roomName: room.displayName,
      inviteToken: room.inviteToken,
      messageId: message.id,
      createdAt: message.sentAt,
    );
    _records[record.id] = record;
    _emit();
    final indexMessage = <String, dynamic>{
      'id': 'index_${record.id}',
      'authorId': profile.id,
      'authorName': profile.nickname,
      'author': profile.nickname,
      'text': attachment.name,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'type': 'public_file_index',
      'deleted': false,
      'meta': <String, dynamic>{
        'record': record.toJson(),
        'publicFileIndex': true,
      },
    };
    await _session?.sendMessage(indexMessage);
  }

  Future<void> remove({
    required CgProfile profile,
    required String recordId,
  }) async {
    await initialize(profile);
    _records.remove(recordId);
    _emit();
    await _session?.sendMessage(<String, dynamic>{
      'id': 'remove_${recordId}_${CgIds.random(8)}',
      'authorId': profile.id,
      'authorName': profile.nickname,
      'author': profile.nickname,
      'text': '',
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'type': 'public_file_index',
      'deleted': false,
      'meta': <String, dynamic>{
        'action': 'remove',
        'recordId': recordId,
        'publicFileIndex': true,
      },
    });
  }

  List<CgPublicFileRecord> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return records;
    return records.where((record) {
      return record.fileName.toLowerCase().contains(normalized) ||
          record.roomName.toLowerCase().contains(normalized) ||
          record.ownerName.toLowerCase().contains(normalized) ||
          record.kind.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _session = null;
  }
}
