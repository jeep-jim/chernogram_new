from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


path = Path("lib/light/light_chat_app.dart")
text = path.read_text(encoding="utf-8")

# Build number follows the reliability build 75 patches.
pubspec = Path("pubspec.yaml")
pub_text = pubspec.read_text(encoding="utf-8")
if "version: 0.52.0+75" not in pub_text:
    raise SystemExit("Expected build 75 version before applying UI build 76")
pubspec.write_text(
    pub_text.replace("version: 0.52.0+75", "version: 0.52.1+76", 1),
    encoding="utf-8",
)

# QR renderer is already a project dependency; import it only in the active UI.
old_import = "import 'package:package_info_plus/package_info_plus.dart';\n"
new_import = old_import + "import 'package:qr_flutter/qr_flutter.dart';\n"
if old_import not in text:
    raise SystemExit("package_info_plus import not found")
text = text.replace(old_import, new_import, 1)

# Remove the large instructional card from the main Contacts screen.
anchor = "'Добавить человека'"
pos = text.find(anchor)
if pos < 0:
    raise SystemExit("Main QR/invite card not found")
start = text.rfind("          SliverPadding(\n", 0, pos)
end = text.find("          const SliverPadding(\n", pos)
if start < 0 or end < 0:
    raise SystemExit("Unable to locate full main QR/invite card")
text = text[:start] + text[end:]

# Make the main page copy shorter and more useful after removing the card.
text = text.replace(
    "subtitle: 'Только реальные контакты Чернограма',",
    "subtitle: 'Люди и последние диалоги',",
    1,
)

profile_start = text.find("class _ProfilePage extends StatelessWidget {")
profile_end = text.find("class _PhoneContactsSheet", profile_start)
if profile_start < 0 or profile_end < 0:
    raise SystemExit("Profile page boundaries not found")
profile = text[profile_start:profile_end]

profile = profile.replace(
    "subtitle: 'Только основные настройки',",
    "subtitle: 'Профиль, установка и настройки',",
    1,
)

settings_marker = """          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LightGlass(
              padding: EdgeInsets.zero,
"""
if settings_marker not in profile:
    raise SystemExit("Profile settings card marker not found")

install_card = """          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: LightGlass(
              padding: const EdgeInsets.all(18),
              borderRadius: BorderRadius.circular(28),
              child: Column(
                children: [
                  Container(
                    width: 172,
                    height: 172,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(
                      data: _androidInstallUrl,
                      version: QrVersions.auto,
                      size: 152,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      semanticsLabel: 'QR-код для установки Чернограма',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Установить Чернограм',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Покажи этот QR на другом телефоне или отправь ссылку.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.35,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .58),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onShareInstall,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Отправить ссылку на установку'),
                    ),
                  ),
                ],
              ),
            ),
          ),
"""
profile = profile.replace(settings_marker, install_card + settings_marker, 1)

# Remove the old duplicate installation ListTile: the new profile card owns QR + share.
install_tile_start = profile.find(
    "                  ListTile(\n",
    profile.find("leading: const Icon(Icons.install_mobile_rounded)"),
)
# find() above starts after the ListTile start, so locate backwards instead.
install_icon = profile.find("leading: const Icon(Icons.install_mobile_rounded)")
if install_icon < 0:
    raise SystemExit("Old install ListTile not found")
install_tile_start = profile.rfind("                  ListTile(\n", 0, install_icon)
next_tile = profile.find("                  ListTile(\n", install_icon)
if install_tile_start < 0 or next_tile < 0:
    raise SystemExit("Unable to remove old install ListTile")
profile = profile[:install_tile_start] + profile[next_tile:]

text = text[:profile_start] + profile + text[profile_end:]
path.write_text(text, encoding="utf-8")

print("UI build 76 patches applied")
