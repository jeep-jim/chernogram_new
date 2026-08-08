from pathlib import Path

# The structural block replacements in 0.91 intentionally keep the end marker;
# collapse the duplicated class marker once after composition.
media = Path('lib/chat_media.dart')
text = media.read_text(encoding='utf-8')
for marker in (
    'class CgMediaLibraryScreen extends StatefulWidget {',
    'class CgVideoPlayerScreen extends StatefulWidget {',
    'class CgImageViewer extends StatelessWidget {',
):
    duplicate = marker + marker
    if duplicate in text:
        text = text.replace(duplicate, marker, 1)
media.write_text(text, encoding='utf-8')

# additionalFlags uses Int32List.fromList at runtime, so the containing Android
# notification details cannot remain const.
for filename in ('lib/background_runtime.dart', 'lib/push_service.dart'):
    path = Path(filename)
    text = path.read_text(encoding='utf-8')
    text = text.replace(
        'notificationDetails: const NotificationDetails(',
        'notificationDetails: NotificationDetails(',
    )
    text = text.replace(
        'android: const AndroidNotificationDetails(',
        'android: AndroidNotificationDetails(',
    )
    path.write_text(text, encoding='utf-8')

print('Chernogram 0.91 compile composition fixes applied')
