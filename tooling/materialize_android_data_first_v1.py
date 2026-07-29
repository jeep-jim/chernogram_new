from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_android_shell() -> None:
    path = ROOT / "lib" / "android_data_first.dart"
    text = path.read_text(encoding="utf-8")

    if "package:mobile_scanner/mobile_scanner.dart" not in text:
        text = replace_once(
            text,
            "import 'package:just_audio/just_audio.dart';\n",
            "import 'package:just_audio/just_audio.dart';\n"
            "import 'package:mobile_scanner/mobile_scanner.dart';\n",
            "mobile scanner import",
        )

    old_scan = """  Future<void> _scanInvite() async {
    _showMessage(
      widget.ru
          ? 'Сканер QR остаётся внутри окна добавления контакта и будет подключён следующим проходом.'
          : 'The QR scanner stays inside the contact flow and will be connected in the next pass.',
    );
  }
"""
    new_scan = """  Future<void> _scanInvite() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => CgInviteQrScanner(ru: widget.ru)),
    );
    if (raw == null || raw.trim().isEmpty) return;
    var token = raw.trim();
    final uri = Uri.tryParse(token);
    if (uri != null) token = _tokenFromUri(uri) ?? token;
    await _joinToken(token);
  }
"""
    if old_scan in text:
        text = replace_once(text, old_scan, new_scan, "QR scan method")

    old_qr_action = """                  child: _QuickContactAction(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR',
                    onTap: widget.onScan,
                  ),
"""
    new_qr_action = """                  child: _QuickContactAction(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onScan();
                    },
                  ),
"""
    if old_qr_action in text:
        text = replace_once(text, old_qr_action, new_qr_action, "QR action")

    if "class CgInviteQrScanner" not in text:
        scanner = r'''

class CgInviteQrScanner extends StatefulWidget {
  final bool ru;

  const CgInviteQrScanner({super.key, required this.ru});

  @override
  State<CgInviteQrScanner> createState() => _CgInviteQrScannerState();
}

class _CgInviteQrScannerState extends State<CgInviteQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  void _detect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.pop(context, value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.ru ? 'Сканировать приглашение' : 'Scan invite'),
          actions: [
            IconButton(
              onPressed: _controller.toggleTorch,
              icon: const Icon(Icons.flashlight_on_rounded),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _detect),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 252,
                  height: 252,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
'''
        text += scanner

    path.write_text(text, encoding="utf-8")


