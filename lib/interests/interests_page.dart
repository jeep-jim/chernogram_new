import 'dart:async';

import 'package:flutter/material.dart';

import '../brand.dart';
import '../optical/optical_models.dart';
import 'interests_models.dart';
import 'interests_store.dart';

class ChernogramInterestsPage extends StatefulWidget {
  final OpticalProfile profile;
  final List<OpticalRoom> rooms;
  final Future<OpticalRoom> Function(String name) onCreateRoom;
  final Future<void> Function(OpticalRoom room) onOpenRoom;

  const ChernogramInterestsPage({
    super.key,
    required this.profile,
    required this.rooms,
    required this.onCreateRoom,
    required this.onOpenRoom,
  });

  @override
  State<ChernogramInterestsPage> createState() =>
      _ChernogramInterestsPageState();
}

class _ChernogramInterestsPageState extends State<ChernogramInterestsPage> {
  final TextEditingController _search = TextEditingController();
  List<InterestTopic> _localTopics = <InterestTopic>[];
  String _planet = InterestPlanets.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final topics = await InterestsStore.load();
    if (!mounted) return;
    setState(() {
      _localTopics = topics;
      _loading = false;
    });
  }

  List<InterestTopic> get _topics {
    final byId = <String, InterestTopic>{};
    for (final topic in topicsFromRooms(widget.rooms)) {
      byId[topic.id] = topic;
    }
    for (final topic in _localTopics) {
      byId[topic.id] = topic;
    }
    return byId.values.toList();
  }

  Future<void> _createTopic() async {
    final text = TextEditingController(text: _search.text.trim());
    var kind = InterestKinds.ask;
    final result = await showDialog<({String text, String kind})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая тема'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: text,
                  autofocus: true,
                  maxLength: 180,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Что вы хотите найти или обсудить?',
                    hintText: 'Например: где купить хороший мёд',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Тип темы'),
                  items: InterestKinds.all
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(_kindLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final clean = text.text.trim();
                if (clean.isEmpty) return;
                Navigator.pop(context, (text: clean, kind: kind));
              },
              child: const Text('Создать комнату'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    if (result == null) return;
    final room = await widget.onCreateRoom(result.text);
    final now = DateTime.now();
    final topic = InterestTopic(
      id: interestRandomId(),
      text: result.text,
      kind: result.kind,
      planet: inferInterestPlanet(result.text),
      authorId: widget.profile.id,
      authorName: widget.profile.nickname,
      roomId: room.id,
      followers: 1,
      replies: 0,
      createdAt: now,
      updatedAt: now,
    );
    final topics = await InterestsStore.upsert(
      topic: topic,
      current: _localTopics,
    );
    if (!mounted) return;
    setState(() {
      _localTopics = topics;
      _search.text = result.text;
    });
    await widget.onOpenRoom(room);
  }

  Future<void> _openTopic(InterestTopic topic) async {
    final roomId = topic.roomId;
    if (roomId != null) {
      final room = widget.rooms
          .where((value) => value.id == roomId)
          .firstOrNull;
      if (room != null) {
        await widget.onOpenRoom(room);
        return;
      }
    }
    final room = await widget.onCreateRoom(topic.text);
    final updated = topic.copyWith(roomId: room.id, updatedAt: DateTime.now());
    final topics = await InterestsStore.upsert(
      topic: updated,
      current: _localTopics,
    );
    if (mounted) setState(() => _localTopics = topics);
    await widget.onOpenRoom(room);
  }

  @override
  Widget build(BuildContext context) {
    final matches = searchInterests(
      query: _search.text,
      topics: _topics,
      planet: _planet,
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Интересы',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Создать тему',
            onPressed: _createTopic,
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF41337D), Color(0xFF173B57)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const ChernogramLogo(size: 66),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'НАПИШИ МЫСЛЬ — НАЙДЁМ БЛИЗКИХ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .6,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Чернограм притянет похожие темы и комнаты, а не только точное совпадение.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .76),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Например: где купить мёд',
                prefixIcon: const Icon(Icons.auto_awesome_rounded),
                suffixIcon: _search.text.isEmpty
                    ? IconButton(
                        tooltip: 'Создать тему',
                        onPressed: _createTopic,
                        icon: const Icon(Icons.add_rounded),
                      )
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onSubmitted: (_) {
                if (matches.isEmpty) _createTopic();
              },
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              children: _planetOptions
                  .map(
                    (option) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilterChip(
                        selected: _planet == option.$1,
                        avatar: Text(option.$2),
                        label: Text(option.$3),
                        onSelected: (_) => setState(() => _planet = option.$1),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text(
                  _search.text.trim().isEmpty
                      ? 'Близкие обсуждения'
                      : 'Найдено похожих: ${matches.length}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '${_topics.length} тем',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : matches.isEmpty
                ? _NoInterestMatches(
                    query: _search.text,
                    onCreate: _createTopic,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final match = matches[index];
                      return _InterestTile(
                        topic: match.topic,
                        score: match.score,
                        onOpen: () => _openTopic(match.topic),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _InterestTile extends StatelessWidget {
  final InterestTopic topic;
  final double score;
  final VoidCallback onOpen;

  const _InterestTile({
    required this.topic,
    required this.score,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _planetColors(topic.planet)),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    _planetEmoji(topic.planet),
                    style: const TextStyle(fontSize: 23),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _kindLabel(topic.kind),
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (score > 1)
                          Text(
                            '${score.round()} совпадений',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      topic.text,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${topic.replies} сообщений',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.visibility_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${topic.followers}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoInterestMatches extends StatelessWidget {
  final String query;
  final Future<void> Function() onCreate;

  const _NoInterestMatches({required this.query, required this.onCreate});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.travel_explore_rounded, size: 70),
          const SizedBox(height: 14),
          Text(
            query.trim().isEmpty ? 'Тем пока нет' : 'Похожая тема не найдена',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            query.trim().isEmpty
                ? 'Создай первую тему — она сразу станет комнатой для обсуждения.'
                : 'Создай комнату с этой формулировкой. Следующие близкие запросы будут притягиваться к ней.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_comment_rounded),
            label: const Text('Создать тему'),
          ),
        ],
      ),
    ),
  );
}

const List<(String, String, String)> _planetOptions =
    <(String, String, String)>[
      (InterestPlanets.all, '🌌', 'Все'),
      (InterestPlanets.tech, '💻', 'Технологии'),
      (InterestPlanets.money, '₿', 'Деньги'),
      (InterestPlanets.world, '🌍', 'Мир'),
      (InterestPlanets.business, '🚀', 'Бизнес'),
      (InterestPlanets.creative, '🎨', 'Творчество'),
      (InterestPlanets.people, '🤝', 'Люди'),
      (InterestPlanets.auto, '🚗', 'Авто'),
      (InterestPlanets.home, '🏠', 'Дом'),
    ];

String _kindLabel(String kind) => switch (kind) {
  InterestKinds.ask => 'Вопрос',
  InterestKinds.talk => 'Обсуждение',
  InterestKinds.want => 'Ищу',
  InterestKinds.offer => 'Предлагаю',
  InterestKinds.buy => 'Куплю',
  InterestKinds.sell => 'Продам',
  InterestKinds.help => 'Помогу',
  _ => 'Тема',
};

String _planetEmoji(String planet) => switch (planet) {
  InterestPlanets.tech => '💻',
  InterestPlanets.money => '₿',
  InterestPlanets.world => '🌍',
  InterestPlanets.business => '🚀',
  InterestPlanets.creative => '🎨',
  InterestPlanets.people => '🤝',
  InterestPlanets.auto => '🚗',
  InterestPlanets.home => '🏠',
  _ => '🌌',
};

List<Color> _planetColors(String planet) => switch (planet) {
  InterestPlanets.tech => const <Color>[Color(0xFF3294E8), Color(0xFF3855C7)],
  InterestPlanets.money => const <Color>[Color(0xFF36AF80), Color(0xFFD0A43D)],
  InterestPlanets.world => const <Color>[Color(0xFF22AAB3), Color(0xFF3AA66F)],
  InterestPlanets.business => const <Color>[
    Color(0xFF7654D6),
    Color(0xFFD04FB2),
  ],
  InterestPlanets.creative => const <Color>[
    Color(0xFFD858A9),
    Color(0xFFE58B3C),
  ],
  InterestPlanets.people => const <Color>[Color(0xFFE18346), Color(0xFFC94F68)],
  InterestPlanets.auto => const <Color>[Color(0xFF4169B8), Color(0xFF293B63)],
  InterestPlanets.home => const <Color>[Color(0xFF6E9C55), Color(0xFF3F715D)],
  _ => const <Color>[Color(0xFF6253CF), Color(0xFF2B7B9E)],
};

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
