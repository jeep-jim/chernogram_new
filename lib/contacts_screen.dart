import 'package:flutter/material.dart';

import 'brand.dart';
import 'chat_state.dart';
import 'core_models.dart';

class CgContactsScreen extends StatefulWidget {
  final bool ru;
  final List<CgContact> contacts;
  final List<CgTunnel> tunnels;
  final bool privacyLens;
  final Future<void> Function(CgTunnel tunnel) onOpenTunnel;

  const CgContactsScreen({
    super.key,
    required this.ru,
    required this.contacts,
    required this.tunnels,
    required this.privacyLens,
    required this.onOpenTunnel,
  });

  @override
  State<CgContactsScreen> createState() => _CgContactsScreenState();
}

class _CgContactsScreenState extends State<CgContactsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final contacts = widget.contacts
        .where((item) => query.isEmpty || item.nickname.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: widget.ru ? 'Поиск контактов' : 'Search contacts',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.ru ? 'Контакты' : 'Contacts',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${contacts.length}',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: .44)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 70),
            child: Column(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 70,
                  color: scheme.onSurface.withValues(alpha: .18),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.ru ? 'Контактов пока нет' : 'No contacts yet',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.ru
                      ? 'Люди, с которыми вы переписывались или созванивались, появятся здесь автоматически.'
                      : 'People you message or call will appear here automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: .52)),
                ),
              ],
            ),
          )
        else
          ...contacts.map((contact) {
            final available = contact.tunnelIds
                .map((id) => widget.tunnels.where((item) => item.id == id).firstOrNull)
                .whereType<CgTunnel>()
                .toList();
            final tunnel = available.isEmpty ? null : available.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: GlassPanel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: tunnel == null ? null : () => widget.onOpenTunnel(tunnel),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  leading: _ContactAvatar(
                    nickname: widget.privacyLens ? '?' : contact.nickname,
                  ),
                  title: Text(
                    widget.privacyLens ? '••••••••' : '@${contact.nickname}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    widget.ru
                        ? '${_formatLastSeen(contact.lastSeenAt)} • чатов ${contact.tunnelIds.length}'
                        : '${_formatLastSeen(contact.lastSeenAt)} • ${contact.tunnelIds.length} chats',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: .48),
                    ),
                  ),
                  trailing: tunnel == null
                      ? const Icon(Icons.person_outline_rounded)
                      : const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                ),
              ),
            );
          }),
      ],
    );
  }

  String _formatLastSeen(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    if (now.difference(local).inDays == 0 && now.day == local.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
  }
}

class _ContactAvatar extends StatelessWidget {
  final String nickname;

  const _ContactAvatar({required this.nickname});

  @override
  Widget build(BuildContext context) {
    final letter = nickname.trim().isEmpty ? '?' : nickname.trim()[0].toUpperCase();
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C5CFF), Color(0xFF18B8FF)],
        ),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
