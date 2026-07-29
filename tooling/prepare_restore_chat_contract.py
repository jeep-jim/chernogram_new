from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    path = ROOT / "lib" / "chat_screen.dart"
    text = path.read_text(encoding="utf-8")

    if "final Future<void> Function(CgMessage message)? onForward;" not in text:
        anchor = (
            "  final ValueChanged<CgTunnel> onChanged;\n"
            "  final ValueChanged<CgContact>? onContactSeen;\n"
        )
        if anchor not in text:
            raise RuntimeError("forward field anchor not found")
        text = text.replace(
            anchor,
            "  final ValueChanged<CgTunnel> onChanged;\n"
            "  final Future<void> Function(CgMessage message)? onForward;\n"
            "  final ValueChanged<CgContact>? onContactSeen;\n",
            1,
        )
        constructor = (
            "    required this.onChanged,\n"
            "    this.onContactSeen,\n"
        )
        if constructor not in text:
            raise RuntimeError("forward constructor anchor not found")
        text = text.replace(
            constructor,
            "    required this.onChanged,\n"
            "    this.onForward,\n"
            "    this.onContactSeen,\n",
            1,
        )

    if "final FocusNode _composerFocus" not in text:
        anchor = "  final ScrollController _scroll = ScrollController();\n"
        if anchor not in text:
            raise RuntimeError("composer focus anchor not found")
        text = text.replace(
            anchor,
            anchor + "  final FocusNode _composerFocus = FocusNode();\n",
            1,
        )

    if "Map<String, dynamic> _replyMeta()" not in text:
        anchor = """  void _onComposerChanged() {
    final next = _text.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }

"""
        if anchor not in text:
            raise RuntimeError("composer changed anchor not found")
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
        text = text.replace(anchor, anchor + methods, 1)

    path.write_text(text, encoding="utf-8")
    print("Chat reply/forward contract prepared")


if __name__ == "__main__":
    main()
