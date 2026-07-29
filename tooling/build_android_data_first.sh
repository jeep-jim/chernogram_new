#!/usr/bin/env bash
set -euo pipefail

STABLE_SOURCE=0ef99e8bd8692bf69d1650da42a364bcb2963ae3

# The published 0.9.1 APK was built after these compatibility materializers.
# Restore the two legacy UI files only while those scripts run, then remove
# them again so Agent and the old navigation are absent from the product.
git show "${STABLE_SOURCE}:lib/v07.dart" > lib/v07.dart
git show "${STABLE_SOURCE}:lib/agent_screen.dart" > lib/agent_screen.dart
python tooling/fix_v07_compile.py
python tooling/fix_v09_media_calls.py
python tooling/fix_v09_compile.py
rm -f lib/v07.dart lib/agent_screen.dart

python tooling/materialize_android_data_first_v1.py
python tooling/finalize_android_data_first_v1.py

flutter --version
flutter pub get
dart format \
  lib/main.dart \
  lib/brand.dart \
  lib/account_access.dart \
  lib/android_data_first.dart \
  lib/chat_screen.dart \
  lib/call_service.dart \
  lib/internet_core.dart \
  lib/chat_media.dart \
  lib/app_monitor.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
test -s build/app/outputs/flutter-apk/app-release.apk
