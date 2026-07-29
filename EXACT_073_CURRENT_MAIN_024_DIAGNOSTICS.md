# Exact 0.7.3 core diagnostic on current main

Outcome: failure
Reference: d1cad8649d00259ab615e65ea196213713b2385f (0.7.3+14)
Time: 2026-07-29T16:14:45Z

```text
Restored exact working 0.7.3+14 chat and WebRTC video calls from d1cad8649d00259ab615e65ea196213713b2385f
Resolving dependencies...
Downloading packages...
  dbus 0.7.13 (0.7.14 available)
+ desktop_drop 0.7.1
  file_picker 10.3.10 (11.0.2 available)
+ flutter_background_service 5.1.0
+ flutter_background_service_android 6.3.1
+ flutter_background_service_ios 5.0.3
+ flutter_background_service_platform_interface 5.1.2
  flutter_contacts 1.1.9+2 (2.3.1 available)
  flutter_lints 3.0.2 (6.0.0 available)
+ flutter_local_notifications 22.2.0
+ flutter_local_notifications_linux 8.0.1
+ flutter_local_notifications_platform_interface 12.1.0
+ flutter_local_notifications_web 1.0.0
+ flutter_local_notifications_windows 3.1.1
  hooks 2.0.2 (2.1.0 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
+ json_annotation 4.12.0
  lints 3.0.0 (6.1.0 available)
  matcher 0.12.19 (0.12.20 available)
+ menu_base 0.1.1
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 8.3.1 (10.2.1 available)
  package_info_plus_platform_interface 3.2.1 (4.1.0 available)
+ permission_handler 12.0.3
+ permission_handler_android 13.0.1
+ permission_handler_apple 9.4.10
+ permission_handler_html 0.1.3+5
+ permission_handler_platform_interface 4.3.0
+ permission_handler_windows 0.2.1
  qr 3.0.2 (4.0.0 available)
  record 6.2.1 (7.1.1 available)
  record_android 1.5.2 (2.1.2 available)
  record_ios 1.2.1 (2.1.1 available)
  record_linux 1.3.1 (2.1.1 available)
  record_macos 1.2.2 (2.1.1 available)
  record_platform_interface 1.6.0 (2.1.0 available)
  record_use 0.6.0 (1.0.0 available)
  record_web 1.3.0 (2.1.1 available)
  record_windows 1.0.7 (2.2.2 available)
+ screen_retriever 0.2.2
+ screen_retriever_linux 0.2.2
+ screen_retriever_macos 0.2.2
+ screen_retriever_platform_interface 0.2.2
+ screen_retriever_windows 0.2.2
  share_plus 10.1.4 (13.3.0 available)
  share_plus_platform_interface 5.0.2 (7.2.0 available)
+ shortid 0.1.2
  test_api 0.7.11 (0.7.13 available)
+ timezone 0.11.1
+ tray_manager 0.5.3
+ universal_platform 1.1.0
  vector_math 2.2.0 (2.4.1 available)
  win32 5.15.0 (6.3.0 available)
+ window_manager 0.5.2
Changed 28 dependencies!
29 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Formatted lib/internet_core.dart
Formatted lib/call_service.dart
Formatted lib/app_monitor.dart
Formatted 3 files (3 changed) in 0.04 seconds.
Analyzing chernogram_new...                                     

   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/app_monitor.dart:279:7 • use_build_context_synchronously
  error • The named parameter 'peerAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'peerAvatarBase64' • lib/app_monitor.dart:380:17 • undefined_named_parameter
  error • The named parameter 'myAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'myAvatarBase64' • lib/app_monitor.dart:381:17 • undefined_named_parameter
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_media.dart:6:8 • unnecessary_import
warning • Unused import: 'dart:typed_data'. Try removing the import directive • lib/chat_screen.dart:4:8 • unused_import
   info • The import of 'package:flutter/services.dart' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart'. Try removing the import directive • lib/chat_screen.dart:10:8 • unnecessary_import
warning • The declaration '_attachmentKind' isn't referenced. Try removing the declaration of '_attachmentKind' • lib/chat_screen.dart:955:10 • unused_element
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1366:7 • use_build_context_synchronously
  error • The named parameter 'peerAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'peerAvatarBase64' • lib/chat_screen.dart:1374:11 • undefined_named_parameter
  error • The named parameter 'myAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'myAvatarBase64' • lib/chat_screen.dart:1375:11 • undefined_named_parameter
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1401:7 • use_build_context_synchronously
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1527:7 • use_build_context_synchronously
  error • The named parameter 'peerAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'peerAvatarBase64' • lib/chat_screen.dart:1587:11 • undefined_named_parameter
  error • The named parameter 'myAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'myAvatarBase64' • lib/chat_screen.dart:1588:11 • undefined_named_parameter
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1606:7 • use_build_context_synchronously
warning • Unused import: 'core_models.dart'. Try removing the import directive • lib/group_call_service.dart:8:8 • unused_import
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/main.dart:92:11 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/media_studio.dart:2:8 • unnecessary_import
warning • Unused import: 'brand.dart'. Try removing the import directive • lib/music_player.dart:10:8 • unused_import
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/notification_service.dart:42:21 • prefer_const_constructors
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/notification_service.dart:115:21 • prefer_const_constructors
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/notification_service.dart:127:16 • prefer_const_constructors
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/permission_center.dart:17:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/tunnels.dart:1100:20 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/v06.dart:408:7 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/foundation.dart'. Try removing the import directive • lib/v12.dart:3:8 • unnecessary_import
warning • The asset file 'assets/audio/chernogram_incoming.mp3' doesn't exist. Try creating the file or fixing the path to the file • pubspec.yaml:52:7 • asset_does_not_exist

27 issues found. (ran in 15.1s)
```
