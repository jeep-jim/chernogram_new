import 'library_models.dart';

List<String> libraryWords(String text) => text
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((word) => word.length > 1)
    .toList();

class LibrarySearchResult {
  final LibraryItem item;
  final double score;

  const LibrarySearchResult({required this.item, required this.score});
}

List<LibrarySearchResult> searchLibrary({
  required String query,
  required Iterable<LibraryItem> items,
  String? kind,
}) {
  final clean = query.trim().toLowerCase().replaceAll('ё', 'е');
  final queryWords = libraryWords(clean).toSet();
  final result = <LibrarySearchResult>[];

  for (final item in items) {
    if (kind != null && kind.isNotEmpty && item.kind != kind) continue;
    if (clean.isEmpty) {
      result.add(LibrarySearchResult(item: item, score: 1));
      continue;
    }

    final haystack = <String>[
      item.name,
      item.artist ?? '',
      item.album ?? '',
      item.description ?? '',
      item.ownerName,
      ...item.tags,
    ].join(' ').toLowerCase().replaceAll('ё', 'е');
    final haystackWords = libraryWords(haystack).toSet();

    var score = 0.0;
    if (haystack.contains(clean)) score += 20;
    if (item.name.toLowerCase().startsWith(clean)) score += 16;
    for (final word in queryWords) {
      if (haystackWords.contains(word)) score += 4;
      if (item.name.toLowerCase().contains(word)) score += 3;
      if ((item.artist ?? '').toLowerCase().contains(word)) score += 2;
      if (item.tags.any((tag) => tag.toLowerCase().contains(word))) score += 2;
    }
    if (score > 0) result.add(LibrarySearchResult(item: item, score: score));
  }

  result.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    return b.item.updatedAt.compareTo(a.item.updatedAt);
  });
  return result;
}
