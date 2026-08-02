import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_identity.dart';
import 'optical_models.dart';

class OpticalStore {
  static const String _profileKey = 'cg_optical_profile_v1';
  static const String _roomsKey = 'cg_optical_rooms_v1';

  static Future<OpticalProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_profileKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        return OpticalProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(stored) as Map),
        );
      } catch (_) {}
    }
    final stableId = await CgDeviceIdentity.stableProfileId();
    final suffix = stableId.length > 6
        ? stableId.substring(stableId.length - 6).toUpperCase()
        : stableId.toUpperCase();
    final profile = OpticalProfile(
      id: stableId,
      nickname: 'Устройство $suffix',
    );
    await saveProfile(profile);
    return profile;
  }

  static Future<void> saveProfile(OpticalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  static Future<List<OpticalRoom>> loadRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_roomsKey);
    if (stored == null || stored.isEmpty) return <OpticalRoom>[];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return <OpticalRoom>[];
      final rooms = decoded
          .whereType<Map>()
          .map(
            (value) => OpticalRoom.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList();
      rooms.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
      return rooms;
    } catch (_) {
      return <OpticalRoom>[];
    }
  }

  static Future<void> saveRooms(List<OpticalRoom> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _roomsKey,
      jsonEncode(rooms.map((room) => room.toJson()).toList()),
    );
  }

  static Future<File> persistFile({
    required String roomId,
    required String messageId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/optical/$roomId');
    await directory.create(recursive: true);
    final safeName = _safeFileName(fileName);
    final file = File('${directory.path}/${messageId}_$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _safeFileName(String input) {
    final trimmed = input.trim().isEmpty ? 'file.bin' : input.trim();
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}
