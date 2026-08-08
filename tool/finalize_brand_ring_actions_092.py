from pathlib import Path
import re


def patch(path: str, transform) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    updated = transform(source)
    if updated == source:
        print(f'No change: {path}')
        return
    file.write_text(updated, encoding='utf-8')
    print(f'Patched: {path}')


def kotlin(source: str) -> str:
    source = source.replace('import android.media.Ringtone\n', 'import android.media.AudioAttributes\nimport android.media.MediaPlayer\n')
    source = source.replace('private var incomingRingtone: Ringtone? = null', 'private var incomingPlayer: MediaPlayer? = null')
    source = source.replace('vibrate(longArrayOf(0, 35))', 'vibrate(longArrayOf(0, 35), repeat = false)')
    source = source.replace('vibrate(longArrayOf(0, 450, 350, 450, 350, 450))', 'vibrate(longArrayOf(0, 450, 350, 450, 350, 450), repeat = true)')
    source = re.sub(
        r'    private fun startIncomingCallSound\(\) \{.*?\n    \}\n\n    private fun stopIncomingCallSound',
        '''    private fun startIncomingCallSound() {
        stopIncomingCallSound()
        val descriptor = resources.openRawResourceFd(R.raw.chernogram_call_ring)
        incomingPlayer = MediaPlayer().also { player ->
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            player.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
            descriptor.close()
            player.isLooping = true
            player.prepare()
            player.start()
        }
    }

    private fun stopIncomingCallSound''',
        source,
        count=1,
        flags=re.S,
    )
    source = re.sub(
        r'    private fun stopIncomingCallSound\(\) \{.*?\n    \}\n\n    @Suppress',
        '''    private fun stopIncomingCallSound() {
        incomingPlayer?.run {
            if (isPlaying) stop()
            release()
        }
        incomingPlayer = null
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        vibrator.cancel()
    }

    @Suppress''',
        source,
        count=1,
        flags=re.S,
    )
    source = re.sub(
        r'    private fun vibrate\(pattern: LongArray(?:, repeat: Boolean)?\) \{.*?\n    \}\n\n    override fun onStop',
        '''    private fun vibrate(pattern: LongArray, repeat: Boolean) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (!vibrator.hasVibrator()) return
        val repeatIndex = if (repeat) 0 else -1
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, repeatIndex))
        } else {
            vibrator.vibrate(pattern, repeatIndex)
        }
    }

    override fun onStop''',
        source,
        count=1,
        flags=re.S,
    )
    return source


VIEWER = r'''class CgImageViewer extends StatefulWidget {
  final Uint8List? bytes;
  final File? file;
  final String title;

  const CgImageViewer({
    super.key,
    this.bytes,
    this.file,
    required this.title,
  }) : assert(bytes != null || file != null);

  @override
  State<CgImageViewer> createState() => _CgImageViewerState();
}

class _CgImageViewerState extends State<CgImageViewer> {
  Offset _pointer = Offset.zero;

  Future<File> _sourceFile() async {
    if (widget.file != null) return widget.file!;
    return CgMediaStore.persistBytes(
      attachmentId: 'viewer_${widget.bytes!.length}',
      name: widget.title,
      bytes: widget.bytes!,
    );
  }

  Future<void> _action(String action) async {
    final file = await _sourceFile();
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: file.path));
    } else if (action == 'share') {
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
    } else if (action == 'save') {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить изображение',
        fileName: widget.title,
      );
      if (target != null && target.isNotEmpty) await file.copy(target);
    } else if (action == 'open') {
      await OpenFilex.open(file.path);
    }
  }

  List<PopupMenuEntry<String>> _items() => const <PopupMenuEntry<String>>[
    PopupMenuItem(value: 'copy', child: Text('Копировать путь')),
    PopupMenuItem(value: 'share', child: Text('Отправить')),
    PopupMenuItem(value: 'save', child: Text('Сохранить как…')),
    PopupMenuItem(value: 'open', child: Text('Открыть в другой программе')),
  ];

  Future<void> _contextMenu() async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final point = overlay.globalToLocal(_pointer);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        point & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _items(),
    );
    if (selected != null) await _action(selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: <Widget>[
        PopupMenuButton<String>(onSelected: _action, itemBuilder: (_) => _items()),
      ],
    ),
    body: Listener(
      onPointerDown: (event) {
        _pointer = event.position;
        if (event.buttons == kSecondaryMouseButton) unawaited(_contextMenu());
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) {
          _pointer = details.globalPosition;
          unawaited(_contextMenu());
        },
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 6,
          child: Center(
            child: widget.file != null
                ? Image.file(widget.file!, fit: BoxFit.contain, gaplessPlayback: true)
                : Image.memory(widget.bytes!, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      ),
    ),
  );
}

class CgVideoPlayerScreen extends StatefulWidget {'''


def media(source: str) -> str:
    if "package:flutter/gestures.dart" not in source:
        source = source.replace("import 'package:flutter/material.dart';\n", "import 'package:flutter/gestures.dart';\nimport 'package:flutter/material.dart';\n", 1)
    if "package:file_picker/file_picker.dart" not in source:
        source = source.replace("import 'package:camera/camera.dart';\n", "import 'package:camera/camera.dart';\nimport 'package:file_picker/file_picker.dart';\n", 1)
    return re.sub(
        r'class CgImageViewer extends (?:StatelessWidget|StatefulWidget) \{.*?class CgVideoPlayerScreen extends StatefulWidget \{',
        VIEWER,
        source,
        count=1,
        flags=re.S,
    )


def chat(source: str) -> str:
    old = '''    if (!changed) return;
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
'''
    new = '''    if (!changed) return;
    messages.sort((left, right) => left.sentAt.compareTo(right.sentAt));
    setState(() => _tunnel = _tunnel.copyWith(messages: messages));
'''
    if old not in source:
        raise RuntimeError('Chat message merge anchor was not found')
    return source.replace(old, new, 1)


patch('android/app/src/main/kotlin/com/example/chernogram/MainActivity.kt', kotlin)
patch('lib/chat_media.dart', media)
patch('lib/chat_screen.dart', chat)
patch('pubspec.yaml', lambda source: re.sub(r'^version: .*$', 'version: 0.92.0+92', source, count=1, flags=re.M))
patch(
    'lib/client_settings.dart',
    lambda source: source
        .replace('chernogram-android-0.91.apk', 'chernogram-android-0.92.apk')
        .replace('chernogram-windows-0.91.zip', 'chernogram-windows-0.92.zip'),
)
