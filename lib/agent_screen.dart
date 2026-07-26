import 'package:flutter/material.dart';

import 'brand.dart';
import 'core_models.dart';

class CgAgentScreen extends StatefulWidget {
  final bool ru;
  final CgProfile profile;
  final List<CgTunnel> tunnels;
  final bool privacyLens;
  final VoidCallback onCreateTunnel;
  final VoidCallback onTogglePrivacy;

  const CgAgentScreen({
    super.key,
    required this.ru,
    required this.profile,
    required this.tunnels,
    required this.privacyLens,
    required this.onCreateTunnel,
    required this.onTogglePrivacy,
  });

  @override
  State<CgAgentScreen> createState() => _CgAgentScreenState();
}

class _CgAgentScreenState extends State<CgAgentScreen> {
  final TextEditingController _command = TextEditingController();
  final List<({bool mine, String text})> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages.add((
      mine: false,
      text: widget.ru
          ? 'Я локальный агент Чернограма. Уже умею создавать туннель, включать режим приватности и показывать состояние приложения.'
          : 'I am the local Chernogram agent. I can create a tunnel, toggle Privacy Lens and report app status.',
    ));
  }

  void _send() {
    final value = _command.text.trim();
    if (value.isEmpty) return;
    _command.clear();
    setState(() => _messages.add((mine: true, text: value)));
    final normalized = value.toLowerCase();
    String reply;
    if (normalized.contains('созд') && normalized.contains('тунн')) {
      widget.onCreateTunnel();
      reply = widget.ru
          ? 'Открываю создание мгновенного туннеля. Название можно не вводить.'
          : 'Opening an instant tunnel. The name is optional.';
    } else if (normalized.contains('приват') || normalized.contains('скры')) {
      widget.onTogglePrivacy();
      reply = widget.ru
          ? 'Режим «Приватный взгляд» переключён. Названия и сообщения скрываются одним нажатием на очки.'
          : 'Privacy Lens toggled. Tunnel names and messages are hidden with one tap.';
    } else if (normalized.contains('сколько') || normalized.contains('статус')) {
      reply = widget.ru
          ? 'Профиль: @${widget.profile.nickname}. Туннелей: ${widget.tunnels.length}. Приватный взгляд: ${widget.privacyLens ? 'включён' : 'выключен'}.'
          : 'Profile: @${widget.profile.nickname}. Tunnels: ${widget.tunnels.length}. Privacy Lens: ${widget.privacyLens ? 'on' : 'off'}.';
    } else {
      reply = widget.ru
          ? 'Команда сохранена в локальном журнале. В следующем сетевом этапе агент получит модели, разрешения и действия внутри туннелей.'
          : 'Command saved to the local log. The next agent layer will add models, permissions and tunnel actions.';
    }
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _messages.add((mine: false, text: reply)));
    });
  }

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .32),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.ru ? 'Агент Чернограма' : 'Chernogram Agent',
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.ru
                          ? 'Локальный помощник • без передачи переписки модели'
                          : 'Local assistant • chat content is not sent to a model',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: .54),
                      ),
                    ),
                  ],
                ),
              ),
              const Chip(
                avatar: Icon(Icons.circle, size: 9, color: ChernogramColors.success),
                label: Text('ONLINE'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Align(
                      alignment: message.mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 310),
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: message.mine
                              ? scheme.primary.withValues(alpha: .88)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          message.text,
                          style: TextStyle(color: message.mine ? Colors.white : scheme.onSurface),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _command,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: widget.ru
                            ? 'Например: создай туннель'
                            : 'Example: create a tunnel',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.ru ? 'Разделы агента' : 'Agent sections',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 9),
        _AgentSection(
          icon: Icons.psychology_alt_outlined,
          title: widget.ru ? 'JSON-профиль агента' : 'Agent JSON profile',
          subtitle: widget.ru
              ? 'Роль, стиль, правила и доступные инструменты.'
              : 'Role, style, rules and available tools.',
          children: [
            _AgentLine(widget.ru ? 'Имя: Чернограм Агент' : 'Name: Chernogram Agent'),
            _AgentLine(widget.ru ? 'Режим: локальный' : 'Mode: local'),
            _AgentLine(widget.ru ? 'Доступ к переписке: только по разрешению' : 'Chat access: permission only'),
          ],
        ),
        _AgentSection(
          icon: Icons.bolt_outlined,
          title: widget.ru ? 'Команды и автоматизации' : 'Commands and automations',
          subtitle: widget.ru
              ? 'Быстрые действия без перегруженных экранов.'
              : 'Quick actions without cluttered screens.',
          children: [
            ListTile(
              leading: const Icon(Icons.add_link_rounded),
              title: Text(widget.ru ? 'Создать туннель' : 'Create tunnel'),
              onTap: widget.onCreateTunnel,
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(widget.ru ? 'Переключить приватный взгляд' : 'Toggle Privacy Lens'),
              onTap: widget.onTogglePrivacy,
            ),
          ],
        ),
        _AgentSection(
          icon: Icons.security_outlined,
          title: widget.ru ? 'Разрешения' : 'Permissions',
          subtitle: widget.ru
              ? 'Камера, микрофон, файлы, туннели и устройства.'
              : 'Camera, microphone, files, tunnels and devices.',
          children: [
            _PermissionLine(icon: Icons.chat_outlined, label: widget.ru ? 'Сообщения' : 'Messages', enabled: true),
            _PermissionLine(icon: Icons.call_outlined, label: widget.ru ? 'Звонки' : 'Calls', enabled: true),
            _PermissionLine(icon: Icons.folder_outlined, label: widget.ru ? 'Файлы' : 'Files', enabled: true),
            _PermissionLine(icon: Icons.router_outlined, label: widget.ru ? 'Управление устройствами' : 'Device control', enabled: false),
          ],
        ),
        _AgentSection(
          icon: Icons.receipt_long_outlined,
          title: widget.ru ? 'Журнал действий' : 'Action log',
          subtitle: widget.ru
              ? 'Прозрачная история того, что сделал агент.'
              : 'Transparent history of every agent action.',
          children: [
            _AgentLine(widget.ru ? 'Локальный журнал включён' : 'Local action log enabled'),
            _AgentLine(widget.ru ? 'Сетевые действия будут подписываться' : 'Network actions will be signed'),
          ],
        ),
        _AgentSection(
          icon: Icons.search_rounded,
          title: widget.ru ? 'Поиск по файлам и туннелям' : 'Search files and tunnels',
          subtitle: widget.ru
              ? 'Единый поиск по названиям, людям и типам вложений.'
              : 'Unified search by names, people and attachment types.',
          children: [
            _AgentLine(widget.ru ? 'Индекс локальных данных подготовлен' : 'Local data index prepared'),
          ],
        ),
        _AgentSection(
          icon: Icons.storefront_outlined,
          title: widget.ru ? 'Маркет и кошелёк' : 'Market and wallet',
          subtitle: widget.ru
              ? 'Будущий раздел цифровых товаров, подписок, ключей и оплаты криптовалютой.'
              : 'Future marketplace for digital goods, subscriptions, keys and crypto payments.',
          badge: widget.ru ? 'КОНЦЕПТ' : 'CONCEPT',
          children: [
            _AgentLine(widget.ru ? 'Подключение MetaMask / Phantom' : 'MetaMask / Phantom connection'),
            _AgentLine(widget.ru ? 'Баланс без хранения seed-фразы' : 'Balance without storing seed phrases'),
            _AgentLine(widget.ru ? 'Escrow-сделки внутри приватного туннеля' : 'Escrow deals inside a private tunnel'),
          ],
        ),
      ],
    );
  }
}

class _AgentSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? badge;

  const _AgentSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ExpansionTile(
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (badge != null)
                  Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: ChernogramColors.gold,
                    ),
                  ),
              ],
            ),
            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: children,
          ),
        ),
      );
}

class _AgentLine extends StatelessWidget {
  final String text;

  const _AgentLine(this.text);

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: const Icon(Icons.check_circle_outline_rounded, size: 20),
        title: Text(text),
      );
}

class _PermissionLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _PermissionLine({required this.icon, required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(label),
        trailing: Icon(
          enabled ? Icons.check_circle : Icons.schedule,
          color: enabled ? ChernogramColors.success : ChernogramColors.textSoft,
        ),
      );
}
