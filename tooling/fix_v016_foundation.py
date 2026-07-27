from pathlib import Path
import re


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise RuntimeError(f'Expected block was not found: {label}')
    return source.replace(old, new, 1)


def patch_v12() -> bool:
    path = Path('lib/v12.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    source = replace_once(
        source,
        """      _V12ChatsHome(
        ru: widget.ru,
        tunnels: _tunnels,
        unreadCounts: _unreadCounts,
        privacyLens: _privacyLens,
        onCreate: _createTunnel,
        onScan: _scanQr,
        onOpen: _openTunnel,
      ),
""",
        """      _V12ChatsHome(
        ru: widget.ru,
        tunnels: _tunnels,
        contacts: _contacts,
        unreadCounts: _unreadCounts,
        privacyLens: _privacyLens,
        onCreate: _createTunnel,
        onScan: _scanQr,
        onOpen: _openTunnel,
        onOpenContact: _openContact,
      ),
""",
        'chat home dependencies',
    )

    new_class = r'''class _V12ChatsHome extends StatefulWidget {
  final bool ru;
  final List<CgTunnel> tunnels;
  final List<CgContact> contacts;
  final Map<String, int> unreadCounts;
  final bool privacyLens;
  final VoidCallback onCreate;
  final VoidCallback onScan;
  final Future<void> Function(CgTunnel tunnel) onOpen;
  final Future<void> Function(CgContact contact) onOpenContact;

  const _V12ChatsHome({
    required this.ru,
    required this.tunnels,
    required this.contacts,
    required this.unreadCounts,
    required this.privacyLens,
    required this.onCreate,
    required this.onScan,
    required this.onOpen,
    required this.onOpenContact,
  });

  @override
  State<_V12ChatsHome> createState() => _V12ChatsHomeState();
}

class _V12ChatsHomeState extends State<_V12ChatsHome> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;
  bool _aboutOpen = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<CgTunnel> get _visibleTunnels => widget.tunnels
      .where((item) => !item.id.startsWith('dm_') || item.messages.isNotEmpty)
      .toList(growable: false);

  String _key(String value) => value.trim().toLowerCase();

  bool _chatMatches(CgTunnel tunnel, String query) {
    if (_key(tunnel.displayName).contains(query)) return true;
    return tunnel.messages.reversed.take(50).any((message) =>
        _key(message.authorName).contains(query) ||
        _key(message.text).contains(query) ||
        _key(message.attachment?.name ?? '').contains(query));
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleTunnels;
    final query = _key(_search.text);
    final foundChats = query.isEmpty
        ? const <CgTunnel>[]
        : visible.where((item) => _chatMatches(item, query)).toList();
    final foundPeople = query.isEmpty
        ? const <CgContact>[]
        : widget.contacts.where((item) {
            return _key(item.nickname).contains(query) ||
                _key(item.id).contains(query);
          }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 106),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.ru
                          ? 'Общайся без впн и рекламы.'
                          : 'Chat without VPN or ads.',
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: widget.ru ? 'О проекте' : 'About',
                    onPressed: () => setState(() => _aboutOpen = !_aboutOpen),
                    icon: AnimatedRotation(
                      turns: _aboutOpen ? .5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _aboutOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.ru
                                  ? 'Чернограм объединяет чаты, звонки, файлы, музыку и прямой обмен между людьми и собственными устройствами. История хранится локально, а тяжёлый контент загружается только по запросу.'
                                  : 'Chernogram combines chats, calls, files, music and direct sharing between people and your own devices. History stays local and heavy content loads only on demand.',
                              style: TextStyle(
                                height: 1.35,
                                color: scheme.onSurface.withValues(alpha: .66),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: <Widget>[
                                _pill(context, Icons.block_rounded,
                                    widget.ru ? 'Без рекламы' : 'No ads'),
                                _pill(context, Icons.folder_copy_outlined,
                                    widget.ru ? 'P2P-файлы' : 'P2P files'),
                                _pill(context, Icons.offline_bolt_outlined,
                                    widget.ru ? 'Локальная история' : 'Local history'),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _searching
                    ? TextField(
                        key: const ValueKey<String>('home-search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: widget.ru
                              ? 'Чаты, люди и аккаунты'
                              : 'Chats, people and accounts',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            onPressed: _closeSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                          filled: true,
                          fillColor: scheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      )
                    : Row(
                        key: const ValueKey<String>('home-actions'),
                        children: <Widget>[
                          Expanded(
                            flex: 4,
                            child: FilledButton.tonalIcon(
                              onPressed: _openSearch,
                              icon: const Icon(Icons.search_rounded),
                              label: Text(widget.ru ? 'Поиск' : 'Search'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 6,
                            child: FilledButton.icon(
                              onPressed: widget.onCreate,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(widget.ru ? 'Новый чат' : 'New chat'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: FilledButton.tonalIcon(
                              onPressed: widget.onScan,
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: const Text('QR'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        if (_searching)
          ..._searchResults(context, query, foundChats, foundPeople)
        else ...<Widget>[
          _header(context, widget.ru ? 'Чаты' : 'Chats', '${visible.length}'),
          const SizedBox(height: 6),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 54),
              child: Column(
                children: <Widget>[
                  Icon(Icons.forum_outlined,
                      size: 64,
                      color: scheme.onSurface.withValues(alpha: .16)),
                  const SizedBox(height: 12),
                  Text(widget.ru ? 'Чатов пока нет' : 'No chats yet',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            )
          else
            for (final tunnel in visible) _chatTile(context, tunnel),
        ],
      ],
    );
  }

  List<Widget> _searchResults(BuildContext context, String query,
      List<CgTunnel> chats, List<CgContact> people) {
    final scheme = Theme.of(context).colorScheme;
    if (query.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
          child: Text(
            widget.ru
                ? 'Введите название чата, никнейм или ID аккаунта.'
                : 'Type a chat name, nickname or account ID.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: .55)),
          ),
        ),
      ];
    }
    if (chats.isEmpty && people.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Center(
            child: Text(widget.ru ? 'Ничего не найдено' : 'Nothing found'),
          ),
        ),
      ];
    }
    return <Widget>[
      if (chats.isNotEmpty) ...<Widget>[
        _header(context, widget.ru ? 'Чаты' : 'Chats', '${chats.length}'),
        for (final tunnel in chats) _chatTile(context, tunnel),
        const SizedBox(height: 12),
      ],
      if (people.isNotEmpty) ...<Widget>[
        _header(context, widget.ru ? 'Люди и аккаунты' : 'People and accounts',
            '${people.length}'),
        for (final contact in people) _contactTile(context, contact),
      ],
    ];
  }

  Widget _header(BuildContext context, String title, String count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w900)),
          ),
          Text(count,
              style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: .45))),
        ],
      ),
    );
  }

  Widget _chatTile(BuildContext context, CgTunnel tunnel) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(widget.onOpen(tunnel)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          child: Row(
            children: <Widget>[
              _V12TunnelAvatar(tunnel: tunnel, size: 50),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.privacyLens ? '••••••••' : tunnel.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      widget.privacyLens
                          ? '••••••••••'
                          : _lastMessage(tunnel, widget.ru),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: .52)),
                    ),
                  ],
                ),
              ),
              if ((widget.unreadCounts[tunnel.id] ?? 0) > 0)
                Container(
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('${widget.unreadCounts[tunnel.id]}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactTile(BuildContext context, CgContact contact) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(widget.onOpenContact(contact)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          child: Row(
            children: <Widget>[
              _V12ProfileAvatar(
                nickname: contact.nickname,
                avatarBase64: contact.avatarBase64,
                size: 48,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.privacyLens ? '••••••••' : contact.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(widget.privacyLens ? '••••••••' : 'ID ${contact.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: .52))),
                  ],
                ),
              ),
              Icon(Icons.chat_bubble_outline_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface.withValues(alpha: .72))),
        ],
      ),
    );
  }

  static String _lastMessage(CgTunnel tunnel, bool ru) {
    final visible = tunnel.messages
        .where((message) => message.meta['localHidden'] != true)
        .toList();
    if (visible.isEmpty) return ru ? 'Готов к приглашению' : 'Ready to invite';
    final message = visible.last;
    if (message.deleted) return ru ? 'Сообщение удалено' : 'Message deleted';
    if (message.type == 'call') return ru ? 'Звонок' : 'Call';
    if (message.attachment != null) return message.attachment!.name;
    return message.text;
  }
}
'''

    pattern = re.compile(
        r'class _V12ChatsHome extends (?:StatelessWidget|StatefulWidget) \{.*?\nclass _V12TunnelAvatar',
        re.S,
    )
    match = pattern.search(source)
    if not match:
        raise RuntimeError('Chats home class was not found')
    source = (source[:match.start()] + new_class +
              '\nclass _V12TunnelAvatar' + source[match.end():])

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_sound_service() -> bool:
    path = Path('lib/sound_service.dart')
    new_source = r'''import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class ChernogramSound {
  static const MethodChannel _channel = MethodChannel('chernogram/sound');
  static const List<String> _incomingAssets = <String>[
    'assets/audio/incoming_call.part1',
    'assets/audio/incoming_call.part2',
    'assets/audio/incoming_call.part3',
    'assets/audio/incoming_call.part4',
    'assets/audio/incoming_call.part5',
    'assets/audio/incoming_call.part6',
  ];
  static AudioPlayer? _incomingPlayer;
  static Future<File>? _incomingFileFuture;

  static Future<void> playMessage() async {
    try {
      await _channel.invokeMethod<void>('playMessage');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<File> _incomingFile() =>
      _incomingFileFuture ??= _prepareIncomingFile();

  static Future<File> _prepareIncomingFile() async {
    final temp = await getTemporaryDirectory();
    final file = File(
      '${temp.path}${Platform.pathSeparator}chernogram-incoming-call-v1.mp3',
    );
    if (await file.exists() && await file.length() > 1024) return file;
    final buffer = StringBuffer();
    for (final asset in _incomingAssets) {
      buffer.write(await rootBundle.loadString(asset));
    }
    final encoded = buffer.toString().replaceAll(RegExp(r'\s+'), '');
    await file.writeAsBytes(base64Decode(encoded), flush: true);
    return file;
  }

  static Future<void> startIncomingCall({required bool video}) async {
    await stopIncomingCall();
    var customStarted = false;
    try {
      final file = await _incomingFile();
      final player = AudioPlayer();
      _incomingPlayer = player;
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1.0);
      await player.setFilePath(file.path);
      unawaited(player.play());
      customStarted = true;
    } catch (_) {
      await _incomingPlayer?.dispose();
      _incomingPlayer = null;
    }
    try {
      await _channel.invokeMethod<void>(
        'startIncomingCall',
        <String, dynamic>{'video': video, 'customSound': customStarted},
      );
    } catch (_) {
      if (!customStarted) await SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> stopIncomingCall() async {
    final player = _incomingPlayer;
    _incomingPlayer = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      await player.dispose();
    }
    try {
      await _channel.invokeMethod<void>('stopIncomingCall');
    } catch (_) {}
  }
}
'''
    old = path.read_text(encoding='utf-8')
    if old == new_source:
        return False
    path.write_text(new_source, encoding='utf-8')
    return True


