from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


# HTTP polling must also run when a network blocks WebSocket upgrades entirely.
replace_once(
    "lib/internet_core.dart",
    "      } else {\n"
    "        _emit('status', const <String, dynamic>{\n"
    "          'state': 'queued',\n"
    "          'transport': 'encrypted_relay',\n"
    "        });\n",
    "      } else {\n"
    "        _startTimers();\n"
    "        _emit('status', const <String, dynamic>{\n"
    "          'state': 'queued',\n"
    "          'transport': 'encrypted_relay',\n"
    "        });\n",
)

# Ask Android for the dedicated full-screen call-notification capability.
replace_once(
    "lib/background_service.dart",
    "    await android?.createNotificationChannel(\n"
    "      const AndroidNotificationChannel(\n"
    "        'chernogram_calls',\n"
    "        'Звонки Чернограма',\n"
    "        description: 'Входящие аудио- и видеозвонки',\n"
    "        importance: Importance.max,\n"
    "        playSound: true,\n"
    "        enableVibration: true,\n"
    "      ),\n"
    "    );\n"
    "    _notificationsReady = true;\n",
    "    await android?.createNotificationChannel(\n"
    "      const AndroidNotificationChannel(\n"
    "        'chernogram_calls',\n"
    "        'Звонки Чернограма',\n"
    "        description: 'Входящие аудио- и видеозвонки',\n"
    "        importance: Importance.max,\n"
    "        playSound: true,\n"
    "        enableVibration: true,\n"
    "      ),\n"
    "    );\n"
    "    await android?.requestFullScreenIntentPermission();\n"
    "    _notificationsReady = true;\n",
)

print("Reliability build 75 extra patches applied")
