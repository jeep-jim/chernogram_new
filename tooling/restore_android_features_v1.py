from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def replace_class(text: str, start_name: str, end_name: str, replacement: str) -> str:
    start = text.index(f"class {start_name}")
    end = text.index(f"class {end_name}", start)
    return text[:start] + replacement.rstrip() + "\n\n" + text[end:]


def patch_chat_screen() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")

    if "package:flutter/gestures.dart" not in text:
        text = replace_once(
            text,
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/gestures.dart';\n"
            "import 'package:flutter/material.dart';\n"
            "import 'package:flutter/services.dart';\n",
            "chat interaction imports",
        )
    if "package:url_launcher/url_launcher.dart" not in text:
        text = replace_once(
            text,
            "import 'package:share_plus/share_plus.dart';\n",
            "import 'package:share_plus/share_plus.dart';\n"
            "import 'package:url_launcher/url_launcher.dart';\n",
            "url launcher import",
        )

    if "final Future<void> Function(CgMessage message)? onForward;" not in text:
        text = replace_once(
            text,
            "  final ValueChanged<CgTunnel> onChanged;\n"
            "  final ValueChanged<CgContact>? onContactSeen;\n",
            "  final ValueChanged<CgTunnel> onChanged;\n"
            "  final Future<void> Function(CgMessage message)? onForward;\n"
            "  final ValueChanged<CgContact>? onContactSeen;\n",
            "forward field",
        )
        text = replace_once(
            text,
            "    required this.onChanged,\n"
            "    this.onContactSeen,\n",
            "    required this.onChanged,\n"
            "    this.onForward,\n"
            "    this.onContactSeen,\n",
            "forward constructor",
        )

    if "final FocusNode _composerFocus" not in text:
        text = replace_once(
            text,
            "  final ScrollController _scroll = ScrollController();\n",
            "  final ScrollController _scroll = ScrollController();\n"
            "  final FocusNode _composerFocus = FocusNode();\n",
            "composer focus",
        )
    if "CgMessage? _replyingTo;" not in text:
        text = replace_once(
            text,
            "  bool _hasText = false;\n",
            "  bool _hasText = false;\n"
            "  CgMessage? _replyingTo;\n",
            "reply state",
        )

    if "Map<String, dynamic> _replyMeta()" not in text:
        methods = """  Map<String, dynamic> _replyMeta() {
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

"""
        text = replace_once(
            text,
            "  Future<void> _connect() async {\n",
            methods + "  Future<void> _connect() async {\n",
            "reply methods",
        )

    old_send_text = """    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: value,
      sentAt: DateTime.now(),
    );
    _text.clear();
    _appendLocal(message);
"""
    new_send_text = """    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: value,
      sentAt: DateTime.now(),
      meta: _replyMeta(),
    );
    _text.clear();
    setState(() => _replyingTo = null);
    _appendLocal(message);
"""
    if old_send_text in text:
        text = replace_once(text, old_send_text, new_send_text, "text reply metadata")

    old_attachment = """    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: attachment,
    );
    _appendLocal(message);
"""
    new_attachment = """    final message = CgMessage(
      id: CgIds.random(24),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      text: '',
      sentAt: DateTime.now(),
      type: 'attachment',
      attachment: attachment,
      meta: _replyMeta(),
    );
    setState(() => _replyingTo = null);
    _appendLocal(message);
"""
    if old_attachment in text:
        text = replace_once(
            text,
            old_attachment,
            new_attachment,
            "attachment reply metadata",
        )

    actions_start = text.index("  Future<void> _showMessageActions(CgMessage message) async {")
    actions_end = text.index("  Future<void> _pickAttachment(", actions_start)
    actions = r'''  Future<void> _showMessageActions(CgMessage message) async {
    if (message.deleted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Действия с сообщением' : 'Message actions',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: ['👍', '❤️', '😂', '🔥', '👏', '🤝']
                    .map(
                      (emoji) => ActionChip(
                        label: Text(emoji, style: const TextStyle(fontSize: 23)),
                        onPressed: () => Navigator.pop(context, emoji),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 28),
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
              if (message.text.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(widget.ru ? 'Копировать текст' : 'Copy text'),
                  onTap: () => Navigator.pop(context, '__copy__'),
                ),
              if (message.authorId == widget.profile.id)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: ChernogramColors.danger,
                  ),
                  title: Text(
                    widget.ru ? 'Удалить сообщение' : 'Delete message',
                    style: const TextStyle(
                      color: ChernogramColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, '__delete__'),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__delete__') {
      await _deleteMessage(message);
    } else if (selected == '__reply__') {
      _replyTo(message);
    } else if (selected == '__forward__') {
      await _forward(message);
    } else if (selected == '__copy__') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.ru ? 'Текст скопирован' : 'Text copied')),
        );
      }
    } else {
      await _toggleReaction(message, selected);
    }
  }

'''
    text = text[:actions_start] + actions + text[actions_end:]

    old_composer = r'''                child: GlassPanel(
                  padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                  borderRadius: BorderRadius.circular(22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: widget.ru ? 'Добавить' : 'Add',
                        onPressed: _sendingFile ? null : _showAttachmentMenu,
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
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _sendText(),
                          decoration: InputDecoration(
                            hintText: widget.ru ? 'Сообщение' : 'Message',
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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _hasText
                            ? IconButton.filled(
                                key: const ValueKey('send'),
                                onPressed: _sendText,
                                icon: const Icon(Icons.arrow_upward_rounded),
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
'''
    new_composer = r'''                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyingTo != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.fromLTRB(13, 9, 7, 9),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: .86),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.reply_rounded, size: 18, color: scheme.primary),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.privacyLens
                                        ? '••••'
                                        : _replyingTo!.authorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    widget.privacyLens
                                        ? '••••••••'
                                        : (_replyingTo!.text.isNotEmpty
                                              ? _replyingTo!.text
                                              : _replyingTo!.attachment?.name ?? ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _replyingTo = null),
                              icon: const Icon(Icons.close_rounded, size: 19),
                            ),
                          ],
                        ),
                      ),
                    GlassPanel(
                      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                      borderRadius: BorderRadius.circular(22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: widget.ru ? 'Добавить' : 'Add',
                            onPressed: _sendingFile ? null : _showAttachmentMenu,
                            icon: _sendingFile
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.add_rounded),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _composerFocus,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _sendText(),
                              decoration: InputDecoration(
                                hintText: widget.ru ? 'Сообщение' : 'Message',
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
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _hasText
                                ? IconButton.filled(
                                    key: const ValueKey('send'),
                                    onPressed: _sendText,
                                    icon: const Icon(Icons.arrow_upward_rounded),
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
'''
    if old_composer in text:
        text = replace_once(text, old_composer, new_composer, "reply composer")

    if "_composerFocus.dispose();" not in text:
        text = replace_once(
            text,
            "    _text.dispose();\n"
            "    _scroll.dispose();\n",
            "    _text.dispose();\n"
            "    _composerFocus.dispose();\n"
            "    _scroll.dispose();\n",
            "composer dispose",
        )

    linkified = r'''class _LinkifiedMessageText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;

  const _LinkifiedMessageText({
    required this.text,
    required this.style,
    required this.linkColor,
  });

  @override
  State<_LinkifiedMessageText> createState() => _LinkifiedMessageTextState();
}

class _LinkifiedMessageTextState extends State<_LinkifiedMessageText> {
  static final RegExp _urlPattern = RegExp(
    r'((?:https?|chernogram)://[^\s]+|www\.[^\s]+)',
    caseSensitive: false,
  );
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  List<InlineSpan> _spans() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      var visible = match.group(0)!;
      var trailing = '';
      while (visible.isNotEmpty && '.,!?;:)]}'.contains(visible[visible.length - 1])) {
        trailing = visible[visible.length - 1] + trailing;
        visible = visible.substring(0, visible.length - 1);
      }
      final normalized = visible.toLowerCase().startsWith('www.')
          ? 'https://$visible'
          : visible;
      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          final uri = Uri.tryParse(normalized);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: visible,
          style: widget.style.copyWith(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
            fontWeight: FontWeight.w700,
          ),
          recognizer: recognizer,
        ),
      );
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) => SelectionArea(
        child: Text.rich(TextSpan(style: widget.style, children: _spans())),
      );

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }
}

'''

    bubble = r'''class _MessageBubble extends StatelessWidget {
  final CgMessage message;
  final bool mine;
  final bool groupChat;
  final bool privacyLens;
  final bool ru;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.groupChat,
    required this.privacyLens,
    required this.ru,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (message.type == 'call') {
      return _CallMessageCard(
        message: message,
        mine: mine,
        ru: ru,
        privacyLens: privacyLens,
        onLongPress: onLongPress,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final attachment = message.attachment;
    final showAvatar = groupChat && !mine;
    final replyAuthor = message.meta['replyAuthor']?.toString();
    final replyText = message.meta['replyText']?.toString();
    final replyAttachment = message.meta['replyAttachmentName']?.toString();
    final hasReply = (replyAuthor?.isNotEmpty ?? false) ||
        (replyText?.isNotEmpty ?? false) ||
        (replyAttachment?.isNotEmpty ?? false);
    final hasTextBubble = message.deleted || message.text.isNotEmpty || hasReply;

    Widget infoRow() => Padding(
          padding: EdgeInsets.only(
            left: mine ? 0 : 5,
            right: mine ? 5 : 0,
            top: 3,
            bottom: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.deleted && message.reactions.isNotEmpty) ...[
                for (final entry in message.reactions.entries)
                  if (entry.value.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Text(
                        '${entry.key} ${entry.value.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
              ],
              Text(
                _formatTime(message.sentAt),
                style: TextStyle(
                  fontSize: 9,
                  color: scheme.onSurface.withValues(alpha: .42),
                ),
              ),
            ],
          ),
        );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChernogramAvatar(
                    size: 27,
                    seed: message.authorId.isEmpty ? message.authorName : message.authorId,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    privacyLens ? '••••' : message.authorName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface.withValues(alpha: .52),
                    ),
                  ),
                ],
              ),
            ),
          GestureDetector(
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (attachment != null && !message.deleted)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 370),
                    child: CgInlineAttachment(
                      attachment: attachment,
                      hidden: privacyLens,
                    ),
                  ),
                if (attachment != null && hasTextBubble)
                  const SizedBox(height: 5),
                if (hasTextBubble)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: mine
                          ? scheme.primary.withValues(alpha: .90)
                          : scheme.surfaceContainerHighest.withValues(alpha: .91),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(mine ? 20 : 5),
                        topRight: Radius.circular(mine ? 5 : 20),
                        bottomLeft: const Radius.circular(20),
                        bottomRight: const Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasReply && !message.deleted) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  privacyLens ? '••••' : (replyAuthor ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  privacyLens
                                      ? '••••••••'
                                      : ((replyText?.isNotEmpty ?? false)
                                            ? replyText!
                                            : replyAttachment ?? ''),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          if (message.text.isNotEmpty) const SizedBox(height: 7),
                        ],
                        if (message.deleted)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.block_rounded, size: 16),
                              const SizedBox(width: 7),
                              Text(
                                ru ? 'Сообщение удалено' : 'Message deleted',
                                style: const TextStyle(fontStyle: FontStyle.italic),
                              ),
                            ],
                          )
                        else if (message.text.isNotEmpty)
                          _LinkifiedMessageText(
                            text: privacyLens ? '••••••••••' : message.text,
                            style: TextStyle(
                              color: mine ? Colors.white : scheme.onSurface,
                              fontSize: 15,
                              height: 1.25,
                            ),
                            linkColor: mine
                                ? Colors.white
                                : scheme.primary,
                          ),
                      ],
                    ),
                  ),
                infoRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
'''
    text = replace_class(
        text,
        "_MessageBubble extends StatelessWidget",
        "_CallMessageCard extends StatelessWidget",
        linkified + bubble,
    )

    path.write_text(text, encoding="utf-8")