def patch_chat() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")

    if "bool get _isGroupChat" not in text:
        text = replace_once(
            text,
            "  bool get _isOwner => widget.profile.id == _tunnel.ownerId;\n",
            "  bool get _isOwner => widget.profile.id == _tunnel.ownerId;\n\n"
            "  bool get _isGroupChat {\n"
            "    final authors = _tunnel.messages\n"
            "        .map((message) => message.authorId)\n"
            "        .where((id) => id.isNotEmpty)\n"
            "        .toSet();\n"
            "    authors.add(_tunnel.ownerId);\n"
            "    return authors.length > 2 ||\n"
            "        _tunnel.messages.any((message) => message.meta['group'] == true);\n"
            "  }\n",
            "group chat getter",
        )

    old_leading = """        leadingWidth: 58,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _TunnelAvatar(tunnel: _tunnel, size: 42),
        ),
        titleSpacing: 0,
"""
    new_leading = """        leadingWidth: _isGroupChat ? 58 : 50,
        leading: _isGroupChat
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: ChernogramAvatar(
                  size: 42,
                  seed: _tunnel.id,
                  avatarBase64: _tunnel.avatarBase64,
                ),
              )
            : const BackButton(),
        titleSpacing: 0,
"""
    if old_leading in text:
        text = replace_once(text, old_leading, new_leading, "chat app bar avatar")

    if "body: CgChatPatternBackground(" not in text:
        body_start = text.index("      body: Column(")
        class_end = text.index("\nclass _AttachmentAction", body_start)
        segment = text[body_start:class_end]
        segment = segment.replace(
            "      body: Column(\n",
            "      body: CgChatPatternBackground(\n        child: Column(\n",
            1,
        )
        closing = "        ],\n      ),\n    );\n  }\n}\n"
        if not segment.endswith(closing):
            raise RuntimeError("chat body closing anchor not found")
        segment = segment[: -len(closing)] + (
            "        ],\n"
            "        ),\n"
            "      ),\n"
            "    );\n"
            "  }\n"
            "}\n"
        )
        text = text[:body_start] + segment + text[class_end:]

    old_bubble_call = """                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        privacyLens: widget.privacyLens,
                        ru: widget.ru,
                        onLongPress: () => _showMessageActions(message),
                      );
"""
    new_bubble_call = """                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        groupChat: _isGroupChat,
                        privacyLens: widget.privacyLens,
                        ru: widget.ru,
                        onLongPress: () => _showMessageActions(message),
                      );
"""
    if old_bubble_call in text:
        text = replace_once(text, old_bubble_call, new_bubble_call, "message group flag")

    text = text.replace(
        "const ChernogramLogo(size: 82, withPlate: true)",
        "const ChernogramLogo(size: 82)",
    )

    bubble_start = text.index("class _MessageBubble extends StatelessWidget")
    call_start = text.index("class _CallMessageCard extends StatelessWidget", bubble_start)
    attachment_start = text.index("class _AttachmentPreview extends StatelessWidget", call_start)

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
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChernogramAvatar(
                    size: 27,
                    seed: message.authorId.isEmpty
                        ? message.authorName
                        : message.authorId,
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
            child: Container(
              constraints: const BoxConstraints(maxWidth: 350),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: mine
                    ? scheme.primary.withValues(alpha: .88)
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
                  if (message.deleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: mine ? Colors.white60 : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          ru ? 'Сообщение удалено' : 'Message deleted',
                          style: TextStyle(
                            color: mine
                                ? Colors.white60
                                : scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    if (attachment != null)
                      _AttachmentPreview(
                        attachment: attachment,
                        hidden: privacyLens,
                      ),
                    if (message.text.isNotEmpty) ...[
                      if (attachment != null) const SizedBox(height: 7),
                      Text(
                        privacyLens ? '••••••••••' : message.text,
                        style: TextStyle(
                          color: mine ? Colors.white : scheme.onSurface,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                  if (!message.deleted && message.reactions.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: message.reactions.entries
                          .where((entry) => entry.value.isNotEmpty)
                          .map(
                            (entry) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .13),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${entry.key} ${entry.value.length}',
                                style: TextStyle(
                                  color: mine ? Colors.white : scheme.onSurface,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatTime(message.sentAt),
                      style: TextStyle(
                        fontSize: 9,
                        color: mine
                            ? Colors.white60
                            : scheme.onSurface.withValues(alpha: .42),
                      ),
                    ),
                  ),
                ],
              ),
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

    call = r'''class _CallMessageCard extends StatelessWidget {
  final CgMessage message;
  final bool mine;
  final bool ru;
  final bool privacyLens;
  final VoidCallback onLongPress;

  const _CallMessageCard({
    required this.message,
    required this.mine,
    required this.ru,
    required this.privacyLens,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final video = message.meta['video'] == true;
    final group = message.meta['group'] == true;
    final status = message.meta['status']?.toString() ?? 'completed';
    final seconds =
        int.tryParse(message.meta['durationSeconds']?.toString() ?? '') ?? 0;
    final participants =
        int.tryParse(message.meta['participants']?.toString() ?? '') ?? 2;
    final successful = status == 'completed';
    final title = group
        ? (video
            ? (ru ? 'Групповой видеозвонок' : 'Group video call')
            : (ru ? 'Групповой звонок' : 'Group call'))
        : (video
            ? (ru ? 'Видеозвонок' : 'Video call')
            : (ru ? 'Аудиозвонок' : 'Audio call'));
    String subtitle;
    if (successful) {
      subtitle =
          '${mine ? (ru ? 'Исходящий' : 'Outgoing') : (ru ? 'Входящий' : 'Incoming')}'
          '${group ? ' • $participants' : ''}'
          ' • ${_durationText(seconds, ru)}';
    } else if (status == 'declined') {
      subtitle = mine
          ? (ru ? 'Звонок отклонён' : 'Call declined')
          : (ru ? 'Отклонённый звонок' : 'Declined call');
    } else if (status == 'cancelled') {
      subtitle = ru ? 'Звонок отменён' : 'Call cancelled';
    } else {
      subtitle = mine
          ? (ru ? 'Нет ответа' : 'No answer')
          : (ru ? 'Пропущенный звонок' : 'Missed call');
    }

    final cardColor = dark
        ? const Color(0xFF0B0E15)
        : const Color(0xFFE9EDF5);
    final accent = successful
        ? (video ? ChernogramColors.cyan : ChernogramColors.success)
        : ChernogramColors.danger;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 335),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      privacyLens ? '••••••••' : title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      privacyLens ? '••••••••' : subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: .58),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _MessageBubble._formatTime(message.sentAt),
                      style: TextStyle(
                        fontSize: 9,
                        color: scheme.onSurface.withValues(alpha: .38),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  group
                      ? Icons.groups_2_rounded
                      : video
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                  color: accent,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _durationText(int seconds, bool ru) {
    if (seconds <= 0) return ru ? 'меньше минуты' : 'under a minute';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes == 0) return '$rest ${ru ? 'сек' : 'sec'}';
    if (rest == 0) return '$minutes ${ru ? 'мин' : 'min'}';
    return '$minutes ${ru ? 'мин' : 'min'} $rest ${ru ? 'сек' : 'sec'}';
  }
}

'''

    text = text[:bubble_start] + bubble + call + text[attachment_start:]
    path.write_text(text, encoding="utf-8")


def main() -> None:
    patch_android_shell()
    patch_chat()
    print("Android data-first UI materialized")


if __name__ == "__main__":
    main()
