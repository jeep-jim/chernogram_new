from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


path = Path('lib/chat_screen.dart')
text = path.read_text(encoding='utf-8')

text = replace_once(
    text,
    """  final ValueChanged<CgContact>? onContactSeen;

  const CgChatScreen({
""",
    """  final ValueChanged<CgContact>? onContactSeen;
  final String initialAction;

  const CgChatScreen({
""",
    'initial action field',
)
text = replace_once(
    text,
    """    this.onContactSeen,
    this.autoInvite = false,
  });
""",
    """    this.onContactSeen,
    this.autoInvite = false,
    this.initialAction = 'chat',
  });
""",
    'initial action constructor',
)
text = replace_once(
    text,
    """    _text.addListener(_onComposerChanged);
    unawaited(_connect());
    if (widget.autoInvite) {
""",
    """    _text.addListener(_onComposerChanged);
    unawaited(_connectAndStart());
    if (widget.autoInvite) {
""",
    'connect and start',
)
text = replace_once(
    text,
    """  void _onComposerChanged() {
""",
    """  Future<void> _connectAndStart() async {
    await _connect();
    if (!mounted || widget.initialAction == 'chat') return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || _networkState != 'connected') return;
    if (widget.initialAction == 'audio') {
      await _startCall(false);
    } else if (widget.initialAction == 'video') {
      await _startCall(true);
    }
  }

  void _onComposerChanged() {
""",
    'connect and start method',
)

old_title = """        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.privacyLens ? '••••••••' : _tunnel.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              _statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: _networkState == 'connected'
                    ? ChernogramColors.success
                    : scheme.onSurface.withValues(alpha: .46),
              ),
            ),
          ],
        ),
"""
new_title = """        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.privacyLens ? '••••••••' : _tunnel.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _networkState == 'connected'
                        ? ChernogramColors.success
                        : scheme.onSurface.withValues(alpha: .28),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _networkState == 'connected' ? 'в сети' : 'подключение',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: .48),
                  ),
                ),
              ],
            ),
          ],
        ),
"""
text = replace_once(text, old_title, new_title, 'compact title')

actions_pattern = re.compile(
    r"        actions: \[\n"
    r"          GlassIconButton\(\n"
    r"            icon: Icons\.call_outlined,.*?"
    r"          const SizedBox\(width: 6\),\n"
    r"        \],",
    re.S,
)
actions_replacement = """        actions: [
          IconButton(
            tooltip: 'Аудиозвонок',
            onPressed: () => _startCall(false),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: 'Видеозвонок',
            onPressed: () => _startCall(true),
            icon: const Icon(Icons.videocam_outlined),
          ),
          if (canInvite)
            IconButton(
              tooltip: 'Пригласить',
              onPressed: _showInvite,
              icon: const Icon(Icons.ios_share_rounded),
            ),
          const SizedBox(width: 4),
        ],"""
text, count = actions_pattern.subn(actions_replacement, text, count=1)
if count != 1:
    raise RuntimeError('Could not replace chat actions')

banner_pattern = re.compile(
    r"            if \(_networkState != 'connected'\)\n"
    r"              Padding\(.*?"
    r"              \),\n"
    r"            if \(_selectedMessageIds\.isNotEmpty\)",
    re.S,
)
text, count = banner_pattern.subn(
    "            if (_selectedMessageIds.isNotEmpty)",
    text,
    count=1,
)
if count != 1:
    raise RuntimeError('Could not remove reconnect banner')

replacements = {
    'Сначала дождитесь подключения туннеля.': 'Сначала дождитесь подключения чата.',
    'Wait for the tunnel to connect first.': 'Wait for the chat to connect first.',
    'Пригласить в туннель': 'Пригласить в чат',
    'Настройки туннеля': 'Настройки чата',
    'Аватар туннеля': 'Фото чата',
    'Tunnel avatar': 'Chat photo',
    'Tunnel settings': 'Chat settings',
}
for old, new in replacements.items():
    text = text.replace(old, new)

path.write_text(text, encoding='utf-8')

manifest = Path('android/app/src/main/AndroidManifest.xml')
manifest_text = manifest.read_text(encoding='utf-8')
manifest_text = manifest_text.replace(
    'android:icon="@mipmap/ic_launcher"',
    'android:icon="@drawable/chernogram_launcher_icon"',
)
manifest_text = manifest_text.replace(
    'android:roundIcon="@mipmap/ic_launcher"',
    'android:roundIcon="@drawable/chernogram_launcher_icon"',
)
manifest.write_text(manifest_text, encoding='utf-8')

print('Light chat build 73 patch applied.')
