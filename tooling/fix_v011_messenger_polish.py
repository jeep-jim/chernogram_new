from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    Path(path).write_text(source, encoding='utf-8')


def replace(path: str, old: str, new: str) -> None:
    source = read(path)
    if old in source:
        write(path, source.replace(old, new))


def insert_after(path: str, marker: str, addition: str) -> None:
    source = read(path)
    if addition.strip() in source:
        return
    index = source.find(marker)
    if index < 0:
        return
    index += len(marker)
    write(path, source[:index] + addition + source[index:])


def replace_between(path: str, start: str, end: str, replacement: str) -> None:
    source = read(path)
    left = source.find(start)
    if left < 0:
        return
    right = source.find(end, left)
    if right < 0:
        return
    write(path, source[:left] + replacement + source[right:])


def main() -> None:
    # ------------------------------------------------------------------
    # Shared theme/system bars: dark icons on a light background and light
    # icons on a dark background, including Samsung navigation/status bars.
    # ------------------------------------------------------------------
    brand = 'lib/brand.dart'
    if "package:flutter/services.dart" not in read(brand):
        replace(
            brand,
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
        )
    replace(
        brand,
        """    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
""",
        """    appBarTheme: AppBarTheme(
      systemOverlayStyle: dark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: ChernogramColors.background,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Color(0xFFF2F6FF),
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Color(0xFFF2F6FF),
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarDividerColor: Color(0xFFDCE4F2),
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: false,
            ),
      backgroundColor: Colors.transparent,
""",
    )

    main_path = 'lib/main.dart'
    if "just_audio_background" not in read(main_path):
        replace(
            main_path,
            "import 'package:flutter/services.dart';\n",
            "import 'package:flutter/services.dart';\nimport 'package:just_audio_background/just_audio_background.dart';\n",
        )
    replace(
        main_path,
        """void main() {
  WidgetsFlutterBinding.ensureInitialized();
""",
        """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.chernogram.audio',
    androidNotificationChannelName: 'Музыка Чернограма',
    androidNotificationOngoing: true,
  );
""",
    )
    # Strengthen the runtime overlay style left by 0.10.1.
    source = read(main_path)
    source = source.replace(
        "systemNavigationBarDividerColor: Color(0xFFDCE4F2),\n            ),",
        "systemNavigationBarDividerColor: Color(0xFFDCE4F2),\n              systemNavigationBarContrastEnforced: false,\n              systemStatusBarContrastEnforced: false,\n            ),",
    )
    source = source.replace(
        "systemNavigationBarIconBrightness: Brightness.light,\n            )",
        "systemNavigationBarIconBrightness: Brightness.light,\n              systemNavigationBarContrastEnforced: false,\n              systemStatusBarContrastEnforced: false,\n            )",
    )
    write(main_path, source)

    # ------------------------------------------------------------------
    # Android background audio service and lock-screen controls.
    # ------------------------------------------------------------------
    manifest = 'android/app/src/main/AndroidManifest.xml'
    replace(
        manifest,
        "    <uses-permission android:name=\"android.permission.READ_EXTERNAL_STORAGE\" android:maxSdkVersion=\"32\" />\n",
        """    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
""",
    )
    audio_components = """
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:exported="true"
            android:foregroundServiceType="mediaPlayback">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>

"""
    if 'com.ryanheise.audioservice.AudioService' not in read(manifest):
        replace(manifest, "        <provider\n", audio_components + "        <provider\n")

    activity = 'android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt'
    replace(
        activity,
        'import io.flutter.embedding.android.FlutterActivity\n',
        'import com.ryanheise.audioservice.AudioServiceActivity\n',
    )
    replace(activity, 'class MainActivity : FlutterActivity() {', 'class MainActivity : AudioServiceActivity() {')

    # ------------------------------------------------------------------
    # Call avatars: the caller sends the profile avatar in signalling and it
    # is visible in both the incoming dialog and the active call screen.
    # ------------------------------------------------------------------
    call_path = 'lib/call_service.dart'
    if "import 'call_avatar.dart';" not in read(call_path):
        replace(
            call_path,
            "import 'brand.dart';\n",
            "import 'brand.dart';\nimport 'call_avatar.dart';\n",
        )
    replace(
        call_path,
        """  final String? peerId;
  final String? peerName;
""",
        """  final String? peerId;
  final String? peerName;
  final String? peerAvatarBase64;
  final String? myAvatarBase64;
""",
    )
    replace(
        call_path,
        """    this.peerId,
    this.peerName,
  });
""",
        """    this.peerId,
    this.peerName,
    this.peerAvatarBase64,
    this.myAvatarBase64,
  });
""",
    )
    replace(
        call_path,
        """        'fromName': widget.nickname,
      });
""",
        """        'fromName': widget.nickname,
        'avatarBase64': widget.myAvatarBase64,
      });
""",
    )
    replace(
        call_path,
        """                      const ChernogramLogo(size: 112, withPlate: true),
                      const SizedBox(height: 22),
""",
        """                      CgCallAvatar(
                        avatarBase64: widget.peerAvatarBase64,
                        name: remoteLabel,
                        size: 112,
                      ),
                      const SizedBox(height: 22),
""",
    )
    replace(
        call_path,
        """              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
""",
        """              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
""",
    )

    group_path = 'lib/group_call_service.dart'
    replace(
        group_path,
        """  final bool video;
  final bool ru;
""",
        """  final bool video;
  final bool ru;
  final String? myAvatarBase64;
""",
    )
    replace(
        group_path,
        """    required this.video,
    required this.ru,
  });
""",
        """    required this.video,
    required this.ru,
    this.myAvatarBase64,
  });
""",
    )
    replace(
        group_path,
        """          'fromName': widget.nickname,
          'video': widget.video,
          'maxParticipants': 6,
""",
        """          'fromName': widget.nickname,
          'avatarBase64': widget.myAvatarBase64,
          'video': widget.video,
          'maxParticipants': 6,
""",
    )

    app_monitor = 'lib/app_monitor.dart'
    if "import 'call_avatar.dart';" not in read(app_monitor):
        replace(
            app_monitor,
            "import 'call_service.dart';\n",
            "import 'call_avatar.dart';\nimport 'call_service.dart';\n",
        )
    replace(
        app_monitor,
        """    final video = signal['video'] == true;
    final group = action == 'group_call_invite';
""",
        """    final video = signal['video'] == true;
    final group = action == 'group_call_invite';
    final callerAvatar = signal['avatarBase64']?.toString();
""",
    )
    replace(
        app_monitor,
        """        icon: Icon(
          group
              ? Icons.groups_2_rounded
              : video
                  ? Icons.videocam_rounded
                  : Icons.call_rounded,
          size: 40,
        ),
""",
        """        icon: CgCallAvatar(
          avatarBase64: callerAvatar,
          name: fromName,
          size: 78,
          fallbackIcon: group
              ? Icons.groups_2_rounded
              : video
                  ? Icons.videocam_rounded
                  : Icons.call_rounded,
        ),
""",
    )
    replace(
        app_monitor,
        """                nickname: profile.nickname,
                peerId: from,
                peerName: fromName,
                callId: callId,
""",
        """                nickname: profile.nickname,
                peerId: from,
                peerName: fromName,
                peerAvatarBase64: callerAvatar,
                myAvatarBase64: profile.avatarBase64,
                callId: callId,
""",
    )
    replace(
        app_monitor,
        """                isHost: false,
                video: video,
                ru: _ru,
""",
        """                isHost: false,
                video: video,
                ru: _ru,
                myAvatarBase64: profile.avatarBase64,
""",
    )

    # ------------------------------------------------------------------
    # Chat: multiple files, reply/forward swipes, quote preview, transparent
    # voice/music cards, caller avatars and ten-pixel spacing.
    # ------------------------------------------------------------------
    chat = 'lib/chat_screen.dart'
    if "import 'call_avatar.dart';" not in read(chat):
        replace(
            chat,
            "import 'call_service.dart';\n",
            "import 'call_avatar.dart';\nimport 'call_service.dart';\n",
        )
    replace(
        chat,
        """  final ValueChanged<CgTunnel> onChanged;
  final Future<void> Function(CgTunnel tunnel)? onDelete;
""",
        """  final ValueChanged<CgTunnel> onChanged;
  final Future<void> Function(CgTunnel tunnel)? onDelete;
  final Future<void> Function(CgMessage message)? onForward;
""",
    )
    replace(
        chat,
        """    required this.onChanged,
    this.onDelete,
    this.onContactSeen,
""",
        """    required this.onChanged,
    this.onDelete,
    this.onForward,
    this.onContactSeen,
""",
    )
    replace(
        chat,
        """  bool _sendingFile = false;
  bool _hasText = false;
""",
        """  bool _sendingFile = false;
  bool _hasText = false;
  CgMessage? _replyingTo;
""",
    )

    reply_helpers = r'''
  Map<String, dynamic> _replyMeta() {
    final reply = _replyingTo;
    if (reply == null) return const <String, dynamic>{};
    return <String, dynamic>{
      'replyToId': reply.id,
      'replyAuthor': reply.authorName,
      'replyText': reply.text,
      'replyAttachmentName': reply.attachment?.name,
    };
  }

  void _replyTo(CgMessage message) {
    if (message.deleted) return;
    setState(() => _replyingTo = message);
    _composerFocus.requestFocus();
  }

  Future<void> _forward(CgMessage message) async {
    if (message.deleted) return;
    await widget.onForward?.call(message);
  }

'''
    if 'Map<String, dynamic> _replyMeta()' not in read(chat):
        insert_after(chat, "  Future<void> _connect() async {", "")
        source = read(chat)
        marker = "  Future<void> _connect() async {"
        source = source.replace(marker, reply_helpers + marker, 1)
        write(chat, source)

    replace(
        chat,
        """      sentAt: DateTime.now(),
    );
    _text.clear();
""",
        """      sentAt: DateTime.now(),
      meta: _replyMeta(),
    );
    _text.clear();
    setState(() => _replyingTo = null);
""",
    )
    replace(
        chat,
        """      type: 'attachment',
      attachment: attachment,
    );
    _appendLocal(message);
""",
        """      type: 'attachment',
      attachment: attachment,
      meta: _replyMeta(),
    );
    setState(() => _replyingTo = null);
    _appendLocal(message);
""",
    )

    multi_picker = r'''  Future<void> _pickAttachment(
    FileType type, {
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    const maxBytes = 20 * 1024 * 1024;
    var skipped = 0;
    setState(() => _sendingFile = true);
    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
          skipped++;
          continue;
        }
        final id = CgIds.random(20);
        final local = await CgMediaStore.persistBytes(
          attachmentId: id,
          name: file.name,
          bytes: bytes,
        );
        await _sendAttachment(
          CgAttachment(
            id: id,
            name: file.name,
            size: bytes.length,
            kind: _attachmentKind(file.name),
            dataBase64: base64Encode(bytes),
            localPath: local.path,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
    if (skipped > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? '$skipped файлов пропущено: пустые или больше 20 МБ.'
                : '$skipped files were skipped: empty or larger than 20 MB.',
          ),
        ),
      );
    }
  }

'''
    replace_between(
        chat,
        '  Future<void> _pickAttachment(',
        '  Future<void> _sendAttachment(CgAttachment attachment) async {',
        multi_picker,
    )

    # Long-press menu also exposes reply and forward.
    replace(
        chat,
        """              if (message.authorId == widget.profile.id) ...[
                const Divider(height: 28),
""",
        """              const Divider(height: 28),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(widget.ru ? 'Ответить' : 'Reply'),
                onTap: () => Navigator.pop(context, '__reply__'),
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: Text(widget.ru ? 'Переслать' : 'Forward'),
                onTap: () => Navigator.pop(context, '__forward__'),
              ),
              if (message.authorId == widget.profile.id) ...[
""",
    )
    replace(
        chat,
        """    if (selected == '__delete__') {
      await _deleteMessage(message);
    } else {
      await _toggleReaction(message, selected);
    }
""",
        """    if (selected == '__delete__') {
      await _deleteMessage(message);
    } else if (selected == '__reply__') {
      _replyTo(message);
    } else if (selected == '__forward__') {
      await _forward(message);
    } else {
      await _toggleReaction(message, selected);
    }
""",
    )

    # Swipe right to quote, swipe left to forward. confirmDismiss=false keeps
    # every text/file/music/circle message in place.
    old_bubble = """                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        privacyLens: widget.privacyLens,
                        ru: widget.ru,
                        onLongPress: () => _showMessageActions(message),
                      );
"""
    new_bubble = """                      return Dismissible(
                        key: ValueKey('swipe-${message.id}'),
                        direction: message.deleted
                            ? DismissDirection.none
                            : DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            _replyTo(message);
                          } else {
                            await _forward(message);
                          }
                          return false;
                        },
                        background: _SwipeActionBackground(
                          alignment: Alignment.centerLeft,
                          icon: Icons.reply_rounded,
                          label: widget.ru ? 'Ответить' : 'Reply',
                        ),
                        secondaryBackground: _SwipeActionBackground(
                          alignment: Alignment.centerRight,
                          icon: Icons.forward_rounded,
                          label: widget.ru ? 'Переслать' : 'Forward',
                        ),
                        child: _MessageBubble(
                          message: message,
                          mine: mine,
                          privacyLens: widget.privacyLens,
                          ru: widget.ru,
                          onLongPress: () => _showMessageActions(message),
                        ),
                      );
"""
    replace(chat, old_bubble, new_bubble)

    # Quote/forward labels inside every message bubble, including files.
    replace(
        chat,
        """              else ...[
                if (attachment != null)
""",
        """              else ...[
                if (message.meta['forwardedFrom'] != null) ...[
                  Text(
                    '${ru ? 'Переслано от' : 'Forwarded from'} ${message.meta['forwardedFrom']}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: mine
                          ? Colors.white70
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (message.meta['replyToId'] != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                      border: Border(
                        left: BorderSide(color: scheme.primary, width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.meta['replyAuthor']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: mine ? Colors.white : scheme.primary,
                          ),
                        ),
                        Text(
                          (message.meta['replyText']?.toString().isNotEmpty == true)
                              ? message.meta['replyText'].toString()
                              : (message.meta['replyAttachmentName']?.toString() ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: mine
                                ? Colors.white70
                                : scheme.onSurface.withValues(alpha: .65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                if (attachment != null)
""",
    )

    # Composer quote preview.
    replace(
        chat,
        """              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                borderRadius: BorderRadius.circular(22),
                child: Row(
""",
        """              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyingTo != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.reply_rounded, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _replyingTo!.authorName,
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  _replyingTo!.text.isNotEmpty
                                      ? _replyingTo!.text
                                      : (_replyingTo!.attachment?.name ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () => setState(() => _replyingTo = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                  GlassPanel(
                    padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                    borderRadius: BorderRadius.circular(22),
                    child: Row(
""",
    )
    # Close the extra composer Column after the inner GlassPanel.
    replace(
        chat,
        """                  ),
                ),
              ),
            ),
          ),
""",
        """                  ),
                    ),
                  ),
                ],
              ),
            ),
          ),
""",
    )

    # Call avatars in chat-level incoming dialogs and active calls.
    replace(
        chat,
        """    final video = signal['video'] == true;
    final fromName = signal['fromName']?.toString() ??
""",
        """    final video = signal['video'] == true;
    final callerAvatar = signal['avatarBase64']?.toString();
    final fromName = signal['fromName']?.toString() ??
""",
    )
    replace(
        chat,
        "unawaited(_showIncomingCall(callId, from, fromName, video));",
        "unawaited(_showIncomingCall(callId, from, fromName, callerAvatar, video));",
    )
    replace(
        chat,
        """    String fromName,
    bool video,
  ) async {
""",
        """    String fromName,
    String? callerAvatar,
    bool video,
  ) async {
""",
    )
    replace(
        chat,
        """        icon: Icon(
          video ? Icons.videocam_rounded : Icons.call_rounded,
          size: 38,
        ),
""",
        """        icon: CgCallAvatar(
          avatarBase64: callerAvatar,
          name: fromName,
          size: 78,
          fallbackIcon: video ? Icons.videocam_rounded : Icons.call_rounded,
        ),
""",
    )
    replace(
        chat,
        """          peerId: fromId,
          peerName: fromName,
          callId: callId,
""",
        """          peerId: fromId,
          peerName: fromName,
          peerAvatarBase64: callerAvatar,
          myAvatarBase64: widget.profile.avatarBase64,
          callId: callId,
""",
    )
    replace(
        chat,
        """          nickname: widget.profile.nickname,
          callId: callId,
          isCaller: true,
""",
        """          nickname: widget.profile.nickname,
          peerAvatarBase64: _tunnel.avatarBase64,
          myAvatarBase64: widget.profile.avatarBase64,
          callId: callId,
          isCaller: true,
""",
    )
    replace(
        chat,
        """          isHost: true,
          video: video,
          ru: widget.ru,
""",
        """          isHost: true,
          video: video,
          ru: widget.ru,
          myAvatarBase64: widget.profile.avatarBase64,
""",
    )
    replace(
        chat,
        """          isHost: false,
          video: video,
          ru: widget.ru,
""",
        """          isHost: false,
          video: video,
          ru: widget.ru,
          myAvatarBase64: widget.profile.avatarBase64,
""",
    )
    replace(chat, "const SizedBox(width: 20),", "const SizedBox(width: 10),")

    swipe_widget = r'''
class _SwipeActionBackground extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;

  const _SwipeActionBackground({
    required this.alignment,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

'''
    if 'class _SwipeActionBackground' not in read(chat):
        source = read(chat)
        marker = 'class _AttachmentAction extends StatelessWidget {'
        source = source.replace(marker, swipe_widget + marker, 1)
        write(chat, source)

    # Audio cards themselves are transparent; the outer message bubble was
    # already removed in 0.10.1.
    replace(
        'lib/chat_media.dart',
        """        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(16),
        ),
""",
        """        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
""",
    )

    # ------------------------------------------------------------------
    # Root app: unread badges/sorting, real music screen, forwarding, quick
    # phone-book/messenger invites, profile avatar in bottom navigation and
    # reserved nickname roots (stop words) restored.
    # ------------------------------------------------------------------
    v07 = 'lib/v07.dart'
    for import_line, after in [
        ("import 'package:flutter_contacts/flutter_contacts.dart';\n", "import 'package:file_picker/file_picker.dart';\n"),
        ("import 'package:share_plus/share_plus.dart';\n", "import 'package:package_info_plus/package_info_plus.dart';\n"),
        ("import 'package:shared_preferences/shared_preferences.dart';\n", "import 'package:share_plus/share_plus.dart';\n"),
        ("import 'music_player.dart';\n", "import 'internet_core.dart';\n"),
    ]:
        if import_line.strip() not in read(v07):
            replace(v07, after, after + import_line)

    stop_words = r'''
const String _chernogramLanding =
    'https://githubraw.com/jeep-jim/chernogram_new/main/docs/index.html';

const Set<String> _forbiddenNicknameRoots = <String>{
  'admin',
  'administrator',
  'support',
  'moderator',
  'security',
  'system',
  'official',
  'chernogram',
  'чернограм',
  'админ',
  'администратор',
  'поддержка',
  'модератор',
  'безопасность',
  'система',
  'официальный',
};

String _nicknameKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s._\-]+'), '')
    .replaceAll('0', 'o')
    .replaceAll('1', 'i');

String? _forbiddenNicknameRoot(String value) {
  final key = _nicknameKey(value);
  for (final root in _forbiddenNicknameRoots) {
    if (key.contains(_nicknameKey(root))) return root;
  }
  return null;
}

'''
    if '_forbiddenNicknameRoots' not in read(v07):
        source = read(v07)
        marker = 'class ChernogramV07 extends StatefulWidget {'
        source = source.replace(marker, stop_words + marker, 1)
        write(v07, source)

    replace(
        v07,
        """  bool _privacyLens = false;
  int _tab = 0;
""",
        """  bool _privacyLens = false;
  int _tab = 0;
  String? _activeTunnelId;
  Map<String, int> _unreadCounts = <String, int>{};
""",
    )
    replace(
        v07,
        """    final privacy = await CgStore.loadPrivacyLens();
    if (!mounted) return;
""",
        """    final privacy = await CgStore.loadPrivacyLens();
    final prefs = await SharedPreferences.getInstance();
    final unreadRaw = prefs.getString('chernogram_unread_v1');
    final unread = <String, int>{};
    if (unreadRaw != null) {
      try {
        final decoded = jsonDecode(unreadRaw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            unread[entry.key.toString()] =
                int.tryParse(entry.value.toString()) ?? 0;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
""",
    )
    replace(
        v07,
        """      _privacyLens = privacy;
      _loading = false;
""",
        """      _privacyLens = privacy;
      _unreadCounts = unread;
      _loading = false;
""",
    )

    unread_helpers = r'''
  Future<void> _persistUnread() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chernogram_unread_v1', jsonEncode(_unreadCounts));
  }

  void _markRead(String tunnelId) {
    if ((_unreadCounts[tunnelId] ?? 0) == 0) return;
    _unreadCounts[tunnelId] = 0;
    if (mounted) setState(() {});
    unawaited(_persistUnread());
  }

'''
    if 'Future<void> _persistUnread()' not in read(v07):
        source = read(v07)
        marker = '  Future<void> _listenLinks() async {'
        source = source.replace(marker, unread_helpers + marker, 1)
        write(v07, source)

    # Replace open tunnel method with active-chat/read tracking and forwarding.
    replace(
        v07,
        """    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgChatScreen(
""",
        """    _activeTunnelId = tunnel.id;
    _markRead(tunnel.id);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgChatScreen(
""",
    )
    replace(
        v07,
        """          onChanged: _updateTunnel,
          onDelete: _deleteTunnel,
          onContactSeen: _rememberContact,
""",
        """          onChanged: _updateTunnel,
          onDelete: _deleteTunnel,
          onForward: (message) => _forwardMessage(message, tunnel.id),
          onContactSeen: _rememberContact,
""",
    )
    replace(
        v07,
        """      ),
    );
  }

  void _updateTunnel(CgTunnel updated) {
""",
        """      ),
    );
    _activeTunnelId = null;
    _markRead(tunnel.id);
  }

  void _updateTunnel(CgTunnel updated) {
""",
    )

    # Count fresh incoming messages while the chat is not open.
    replace(
        v07,
        """  void _updateTunnel(CgTunnel updated) {
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
""",
        """  void _updateTunnel(CgTunnel updated) {
    final index = _tunnels.indexWhere((item) => item.id == updated.id);
    final previous = index < 0 ? null : _tunnels[index];
    if (previous != null && _activeTunnelId != updated.id) {
      final known = previous.messages.map((message) => message.id).toSet();
      final profileId = _profile?.id;
      final incoming = updated.messages.where((message) {
        if (known.contains(message.id) || message.authorId == profileId) return false;
        return DateTime.now().difference(message.sentAt.toLocal()).inMinutes.abs() <= 2;
      }).length;
      if (incoming > 0) {
        _unreadCounts[updated.id] = (_unreadCounts[updated.id] ?? 0) + incoming;
        unawaited(_persistUnread());
      }
    } else if (_activeTunnelId == updated.id) {
      _unreadCounts[updated.id] = 0;
    }
""",
    )

    forward_method = r'''
  Future<void> _forwardMessage(CgMessage source, String sourceTunnelId) async {
    if (source.deleted || !mounted) return;
    final targets = _tunnels
        .where((tunnel) => tunnel.id != sourceTunnelId)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Создайте ещё один чат для пересылки.'
                : 'Create another chat to forward this message.',
          ),
        ),
      );
      return;
    }
    final target = await showModalBottomSheet<CgTunnel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
          itemCount: targets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final tunnel = targets[index];
            return Card(
              child: ListTile(
                leading: _TunnelListAvatar(tunnel: tunnel),
                title: Text(
                  tunnel.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(widget.ru ? 'Переслать сюда' : 'Forward here'),
                onTap: () => Navigator.pop(context, tunnel),
              ),
            );
          },
        ),
      ),
    );
    final profile = _profile;
    if (target == null || profile == null) return;
    final forwarded = CgMessage(
      id: CgIds.random(24),
      authorId: profile.id,
      authorName: profile.nickname,
      text: source.text,
      sentAt: DateTime.now(),
      type: source.attachment == null ? 'text' : 'attachment',
      attachment: source.attachment,
      meta: <String, dynamic>{
        ...source.meta,
        'forwardedFrom': source.authorName,
      },
    );
    final updated = target.copyWith(
      messages: <CgMessage>[...target.messages, forwarded],
    );
    _updateTunnel(updated);
    final session = InternetRelay.session(target.id) ??
        await InternetRelay.open(
          tunnelId: target.id,
          secret: target.secret,
          profileId: profile.id,
          nickname: profile.nickname,
          history: updated.messages.map((message) => message.toJson()).toList(),
        );
    await session.sendMessage(forwarded.toJson());
  }

'''
    if 'Future<void> _forwardMessage' not in read(v07):
        source = read(v07)
        marker = '  void _rememberContact(CgContact incoming) {'
        source = source.replace(marker, forward_method + marker, 1)
        write(v07, source)

    # Real player is no longer a duplicate media manager.
    music_method = r'''
  Future<void> _openMusicPlayer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMusicPlayerScreen(
          ru: widget.ru,
          tunnels: _tunnels,
        ),
      ),
    );
  }

'''
    if 'Future<void> _openMusicPlayer()' not in read(v07):
        source = read(v07)
        marker = '  Future<void> _openMediaLibrary('
        source = source.replace(marker, music_method + marker, 1)
        write(v07, source)
    replace(
        v07,
        "onPressed: () => _openMediaLibrary(initialFilter: 'audio'),",
        "onPressed: _openMusicPlayer,",
    )

    invite_methods = r'''
  String _inviteText(CgTunnel tunnel) {
    final deep = 'chernogram://join/${Uri.encodeComponent(tunnel.inviteToken)}';
    final landing = '$_chernogramLanding?v=21&invite=${Uri.encodeQueryComponent(tunnel.inviteToken)}';
    return widget.ru
        ? 'Открой чат в Чернограме: $deep\n\nЕсли приложение не открылось: $landing'
        : 'Open the Chernogram chat: $deep\n\nIf the app did not open: $landing';
  }

  Future<CgTunnel?> _createInviteTunnel(String name) async {
    final profile = _profile;
    if (profile == null) return null;
    final tunnel = CgTunnel(
      id: CgIds.random(18),
      name: name.trim(),
      isPrivate: true,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      messages: const <CgMessage>[],
    );
    _tunnels = <CgTunnel>[tunnel, ..._tunnels];
    await CgStore.saveTunnels(_tunnels);
    _syncMonitor();
    if (mounted) setState(() {});
    return tunnel;
  }

  Future<void> _inviteFromPhoneBook() async {
    final allowed = await FlutterContacts.requestPermission();
    if (!allowed || !mounted) return;
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    if (!mounted) return;
    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .76,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final phone = contact.phones.isEmpty
                  ? ''
                  : contact.phones.first.number;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      contact.displayName.trim().isEmpty
                          ? '?'
                          : contact.displayName.trim()[0].toUpperCase(),
                    ),
                  ),
                  title: Text(
                    contact.displayName.trim().isEmpty
                        ? (widget.ru ? 'Без имени' : 'No name')
                        : contact.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: phone.isEmpty ? null : Text(phone),
                  trailing: const Icon(Icons.person_add_alt_1_rounded),
                  onTap: () => Navigator.pop(context, contact),
                ),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null) return;
    final tunnel = await _createInviteTunnel(selected.displayName);
    if (tunnel == null) return;
    await Share.share(_inviteText(tunnel));
    await _openTunnel(tunnel);
  }

  Future<void> _inviteViaMessengers() async {
    final tunnel = await _createInviteTunnel('');
    if (tunnel == null) return;
    await Share.share(_inviteText(tunnel));
    await _openTunnel(tunnel);
  }

'''
    if 'Future<void> _inviteFromPhoneBook()' not in read(v07):
        source = read(v07)
        marker = '  Future<void> _saveProfile(CgProfile profile) async {'
        source = source.replace(marker, invite_methods + marker, 1)
        write(v07, source)

    # Pass unread counts and invite actions to pages.
    replace(
        v07,
        """        privacyLens: _privacyLens,
        onCreate: _createTunnel,
""",
        """        privacyLens: _privacyLens,
        unreadCounts: _unreadCounts,
        onCreate: _createTunnel,
""",
    )
    replace(
        v07,
        """        privacyLens: _privacyLens,
        onOpen: _openContact,
""",
        """        privacyLens: _privacyLens,
        onOpen: _openContact,
        onInvitePhoneBook: _inviteFromPhoneBook,
        onInviteMessengers: _inviteViaMessengers,
""",
    )
    replace(
        v07,
        """  final bool privacyLens;
  final VoidCallback onCreate;
""",
        """  final bool privacyLens;
  final Map<String, int> unreadCounts;
  final VoidCallback onCreate;
""",
    )
    replace(
        v07,
        """    required this.privacyLens,
    required this.onCreate,
""",
        """    required this.privacyLens,
    required this.unreadCounts,
    required this.onCreate,
""",
    )
    replace(
        v07,
        """              ru: ru,
              onTap: () => onOpen(tunnel),
""",
        """              ru: ru,
              unreadCount: unreadCounts[tunnel.id] ?? 0,
              onTap: () => onOpen(tunnel),
""",
    )
    replace(
        v07,
        """  final bool ru;
  final VoidCallback onTap;
""",
        """  final bool ru;
  final int unreadCount;
  final VoidCallback onTap;
""",
    )
    replace(
        v07,
        """    required this.ru,
    required this.onTap,
""",
        """    required this.ru,
    required this.unreadCount,
    required this.onTap,
""",
    )
    replace(
        v07,
        """                        Icon(
                          tunnel.isPrivate
""",
        """                        if (unreadCount > 0) ...[
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Icon(
                          tunnel.isPrivate
""",
    )

    # Contacts invite UI.
    replace(
        v07,
        """  final Future<void> Function(CgContact contact) onOpen;

  const _ContactsScreen({
""",
        """  final Future<void> Function(CgContact contact) onOpen;
  final VoidCallback onInvitePhoneBook;
  final VoidCallback onInviteMessengers;

  const _ContactsScreen({
""",
    )
    replace(
        v07,
        """    required this.privacyLens,
    required this.onOpen,
  });
""",
        """    required this.privacyLens,
    required this.onOpen,
    required this.onInvitePhoneBook,
    required this.onInviteMessengers,
  });
""",
    )
    replace(
        v07,
        """        const SizedBox(height: 16),
        if (contacts.isEmpty)
""",
        """        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onInvitePhoneBook,
              icon: const Icon(Icons.contact_phone_rounded),
              label: Text(ru ? 'Телефонная книга' : 'Phone book'),
            ),
            OutlinedButton.icon(
              onPressed: onInviteMessengers,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(ru ? 'Мессенджеры' : 'Messengers'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (contacts.isEmpty)
""",
    )

    # Profile avatar replaces the generic bottom navigation profile icon.
    replace(
        v07,
        """          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person_rounded),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
""",
        """          NavigationDestination(
            icon: _ProfileNavAvatar(
              profile: _profile!,
              selected: false,
            ),
            selectedIcon: _ProfileNavAvatar(
              profile: _profile!,
              selected: true,
            ),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
""",
    )

    nav_avatar = r'''
class _ProfileNavAvatar extends StatelessWidget {
  final CgProfile profile;
  final bool selected;

  const _ProfileNavAvatar({required this.profile, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
        width: selected ? 32 : 28,
        height: selected ? 32 : 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: _ProfileAvatar(
          nickname: profile.nickname,
          avatarBase64: profile.avatarBase64,
          size: selected ? 26 : 22,
        ),
      );
}

'''
    if 'class _ProfileNavAvatar' not in read(v07):
        source = read(v07)
        marker = 'class _ChatsHome extends StatelessWidget {'
        source = source.replace(marker, nav_avatar + marker, 1)
        write(v07, source)

    # Stop words / forbidden nickname roots are enforced on every save.
    replace(
        v07,
        """    if (nickname.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
""",
        """    if (nickname.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
""",
    )
    profile_source = read(v07)
    marker = """      return;
    }
    widget.onSave(
      widget.profile.copyWith(
"""
    replacement = """      return;
    }
    final forbiddenRoot = _forbiddenNicknameRoot(nickname);
    if (forbiddenRoot != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'Этот ник содержит запрещённое слово: $forbiddenRoot'
                : 'This nickname contains a reserved word: $forbiddenRoot',
          ),
        ),
      );
      return;
    }
    widget.onSave(
      widget.profile.copyWith(
"""
    if marker in profile_source and 'final forbiddenRoot = _forbiddenNicknameRoot' not in profile_source:
        write(v07, profile_source.replace(marker, replacement, 1))

    # Ten-pixel separation between profile action buttons.
    replace(
        v07,
        """          OutlinedButton.icon(
            onPressed: widget.onCheckUpdates,
""",
        """          OutlinedButton.icon(
            onPressed: widget.onCheckUpdates,
""",
    )
    replace(
        v07,
        """          OutlinedButton.icon(
            onPressed: widget.onChangeLanguage,
""",
        """          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onChangeLanguage,
""",
    )
    replace(v07, "const SizedBox(width: 6),", "const SizedBox(width: 10),")

    # ------------------------------------------------------------------
    # Fix nullable PhotoManager title and make player startup reliable.
    # ------------------------------------------------------------------
    music = 'lib/music_player.dart'
    replace(
        music,
        "final title = (await asset.titleAsync).trim();",
        "final title = ((await asset.titleAsync) ?? '').trim();",
    )
    replace(
        music,
        "activeTrackId.value == track.id && player.audioSource != null",
        "activeTrackId.value == track.id && queue.value.isNotEmpty",
    )

    print('Applied Chernogram 0.11 messenger polish and background music')


if __name__ == '__main__':
    main()
