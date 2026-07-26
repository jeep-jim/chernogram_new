from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    if old not in source:
        raise RuntimeError(f'Expected block was not found in {path}')
    file.write_text(source.replace(old, new), encoding='utf-8')


def main() -> None:
    replace(
        'lib/chat_media.dart',
        """  final ValueChanged<List<CgTunnel>> onTunnelsChanged;

  const CgMediaLibraryScreen({
""",
        """  final ValueChanged<List<CgTunnel>> onTunnelsChanged;
  final String initialFilter;

  const CgMediaLibraryScreen({
""",
    )
    replace(
        'lib/chat_media.dart',
        """    required this.tunnels,
    required this.onTunnelsChanged,
  });
""",
        """    required this.tunnels,
    required this.onTunnelsChanged,
    this.initialFilter = 'all',
  });
""",
    )
    replace(
        'lib/chat_media.dart',
        "  String _filter = 'all';\n",
        "  late String _filter;\n",
    )
    replace(
        'lib/chat_media.dart',
        """    _tunnels = widget.tunnels;
    _reload();
""",
        """    _tunnels = widget.tunnels;
    _filter = widget.initialFilter;
    _reload();
""",
    )
    replace(
        'lib/chat_media.dart',
        """        title: Text(widget.ru ? 'Файлы и медиа' : 'Files and media'),
""",
        """        title: Text(
          widget.initialFilter == 'audio'
              ? (widget.ru ? 'Музыкальный плеер' : 'Music player')
              : (widget.ru ? 'Файлы и медиа' : 'Files and media'),
        ),
""",
    )

    replace(
        'lib/v07.dart',
        "  Future<void> _openMediaLibrary() async {\n",
        "  Future<void> _openMediaLibrary({String initialFilter = 'all'}) async {\n",
    )
    replace(
        'lib/v07.dart',
        """          tunnels: _tunnels,
          onTunnelsChanged: (updated) {
""",
        """          tunnels: _tunnels,
          initialFilter: initialFilter,
          onTunnelsChanged: (updated) {
""",
    )

    replace(
        'lib/v07.dart',
        """        actions: [
          GlassIconButton(
            icon: Icons.folder_copy_outlined,
            tooltip: widget.ru ? 'Файлы и медиа' : 'Files and media',
            onPressed: _openMediaLibrary,
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            icon: _privacyLens
                ? Icons.visibility_off_rounded
                : Icons.visibility_outlined,
            tooltip: widget.ru ? 'Приватный взгляд' : 'Privacy Lens',
            active: _privacyLens,
            onPressed: _togglePrivacy,
          ),
          const SizedBox(width: 6),
""",
        """        actions: [
          GlassIconButton(
            icon: Icons.folder_copy_outlined,
            tooltip: widget.ru ? 'Файлы и медиа' : 'Files and media',
            onPressed: _openMediaLibrary,
          ),
          const SizedBox(width: 6),
          GlassIconButton(
            icon: Icons.queue_music_rounded,
            tooltip: widget.ru ? 'Музыкальный плеер' : 'Music player',
            active: true,
            onPressed: () => _openMediaLibrary(initialFilter: 'audio'),
          ),
          const SizedBox(width: 6),
""",
    )

    print('Applied Chernogram 0.9.1 music-player header update')


if __name__ == '__main__':
    main()
