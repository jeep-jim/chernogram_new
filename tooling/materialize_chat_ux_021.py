from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: source block not found')
    return text.replace(old, new, 1)


def find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    index = open_index
    quote = None
    triple = False
    line_comment = False
    block_comment = False
    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ''

        if line_comment:
            if char == '\n':
                line_comment = False
            index += 1
            continue
        if block_comment:
            if char == '*' and nxt == '/':
                block_comment = False
                index += 2
            else:
                index += 1
            continue
        if quote is not None:
            if triple:
                if text.startswith(quote * 3, index):
                    quote = None
                    triple = False
                    index += 3
                    continue
                index += 1
                continue
            if char == '\\':
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue

        if char == '/' and nxt == '/':
            line_comment = True
            index += 2
            continue
        if char == '/' and nxt == '*':
            block_comment = True
            index += 2
            continue
        if char in ("'", '"'):
            quote = char
            triple = text.startswith(char * 3, index)
            index += 3 if triple else 1
            continue
        if char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise SystemExit('matching parenthesis not found')


# Version.
pubspec = Path('pubspec.yaml')
pub = pubspec.read_text(encoding='utf-8')
pub = replace_once(pub, 'version: 0.20.0+50', 'version: 0.21.0+51', 'version')
pubspec.write_text(pub, encoding='utf-8')


# Chat screen UX.
chat_path = Path('lib/chat_screen.dart')
chat = chat_path.read_text(encoding='utf-8')

if 'onCreateGroupFromDirect' not in chat:
    chat = replace_once(
        chat,
        """  final ValueChanged<CgContact>? onContactSeen;

  const CgChatScreen({""",
        """  final ValueChanged<CgContact>? onContactSeen;
  final Future<void> Function(CgTunnel source)? onCreateGroupFromDirect;

  const CgChatScreen({""",
        'chat callback field',
    )
    chat = replace_once(
        chat,
        """    this.onForward,
    this.onContactSeen,
    this.autoInvite = false,""",
        """    this.onForward,
    this.onContactSeen,
    this.onCreateGroupFromDirect,
    this.autoInvite = false,""",
        'chat callback constructor',
    )

# Tapping the existing approved chat avatar opens the profile sheet.
old_avatar = """            Padding(
              padding: const EdgeInsets.all(8),
              child: _TunnelAvatar(tunnel: _tunnel, size: 42),
            ),"""
new_avatar = """            InkWell(
              onTap: _showChatProfile,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _TunnelAvatar(tunnel: _tunnel, size: 42),
              ),
            ),"""
if old_avatar in chat:
    chat = chat.replace(old_avatar, new_avatar, 1)

# Real pattern below the chat content. Locate the exact Column owned by DropTarget.
if 'CgChatBackgroundContainer(child: Column(' not in chat:
    body_anchor = chat.index('      body: DropTarget(')
    column_start = chat.index('Column(', body_anchor)
    open_index = chat.index('(', column_start)
    close_index = find_matching_paren(chat, open_index)
    original = chat[column_start : close_index + 1]
    wrapped = f'CgChatBackgroundContainer(child: {original})'
    chat = chat[:column_start] + wrapped + chat[close_index + 1 :]

# Convert a one-to-one chat into a separate group while preserving local history.
profile_start = chat.index('  Future<void> _showChatProfile() async {')
profile_end = chat.index('  Future<void> _showInvite() async {', profile_start)
profile = chat[profile_start:profile_end]
if 'Создать группу из переписки' not in profile:
    insert_at = profile.rfind('            ],\n          ),')
    if insert_at < 0:
        raise SystemExit('chat profile column end not found')
    group_block = """              if (_tunnel.id.startsWith('dm_') &&
                  widget.onCreateGroupFromDirect != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(
                        widget.onCreateGroupFromDirect!.call(_tunnel),
                      );
                    },
                    icon: const Icon(Icons.group_add_rounded),
                    label: Text(
                      widget.ru
                          ? 'Создать группу из переписки'
                          : 'Create group from this chat',
                    ),
                  ),
                ),
              ],
"""
    profile = profile[:insert_at] + group_block + profile[insert_at:]
    chat = chat[:profile_start] + profile + chat[profile_end:]

chat_path.write_text(chat, encoding='utf-8')


# Root creates a new independent tunnel and immediately opens its invite.
v12_path = Path('lib/v12.dart')
v12 = v12_path.read_text(encoding='utf-8')
if '_createGroupFromDirect' not in v12:
    method_anchor = '  Future<void> _openTunnel(CgTunnel tunnel, {bool autoInvite = false}) async {'
    method_index = v12.index(method_anchor)
    method = r'''  Future<void> _createGroupFromDirect(CgTunnel source) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final name = TextEditingController(
      text: widget.ru
          ? 'Группа: ${source.displayName}'
          : 'Group: ${source.displayName}',
    );
    var isPrivate = true;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.ru
                    ? 'Новая группа из переписки'
                    : 'New group from conversation',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ru
                    ? 'История личной переписки будет скопирована в новый отдельный чат. Исходный личный чат останется без изменений.'
                    : 'The direct conversation history will be copied into a new independent chat. The original direct chat remains unchanged.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.ru ? 'Название группы' : 'Group name',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: isPrivate,
                secondary: Icon(
                  isPrivate
                      ? Icons.visibility_off_outlined
                      : Icons.public_rounded,
                ),
                title: Text(
                  isPrivate
                      ? (widget.ru ? 'Приватная группа' : 'Private group')
                      : (widget.ru ? 'Открытая группа' : 'Public group'),
                ),
                subtitle: Text(
                  isPrivate
                      ? (widget.ru
                          ? 'Вход только по приглашению или QR.'
                          : 'Join only through an invite or QR.')
                      : (widget.ru
                          ? 'Ссылку можно свободно пересылать.'
                          : 'The invite can be freely shared.'),
                ),
                onChanged: (value) =>
                    setSheetState(() => isPrivate = value),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.group_add_rounded),
                  label: Text(
                    widget.ru ? 'Создать и пригласить' : 'Create and invite',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted != true || !mounted) {
      name.dispose();
      return;
    }
    final displayName = name.text.trim().isEmpty
        ? (widget.ru ? 'Новая группа' : 'New group')
        : name.text.trim();
    name.dispose();
    final group = CgTunnel(
      id: CgIds.random(18),
      name: displayName,
      isPrivate: isPrivate,
      ownerId: profile.id,
      secret: CgIds.random(42),
      createdAt: DateTime.now(),
      avatarBase64: source.avatarBase64,
      messages: List<CgMessage>.from(source.messages),
      permissions: const CgPermissions(canInvite: true),
    );
    setState(() => _tunnels = <CgTunnel>[group, ..._tunnels]);
    await _saveTunnelsFast(_tunnels);
    if (!mounted) return;
    await _openTunnel(group, autoInvite: true);
  }

'''
    v12 = v12[:method_index] + method + v12[method_index:]

callback_anchor = """          onForward: (message) => _forwardMessage(message, current.id),
          onContactSeen: _rememberContact,"""
callback_new = """          onForward: (message) => _forwardMessage(message, current.id),
          onContactSeen: _rememberContact,
          onCreateGroupFromDirect: _createGroupFromDirect,"""
if callback_anchor in v12 and 'onCreateGroupFromDirect: _createGroupFromDirect' not in v12:
    v12 = v12.replace(callback_anchor, callback_new, 1)

v12_path.write_text(v12, encoding='utf-8')
print('Chat UX 0.21 materialized')
