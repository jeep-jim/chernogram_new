import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'contact_policy.dart';
import 'core_models.dart';

class CgContactProfileScreen extends StatefulWidget {
  final bool ru;
  final CgContact contact;
  final bool online;
  final Future<void> Function(CgContact contact) onOpenChat;

  const CgContactProfileScreen({
    super.key,
    required this.ru,
    required this.contact,
    required this.online,
    required this.onOpenChat,
  });

  @override
  State<CgContactProfileScreen> createState() =>
      _CgContactProfileScreenState();
}

class _CgContactProfileScreenState extends State<CgContactProfileScreen> {
  CgContactPolicy _policy = const CgContactPolicy();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final policy = await CgContactPolicyStore.load(widget.contact.id);
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _loading = false;
    });
  }

  Future<void> _setPolicy(CgContactPolicy policy) async {
    setState(() {
      _policy = policy;
      _saving = true;
    });
    await CgContactPolicyStore.save(widget.contact.id, policy);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: widget.contact.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.ru ? 'ID скопирован' : 'ID copied'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _lastSeen() {
    if (widget.online) return widget.ru ? 'в сети' : 'online';
    final difference = DateTime.now().difference(widget.contact.lastSeenAt);
    if (difference.inMinutes < 1) return widget.ru ? 'только что' : 'just now';
    if (difference.inHours < 1) {
      return widget.ru
          ? '${difference.inMinutes} мин назад'
          : '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return widget.ru
          ? '${difference.inHours} ч назад'
          : '${difference.inHours} h ago';
    }
    final value = widget.contact.lastSeenAt;
    return '${value.day.toString().padLeft(2, '0')}.'
        '${value.month.toString().padLeft(2, '0')}.'
        '${value.year}';
  }

  Widget _avatar(BuildContext context) {
    final raw = widget.contact.avatarBase64;
    if (raw != null && raw.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 48,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {}
    }
    final nickname = widget.contact.nickname.trim();
    return CircleAvatar(
      radius: 48,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        nickname.isEmpty ? '?' : nickname.characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Профиль контакта' : 'Contact profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _avatar(context),
                      if (widget.online)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C7F2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.surface,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '@${widget.contact.nickname}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Center(
                  child: Text(
                    _lastSeen(),
                    style: TextStyle(
                      color: widget.online
                          ? const Color(0xFF22C7F2)
                          : scheme.onSurface.withValues(alpha: .55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _policy.blocked
                      ? null
                      : () async {
                          await widget.onOpenChat(widget.contact);
                          if (mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.chat_bubble_rounded),
                  label: Text(widget.ru ? 'Открыть личный чат' : 'Open private chat'),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Cernogram ID'),
                        subtitle: SelectableText(widget.contact.id),
                        trailing: IconButton(
                          tooltip: widget.ru ? 'Копировать' : 'Copy',
                          onPressed: _copyId,
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(
                          widget.ru ? 'Общие чаты' : 'Shared chats',
                        ),
                        trailing: Text(
                          '${widget.contact.tunnelIds.length}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.ru ? 'Разрешения контакта' : 'Contact permissions',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      _PolicySwitch(
                        icon: Icons.message_outlined,
                        title: widget.ru ? 'Сообщения' : 'Messages',
                        value: _policy.allowMessages && !_policy.blocked,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(allowMessages: value),
                        ),
                      ),
                      _PolicySwitch(
                        icon: Icons.call_outlined,
                        title: widget.ru ? 'Аудиозвонки' : 'Audio calls',
                        value: _policy.allowCalls && !_policy.blocked,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(allowCalls: value),
                        ),
                      ),
                      _PolicySwitch(
                        icon: Icons.videocam_outlined,
                        title: widget.ru ? 'Видеозвонки' : 'Video calls',
                        value: _policy.allowVideoCalls && !_policy.blocked,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(allowVideoCalls: value),
                        ),
                      ),
                      _PolicySwitch(
                        icon: Icons.attach_file_rounded,
                        title: widget.ru ? 'Получение файлов' : 'Receive files',
                        value: _policy.allowFiles && !_policy.blocked,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(allowFiles: value),
                        ),
                      ),
                      _PolicySwitch(
                        icon: Icons.download_outlined,
                        title: widget.ru ? 'Скачивание файлов' : 'Download files',
                        value: _policy.allowDownloads && !_policy.blocked,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(allowDownloads: value),
                        ),
                      ),
                      _PolicySwitch(
                        icon: Icons.forward_rounded,
                        title: widget.ru ? 'Пересылка контента' : 'Forward content',
                        value: _policy.allowForwarding && !_policy.blocked,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(allowForwarding: value),
                        ),
                      ),
                      _PolicySwitch(
                        icon: Icons.notifications_off_outlined,
                        title: widget.ru ? 'Без уведомлений' : 'Mute notifications',
                        value: _policy.muted,
                        enabled: !_policy.blocked,
                        onChanged: (value) => _setPolicy(
                          _policy.copyWith(muted: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: _policy.blocked
                      ? scheme.errorContainer
                      : scheme.surfaceContainerLow,
                  child: SwitchListTile(
                    value: _policy.blocked,
                    onChanged: (value) => _setPolicy(
                      _policy.copyWith(blocked: value),
                    ),
                    secondary: Icon(
                      Icons.block_rounded,
                      color: _policy.blocked ? scheme.error : null,
                    ),
                    title: Text(
                      widget.ru ? 'Заблокировать контакт' : 'Block contact',
                      style: TextStyle(
                        color: _policy.blocked ? scheme.error : null,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      widget.ru
                          ? 'Сообщения, звонки и файлы от контакта будут скрываться.'
                          : 'Messages, calls and files from this contact will be hidden.',
                    ),
                  ),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 14),
                Text(
                  widget.ru
                      ? 'Настройки хранятся только на вашем устройстве. Для полной синхронизации между устройствами они позже будут передаваться через зашифрованный Realtime Core.'
                      : 'These settings are stored only on this device. Encrypted cross-device sync will be added through Realtime Core.',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: .48),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PolicySwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _PolicySwitch({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      secondary: Icon(icon),
      title: Text(title),
    );
  }
}
