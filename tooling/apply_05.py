from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f'Pattern not found: {label}')
    return text.replace(old, new, 1)


def patch_tunnels() -> None:
    path = Path('lib/tunnels.dart')
    text = path.read_text(encoding='utf-8')
    if '// CHERNOGRAM_05_EXTRAS' in text:
        return

    text = replace_once(
        text,
        "import 'brand.dart';\n",
        "import 'brand.dart';\nimport 'tunnel_extras.dart'; // CHERNOGRAM_05_EXTRAS\n",
        'extras import',
    )

    text = replace_once(
        text,
        "  final _nickname = TextEditingController();\n  String? _error;\n",
        "  final _nickname = TextEditingController();\n  String? _error;\n  int _avatarRevision = 0;\n",
        'profile avatar state',
    )

    text = replace_once(
        text,
        "  Future<void> _save() async {\n",
        "  Future<void> _chooseAvatar() async {\n"
        "    final profile = widget.profile;\n"
        "    if (profile == null) {\n"
        "      ScaffoldMessenger.of(context).showSnackBar(\n"
        "        SnackBar(\n"
        "          content: Text(\n"
        "            widget.ru\n"
        "                ? 'Сначала сохраните никнейм.'\n"
        "                : 'Save your nickname first.',\n"
        "          ),\n"
        "        ),\n"
        "      );\n"
        "      return;\n"
        "    }\n"
        "    final changed = await chooseAndSaveLocalAvatar(\n"
        "      context,\n"
        "      profileId: profile.id,\n"
        "      ru: widget.ru,\n"
        "    );\n"
        "    if (changed && mounted) {\n"
        "      setState(() => _avatarRevision++);\n"
        "    }\n"
        "  }\n\n"
        "  Future<void> _save() async {\n",
        'avatar method',
    )

    text = replace_once(
        text,
        "              const ChernogramLogo(size: 104, withPlate: true),\n",
        "              Stack(\n"
        "                alignment: Alignment.bottomRight,\n"
        "                children: [\n"
        "                  LocalProfileAvatar(\n"
        "                    key: ValueKey(_avatarRevision),\n"
        "                    profileId: widget.profile?.id,\n"
        "                    nickname: widget.profile?.nickname ?? '',\n"
        "                    size: 104,\n"
        "                    showBrandWhenEmpty: true,\n"
        "                  ),\n"
        "                  Container(\n"
        "                    decoration: const BoxDecoration(\n"
        "                      color: ChernogramColors.orange,\n"
        "                      shape: BoxShape.circle,\n"
        "                    ),\n"
        "                    child: IconButton(\n"
        "                      tooltip: ru ? 'Выбрать аватарку' : 'Choose avatar',\n"
        "                      onPressed: _chooseAvatar,\n"
        "                      icon: const Icon(Icons.photo_camera_outlined),\n"
        "                    ),\n"
        "                  ),\n"
        "                ],\n"
        "              ),\n",
        'profile logo replacement',
    )

    text = text.replace("'CHERNOGRAM 0.4.0'", "'CHERNOGRAM 0.5.0'")

    old_leading = """                  leading: CircleAvatar(
                    backgroundColor: tunnel.isPublic
                        ? ChernogramColors.orange
                        : ChernogramColors.gold,
                    child: Icon(tunnel.isPublic ? Icons.public : Icons.lock),
                  ),
"""
    new_leading = """                  leading: LocalProfileAvatar(
                    profileId: widget.profile?.id,
                    nickname: widget.profile?.nickname ?? tunnel.name,
                    size: 46,
                    showBrandWhenEmpty: true,
                  ),
"""
    text = replace_once(text, old_leading, new_leading, 'tunnel list avatar')

    text = replace_once(
        text,
        "  final _controller = TextEditingController();\n  late TunnelInfo _tunnel;\n",
        "  final _controller = TextEditingController();\n"
        "  late TunnelInfo _tunnel;\n"
        "  TunnelPermissions _permissions = const TunnelPermissions();\n",
        'chat permissions state',
    )

    text = replace_once(
        text,
        "    _tunnel = widget.tunnel;\n  }\n",
        "    _tunnel = widget.tunnel;\n"
        "    _loadPermissions();\n"
        "  }\n",
        'load permissions init',
    )

    text = replace_once(
        text,
        "  @override\n  void dispose() {\n    _controller.dispose();\n    super.dispose();\n  }\n\n",
        "  @override\n"
        "  void dispose() {\n"
        "    _controller.dispose();\n"
        "    super.dispose();\n"
        "  }\n\n"
        "  Future<void> _loadPermissions() async {\n"
        "    final value = await LocalTunnelExtrasStore.loadPermissions(_tunnel.id);\n"
        "    if (mounted) setState(() => _permissions = value);\n"
        "  }\n\n"
        "  Future<void> _showQr() async {\n"
        "    await showTunnelQrDialog(\n"
        "      context,\n"
        "      link: _tunnel.link,\n"
        "      tunnelName: _tunnel.name,\n"
        "      ru: widget.ru,\n"
        "    );\n"
        "  }\n\n"
        "  Future<void> _editPermissions() async {\n"
        "    final value = await showTunnelPermissionsDialog(\n"
        "      context,\n"
        "      initial: _permissions,\n"
        "      ru: widget.ru,\n"
        "    );\n"
        "    if (value == null) return;\n"
        "    await LocalTunnelExtrasStore.savePermissions(_tunnel.id, value);\n"
        "    if (mounted) setState(() => _permissions = value);\n"
        "  }\n\n",
        'chat extras methods',
    )

    text = replace_once(
        text,
        "        appBar: AppBar(\n          title: Column(\n",
        "        appBar: AppBar(\n"
        "          leadingWidth: 58,\n"
        "          leading: Padding(\n"
        "            padding: const EdgeInsets.all(8),\n"
        "            child: LocalProfileAvatar(\n"
        "              profileId: widget.profile.id,\n"
        "              nickname: widget.profile.nickname,\n"
        "              size: 40,\n"
        "            ),\n"
        "          ),\n"
        "          title: Column(\n",
        'chat appbar avatar',
    )

    old_actions = """          actions: [
            IconButton(onPressed: _copyLink, icon: const Icon(Icons.link)),
            IconButton(
              onPressed: () => Share.share(_inviteText),
              icon: const Icon(Icons.share),
            ),
          ],
"""
    new_actions = """          actions: [
            IconButton(
              tooltip: ru ? 'QR-код' : 'QR code',
              onPressed: _showQr,
              icon: const Icon(Icons.qr_code_2),
            ),
            IconButton(
              tooltip: ru ? 'Права доступа' : 'Permissions',
              onPressed: _editPermissions,
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
            IconButton(onPressed: _copyLink, icon: const Icon(Icons.link)),
            IconButton(
              onPressed: () => Share.share(_inviteText),
              icon: const Icon(Icons.share),
            ),
          ],
"""
    text = replace_once(text, old_actions, new_actions, 'chat appbar actions')

    old_meta = """                          Text(
                            '${message.author} • ${_time(message.sentAt)}',
                            style: const TextStyle(fontSize: 9, color: Colors.white38),
                          ),
"""
    new_meta = """                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LocalProfileAvatar(
                                profileId: mine ? widget.profile.id : null,
                                nickname: message.author,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${message.author} • ${_time(message.sentAt)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                            ],
                          ),
"""
    text = replace_once(text, old_meta, new_meta, 'message avatar')

    path.write_text(text, encoding='utf-8')


