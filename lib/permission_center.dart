import 'package:flutter/material.dart';

import 'legacy_v16_features.dart';

class CgPermissionCenter {
  static Future<void> open(BuildContext context, {required bool ru}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CgV16PermissionsScreen(ru: ru),
      ),
    );
  }
}
