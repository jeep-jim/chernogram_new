from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


chat = Path('lib/chat_screen.dart')
text = chat.read_text(encoding='utf-8')

text = replace_once(
    text,
    """    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connectAndStart());
""",
    """    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToBottomImmediately();
    });
    unawaited(_connectAndStart());
""",
    'initial scroll',
)

text = replace_once(
    text,
    """  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
""",
    """  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    _dismissKeyboard();
""",
    'hide keyboard after text send',
)

text = replace_once(
    text,
    """  Future<void> _sendAttachment(CgAttachment attachment) async {
    final message = CgMessage(
""",
    """  Future<void> _sendAttachment(CgAttachment attachment) async {
    _dismissKeyboard();
    final message = CgMessage(
""",
    'hide keyboard after attachment send',
)

text = replace_once(
    text,
    """  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }
""",
    """  void _dismissKeyboard() {
    _composerFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _jumpToBottomImmediately() {
    if (!_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToBottomImmediately();
      });
      return;
    }
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }
""",
    'keyboard and scroll helpers',
)

text = replace_once(
    text,
    """      body: CgChatPatternBackground(
        child: Column(
""",
    """      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissKeyboard,
        child: CgChatPatternBackground(
          child: Column(
""",
    'tap outside composer',
)

text = replace_once(
    text,
    """                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
""",
    """                  : ListView.builder(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
""",
    'dismiss keyboard on list drag',
)

text = replace_once(
    text,
    """                    GlassPanel(
                      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                      borderRadius: BorderRadius.circular(22),
                      child: Row(
""",
    """                    Container(
                      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: .58),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: .10),
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
""",
    'transparent rounded composer',
)

text = replace_once(
    text,
    """          ],
        ),
      ),
    );
  }
}

class _AttachmentAction extends StatelessWidget {
""",
    """          ],
        ),
      ),
    ),
  );
  }
}

class _AttachmentAction extends StatelessWidget {
""",
    'close chat gesture wrapper',
)

chat.write_text(text, encoding='utf-8')

qr = Path('lib/light/light_invite_qr.dart')
text = qr.read_text(encoding='utf-8')
if not text.startswith("import 'dart:async';"):
    text = "import 'dart:async';\n\n" + text
text = replace_once(
    text,
    """      _finished = true;
      await _controller.stop();
      if (mounted) Navigator.pop(context, chat);
      return;
""",
    """      _finished = true;
      unawaited(_controller.stop());
      if (mounted) Navigator.pop(context, chat);
      return;
""",
    'close scanner immediately',
)
qr.write_text(text, encoding='utf-8')

print('Chat polish build 74 applied.')