def patch_updater() -> None:
    path = Path('lib/update_service.dart')
    text = path.read_text(encoding='utf-8')
    if '// CHERNOGRAM_05_INSTALL_FLOW' in text:
        return

    old_installing = """          if (eventName == 'INSTALLING') {
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
"""
    new_installing = """          if (eventName == 'INSTALLING') {
            // CHERNOGRAM_05_INSTALL_FLOW
            closeDialog();
            messenger.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 10),
                content: Text(
                  ru
                      ? 'APK скачан. Подтвердите установку в системном окне Android. Если появится запрос — разрешите установку из Чернограма и вернитесь назад.'
                      : 'APK downloaded. Confirm installation in Android. If asked, allow installs from Chernogram and return.',
                ),
              ),
            );
            return;
          }
"""
    text = replace_once(text, old_installing, new_installing, 'installer dialog flow')

    text = replace_once(
        text,
        "      await completed.future;\n",
        "      await completed.future.timeout(\n"
        "        const Duration(minutes: 4),\n"
        "        onTimeout: () {\n"
        "          closeDialog();\n"
        "          messenger.showSnackBar(\n"
        "            SnackBar(\n"
        "              content: Text(\n"
        "                ru\n"
        "                    ? 'Установка передана Android. Проверьте системное окно или повторите обновление.'\n"
        "                    : 'Installation was handed to Android. Check the system window or retry.',\n"
        "              ),\n"
        "            ),\n"
        "          );\n"
        "        },\n"
        "      );\n",
        'installer timeout',
    )

    path.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    patch_tunnels()
    patch_updater()
    print('Chernogram 0.5 patches applied')