def patch_android_shell() -> None:
    path = ROOT / "lib" / "android_data_first.dart"
    text = path.read_text(encoding="utf-8")

    if "import 'chat_media.dart';" not in text:
        text = replace_once(
            text,
            "import 'brand.dart';\n",
            "import 'brand.dart';\nimport 'chat_media.dart';\n",
            "chat media import",
        )

    if "bool _privacyLens = false;" not in text:
        text = replace_once(
            text,
            "  bool _loading = true;\n",
            "  bool _loading = true;\n  bool _privacyLens = false;\n",
            "privacy state",
        )

    old_bootstrap = """    final profile = await CgStore.loadOrCreateProfile();
    final tunnels = await CgStore.loadTunnels();
    final contacts = await CgStore.loadContacts();
"""
    new_bootstrap = """    final profile = await CgStore.loadOrCreateProfile();
    final tunnels = await CgStore.loadTunnels();
    final contacts = await CgStore.loadContacts();
    final privacyLens = await CgStore.loadPrivacyLens();
"""
    if old_bootstrap in text:
        text = replace_once(text, old_bootstrap, new_bootstrap, "load privacy")
    old_state = """      _contacts = contacts;
      _loading = false;
"""
    new_state = """      _contacts = contacts;
      _privacyLens = privacyLens;
      _loading = false;
"""
    if old_state in text:
        text = replace_once(text, old_state, new_state, "apply privacy")

    old_open = """          privacyLens: false,
          autoInvite: autoInvite,
          onChanged: _updateTunnel,
          onContactSeen: _rememberContact,
"""
    new_open = """          privacyLens: _privacyLens,
          autoInvite: autoInvite,
          onChanged: _updateTunnel,
          onForward: _forwardMessage,
          onContactSeen: _rememberContact,
"""
    if old_open in text:
        text = replace_once(text, old_open, new_open, "open chat features")

    if "Future<void> _forwardMessage(CgMessage source)" not in text:
        forward = r'''  Future<void> _forwardMessage(CgMessage source) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    final candidates = _tunnels.toList();
    if (candidates.isEmpty) return;
    final target = await showModalBottomSheet<CgTunnel>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.ru ? 'Переслать в чат' : 'Forward to chat',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final tunnel = candidates[index];
                    return ListTile(
                      leading: ChernogramAvatar(
                        size: 42,
                        seed: tunnel.id,
                        avatarBase64: tunnel.avatarBase64,
                      ),
                      title: Text(tunnel.displayName),
                      trailing: const Icon(Icons.forward_rounded),
                      onTap: () => Navigator.pop(context, tunnel),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    final forwarded = CgMessage(
      id: CgIds.random(24),
      authorId: profile.id,
      authorName: profile.nickname,
      text: source.text,
      sentAt: DateTime.now(),
      type: source.type,
      attachment: source.attachment,
      meta: <String, dynamic>{
        ...source.meta,
        'forwarded': true,
        'forwardedFrom': source.authorName,
      },
    );
    final updated = target.copyWith(messages: [...target.messages, forwarded]);
    _updateTunnel(updated);
    await ChernogramAppMonitor.publishMessage(
      profile: profile,
      tunnel: updated,
      message: forwarded,
    );
    _showMessage(widget.ru ? 'Сообщение переслано.' : 'Message forwarded.');
  }

'''
        text = replace_once(
            text,
            "  Future<void> _openKnownContact(CgContact contact) async {\n",
            forward + "  Future<void> _openKnownContact(CgContact contact) async {\n",
            "forward implementation",
        )

    old_profile_args = """        contacts: _contacts,
        onProfileChanged: (profile) async {
"""
    new_profile_args = """        contacts: _contacts,
        privacyLens: _privacyLens,
        onPrivacyChanged: (value) async {
          await CgStore.savePrivacyLens(value);
          if (mounted) setState(() => _privacyLens = value);
        },
        onProfileChanged: (profile) async {
"""
    if old_profile_args in text:
        text = replace_once(
            text,
            old_profile_args,
            new_profile_args,
            "profile privacy arguments",
        )

    old_track = r'''  Future<File?> _trackFile(CgAttachment attachment) async {
    final path = attachment.localPath;
    if (path != null && await File(path).exists()) return File(path);
    if (attachment.dataBase64 == null) return null;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${attachment.id}_${attachment.name}');
    await file.writeAsBytes(base64Decode(attachment.dataBase64!), flush: true);
    return file;
  }
'''
    new_track = r'''  Future<File?> _trackFile(CgAttachment attachment) =>
      CgMediaStore.ensureFile(attachment);
'''
    if old_track in text:
        text = replace_once(text, old_track, new_track, "music file materialization")

    old_play = r'''  Future<void> _play(_MusicEntry entry) async {
    final file = await _trackFile(entry.attachment);
    if (file == null) return;
    if (_current?.attachment.id == entry.attachment.id) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    await _player.setFilePath(file.path);
    setState(() => _current = entry);
    await _player.play();
  }
'''
    new_play = r'''  Future<void> _play(_MusicEntry entry) async {
    final file = await _trackFile(entry.attachment);
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Аудиофайл ещё не загружен на устройство.'
                  : 'The audio file is not downloaded to this device yet.',
            ),
          ),
        );
      }
      return;
    }
    try {
      if (_current?.attachment.id == entry.attachment.id) {
        if (_player.playing) {
          await _player.pause();
        } else {
          unawaited(_player.play());
        }
        return;
      }
      await _player.setAudioSource(AudioSource.uri(Uri.file(file.path)));
      if (mounted) setState(() => _current = entry);
      unawaited(_player.play());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Не удалось воспроизвести файл: $error'
                  : 'Playback failed: $error',
            ),
          ),
        );
      }
    }
  }
'''
    if old_play in text:
        text = replace_once(text, old_play, new_play, "music playback")

    text = text.replace(
        "                              await _player.play();\n",
        "                              unawaited(_player.play());\n",
    )

    if "final bool privacyLens;" not in text[text.index("class _ProfilePage"):]:
        text = replace_once(
            text,
            "  final List<CgContact> contacts;\n"
            "  final ValueChanged<CgProfile> onProfileChanged;\n",
            "  final List<CgContact> contacts;\n"
            "  final bool privacyLens;\n"
            "  final ValueChanged<bool> onPrivacyChanged;\n"
            "  final ValueChanged<CgProfile> onProfileChanged;\n",
            "profile privacy fields",
        )
        text = replace_once(
            text,
            "    required this.contacts,\n"
            "    required this.onProfileChanged,\n",
            "    required this.contacts,\n"
            "    required this.privacyLens,\n"
            "    required this.onPrivacyChanged,\n"
            "    required this.onProfileChanged,\n",
            "profile privacy constructor",
        )

    privacy_card = r'''      Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          value: privacyLens,
          onChanged: onPrivacyChanged,
          secondary: Icon(
            privacyLens ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
          title: Text(
            ru ? 'Приватный экран' : 'Privacy screen',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            ru
                ? 'Скрывает имена и текст сообщений, не отключая связь.'
                : 'Hides names and message text without disconnecting.',
          ),
        ),
      ),
      const SizedBox(height: 8),
'''
    profile_anchor = r'''      _ProfileAction(
        icon: Icons.fingerprint_rounded,
'''
    profile_section = text[text.index("class _ProfilePage"):]
    if "Приватный экран" not in profile_section:
        text = replace_once(
            text,
            profile_anchor,
            privacy_card + profile_anchor,
            "privacy settings card",
        )

    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_chat_screen()
    patch_android_shell()
    print("Android legacy features restored inside data-first UI")


if __name__ == "__main__":
    main()
