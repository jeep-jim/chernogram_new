from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def replace_between(path: str, start: str, end: str, replacement: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    left = source.find(start)
    right = source.find(end, left)
    if left < 0 or right < 0:
        return
    file.write_text(source[:left] + replacement + source[right:], encoding='utf-8')


def restore_broad_closings() -> None:
    path = Path('lib/chat_screen.dart')
    source = path.read_text(encoding='utf-8')
    source = source.replace(
        """                  ),
                    ),
                  ),
                ],
              ),
            ),
          ),
""",
        """                  ),
                ),
              ),
            ),
          ),
""",
    )
    path.write_text(source, encoding='utf-8')


def rebuild_settings() -> None:
    settings = r'''  Future<void> _showSettings() async {
    final name = TextEditingController(text: _tunnel.name);
    var isPrivate = _tunnel.isPrivate;
    var revoke = false;
    final fileCount = _tunnel.messages
        .where((message) => !message.deleted && message.attachment != null)
        .length;
    final created = _tunnel.createdAt.toLocal().toString();
    final createdLabel = created.length >= 16 ? created.substring(0, 16) : created;
    final secret = _tunnel.secret;
    final secretLabel = secret.length > 12
        ? '${secret.substring(0, 6)}…${secret.substring(secret.length - 4)}'
        : secret;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .90,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.ru ? 'Настройки чата' : 'Chat settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    readOnly: !_isOwner,
                    decoration: InputDecoration(
                      labelText: widget.ru ? 'Название чата' : 'Chat name',
                      suffixIcon: _isOwner
                          ? const Icon(Icons.edit_outlined)
                          : const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.fingerprint_rounded),
                          title: Text(widget.ru ? 'ID чата' : 'Chat ID'),
                          subtitle: SelectableText(_tunnel.id),
                        ),
                        ListTile(
                          leading: Icon(
                            isPrivate
                                ? Icons.lock_outline_rounded
                                : Icons.public_rounded,
                          ),
                          title: Text(widget.ru ? 'Тип' : 'Type'),
                          subtitle: Text(
                            isPrivate
                                ? (widget.ru ? 'Приватный' : 'Private')
                                : (widget.ru ? 'Открытый' : 'Open'),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.admin_panel_settings_outlined,
                          ),
                          title: Text(widget.ru ? 'Ваша роль' : 'Your role'),
                          subtitle: Text(
                            _isOwner
                                ? (widget.ru ? 'Владелец' : 'Owner')
                                : (widget.ru ? 'Участник' : 'Member'),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.people_outline_rounded),
                          title: Text(widget.ru ? 'Сейчас онлайн' : 'Online now'),
                          trailing: Text('$_onlinePeers'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: Text(widget.ru ? 'Сообщений' : 'Messages'),
                          trailing: Text('${_tunnel.messages.length}'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.folder_copy_outlined),
                          title: Text(
                            widget.ru ? 'Файлов и медиа' : 'Files and media',
                          ),
                          trailing: Text('$fileCount'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.calendar_today_outlined),
                          title: Text(widget.ru ? 'Создан' : 'Created'),
                          subtitle: Text(createdLabel),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.enhanced_encryption_outlined,
                          ),
                          title: Text(widget.ru ? 'Шифрование' : 'Encryption'),
                          subtitle: const Text('AES-256-GCM'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: Text(
                            widget.ru ? 'Ключ туннеля' : 'Tunnel key',
                          ),
                          subtitle: SelectableText(secretLabel),
                          trailing: Text('v${_tunnel.revision}'),
                        ),
                      ],
                    ),
                  ),
                  if (_isOwner) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: isPrivate,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        isPrivate
                            ? Icons.visibility_off_outlined
                            : Icons.public,
                      ),
                      title: Text(
                        isPrivate
                            ? (widget.ru ? 'Приватный чат' : 'Private chat')
                            : (widget.ru ? 'Открытый чат' : 'Open chat'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        isPrivate
                            ? (widget.ru
                                ? 'Вход только по секретной ссылке или QR.'
                                : 'Join only with the secret invite or QR.')
                            : (widget.ru
                                ? 'Ссылку можно свободно пересылать.'
                                : 'The invite may be freely forwarded.'),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => isPrivate = value),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: revoke,
                      onChanged: (value) =>
                          setSheetState(() => revoke = value ?? false),
                      title: Text(
                        widget.ru
                            ? 'Отозвать старую ссылку и QR'
                            : 'Revoke the old link and QR',
                      ),
                      subtitle: Text(
                        widget.ru
                            ? 'Подключённые участники автоматически получат новый ключ.'
                            : 'Connected members automatically receive the new key.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'save'),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          widget.ru ? 'Сохранить изменения' : 'Save changes',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ChernogramColors.danger,
                        side: BorderSide(
                          color: ChernogramColors.danger.withValues(alpha: .45),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: Text(
                        widget.ru
                            ? 'Выйти и удалить чат полностью'
                            : 'Leave and delete chat permanently',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (action == 'save' && _isOwner) {
      final updated = _tunnel.copyWith(
        name: name.text.trim(),
        isPrivate: isPrivate,
        secret: revoke ? CgIds.random(42) : _tunnel.secret,
        revision: _tunnel.revision + 1,
      );
      name.dispose();
      await _applyOwnerUpdate(updated);
      return;
    }
    name.dispose();
    if (action == 'delete' && mounted) await _leaveAndDeleteChat();
  }

'''
    replace_between(
        'lib/chat_screen.dart',
        '  Future<void> _showSettings() async {',
        '  Future<void> _startCall(bool video) async {',
        settings,
    )


def rebuild_composer() -> None:
    path = Path('lib/chat_screen.dart')
    source = path.read_text(encoding='utf-8')
    class_marker = 'class _SwipeActionBackground extends StatelessWidget {'
    class_index = source.find(class_marker)
    if class_index < 0:
        return
    start = source.rfind(
        "          SafeArea(\n            top: false,",
        0,
        class_index,
    )
    tail_marker = "        ],\n      ),\n    );\n  }\n}\n\n"
    end = source.find(tail_marker, start)
    if start < 0 or end < 0:
        return

    composer = r'''          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyingTo != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: .92,
                        ),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
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
                            onPressed: () =>
                                setState(() => _replyingTo = null),
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: widget.ru ? 'Добавить' : 'Add',
                          onPressed:
                              _sendingFile ? null : _showAttachmentMenu,
                          icon: _sendingFile
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            focusNode: _composerFocus,
                            autofocus: false,
                            onTapOutside: (_) => _composerFocus.unfocus(),
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendText(),
                            decoration: InputDecoration(
                              hintText:
                                  widget.ru ? 'Сообщение' : 'Message',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _hasText
                              ? IconButton.filled(
                                  key: const ValueKey('send'),
                                  onPressed: _sendText,
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                  ),
                                )
                              : CgVoiceRecordButton(
                                  key: const ValueKey('voice'),
                                  ru: widget.ru,
                                  enabled: _networkState == 'connected',
                                  onRecorded: _sendVoice,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
'''
    source = source[:start] + composer + source[end:]
    path.write_text(source, encoding='utf-8')


def main() -> None:
    restore_broad_closings()
    rebuild_settings()
    rebuild_composer()

    replace(
        'lib/chat_screen.dart',
        "unawaited(_showIncomingGroupCall(callId, fromName, video));",
        "unawaited(_showIncomingGroupCall(\n          callId,\n          fromName,\n          signal['avatarBase64']?.toString(),\n          video,\n        ));",
    )
    replace(
        'lib/chat_screen.dart',
        """        icon: Icon(
          video ? Icons.groups_2_rounded : Icons.group_rounded,
          size: 40,
        ),
""",
        """        icon: CgCallAvatar(
          avatarBase64: callerAvatar,
          name: fromName,
          size: 78,
          fallbackIcon:
              video ? Icons.groups_2_rounded : Icons.group_rounded,
        ),
""",
    )

    inline = Path('lib/inline_music_player.dart')
    source = inline.read_text(encoding='utf-8')
    if "package:just_audio/just_audio.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:just_audio/just_audio.dart';\n",
        )
        inline.write_text(source, encoding='utf-8')

    print('Applied Chernogram 0.11 full deterministic compile fixes')


if __name__ == '__main__':
    main()
