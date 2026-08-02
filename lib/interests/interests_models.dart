import 'dart:convert';
import 'dart:math';

import '../optical/optical_models.dart';

String interestRandomId() {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(12, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

abstract final class InterestKinds {
  static const String ask = 'ask';
  static const String talk = 'talk';
  static const String want = 'want';
  static const String offer = 'offer';
  static const String buy = 'buy';
  static const String sell = 'sell';
  static const String help = 'help';

  static const List<String> all = <String>[
    ask,
    talk,
    want,
    offer,
    buy,
    sell,
    help,
  ];
}

abstract final class InterestPlanets {
  static const String all = 'all';
  static const String tech = 'tech';
  static const String money = 'money';
  static const String world = 'world';
  static const String business = 'business';
  static const String creative = 'creative';
  static const String people = 'people';
  static const String auto = 'auto';
  static const String home = 'home';

  static const Map<String, List<String>> keywords = <String, List<String>>{
    tech: <String>[
      'ai',
      'нейро',
      'код',
      'flutter',
      'android',
      'windows',
      'бот',
      'сайт',
      'прилож',
      'технолог',
    ],
    money: <String>[
      'деньг',
      'инвест',
      'крипт',
      'цена',
      'курс',
      'оплат',
      'банк',
      'заработ',
    ],
    world: <String>[
      'страна',
      'город',
      'переезд',
      'путеше',
      'европ',
      'азия',
      'россия',
      'китай',
    ],
    business: <String>[
      'бизнес',
      'проект',
      'стартап',
      'продаж',
      'клиент',
      'команд',
      'магазин',
      'услуг',
    ],
    creative: <String>[
      'музык',
      'кино',
      'видео',
      'дизайн',
      'фото',
      'монтаж',
      'творч',
      'картин',
    ],
    people: <String>[
      'обсуд',
      'совет',
      'помог',
      'ищу людей',
      'знаком',
      'общени',
      'мнение',
    ],
    auto: <String>[
      'авто',
      'машин',
      'двигател',
      'коробк',
      'кроссовер',
      'седан',
      'китайск',
      'японск',
    ],
    home: <String>[
      'дом',
      'участок',
      'ремонт',
      'строит',
      'мебел',
      'сад',
      'земл',
      'квартир',
    ],
  };
}

class InterestTopic {
  final String id;
  final String text;
  final String kind;
  final String planet;
  final String authorId;
  final String authorName;
  final String? roomId;
  final int followers;
  final int replies;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InterestTopic({
    required this.id,
    required this.text,
    required this.kind,
    required this.planet,
    required this.authorId,
    required this.authorName,
    required this.followers,
    required this.replies,
    required this.createdAt,
    required this.updatedAt,
    this.roomId,
  });

  InterestTopic copyWith({
    String? roomId,
    int? followers,
    int? replies,
    DateTime? updatedAt,
  }) => InterestTopic(
    id: id,
    text: text,
    kind: kind,
    planet: planet,
    authorId: authorId,
    authorName: authorName,
    roomId: roomId ?? this.roomId,
    followers: followers ?? this.followers,
    replies: replies ?? this.replies,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'text': text,
    'kind': kind,
    'planet': planet,
    'authorId': authorId,
    'authorName': authorName,
    'roomId': roomId,
    'followers': followers,
    'replies': replies,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory InterestTopic.fromJson(Map<String, dynamic> json) => InterestTopic(
    id: json['id']?.toString() ?? interestRandomId(),
    text: json['text']?.toString() ?? '',
    kind: json['kind']?.toString() ?? InterestKinds.talk,
    planet: json['planet']?.toString() ?? InterestPlanets.all,
    authorId: json['authorId']?.toString() ?? '',
    authorName: json['authorName']?.toString() ?? 'Устройство',
    roomId: json['roomId']?.toString(),
    followers: int.tryParse(json['followers']?.toString() ?? '') ?? 1,
    replies: int.tryParse(json['replies']?.toString() ?? '') ?? 0,
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

class InterestMatch {
  final InterestTopic topic;
  final double score;

  const InterestMatch({required this.topic, required this.score});
}

List<String> interestWords(String text) => text
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((word) => word.length > 2)
    .toList();

String inferInterestPlanet(String text) {
  final normalized = interestWords(text).join(' ');
  var best = InterestPlanets.all;
  var bestScore = 0;
  for (final entry in InterestPlanets.keywords.entries) {
    var score = 0;
    for (final keyword in entry.value) {
      if (normalized.contains(keyword)) score++;
    }
    if (score > bestScore) {
      bestScore = score;
      best = entry.key;
    }
  }
  return best;
}

double interestSimilarity(String query, InterestTopic topic) {
  final queryWords = interestWords(query).toSet();
  final topicWords = interestWords(topic.text).toSet();
  if (queryWords.isEmpty || topicWords.isEmpty) return 0;
  var score = 0.0;
  for (final word in queryWords) {
    if (topicWords.contains(word)) score += 4;
    if (topic.text.toLowerCase().contains(word)) score += 1;
  }
  final normalizedQuery = query.trim().toLowerCase().replaceAll('ё', 'е');
  final normalizedTopic = topic.text.toLowerCase().replaceAll('ё', 'е');
  if (normalizedTopic.contains(normalizedQuery)) score += 16;
  if (topic.planet == inferInterestPlanet(query)) score += 2;
  score += min(3, topic.followers / 5);
  score += min(2, topic.replies / 8);
  return score;
}

List<InterestMatch> searchInterests({
  required String query,
  required Iterable<InterestTopic> topics,
  String? planet,
}) {
  final result = <InterestMatch>[];
  for (final topic in topics) {
    if (planet != null && planet != InterestPlanets.all && topic.planet != planet) {
      continue;
    }
    final score = query.trim().isEmpty ? 1.0 : interestSimilarity(query, topic);
    if (score > 0) result.add(InterestMatch(topic: topic, score: score));
  }
  result.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    return b.topic.updatedAt.compareTo(a.topic.updatedAt);
  });
  return result;
}

List<InterestTopic> topicsFromRooms(List<OpticalRoom> rooms) {
  return rooms.map((room) {
    final messages = room.messages.where((message) => !message.deleted).toList();
    final textParts = <String>[room.name];
    for (final message in messages.reversed.take(4)) {
      if (message.text.trim().isNotEmpty) textParts.add(message.text.trim());
    }
    return InterestTopic(
      id: 'room_${room.id}',
      text: room.name,
      kind: InterestKinds.talk,
      planet: inferInterestPlanet(textParts.join(' ')),
      authorId: room.id,
      authorName: 'Комната',
      roomId: room.id,
      followers: 1,
      replies: messages.length,
      createdAt: room.createdAt,
      updatedAt: room.lastActivity,
    );
  }).toList();
}
