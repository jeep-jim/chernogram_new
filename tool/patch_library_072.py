from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


path = Path('lib/library/library_page.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => _ImageViewer(item: item)),
        );
      case LibraryKinds.audio:
""",
    """        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => _ImageViewer(item: item)),
        );
        return;
      case LibraryKinds.audio:
""",
    'image switch return',
)
text = replace_once(
    text,
    """        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LibraryAudioPlayer(items: audio, initialIndex: index),
          ),
        );
      case LibraryKinds.video:
""",
    """        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LibraryAudioPlayer(items: audio, initialIndex: index),
          ),
        );
        return;
      case LibraryKinds.video:
""",
    'audio switch return',
)
text = replace_once(
    text,
    """        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LibraryVideoPlayer(
              item: item,
              circular: item.kind == LibraryKinds.circle,
            ),
          ),
        );
      default:
        await OpenFilex.open(path);
    }
""",
    """        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LibraryVideoPlayer(
              item: item,
              circular: item.kind == LibraryKinds.circle,
            ),
          ),
        );
        return;
      default:
        await OpenFilex.open(path);
        return;
    }
""",
    'video and default switch return',
)
text = replace_once(
    text,
    """  late int _index = widget.initialIndex.clamp(0, max(0, widget.items.length - 1));
""",
    """  late int _index;
""",
    'audio index field',
)
text = replace_once(
    text,
    """  void initState() {
    super.initState();
    _durationSubscription = _player.durationStream.listen((value) {
""",
    """  void initState() {
    super.initState();
    _index = widget.initialIndex
        .clamp(0, max(0, widget.items.length - 1))
        .toInt();
    _durationSubscription = _player.durationStream.listen((value) {
""",
    'audio index init',
)
text = text.replace(
    'min(MediaQuery.sizeOf(context).width - 70, 320)',
    'min(MediaQuery.sizeOf(context).width - 70, 320.0)',
)
text = text.replace(
    'min(MediaQuery.sizeOf(context).width - 44, 420)',
    'min(MediaQuery.sizeOf(context).width - 44, 420.0)',
)
path.write_text(text, encoding='utf-8')

path = Path('lib/interests/interests_models.dart')
text = path.read_text(encoding='utf-8')
text = text.replace(
    'score += min(3, topic.followers / 5);',
    'score += min<double>(3, topic.followers / 5);',
)
text = text.replace(
    'score += min(2, topic.replies / 8);',
    'score += min<double>(2, topic.replies / 8);',
)
path.write_text(text, encoding='utf-8')

print('Library Network build 72 patch applied.')
