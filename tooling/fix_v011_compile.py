from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    # Correct the extra closing parenthesis introduced around the composer
    # reply preview. The intended nesting is Row -> GlassPanel -> children ->
    # Column -> Padding -> SafeArea.
    replace(
        'lib/chat_screen.dart',
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
              ],
            ),
          ),
        ),
""",
    )

    # The avatar-aware group incoming method now receives the avatar carried
    # in the invite signal.
    replace(
        'lib/chat_screen.dart',
        "unawaited(_showIncomingGroupCall(callId, fromName, video));",
        "unawaited(_showIncomingGroupCall(\n          callId,\n          fromName,\n          signal['avatarBase64']?.toString(),\n          video,\n        ));",
    )

    # Show the group caller avatar instead of a generic icon as well.
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

    # PlayerState belongs to just_audio.
    inline = Path('lib/inline_music_player.dart')
    source = inline.read_text(encoding='utf-8')
    if "package:just_audio/just_audio.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:just_audio/just_audio.dart';\n",
        )
        inline.write_text(source, encoding='utf-8')

    print('Applied Chernogram 0.11 compile fixes')


if __name__ == '__main__':
    main()
