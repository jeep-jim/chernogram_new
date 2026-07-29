from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "lib" / "android_data_first.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    text = PATH.read_text(encoding="utf-8")

    if "import 'agent_screen.dart';" not in text:
        text = replace_once(
            text,
            "import 'account_access.dart';\n",
            "import 'account_access.dart';\nimport 'agent_screen.dart';\n",
            "agent import",
        )
    if "import 'legacy_v16_features.dart';" not in text:
        text = replace_once(
            text,
            "import 'core_models.dart';\n",
            "import 'core_models.dart';\nimport 'legacy_v16_features.dart';\n",
            "legacy feature import",
        )

    marker = "title: ru ? 'Два устройства' : 'Two devices'"
    if marker not in text:
        anchor = """      _ProfileAction(
        icon: Icons.install_mobile_rounded,
"""
        cards = """      _ProfileAction(
        icon: Icons.privacy_tip_outlined,
        title: ru ? 'Приватность' : 'Privacy',
        subtitle: ru
            ? 'Номер телефона, активность, звонки, группы и отчёты о прочтении.'
            : 'Phone number, activity, calls, groups and read receipts.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16PrivacyScreen(ru: ru),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.devices_rounded,
        title: ru ? 'Два устройства' : 'Two devices',
        subtitle: ru
            ? 'Один аккаунт — телефон и компьютер.'
            : 'One account on phone and computer.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16TwoDevicesScreen(
                  ru: ru,
                  profile: profile,
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.phonelink_lock_rounded,
        title: ru ? 'Активные сессии' : 'Active sessions',
        subtitle: ru
            ? 'Устройства, где сейчас открыт ваш аккаунт.'
            : 'Devices where your account is currently open.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16SessionsScreen(
                  ru: ru,
                  profile: profile,
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.contacts_outlined,
        title: ru ? 'Системные контакты' : 'System contacts',
        subtitle: ru
            ? 'Телефонная книга и приглашения в Чернограм.'
            : 'Phone book and Chernogram invites.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgV16SystemContactsScreen(ru: ru),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      _ProfileAction(
        icon: Icons.auto_awesome_rounded,
        title: ru ? 'Агент и автоматизация' : 'Agent and automation',
        subtitle: ru
            ? 'Помощник, голосовые команды и локальные задачи.'
            : 'Assistant, voice commands and local tasks.',
        onTap: () {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CgAgentScreen(
                  ru: ru,
                  profile: profile,
                  tunnels: tunnels,
                  privacyLens: privacyLens,
                  onCreateTunnel: () {},
                  onTogglePrivacy: () {},
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
"""
        text = replace_once(text, anchor, cards + anchor, "v16 profile cards")

    PATH.write_text(text, encoding="utf-8")
    print("Chernogram 0.16 feature set restored")


if __name__ == "__main__":
    main()
