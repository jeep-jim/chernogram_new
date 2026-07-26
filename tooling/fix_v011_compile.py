from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def rebuild_composer() -> None:
    path = Path('lib/chat_screen.dart')
    source = path.read_text(encoding='utf-8')

    # The broad 0.11 UI replacement may touch several unrelated closing
    # sequences. Restore all of them to the original valid structure first.
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

    class_marker = 'class _SwipeActionBackground extends StatelessWidget {'
    class_index = source.find(class_marker)
    if class_index < 0:
        path.write_text(source, encoding='utf-8')
        return

    start = source.rfind(
        "          SafeArea(\n            top: false,",
        0,
        class_index,
    )
    tail_marker = "        ],\n      ),\n    );\n  }\n}\n\n"
    end = source.find(tail_marker, start)
    if start < 0 or end < 0:
        path.write_text(source, encoding='utf-8')
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
    rebuild_composer()

    # The avatar-aware group incoming method receives the avatar carried in
    # the invite signal.
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

    print('Applied Chernogram 0.11 deterministic compile fixes')


if __name__ == '__main__':
    main()
