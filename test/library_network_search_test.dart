import 'package:chernogram/interests/interests_models.dart';
import 'package:chernogram/library/library_models.dart';
import 'package:chernogram/library/library_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library search ranks exact file names first', () {
    final now = DateTime.utc(2026, 8, 2);
    final items = <LibraryItem>[
      LibraryItem(
        id: '1',
        name: 'Мёд и пасека.pdf',
        kind: LibraryKinds.document,
        access: LibraryAccess.private,
        ownerId: 'a',
        ownerName: 'Антон',
        sourceDeviceId: 'phone',
        size: 120,
        createdAt: now,
        updatedAt: now,
      ),
      LibraryItem(
        id: '2',
        name: 'Список покупок.txt',
        kind: LibraryKinds.document,
        access: LibraryAccess.private,
        ownerId: 'a',
        ownerName: 'Антон',
        sourceDeviceId: 'phone',
        size: 80,
        createdAt: now,
        updatedAt: now,
        tags: const <String>['мёд'],
      ),
    ];

    final result = searchLibrary(query: 'мёд', items: items);
    expect(result.length, 2);
    expect(result.first.item.id, '1');
  });

  test('interest search ranks close Russian topics first', () {
    final now = DateTime.utc(2026, 8, 2);
    final topics = <InterestTopic>[
      InterestTopic(
        id: 'honey',
        text: 'Где купить натуральный мёд рядом',
        kind: InterestKinds.ask,
        planet: InterestPlanets.people,
        authorId: 'a',
        authorName: 'Антон',
        followers: 3,
        replies: 8,
        createdAt: now,
        updatedAt: now,
      ),
      InterestTopic(
        id: 'cars',
        text: 'Обсуждение китайских автомобилей',
        kind: InterestKinds.talk,
        planet: InterestPlanets.auto,
        authorId: 'b',
        authorName: 'Иван',
        followers: 3,
        replies: 8,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final result = searchInterests(query: 'где купить мёд', topics: topics);
    expect(result, isNotEmpty);
    expect(result.first.topic.id, 'honey');
    if (result.length > 1) {
      expect(result.first.score, greaterThan(result[1].score));
    }
  });
}
