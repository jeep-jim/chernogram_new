import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';

class TunnelPermissions {
  final bool canWriteMessages;
  final bool canSendMedia;
  final bool canDownload;
  final bool canInvite;
  final bool canSeeHistory;

  const TunnelPermissions({
    this.canWriteMessages = true,
    this.canSendMedia = true,
    this.canDownload = true,
    this.canInvite = false,
    this.canSeeHistory = true,
  });

  TunnelPermissions copyWith({
    bool? canWriteMessages,
    bool? canSendMedia,
    bool? canDownload,
    bool? canInvite,
    bool? canSeeHistory,
  }) {
    return TunnelPermissions(
      canWriteMessages: canWriteMessages ?? this.canWriteMessages,
      canSendMedia: canSendMedia ?? this.canSendMedia,
      canDownload: canDownload ?? this.canDownload,
      canInvite: canInvite ?? this.canInvite,
      canSeeHistory: canSeeHistory ?? this.canSeeHistory,
    );
  }

  Map<String, dynamic> toJson() => {
    'canWriteMessages': canWriteMessages,
    'canSendMedia': canSendMedia,
    'canDownload': canDownload,
    'canInvite': canInvite,
    'canSeeHistory': canSeeHistory,
  };

  factory TunnelPermissions.fromJson(Map<String, dynamic> json) {
    return TunnelPermissions(
      canWriteMessages: json['canWriteMessages'] != false,
      canSendMedia: json['canSendMedia'] != false,
      canDownload: json['canDownload'] != false,
      canInvite: json['canInvite'] == true,
      canSeeHistory: json['canSeeHistory'] != false,
    );
  }
}

class LocalTunnelExtrasStore {
  static String _avatarKey(String profileId) =>
      'chernogram_avatar_v1_$profileId';
  static String _permissionsKey(String tunnelId) =>
      'chernogram_permissions_v1_$tunnelId';

  static Future<String?> loadAvatar(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarKey(profileId));
  }

  static Future<void> saveAvatar(String profileId, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarKey(profileId), base64Encode(bytes));
  }

  static Future<void> removeAvatar(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_avatarKey(profileId));
  }

  static Future<TunnelPermissions> loadPermissions(String tunnelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_permissionsKey(tunnelId));
    if (raw == null) return const TunnelPermissions();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TunnelPermissions.fromJson(decoded);
      }
    } catch (_) {
      // Keep safe defaults when local JSON is damaged.
    }
    return const TunnelPermissions();
  }

  static Future<void> savePermissions(
    String tunnelId,
    TunnelPermissions permissions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _permissionsKey(tunnelId),
      jsonEncode(permissions.toJson()),
    );
  }
}

class LocalProfileAvatar extends StatefulWidget {
  final String? profileId;
  final String nickname;
  final double size;
  final bool showBrandWhenEmpty;

  const LocalProfileAvatar({
    super.key,
    required this.profileId,
    required this.nickname,
    required this.size,
    this.showBrandWhenEmpty = false,
  });

  @override
  State<LocalProfileAvatar> createState() => _LocalProfileAvatarState();
}

class _LocalProfileAvatarState extends State<LocalProfileAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LocalProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _load();
  }

  Future<void> _load() async {
    final id = widget.profileId;
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _bytes = null);
      return;
    }
    final raw = await LocalTunnelExtrasStore.loadAvatar(id);
    Uint8List? bytes;
    if (raw != null && raw.isNotEmpty) {
      try {
        bytes = base64Decode(raw);
      } catch (_) {
        bytes = null;
      }
    }
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return ClipOval(
        child: Image.memory(
          _bytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    if (widget.showBrandWhenEmpty) {
      return ChernogramLogo(size: widget.size, withPlate: true);
    }

    final text = widget.nickname.trim();
    final letter = text.isEmpty ? '?' : text.characters.first.toUpperCase();
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ChernogramColors.orange, ChernogramColors.gold],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: widget.size * .4,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

Future<bool> chooseAndSaveLocalAvatar(
  BuildContext context, {
  required String profileId,
  required bool ru,
}) async {
  final asset = await Navigator.push<AssetEntity>(
    context,
    MaterialPageRoute(builder: (_) => _AvatarPickerScreen(ru: ru)),
  );
  if (asset == null) return false;

  final bytes = await asset.thumbnailDataWithSize(
    const ThumbnailSize.square(512),
    quality: 92,
  );
  if (bytes == null) return false;
  await LocalTunnelExtrasStore.saveAvatar(profileId, bytes);
  return true;
}

Future<void> showTunnelQrDialog(
  BuildContext context, {
  required String link,
  required String tunnelName,
  required bool ru,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(ru ? 'QR-код туннеля' : 'Tunnel QR code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 230,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tunnelName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            ru
                ? 'Другой пользователь сканирует код камерой и сразу открывает приглашение.'
                : 'Another user scans this code to open the invite instantly.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: ChernogramColors.textSoft,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(ru ? 'Готово' : 'Done'),
        ),
      ],
    ),
  );
}

