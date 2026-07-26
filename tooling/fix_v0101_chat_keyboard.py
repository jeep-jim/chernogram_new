from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old in source:
        file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    path = 'lib/chat_screen.dart'

    replace(
        path,
        """  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
""",
        """  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'chat-composer');
""",
    )

    replace(
        path,
        """    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connect());
""",
        """    _tunnel = widget.tunnel;
    _text.addListener(_onComposerChanged);
    unawaited(_connect());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      _composerFocus.unfocus();
      _scrollToBottom(animate: false);
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _scrollToBottom(animate: false);
      });
    });
""",
    )

    replace(
        path,
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
        """  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (!animate) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }
""",
    )

    replace(
        path,
        """                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
""",
        """                : ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
""",
    )

    replace(
        path,
        """                      child: TextField(
                        controller: _text,
                        minLines: 1,
""",
        """                      child: TextField(
                        controller: _text,
                        focusNode: _composerFocus,
                        autofocus: false,
                        onTapOutside: (_) => _composerFocus.unfocus(),
                        minLines: 1,
""",
    )

    replace(
        path,
        """    _text.removeListener(_onComposerChanged);
    _text.dispose();
    _scroll.dispose();
""",
        """    _text.removeListener(_onComposerChanged);
    _composerFocus.dispose();
    _text.dispose();
    _scroll.dispose();
""",
    )

    print('Applied Chernogram 0.10.1 chat keyboard and latest-message UX')


if __name__ == '__main__':
    main()
