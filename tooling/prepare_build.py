from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"Could not patch {label}")
    return text.replace(old, new, 1)


main_path = Path("lib/main.dart")
main = main_path.read_text(encoding="utf-8")

main = replace_once(
    main,
    "import 'package:shared_preferences/shared_preferences.dart';\n",
    "import 'package:shared_preferences/shared_preferences.dart';\n\nimport 'update_service.dart';\n",
    "updater import",
)

main = replace_once(
    main,
    "class _HomeState extends State<Home> {\n  int _tab = 0;\n  Gram _gram = Gram.instagram;\n",
    "class _HomeState extends State<Home> {\n  int _tab = 0;\n  Gram _gram = Gram.instagram;\n\n  @override\n  void initState() {\n    super.initState();\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted) return;\n      ChernogramUpdater.checkAndPrompt(\n        context,\n        ru: widget.lang == Lang.ru,\n      );\n    });\n  }\n",
    "automatic update check",
)

main = replace_once(
    main,
    "        actions: [\n          TextButton.icon(\n",
    "        actions: [\n          IconButton(\n            tooltip: widget.lang == Lang.ru\n                ? 'Проверить обновления'\n                : 'Check for updates',\n            onPressed: () => ChernogramUpdater.checkAndPrompt(\n              context,\n              ru: widget.lang == Lang.ru,\n              manual: true,\n            ),\n            icon: const Icon(Icons.system_update_alt_rounded),\n          ),\n          TextButton.icon(\n",
    "manual update button",
)

main = main.replace("Chernogram 0.2.0", "Chernogram 0.3.0")
main_path.write_text(main, encoding="utf-8")

update_path = Path("lib/update_service.dart")
update = update_path.read_text(encoding="utf-8")
update = update.replace(
    "progress.value = value.clamp(0, 100);",
    "progress.value = value.clamp(0, 100).toDouble();",
)
update = update.replace(
    "if (value != null) progress.value = value.clamp(0, 100);",
    "if (value != null) {\n                progress.value = value.clamp(0, 100).toDouble();\n              }",
)

old_switch = """          final eventName = event.status.toString().split('.').last;
          switch (eventName) {
            case 'DOWNLOADING':
              final value = double.tryParse(event.value ?? '') ?? 0;
              progress.value = value.clamp(0, 100).toDouble();
              status.value = ru ? 'Скачиваем новую версию…' : 'Downloading the new version…';
            case 'INSTALLING':
              final value = double.tryParse(event.value ?? '');
              if (value != null) {
                progress.value = value.clamp(0, 100).toDouble();
              }
              status.value = ru
                  ? 'Откройте системное окно и подтвердите установку.'
                  : 'Confirm installation in the Android system window.';
              if (value == null) closeDialog();
            case 'INSTALLATION_DONE':
              closeDialog();
              if (!completed.isCompleted) completed.complete();
            case 'PERMISSION_NOT_GRANTED_ERROR':
              fail(
                ru
                    ? 'Разрешите Чернограму устанавливать обновления в настройках Android и повторите попытку.'
                    : 'Allow Chernogram to install updates in Android settings and try again.',
              );
              if (!completed.isCompleted) completed.complete();
            case 'DOWNLOAD_ERROR':
            case 'CHECKSUM_ERROR':
            case 'INSTALLATION_ERROR':
            case 'INTERNAL_ERROR':
            case 'ALREADY_RUNNING_ERROR':
              fail(
                ru
                    ? 'Не удалось установить обновление. Повторите попытку.'
                    : 'The update could not be installed. Please try again.',
              );
              if (!completed.isCompleted) completed.complete();
            case 'CANCELED':
              closeDialog();
              if (!completed.isCompleted) completed.complete();
          }
"""

new_switch = """          final eventName = event.status.toString().split('.').last;
          if (eventName == 'DOWNLOADING') {
            final value = double.tryParse(event.value ?? '') ?? 0;
            progress.value = value.clamp(0, 100).toDouble();
            status.value = ru
                ? 'Скачиваем новую версию…'
                : 'Downloading the new version…';
            return;
          }

          if (eventName == 'INSTALLING') {
            final value = double.tryParse(event.value ?? '');
            if (value != null) {
              progress.value = value.clamp(0, 100).toDouble();
            }
            status.value = ru
                ? 'Откройте системное окно и подтвердите установку.'
                : 'Confirm installation in the Android system window.';
            if (value == null) closeDialog();
            return;
          }

          if (eventName == 'INSTALLATION_DONE') {
            closeDialog();
            if (!completed.isCompleted) completed.complete();
            return;
          }

          if (eventName == 'PERMISSION_NOT_GRANTED_ERROR') {
            fail(
              ru
                  ? 'Разрешите Чернограму устанавливать обновления в настройках Android и повторите попытку.'
                  : 'Allow Chernogram to install updates in Android settings and try again.',
            );
            if (!completed.isCompleted) completed.complete();
            return;
          }

          const errors = {
            'DOWNLOAD_ERROR',
            'CHECKSUM_ERROR',
            'INSTALLATION_ERROR',
            'INTERNAL_ERROR',
            'ALREADY_RUNNING_ERROR',
          };
          if (errors.contains(eventName)) {
            fail(
              ru
                  ? 'Не удалось установить обновление. Повторите попытку.'
                  : 'The update could not be installed. Please try again.',
            );
            if (!completed.isCompleted) completed.complete();
            return;
          }

          if (eventName == 'CANCELED') {
            closeDialog();
            if (!completed.isCompleted) completed.complete();
          }
"""

if new_switch not in update:
    if old_switch not in update:
        raise RuntimeError("Could not patch OTA event handler")
    update = update.replace(old_switch, new_switch, 1)

update_path.write_text(update, encoding="utf-8")
