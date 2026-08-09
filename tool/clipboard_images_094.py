from pathlib import Path
import re


def patch(path: str, transform) -> None:
    file = Path(path)
    source = file.read_text(encoding='utf-8')
    updated = transform(source)
    if updated == source:
        raise RuntimeError(f'No 0.94 change applied to {path}')
    file.write_text(updated, encoding='utf-8')
    print(f'Patched 0.94: {path}')


def pubspec(source: str) -> str:
    source = source.replace(
        '  camera: ^0.12.0+2\n',
        '  camera: ^0.12.0+2\n  pasteboard: ^0.5.0\n',
        1,
    )
    return re.sub(r'^version: .*$', 'version: 0.94.0+94', source, count=1, flags=re.M)


def chat(source: str) -> str:
    source = source.replace(
        "import 'package:cross_file/cross_file.dart';\n",
        "import 'package:cross_file/cross_file.dart';\nimport 'package:pasteboard/pasteboard.dart';\n",
        1,
    )

    anchor = '  Future<void> _pickAttachment(\n'
    methods = r'''  void _insertClipboardText(String value) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    final safeStart = start.clamp(0, _text.text.length);
    final safeEnd = end.clamp(safeStart, _text.text.length);
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(safeStart, safeEnd, value),
      selection: TextSelection.collapsed(offset: safeStart + value.length),
    );
    _composerFocus.requestFocus();
  }

  Future<void> _pasteClipboard() async {
    if (_sendingFile) return;
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        await _sendClipboardImage(bytes);
        return;
      }
    } catch (_) {}

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (value != null && value.isNotEmpty) {
      _insertClipboardText(value);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.ru
                ? 'В буфере нет изображения или текста.'
                : 'Clipboard has no image or text.',
          ),
        ),
      );
    }
  }

  Future<void> _sendClipboardImage(Uint8List bytes) async {
    if (_sendingFile || bytes.isEmpty) return;
    setState(() => _sendingFile = true);
    try {
      final id = CgIds.random(20);
      final name = 'clipboard_${DateTime.now().millisecondsSinceEpoch}.png';
      final local = await CgMediaStore.persistBytes(
        attachmentId: id,
        name: name,
        bytes: bytes,
      );
      await _sendAttachment(
        CgAttachment(
          id: id,
          name: name,
          size: bytes.length,
          kind: 'image',
          localPath: local.path,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.ru
                  ? 'Не удалось вставить изображение.'
                  : 'Could not paste the image.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingFile = false);
    }
  }

  Widget _composerContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final standard = editableTextState.contextMenuButtonItems.where(
      (item) => item.type != ContextMenuButtonType.paste,
    );
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          label: widget.ru ? 'Вставить' : 'Paste',
          onPressed: () {
            ContextMenuController.removeAny();
            unawaited(_pasteClipboard());
          },
        ),
        ...standard,
      ],
    );
  }

'''
    if anchor not in source:
        raise RuntimeError('Attachment picker anchor missing')
    source = source.replace(anchor, methods + anchor, 1)

    old = '''                            Expanded(
                              child: TextField(
                                controller: _text,
                                focusNode: _composerFocus,
'''
    new = '''                            Expanded(
                              child: CallbackShortcuts(
                                bindings: <ShortcutActivator, VoidCallback>{
                                  const SingleActivator(
                                    LogicalKeyboardKey.keyV,
                                    control: true,
                                  ): () => unawaited(_pasteClipboard()),
                                },
                                child: TextField(
                                  controller: _text,
                                  focusNode: _composerFocus,
                                  contextMenuBuilder: _composerContextMenu,
'''
    if old not in source:
        raise RuntimeError('Composer field opening anchor missing')
    source = source.replace(old, new, 1)

    old_close = '''                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
'''
    new_close = '''                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
'''
    if old_close not in source:
        raise RuntimeError('Composer field closing anchor missing')
    return source.replace(old_close, new_close, 1)


def settings(source: str) -> str:
    return source.replace('chernogram-android-0.93.apk', 'chernogram-android-0.94.apk').replace(
        'chernogram-windows-0.93.zip', 'chernogram-windows-0.94.zip'
    )


def manifest(source: str) -> str:
    anchor = '''        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
'''
    provider = '''        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/provider_paths" />
        </provider>

'''
    if anchor not in source:
        raise RuntimeError('Android provider anchor missing')
    return source.replace(anchor, provider + anchor, 1)


patch('pubspec.yaml', pubspec)
patch('lib/chat_screen.dart', chat)
patch('lib/client_settings.dart', settings)
patch('android/app/src/main/AndroidManifest.xml', manifest)

provider_paths = Path('android/app/src/main/res/xml/provider_paths.xml')
provider_paths.write_text(
    '''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path name="external_files" path="." />
</paths>
''',
    encoding='utf-8',
)
print(f'Created 0.94: {provider_paths}')
