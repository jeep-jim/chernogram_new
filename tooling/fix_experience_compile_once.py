from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: source block not found')
    return text.replace(old, new, 1)


# Android audio metadata can omit a creation timestamp.
path = Path('lib/music_player.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """            addedAt: DateTime.fromMillisecondsSinceEpoch(asset.createDateSecond * 1000)
                .toUtc(),""",
    """            addedAt: asset.createDateSecond == null
                ? DateTime.now().toUtc()
                : DateTime.fromMillisecondsSinceEpoch(
                    asset.createDateSecond! * 1000,
                  ).toUtc(),""",
    'music nullable create date',
)
path.write_text(text, encoding='utf-8')

# Add a lightweight reusable background wrapper without touching the approved logo.
background = Path('lib/chat_background.dart')
bg = background.read_text(encoding='utf-8')
if 'class CgChatBackgroundContainer' not in bg:
    marker = 'class CgChatBackdrop extends StatefulWidget {'
    wrapper = '''class CgChatBackgroundContainer extends StatelessWidget {
  final Widget child;

  const CgChatBackgroundContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const CgChatBackdrop(),
          child,
        ],
      );
}

'''
    bg = replace_once(bg, marker, wrapper + marker, 'chat backdrop wrapper')
background.write_text(bg, encoding='utf-8')

# Chat UX: selectable/copyable text, avatars, profile sheet and background patterns.
chat = Path('lib/chat_screen.dart')
source = chat.read_text(encoding='utf-8')
source = replace_once(
    source,
    "import 'call_service.dart';\nimport 'chat_media.dart';\n",
    "import 'call_service.dart';\nimport 'chat_background.dart';\nimport 'chat_media.dart';\n",
    'chat background import',
)
source = replace_once(
    source,
    '''              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: Text(widget.ru ? 'Переслать' : 'Forward'),
                onTap: () => Navigator.pop(context, '__forward__'),
              ),
              if (message.authorId == widget.profile.id) ...[''',
    '''              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: Text(widget.ru ? 'Переслать' : 'Forward'),
                onTap: () => Navigator.pop(context, '__forward__'),
              ),
              if (message.text.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(widget.ru ? 'Копировать текст' : 'Copy text'),
                  onTap: () => Navigator.pop(context, '__copy__'),
                ),
              if (message.authorId == widget.profile.id) ...[''',
    'message copy action',
)
source = replace_once(
    source,
    '''    } else if (selected == '__forward__') {
      await _forward(message);
    } else {
      await _toggleReaction(message, selected);
    }''',
    '''    } else if (selected == '__forward__') {
      await _forward(message);
    } else if (selected == '__copy__') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.ru ? 'Текст скопирован' : 'Text copied'),
          ),
        );
      }
    } else {
      await _toggleReaction(message, selected);
    }''',
    'copy result handler',
)
source = replace_once(
    source,
    '    return Text.rich(TextSpan(style: widget.style, children: _spans()));',
    '''    return SelectionArea(
      child: Text.rich(TextSpan(style: widget.style, children: _spans())),
    );''',
    'selectable message text',
)
source = replace_once(
    source,
    '''            Padding(
              padding: const EdgeInsets.all(8),
              child: _TunnelAvatar(tunnel: _tunnel, size: 42),
            ),''',
    '''            Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: _showChatProfile,
                child: _TunnelAvatar(tunnel: _tunnel, size: 42),
              ),
            ),''',
    'chat avatar profile tap',
)
source = replace_once(
    source,
    '''                case 'shared':
                  _showSharedLibrary();
                  break;
                case 'settings':
                  _showSettings();
                  break;''',
    '''                case 'shared':
                  _showSharedLibrary();
                  break;
                case 'profile':
                  _showChatProfile();
                  break;
                case 'appearance':
                  CgChatAppearanceController.instance.showSettings(
                    context,
                    ru: widget.ru,
                  );
                  break;
                case 'settings':
                  _showSettings();
                  break;''',
    'chat menu handlers',
)
source = replace_once(
    source,
    '''              PopupMenuItem(
                value: 'shared',
                child: ListTile(
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: Text(widget.ru ? 'Общие файлы' : 'Shared files'),
                ),
              ),''',
    '''              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(widget.ru ? 'Профиль чата' : 'Chat profile'),
                ),
              ),
              PopupMenuItem(
                value: 'shared',
                child: ListTile(
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: Text(widget.ru ? 'Общие файлы' : 'Shared files'),
                ),
              ),
              PopupMenuItem(
                value: 'appearance',
                child: ListTile(
                  leading: const Icon(Icons.wallpaper_rounded),
                  title: Text(widget.ru ? 'Фон и паттерн' : 'Background pattern'),
                ),
              ),''',
    'chat profile and appearance menu items',
)
profile_marker = '  Future<void> _showInvite() async {'
profile_method = '''  Future<void> _showChatProfile() async {
    final members = _session?.members ?? const <Map<String, dynamic>>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            children: [
              _TunnelAvatar(tunnel: _tunnel, size: 86),
              const SizedBox(height: 12),
              Text(
                widget.privacyLens ? '••••••••' : _tunnel.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                _tunnel.isPrivate
                    ? (widget.ru ? 'Приватный чат' : 'Private chat')
                    : (widget.ru ? 'Публичный чат' : 'Public chat'),
              ),
              const SizedBox(height: 12),
              SelectableText(
                'ID ${_tunnel.id}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .50),
                ),
              ),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.ru ? 'Участники' : 'Members',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 6),
              if (members.isEmpty)
                ListTile(
                  leading: const Icon(Icons.hourglass_empty_rounded),
                  title: Text(
                    widget.ru
                        ? 'Участники появятся после подключения'
                        : 'Members appear after connecting',
                  ),
                )
              else
                for (final member in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        (member['name']?.toString().trim().isNotEmpty == true
                                ? member['name'].toString().trim()[0]
                                : '?')
                            .toUpperCase(),
                      ),
                    ),
                    title: Text(member['name']?.toString() ?? 'user'),
                    subtitle: Text(member['id']?.toString() ?? ''),
                    trailing: member['self'] == true
                        ? Text(widget.ru ? 'вы' : 'you')
                        : null,
                  ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_canInvite)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(_showInvite());
                        },
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(widget.ru ? 'Добавить людей' : 'Add people'),
                      ),
                    ),
                  if (_canInvite) const SizedBox(width: 9),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(_showSettings());
                      },
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(widget.ru ? 'Разрешения' : 'Permissions'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
source = replace_once(
    source,
    profile_marker,
    profile_method + profile_marker,
    'chat profile method',
)
source = replace_once(
    source,
    '''        child: Column(
        children: [''',
    '''        child: CgChatBackgroundContainer(
          child: Column(
        children: [''',
    'chat background wrapper start',
)
source = replace_once(
    source,
    '''          ],
        ),
      ),
      ),
    );
  }
}


class _SwipeActionBackground''',
    '''          ],
        ),
          ),
      ),
      ),
    );
  }
}


class _SwipeActionBackground''',
    'chat background wrapper end',
)
old_bubble = '''                        child: _MessageBubble(
                          message: message,
                          mine: mine,
                          privacyLens: widget.privacyLens,
                          ru: widget.ru,
                          onLongPress: () => _showMessageActions(message),
                          onEnsureAttachment: _ensureAttachment,
                          onPlayAudio: _playAttachment,
                          onDelete: _deleteMessage,
                          canDownload: _canDownload,
                        ),'''
new_bubble = '''                        child: Row(
                          mainAxisAlignment: mine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!mine) ...[
                              _MessageAuthorAvatar(message: message, mine: false),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: _MessageBubble(
                                message: message,
                                mine: mine,
                                privacyLens: widget.privacyLens,
                                ru: widget.ru,
                                onLongPress: () => _showMessageActions(message),
                                onEnsureAttachment: _ensureAttachment,
                                onPlayAudio: _playAttachment,
                                onDelete: _deleteMessage,
                                canDownload: _canDownload,
                              ),
                            ),
                            if (mine) ...[
                              const SizedBox(width: 6),
                              _MessageAuthorAvatar(message: message, mine: true),
                            ],
                          ],
                        ),'''
source = replace_once(source, old_bubble, new_bubble, 'message avatars row')
avatar_marker = 'class _TunnelAvatar extends StatelessWidget {'
avatar_class = '''class _MessageAuthorAvatar extends StatelessWidget {
  final CgMessage message;
  final bool mine;

  const _MessageAuthorAvatar({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final raw = message.meta['avatarBase64']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 15,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {}
    }
    final name = message.authorName.trim();
    return CircleAvatar(
      radius: 15,
      backgroundColor: mine
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: mine
              ? Colors.white
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

'''
source = replace_once(
    source,
    avatar_marker,
    avatar_class + avatar_marker,
    'message author avatar class',
)
chat.write_text(source, encoding='utf-8')

# Device address book and dialer entry inside the Contacts section.
v12 = Path('lib/v12.dart')
v = v12.read_text(encoding='utf-8')
v = replace_once(
    v,
    "import 'core_models.dart';\nimport 'group_call_service.dart';\n",
    "import 'core_models.dart';\nimport 'device_contacts_screen.dart';\nimport 'group_call_service.dart';\n",
    'device contacts import',
)
v = replace_once(
    v,
    '''        Text(
          ru
              ? 'Здесь сохраняются люди, с которыми вы общались.'
              : 'People you have chatted with are saved here.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: .56)),
        ),
        const SizedBox(height: 16),''',
    '''        Text(
          ru
              ? 'Здесь сохраняются люди, с которыми вы общались.'
              : 'People you have chatted with are saved here.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: .56)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgDeviceContactsScreen(ru: ru),
              ),
            ),
            icon: const Icon(Icons.contact_phone_outlined),
            label: Text(ru ? 'Телефонная книга и набор номера' : 'Phone book and dialer'),
          ),
        ),
        const SizedBox(height: 16),''',
    'contacts phone book entry',
)
v12.write_text(v, encoding='utf-8')

print('Applied Experience Suite compile and local UX fixes')
