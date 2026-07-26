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

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _preview() {
    final value = _query.text.trim();
    if (value.isEmpty) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.ru
              ? 'Запрос сохранён. Интернет-поиск и модель агента будут подключены отдельным обновлением.'
              : 'Query saved. Web search and the agent model will arrive in a separate update.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                          color: scheme.primary.withValues(alpha: .28),
                          blurRadius: 22,
                        ),
                      ],
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
                      children: [
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
                              ? 'Поиск, браузер и помощник публикаций'
                              : 'Search, browser and publishing assistant',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: .56),
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
                onSubmitted: (_) => _preview(),
                decoration: InputDecoration(
                  hintText: widget.ru
                      ? 'Спросить или найти в интернете'
                      : 'Ask or search the web',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    onPressed: _preview,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.ru ? 'Возможности агента' : 'Agent capabilities',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        _AgentCard(
          icon: Icons.travel_explore_rounded,
          title: widget.ru ? 'Поиск в интернете' : 'Web search',
          subtitle: widget.ru
              ? 'Ищет информацию, сравнивает источники и открывает страницы внутри приложения.'
              : 'Finds information, compares sources and opens pages in the app.',
          label: widget.ru ? 'ГОТОВИТСЯ' : 'COMING',
        ),
        _AgentCard(
          icon: Icons.campaign_outlined,
          title: widget.ru ? 'Помощник публикаций' : 'Publishing assistant',
          subtitle: widget.ru
              ? 'Готовит тексты, изображения, планы публикаций и варианты оформления.'
              : 'Prepares copy, images, publishing plans and layout options.',
          label: widget.ru ? 'ГОТОВИТСЯ' : 'COMING',
        ),
        _AgentCard(
          icon: Icons.edit_note_rounded,
          title: widget.ru ? 'Черновики' : 'Drafts',
          subtitle: widget.ru
              ? 'Сохраняет идеи и продолжает работу с ними позже.'
              : 'Saves ideas and continues working on them later.',
          label: widget.ru ? 'ГОТОВИТСЯ' : 'COMING',
        ),
        const SizedBox(height: 8),
        GlassPanel(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.ru
                      ? 'Основные функции Чернограма — чаты, файлы и звонки — работают независимо от Агента.'
                      : 'Chernogram chats, files and calls work independently from the Agent.',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .58),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.shield_outlined,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String label;

  const _AgentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            leading: Icon(
              icon,
              size: 29,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(subtitle),
            trailing: Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .42),
              ),
            ),
          ),
        ),
      );
}
