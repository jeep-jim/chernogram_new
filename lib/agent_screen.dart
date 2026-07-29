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
  final TextEditingController _query = TextEditingController();
  final List<String> _history = <String>[];

  void _submit() {
    final value = _query.text.trim();
    if (value.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _history.insert(0, value);
      _query.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'Задача сохранена локально. Агент не получает доступ к чатам без отдельного разрешения.'
              : 'The task was saved locally. The agent cannot access chats without explicit permission.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ru ? 'Агент и автоматизация' : 'Agent and automation'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
        children: <Widget>[
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: <Color>[scheme.primary, scheme.secondary],
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.ru ? 'Агент' : 'Agent',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.ru
                                ? 'Помощник, голосовые команды и автоматизация'
                                : 'Assistant, voice commands and automation',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: .58),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _query,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: widget.ru
                        ? 'Спросить или создать задачу'
                        : 'Ask or create a task',
                    prefixIcon: const Icon(Icons.auto_awesome_outlined),
                    suffixIcon: IconButton(
                      onPressed: _submit,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.ru ? 'Возможности' : 'Capabilities',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 9),
          _AgentCard(
            icon: Icons.record_voice_over_outlined,
            title: widget.ru ? 'Голосовые команды' : 'Voice commands',
            subtitle: widget.ru
                ? 'Управление звонками, сообщениями и задачами с подтверждением пользователя.'
                : 'Control calls, messages and tasks with user confirmation.',
          ),
          _AgentCard(
            icon: Icons.travel_explore_rounded,
            title: widget.ru ? 'Поиск в интернете' : 'Web search',
            subtitle: widget.ru
                ? 'Поиск и сравнение источников без доступа к личным чатам.'
                : 'Search and compare sources without access to private chats.',
          ),
          _AgentCard(
            icon: Icons.edit_note_rounded,
            title: widget.ru ? 'Черновики и автоматизация' : 'Drafts and automation',
            subtitle: widget.ru
                ? 'Локальные идеи, напоминания и повторяемые действия.'
                : 'Local ideas, reminders and repeatable actions.',
          ),
          if (_history.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              widget.ru ? 'Локальные задачи' : 'Local tasks',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final task in _history)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.task_alt_rounded),
                  title: Text(task),
                  trailing: IconButton(
                    onPressed: () => setState(() => _history.remove(task)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          GlassPanel(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.ru
                        ? 'Агент работает отдельно от чатов. Доступ к микрофону, контактам и сообщениям задаётся пользователем в разрешениях.'
                        : 'The agent is isolated from chats. Microphone, contacts and message access are controlled by the user.',
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: .60),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.shield_outlined, color: scheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }
}

class _AgentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AgentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        leading: Icon(
          icon,
          size: 29,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
      ),
    ),
  );
}