Future<TunnelPermissions?> showTunnelPermissionsDialog(
  BuildContext context, {
  required TunnelPermissions initial,
  required bool ru,
}) async {
  var value = initial;
  return showModalBottomSheet<TunnelPermissions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        Widget permissionTile({
          required IconData icon,
          required String titleRu,
          required String titleEn,
          required String subtitleRu,
          required String subtitleEn,
          required bool current,
          required ValueChanged<bool> onChanged,
        }) {
          return SwitchListTile(
            secondary: Icon(icon),
            title: Text(ru ? titleRu : titleEn),
            subtitle: Text(ru ? subtitleRu : subtitleEn),
            value: current,
            onChanged: (next) {
              onChanged(next);
              setSheetState(() {});
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ru ? 'Права собеседника' : 'Guest permissions',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ru
                      ? 'Эти настройки сохраняются локально в JSON туннеля и будут передаваться участнику при P2P-подключении.'
                      : 'These settings are stored in the tunnel JSON and will be sent to a peer during P2P connection.',
                  style: const TextStyle(color: ChernogramColors.textSoft),
                ),
                const SizedBox(height: 8),
                permissionTile(
                  icon: Icons.chat_bubble_outline,
                  titleRu: 'Писать сообщения',
                  titleEn: 'Send messages',
                  subtitleRu: 'Разрешить текстовые сообщения в чате.',
                  subtitleEn: 'Allow text messages in the chat.',
                  current: value.canWriteMessages,
                  onChanged: (next) =>
                      value = value.copyWith(canWriteMessages: next),
                ),
                permissionTile(
                  icon: Icons.add_photo_alternate_outlined,
                  titleRu: 'Отправлять медиа',
                  titleEn: 'Send media',
                  subtitleRu: 'Фото, видео и файлы устройства.',
                  subtitleEn: 'Photos, videos and device files.',
                  current: value.canSendMedia,
                  onChanged: (next) =>
                      value = value.copyWith(canSendMedia: next),
                ),
                permissionTile(
                  icon: Icons.download_outlined,
                  titleRu: 'Скачивать файлы',
                  titleEn: 'Download files',
                  subtitleRu: 'Сохранять открытые медиа на устройство.',
                  subtitleEn: 'Save shared media to the device.',
                  current: value.canDownload,
                  onChanged: (next) =>
                      value = value.copyWith(canDownload: next),
                ),
                permissionTile(
                  icon: Icons.person_add_alt_1_outlined,
                  titleRu: 'Приглашать других',
                  titleEn: 'Invite others',
                  subtitleRu: 'Разрешить пересылать ссылку туннеля.',
                  subtitleEn: 'Allow forwarding the tunnel invite.',
                  current: value.canInvite,
                  onChanged: (next) => value = value.copyWith(canInvite: next),
                ),
                permissionTile(
                  icon: Icons.history,
                  titleRu: 'Видеть историю',
                  titleEn: 'See message history',
                  subtitleRu: 'Показывать сообщения до момента подключения.',
                  subtitleEn: 'Show messages sent before joining.',
                  current: value.canSeeHistory,
                  onChanged: (next) =>
                      value = value.copyWith(canSeeHistory: next),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, value),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(ru ? 'Сохранить права' : 'Save permissions'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _AvatarPickerScreen extends StatefulWidget {
  final bool ru;

  const _AvatarPickerScreen({required this.ru});

  @override
  State<_AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<_AvatarPickerScreen> {
  bool _loading = true;
  bool _denied = false;
  List<AssetEntity> _assets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      if (mounted) {
        setState(() {
          _loading = false;
          _denied = true;
        });
      }
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      hasAll: true,
      type: RequestType.image,
    );
    final assets = albums.isEmpty
        ? <AssetEntity>[]
        : await albums.first.getAssetListPaged(page: 0, size: 300);
    if (mounted) {
      setState(() {
        _assets = assets;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Выберите аватарку' : 'Choose an avatar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _denied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.ru
                      ? 'Разрешите доступ к фотографиям, чтобы выбрать локальную аватарку.'
                      : 'Allow photo access to choose a local avatar.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _assets.length,
              itemBuilder: (_, index) {
                final asset = _assets[index];
                return InkWell(
                  onTap: () => Navigator.pop(context, asset),
                  child: FutureBuilder<Uint8List?>(
                    future: asset.thumbnailDataWithSize(
                      const ThumbnailSize.square(260),
                      quality: 80,
                    ),
                    builder: (_, snapshot) => snapshot.data == null
                        ? const ColoredBox(
                            color: ChernogramColors.surfaceHigh,
                            child: Icon(Icons.image_outlined),
                          )
                        : Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                );
              },
            ),
    );
  }
}
