# Android Data First CI failed

Commit: 0c6c163974744405750120fdfae1bf9fcafab88c
Time: 2026-07-29T09:53:36Z
```text
Applied Chernogram 0.8 app-wide calls, sounds and message ordering fixes
Applied Chernogram 0.9 media library, voice, circles and WebRTC replay fixes
Applied Chernogram 0.9 compile safeguards
Android data-first UI materialized
Android data-first compatibility finalized
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (6 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (6 days ago) • 2026-07-23 16:11:34.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
Resolving dependencies...
Downloading packages...
+ app_links 7.2.1
+ app_links_linux 1.0.3
+ app_links_platform_interface 2.0.4
+ app_links_web 1.0.4
+ audio_session 0.2.4
+ camera 0.12.0+2
+ camera_android_camerax 0.7.4+2
+ camera_avfoundation 0.10.2
+ camera_platform_interface 2.13.1
+ camera_web 0.3.5+4
+ cryptography 2.9.0
+ csslib 1.0.2
+ dart_webrtc 1.8.1
+ dbus 0.7.14
+ file_picker 10.3.10 (11.0.2 available)
+ fixnum 1.1.1
+ flutter_contacts 1.1.9+2 (2.3.0 available)
  flutter_lints 3.0.2 (6.0.0 available)
+ flutter_webrtc 1.5.2
+ gtk 2.2.0
  hooks 2.0.2 (2.1.0 available)
+ html 0.15.6
  http 1.6.0 (from transitive dependency to direct dependency)
+ intl 0.20.3
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
+ js 0.7.2
+ just_audio 0.10.6
+ just_audio_platform_interface 4.6.0
+ just_audio_web 0.4.16
  lints 3.0.0 (6.1.0 available)
+ local_auth 3.0.2
+ local_auth_android 2.0.9
+ local_auth_darwin 2.0.3
+ local_auth_platform_interface 1.1.0
+ local_auth_windows 2.0.1
+ logger 2.7.0
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
+ mobile_scanner 7.4.0
  objective_c 9.4.1 (9.5.0 available)
+ open_filex 4.7.0
+ ota_update 7.1.0
  package_config 2.2.0 (3.0.0 available)
+ package_info_plus 8.3.1 (10.2.1 available)
+ package_info_plus_platform_interface 3.2.1 (4.1.0 available)
+ petitparser 7.0.2
+ photo_manager 3.11.0
+ qr 3.0.2 (4.0.0 available)
+ qr_flutter 4.1.0
+ record 6.2.1 (7.1.1 available)
+ record_android 1.5.2 (2.1.2 available)
+ record_ios 1.2.1 (2.1.1 available)
+ record_linux 1.3.1 (2.1.1 available)
+ record_macos 1.2.2 (2.1.1 available)
+ record_platform_interface 1.6.0 (2.1.0 available)
  record_use 0.6.0 (1.0.0 available)
+ record_web 1.3.0 (2.1.1 available)
+ record_windows 1.0.7 (2.2.2 available)
+ rxdart 0.28.0
+ share_plus 10.1.4 (13.3.0 available)
+ share_plus_platform_interface 5.0.2 (7.2.0 available)
+ stream_transform 2.1.1
  test_api 0.7.11 (0.7.13 available)
+ url_launcher 6.3.2
+ url_launcher_android 6.3.32
+ url_launcher_ios 6.4.1
+ url_launcher_linux 3.2.2
+ url_launcher_macos 3.2.5
+ url_launcher_platform_interface 2.3.2
+ url_launcher_web 2.4.3
+ url_launcher_windows 3.1.5
+ uuid 4.6.0
  vector_math 2.2.0 (2.4.1 available)
+ video_player 2.13.0
+ video_player_android 2.12.0
+ video_player_avfoundation 2.11.0
+ video_player_platform_interface 6.9.0
+ video_player_web 2.4.0
+ webrtc_interface 1.5.1
+ win32 5.15.0 (6.3.0 available)
+ xml 6.6.1 (7.0.1 available)
These packages are no longer being depended on:
- file_selector_linux 0.9.4
- file_selector_macos 0.9.5
- file_selector_platform_interface 2.7.0
- file_selector_windows 0.9.3+5
- image_picker 1.2.3
- image_picker_android 0.8.13+19
- image_picker_for_web 3.1.1
- image_picker_ios 0.8.13+6
- image_picker_linux 0.2.2
- image_picker_macos 0.2.2+1
- image_picker_platform_interface 2.11.1
- image_picker_windows 0.2.2
- sqflite 2.4.3
- sqflite_android 2.4.3
- sqflite_common 2.5.11
- sqflite_darwin 2.4.3+1
- sqflite_platform_interface 2.4.1
Changed 87 dependencies!
29 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Formatted lib/main.dart
Formatted lib/brand.dart
Formatted lib/account_access.dart
Formatted lib/android_data_first.dart
Formatted lib/chat_screen.dart
Formatted lib/call_service.dart
Formatted lib/internet_core.dart
Formatted lib/chat_media.dart
Formatted lib/app_monitor.dart
Formatted 9 files (9 changed) in 0.14 seconds.
Analyzing chernogram_new...                                     

   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/android_data_first.dart:1178:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1242:7 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1244:7 • curly_braces_in_flow_control_structures
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/android_data_first.dart:1547:27 • prefer_const_constructors
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1874:7 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/app_monitor.dart:277:7 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/brand.dart:3:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/call_service.dart:260:11 • curly_braces_in_flow_control_structures
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_media.dart:5:8 • unnecessary_import
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1045:7 • use_build_context_synchronously
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1119:7 • use_build_context_synchronously
warning • The declaration '_TunnelAvatar' isn't referenced. Try removing the declaration of '_TunnelAvatar' • lib/chat_screen.dart:1490:7 • unused_element
warning • The declaration '_AttachmentPreview' isn't referenced. Try removing the declaration of '_AttachmentPreview' • lib/chat_screen.dart:1896:7 • unused_element
warning • Unused import: 'core_models.dart'. Try removing the import directive • lib/group_call_service.dart:8:8 • unused_import
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/main.dart:86:42 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/media_studio.dart:2:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/tunnels.dart:1100:20 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/v06.dart:408:7 • use_build_context_synchronously

18 issues found. (ran in 9.5s)

✅ basic smoke test

🎉 1 test passed.
Running Gradle task 'assembleRelease'...                        
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker, flutter_contacts, flutter_webrtc, mobile_scanner, package_info_plus, photo_manager, record_android, share_plus
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.

Please check the changelogs of these plugins and upgrade to a version that supports Built-in Kotlin.
If no such version exists, report the issue to the plugin. If necessary, here is a guide on filing 
an issue against a plugin: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#report-incompatible-kotlin-gradle-plugin-usage-to-plugin-authors

If you are a plugin author, please migrate your plugin to Built-in Kotlin using this guide: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 14540 bytes (99.1% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Note: Some input files use or override a deprecated API.
Note: Recompile with -Xlint:deprecation for details.
Note: Some input files use unchecked or unsafe operations.
Note: Recompile with -Xlint:unchecked for details.
Caught exception: Already watching path: /home/runner/work/chernogram_new/chernogram_new/android
Running Gradle task 'assembleRelease'...                          414.7s
✓ Built build/app/outputs/flutter-apk/app-release.apk (111.4MB)
```
