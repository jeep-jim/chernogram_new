import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'interests_models.dart';

class InterestsStore {
  static Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/chernogram_interests');
    await directory.create(recursive: true);
    return File('${directory.path}/topics.json');
  }

  static Future<List<InterestTopic>> load() async {
    final file = await _file();
    if (!await file.exists()) return <InterestTopic>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <InterestTopic>[];
      final result = decoded
          .whereType<Map>()
          .map(
            (value) => InterestTopic.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((topic) => topic.text.trim().isNotEmpty)
          .toList();
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return result;
    } catch (_) {
      return <InterestTopic>[];
    }
  }

  static Future<void> save(List<InterestTopic> topics) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(topics.map((topic) => topic.toJson()).toList()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static Future<List<InterestTopic>> upsert({
    required InterestTopic topic,
    required List<InterestTopic> current,
  }) async {
    final result = <InterestTopic>[...current];
    final index = result.indexWhere((value) => value.id == topic.id);
    if (index < 0) {
      result.insert(0, topic);
    } else {
      result[index] = topic;
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save(result);
    return result;
  }
}