def patch_android_activity() -> bool:
    path = Path(
        'android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt'
    )
    source = path.read_text(encoding='utf-8')
    original = source
    source = replace_once(
        source,
        '''                "startIncomingCall" -> {
                    startIncomingCallSound()
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
''',
        '''                "startIncomingCall" -> {
                    val customSound = call.argument<Boolean>("customSound") ?: false
                    if (!customSound) startIncomingCallSound()
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
''',
        'Android custom incoming ringtone',
    )
    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_pubspec() -> bool:
    path = Path('pubspec.yaml')
    source = path.read_text(encoding='utf-8')
    original = source
    if 'assets/audio/incoming_call.part1' not in source:
        source = replace_once(
            source,
            '''flutter:
  uses-material-design: true
''',
            '''flutter:
  uses-material-design: true
  assets:
    - assets/audio/incoming_call.part1
    - assets/audio/incoming_call.part2
    - assets/audio/incoming_call.part3
    - assets/audio/incoming_call.part4
    - assets/audio/incoming_call.part5
    - assets/audio/incoming_call.part6
''',
            'incoming ringtone assets',
        )
    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def main() -> None:
    changed = False
    changed |= patch_v12()
    changed |= patch_sound_service()
    changed |= patch_android_activity()
    changed |= patch_pubspec()
    print(
        'Applied Chernogram 0.16 home, global search and custom ringtone'
        if changed
        else 'Chernogram 0.16 foundation is already applied'
    )


if __name__ == '__main__':
    main()
