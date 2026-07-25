import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChernogramApp());
}

enum Lang { ru, en }

enum Gram { instagram, telegram }

class ChernogramApp extends StatefulWidget {
  const ChernogramApp({super.key});

  @override
  State<ChernogramApp> createState() => _ChernogramAppState();
}

class _ChernogramAppState extends State<ChernogramApp> {
  Lang? _lang;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(
        () => _lang = prefs.getString('lang') == 'en' ? Lang.en : Lang.ru,
      );
    });
  }

  Future<void> _setLang(Lang value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', value.name);
    if (mounted) setState(() => _lang = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chernogram',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE9FF61),
          secondary: Color(0xFF7C8CFF),
          surface: Color(0xFF14161A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF090A0C),
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
      home: _lang == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : Home(lang: _lang!, onLang: _setLang),
    );
  }
}

class Home extends StatefulWidget {
  final Lang lang;
  final ValueChanged<Lang> onLang;

  const Home({super.key, required this.lang, required this.onLang});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;
  Gram _gram = Gram.instagram;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ChernogramUpdater.checkAndPrompt(context, ru: widget.lang == Lang.ru);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S(widget.lang);
    final pages = [
      LibraryScreen(
        s: s,
        gram: _gram,
        onGram: (v) => setState(() => _gram = v),
      ),
      DraftScreen(s: s, gram: _gram, onGram: (v) => setState(() => _gram = v)),
      SettingsScreen(s: s, lang: widget.lang, onLang: widget.onLang),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            Mark(size: 34),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHERNOGRAM',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'LOCAL CONTENT STUDIO',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white38,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.lang == Lang.ru
                ? 'Проверить обновления'
                : 'Check for updates',
            onPressed: () => ChernogramUpdater.checkAndPrompt(
              context,
              ru: widget.lang == Lang.ru,
              manual: true,
            ),
            icon: const Icon(Icons.system_update_alt_rounded),
          ),
          TextButton.icon(
            onPressed: () =>
                widget.onLang(widget.lang == Lang.ru ? Lang.en : Lang.ru),
            icon: const Icon(Icons.language, size: 18),
            label: Text(widget.lang == Lang.ru ? 'RU' : 'EN'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: s.media,
          ),
          NavigationDestination(
            icon: const Icon(Icons.edit_note_outlined),
            selectedIcon: const Icon(Icons.edit_note),
            label: s.draft,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: s.settings,
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  final S s;
  final Gram gram;
  final ValueChanged<Gram> onGram;

  const LibraryScreen({
    super.key,
    required this.s,
    required this.gram,
    required this.onGram,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scroll = ScrollController();
  PermissionState? _permission;
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _more = false;
  bool _hasMore = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 450)
        _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    _permission = permission;
    if (!permission.hasAccess) {
      setState(() => _loading = false);
      return;
    }
    _albums = await PhotoManager.getAssetPathList(
      hasAll: true,
      type: RequestType.common,
    );
    _album = _albums.isEmpty ? null : _albums.first;
    await _firstPage();
  }

  Future<void> _firstPage() async {
    _page = 0;
    final items = _album == null
        ? <AssetEntity>[]
        : await _album!.getAssetListPaged(page: 0, size: 90);
    if (!mounted) return;
    setState(() {
      _assets = items;
      _hasMore = items.length == 90;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _more || !_hasMore || _album == null) return;
    setState(() => _more = true);
    final items = await _album!.getAssetListPaged(page: _page + 1, size: 90);
    if (!mounted) return;
    setState(() {
      _page++;
      _assets.addAll(items);
      _hasMore = items.length == 90;
      _more = false;
    });
  }

  Future<void> _pickAlbum() async {
    final selected = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _albums.length,
          itemBuilder: (_, i) => ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(_albums[i].name),
            trailing: _albums[i].id == _album?.id
                ? const Icon(Icons.check_circle)
                : null,
            onTap: () => Navigator.pop(context, _albums[i]),
          ),
        ),
      ),
    );
    if (selected == null || selected.id == _album?.id) return;
    setState(() {
      _album = selected;
      _loading = true;
    });
    await _firstPage();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!(_permission?.hasAccess ?? false)) {
      return PermissionView(s: widget.s, retry: _load);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            children: [
              GramSwitch(
                value: widget.gram,
                s: widget.s,
                onChanged: widget.onGram,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickAlbum,
                      borderRadius: BorderRadius.circular(15),
                      child: Box(
                        child: Row(
                          children: [
                            const Icon(Icons.folder_open_outlined, size: 19),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _album?.name ?? widget.s.allMedia,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _assets.isEmpty
              ? Center(child: Text(widget.s.noMedia))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: _assets.length + (_more ? 3 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _assets.length)
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    final asset = _assets[i];
                    return AssetThumb(
                      asset: asset,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PreviewScreen(
                            asset: asset,
                            gram: widget.gram,
                            s: widget.s,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class AssetThumb extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const AssetThumb({super.key, required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize.square(320),
              quality: 82,
            ),
            builder: (_, snap) => snap.data == null
                ? const ColoredBox(
                    color: Color(0xFF181A1E),
                    child: Icon(Icons.image_outlined),
                  )
                : Image.memory(
                    snap.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
          if (asset.type == AssetType.video)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 13),
                    Text(
                      durationText(asset.videoDuration),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  final AssetEntity asset;
  final Gram gram;
  final S s;

  const PreviewScreen({
    super.key,
    required this.asset,
    required this.gram,
    required this.s,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late Gram _gram;
  final _caption = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gram = widget.gram;
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _soon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title — ${widget.s.soon}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.s.preview)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: [
            GramSwitch(
              value: _gram,
              s: widget.s,
              onChanged: (v) => setState(() => _gram = v),
            ),
            const SizedBox(height: 12),
            _gram == Gram.instagram
                ? InstagramCard(
                    asset: widget.asset,
                    caption: _caption.text,
                    s: widget.s,
                  )
                : TelegramCard(
                    asset: widget.asset,
                    caption: _caption.text,
                    s: widget.s,
                  ),
            const SizedBox(height: 12),
            TextField(
              controller: _caption,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.s.caption,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _soon(widget.s.edit),
                    icon: const Icon(Icons.tune),
                    label: Text(widget.s.edit),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _soon(widget.s.export),
                    icon: const Icon(Icons.ios_share),
                    label: Text(widget.s.export),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class InstagramCard extends StatelessWidget {
  final AssetEntity asset;
  final String caption;
  final S s;

  const InstagramCard({
    super.key,
    required this.asset,
    required this.caption,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: const Color(0xFF14161A),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('C')),
              title: Text('chernogram.preview'),
              subtitle: Text('Local device'),
              trailing: Icon(Icons.more_horiz),
            ),
            AssetImageView(asset: asset),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 11, 14, 5),
              child: Row(
                children: [
                  Icon(Icons.favorite_border),
                  SizedBox(width: 14),
                  Icon(Icons.mode_comment_outlined),
                  SizedBox(width: 14),
                  Icon(Icons.send_outlined),
                  Spacer(),
                  Icon(Icons.bookmark_border),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 5, 14, 16),
              child: Text(
                caption.isEmpty ? s.instaSample : caption,
                style: TextStyle(
                  color: caption.isEmpty ? Colors.white54 : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TelegramCard extends StatelessWidget {
  final AssetEntity asset;
  final String caption;
  final S s;

  const TelegramCard({
    super.key,
    required this.asset,
    required this.caption,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: ColoredBox(
            color: const Color(0xFF246B52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AssetImageView(asset: asset),
                Padding(
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          caption.isEmpty ? s.tgSample : caption,
                          style: TextStyle(
                            color: caption.isEmpty
                                ? Colors.white60
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '18:42 ✓✓',
                        style: TextStyle(fontSize: 9, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AssetImageView extends StatelessWidget {
  final AssetEntity asset;

  const AssetImageView({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    final ratio = asset.height == 0 ? 1.0 : asset.width / asset.height;
    return AspectRatio(
      aspectRatio: ratio.clamp(.75, 1.6).toDouble(),
      child: FutureBuilder<Uint8List?>(
        future: asset.thumbnailDataWithSize(
          const ThumbnailSize(1200, 1200),
          quality: 92,
        ),
        builder: (_, snap) {
          if (snap.data == null)
            return const ColoredBox(
              color: Color(0xFF202329),
              child: Center(child: CircularProgressIndicator()),
            );
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                snap.data!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              if (asset.type == AssetType.video)
                const Center(
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.play_arrow, size: 38),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class DraftScreen extends StatefulWidget {
  final S s;
  final Gram gram;
  final ValueChanged<Gram> onGram;

  const DraftScreen({
    super.key,
    required this.s,
    required this.gram,
    required this.onGram,
  });

  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _insert(String value) {
    final selection = _text.selection;
    final at = selection.isValid ? selection.start : _text.text.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(at, at, value),
      selection: TextSelection.collapsed(offset: at + value.length),
    );
    setState(() {});
  }

  void _wrap(String left, String right) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    final selected = _text.text.substring(start, end);
    final next = _text.text.replaceRange(start, end, '$left$selected$right');
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + left.length + selected.length,
      ),
    );
    setState(() {});
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.s.copied)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        GramSwitch(value: widget.gram, s: widget.s, onChanged: widget.onGram),
        const SizedBox(height: 14),
        Text(
          widget.s.editor,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          widget.s.editorHint,
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            IconButton.filledTonal(
              onPressed: () => _wrap('**', '**'),
              icon: const Icon(Icons.format_bold),
            ),
            IconButton.filledTonal(
              onPressed: () => _wrap('_', '_'),
              icon: const Icon(Icons.format_italic),
            ),
            IconButton.filledTonal(
              onPressed: () => _wrap('`', '`'),
              icon: const Icon(Icons.code),
            ),
            IconButton.filledTonal(
              onPressed: () => _insert('> '),
              icon: const Icon(Icons.format_quote),
            ),
            for (final e in ['🔥', '✅', '💡', '🚀', '❤️'])
              ActionChip(label: Text(e), onPressed: () => _insert(e)),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 14,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: widget.s.write,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        Row(
          children: [
            Text(
              '${_text.text.runes.length} ${widget.s.symbols}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _text.text.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy),
              label: Text(widget.s.copy),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.s.live,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        widget.gram == Gram.telegram
            ? Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101820),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF246B52),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _text.text.isEmpty ? widget.s.tgSample : _text.text,
                    ),
                  ),
                ),
              )
            : Box(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(child: Text('C')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _text.text.isEmpty ? widget.s.instaSample : _text.text,
                      ),
                    ),
                  ],
                ),
              ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final S s;
  final Lang lang;
  final ValueChanged<Lang> onLang;

  const SettingsScreen({
    super.key,
    required this.s,
    required this.lang,
    required this.onLang,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        Text(
          s.settings,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Box(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(s.language),
              ),
              SegmentedButton<Lang>(
                segments: const [
                  ButtonSegment(value: Lang.ru, label: Text('Русский')),
                  ButtonSegment(value: Lang.en, label: Text('English')),
                ],
                selected: {lang},
                onSelectionChanged: (v) => onLang(v.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Box(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(s.local),
                subtitle: Text(s.localHint),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: Text(s.noDb),
                subtitle: Text(s.noDbHint),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(s.account),
                subtitle: Text(s.accountHint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Box(
          child: ListTile(
            leading: const Mark(size: 44),
            title: const Text('Chernogram 0.3.0'),
            subtitle: Text(s.prototype),
          ),
        ),
      ],
    );
  }
}

class GramSwitch extends StatelessWidget {
  final Gram value;
  final S s;
  final ValueChanged<Gram> onChanged;

  const GramSwitch({
    super.key,
    required this.value,
    required this.s,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF14161A),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF272A30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GramButton(
              selected: value == Gram.instagram,
              icon: Icons.camera_alt_outlined,
              title: 'Instagram',
              subtitle: s.feed,
              onTap: () => onChanged(Gram.instagram),
            ),
          ),
          Expanded(
            child: GramButton(
              selected: value == Gram.telegram,
              icon: Icons.send_rounded,
              title: 'Telegram',
              subtitle: s.message,
              onTap: () => onChanged(Gram.telegram),
            ),
          ),
        ],
      ),
    );
  }
}

class GramButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const GramButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE9FF61) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 21,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: selected ? Colors.black54 : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionView extends StatelessWidget {
  final S s;
  final VoidCallback retry;

  const PermissionView({super.key, required this.s, required this.retry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mark(size: 86),
            const SizedBox(height: 18),
            Text(
              s.permissionTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            Text(
              s.permissionText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(s.allow),
            ),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: Text(s.openSettings),
            ),
          ],
        ),
      ),
    );
  }
}

class Box extends StatelessWidget {
  final Widget child;

  const Box({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF14161A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF272A30)),
      ),
      child: child,
    );
  }
}

class Mark extends StatelessWidget {
  final double size;

  const Mark({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFE9FF61),
      ),
      child: Icon(Icons.layers_rounded, color: Colors.black, size: size * .5),
    );
  }
}

class S {
  final Lang lang;
  const S(this.lang);
  bool get ru => lang == Lang.ru;
  String get media => ru ? 'Медиа' : 'Media';
  String get draft => ru ? 'Черновик' : 'Draft';
  String get settings => ru ? 'Настройки' : 'Settings';
  String get allMedia => ru ? 'Все медиа' : 'All media';
  String get noMedia =>
      ru ? 'Нет доступных фото и видео' : 'No accessible photos or videos';
  String get preview => ru ? 'Предпросмотр' : 'Preview';
  String get caption =>
      ru ? 'Добавьте подпись или текст поста…' : 'Add a caption or post text…';
  String get edit => ru ? 'Обработать' : 'Edit';
  String get export => ru ? 'Экспорт' : 'Export';
  String get soon =>
      ru ? 'добавим следующим этапом' : 'coming in the next step';
  String get instaSample => ru
      ? 'Так контент будет выглядеть в Instagram.'
      : 'This is how the content will look on Instagram.';
  String get tgSample => ru
      ? 'Так пост будет выглядеть в Telegram.'
      : 'This is how the post will look on Telegram.';
  String get editor => ru ? 'Редактор поста' : 'Post editor';
  String get editorHint => ru
      ? 'Готовьте текст и сразу смотрите результат в выбранном «граме».'
      : 'Write text and instantly preview it in the selected gram.';
  String get write => ru ? 'Напишите будущий пост…' : 'Write your future post…';
  String get symbols => ru ? 'символов' : 'characters';
  String get copy => ru ? 'Копировать' : 'Copy';
  String get copied => ru ? 'Текст скопирован' : 'Text copied';
  String get live => ru ? 'Живой предпросмотр' : 'Live preview';
  String get language => ru ? 'Язык интерфейса' : 'Interface language';
  String get local => ru ? 'Только на устройстве' : 'On-device only';
  String get localHint => ru
      ? 'Медиа не загружается в облако Чернограма.'
      : 'Media is not uploaded to a Chernogram cloud.';
  String get noDb => ru ? 'Без базы данных' : 'No database';
  String get noDbHint => ru
      ? 'Приложение читает системную медиатеку напрямую.'
      : 'The app reads the system media library directly.';
  String get account => ru ? 'Аккаунт необязателен' : 'Account is optional';
  String get accountHint => ru
      ? 'Авторизация понадобится только для прямой публикации.'
      : 'Sign-in will only be needed for direct publishing.';
  String get prototype => ru
      ? 'Локальная галерея, два режима предпросмотра и редактор текста.'
      : 'Local gallery, two preview modes and a text editor.';
  String get feed => ru ? 'лента и подпись' : 'feed and caption';
  String get message => ru ? 'пост и сообщение' : 'post and message';
  String get permissionTitle =>
      ru ? 'Разрешите доступ к медиатеке' : 'Allow media library access';
  String get permissionText => ru
      ? 'Чернограм покажет фото и видео только на этом устройстве и не отправит их на сервер.'
      : 'Chernogram will show photos and videos only on this device and will not upload them.';
  String get allow => ru ? 'Разрешить доступ' : 'Allow access';
  String get openSettings =>
      ru ? 'Открыть настройки телефона' : 'Open device settings';
}

String durationText(Duration value) {
  final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
