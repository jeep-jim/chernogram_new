from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Expected block not found: {label}')
    return text.replace(old, new, 1)


def patch_v12() -> None:
    path = 'lib/v12.dart'
    text = read(path)
    text = replace_once(
        text,
        "import 'chat_screen.dart';\nimport 'core_models.dart';",
        "import 'chat_media.dart';\nimport 'chat_screen.dart';\nimport 'core_models.dart';\nimport 'music_player.dart';",
        'v12 imports',
    )

    scan_block = """  Future<void> _scanQr() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _V12QrScanner(ru: widget.ru)),
    );
    if (token != null) await _joinToken(token);
  }

"""
    media_methods = scan_block + """  Future<void> _openMediaLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMediaLibraryScreen(
          ru: widget.ru,
          tunnels: _tunnels,
          onTunnelsChanged: (updated) {
            _tunnels = List<CgTunnel>.from(updated);
            if (mounted) setState(() {});
            final snapshot = List<CgTunnel>.from(_tunnels);
            unawaited(_saveTunnelsFast(snapshot));
          },
        ),
      ),
    );
  }

  Future<void> _openMusicPlayer() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgMusicPlayerScreen(
          ru: widget.ru,
          tunnels: _tunnels,
        ),
      ),
    );
  }

"""
    text = replace_once(text, scan_block, media_methods, 'v12 media methods')

    pattern = re.compile(
        r"  Future<void> _openTunnel\(\n    CgTunnel tunnel, \{\n    bool autoInvite = false,\n  \}\) async \{.*?\n  \}\n\n  void _updateTunnel",
        re.S,
    )
    replacement = """  Future<void> _openTunnel(
    CgTunnel tunnel, {
    bool autoInvite = false,
  }) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CgChatScreen(
          ru: widget.ru,
          profile: profile,
          tunnel: tunnel,
          privacyLens: _privacyLens,
          autoInvite: autoInvite,
          onChanged: _updateTunnel,
          onContactSeen: _rememberContact,
        ),
      ),
    );
  }

  void _updateTunnel"""
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError('Could not replace _openTunnel')

    old_actions = """        actions: [
          GlassIconButton(
            icon: _privacyLens
                ? Icons.visibility_off_rounded
                : Icons.visibility_outlined,
            tooltip: widget.ru ? 'Приватный взгляд' : 'Privacy Lens',
            active: _privacyLens,
            onPressed: _togglePrivacy,
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
"""
    new_actions = """        actions: [
          GlassIconButton(
            icon: Icons.folder_copy_outlined,
            tooltip: widget.ru ? 'Файлы и медиа' : 'Files and media',
            onPressed: _openMediaLibrary,
          ),
          const SizedBox(width: 10),
          GlassIconButton(
            icon: Icons.queue_music_rounded,
            tooltip: widget.ru ? 'Музыкальный плеер' : 'Music player',
            onPressed: _openMusicPlayer,
          ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
"""
    text = replace_once(text, old_actions, new_actions, 'v12 header actions')

    old_profile = """          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person_rounded),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
"""
    new_profile = """          NavigationDestination(
            icon: _V12ProfileAvatar(
              nickname: _profile!.nickname,
              avatarBase64: _profile!.avatarBase64,
              size: 25,
            ),
            selectedIcon: _V12ProfileAvatar(
              nickname: _profile!.nickname,
              avatarBase64: _profile!.avatarBase64,
              size: 29,
            ),
            label: widget.ru ? 'Профиль' : 'Profile',
          ),
"""
    text = replace_once(text, old_profile, new_profile, 'v12 bottom avatar')
    write(path, text)


def patch_chat() -> None:
    path = 'lib/chat_screen.dart'
    text = read(path)
    text = replace_once(
        text,
        "import 'package:file_picker/file_picker.dart';\nimport 'package:flutter/material.dart';",
        "import 'package:file_picker/file_picker.dart';\nimport 'package:flutter/gestures.dart';\nimport 'package:flutter/material.dart';",
        'gestures import',
    )
    text = replace_once(
        text,
        "import 'package:share_plus/share_plus.dart';",
        "import 'package:share_plus/share_plus.dart';\nimport 'package:url_launcher/url_launcher.dart';",
        'url launcher import',
    )

    old_leading = """      appBar: AppBar(
        leadingWidth: 58,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _TunnelAvatar(tunnel: _tunnel, size: 42),
        ),
        titleSpacing: 0,
"""
    new_leading = """      appBar: AppBar(
        leadingWidth: Navigator.of(context).canPop() ? 106 : 58,
        leading: Row(
          children: [
            if (Navigator.of(context).canPop())
              IconButton(
                tooltip: widget.ru ? 'Назад' : 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: _TunnelAvatar(tunnel: _tunnel, size: 42),
            ),
          ],
        ),
        titleSpacing: 0,
"""
    text = replace_once(text, old_leading, new_leading, 'back button')

    banner = re.compile(
        r"          if \(_networkState != 'connected'\)\n            Padding\(.*?\n            \),\n          Expanded\(",
        re.S,
    )
    text, count = banner.subn("          Expanded(", text, count=1)
    if count != 1:
        raise RuntimeError('Could not remove reconnect banner')

    old_text = """                  Text(
                    privacyLens ? '••••••••••' : message.text,
                    style: TextStyle(
                      color: mine ? Colors.white : scheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
"""
    new_text = """                  _LinkifiedMessageText(
                    text: privacyLens ? '••••••••••' : message.text,
                    style: TextStyle(
                      color: mine ? Colors.white : scheme.onSurface,
                      fontSize: 15,
                    ),
                    linkColor: mine ? Colors.white : scheme.primary,
                  ),
"""
    text = replace_once(text, old_text, new_text, 'linkified text')

    marker = 'class _MessageBubble extends StatelessWidget {'
    widget_code = r'''class _LinkifiedMessageText extends StatefulWidget {
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

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

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
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
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
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(style: widget.style, children: _spans()));
  }
}

'''
    if marker not in text:
        raise RuntimeError('Message bubble marker missing')
    text = text.replace(marker, widget_code + marker, 1)
    write(path, text)


def patch_internet() -> None:
    path = 'lib/internet_core.dart'
    text = read(path)
    text = replace_once(
        text,
        """    _sessions[tunnelId] = session;
    await session.connect();
    return session;
""",
        """    _sessions[tunnelId] = session;
    unawaited(session.connect());
    return session;
""",
        'non-blocking session open',
    )
    write(path, text)


def bump_version() -> None:
    path = 'pubspec.yaml'
    text = read(path)
    text, count = re.subn(
        r'^version:\s*[^\n]+$',
        'version: 0.14.0+24',
        text,
        count=1,
        flags=re.M,
    )
    if count != 1:
        raise RuntimeError('Version line not found')
    write(path, text)


if __name__ == '__main__':
    patch_v12()
    patch_chat()
    patch_internet()
    bump_version()
    print('Chernogram 0.14 regression fix applied')
