import 'dart:io';

import 'package:flutter/material.dart';

import 'update_service.dart';
import 'windows_update_service.dart';

class ChernogramAppUpdater {
  static Future<void> checkAndPrompt(
    BuildContext context, {
    required bool ru,
    bool manual = false,
  }) async {
    if (Platform.isWindows) {
      await ChernogramWindowsUpdater.checkAndPrompt(
        context,
        ru: ru,
        manual: manual,
      );
      return;
    }

    await ChernogramUpdater.checkAndPrompt(context, ru: ru, manual: manual);
  }
}
