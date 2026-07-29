# Android Data First CI failed

Commit: c60f8079c157d976447fc73bbbfaab807ae09542
Time: 2026-07-29T09:35:52Z

## android-data-first-ci.log
```text
Android data-first UI materialized
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (6 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (5 days ago) • 2026-07-23 16:11:34.000Z
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
Formatted 5 files (5 changed) in 0.15 seconds.
Analyzing chernogram_new...                                     

   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/android_data_first.dart:1178:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1242:7 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1244:7 • curly_braces_in_flow_control_structures
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/android_data_first.dart:1547:27 • prefer_const_constructors
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1874:7 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/app_monitor.dart:275:7 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/brand.dart:3:8 • unnecessary_import
  error • The method 'replaySignals' isn't defined for the type 'InternetTunnelSession'. Try correcting the name to the name of an existing method, or defining a method named 'replaySignals' • lib/call_service.dart:245:36 • undefined_method
  error • Expected to find '}' • lib/call_service.dart:775:1 • expected_token
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_media.dart:5:8 • unnecessary_import
  error • The getter 'purple' isn't defined for the type 'ChernogramColors'. Try importing the library that defines 'purple', correcting the name to the name of an existing getter, or defining a getter or field named 'purple' • lib/chat_media.dart:1377:54 • undefined_getter
warning • The declaration '_TunnelAvatar' isn't referenced. Try removing the declaration of '_TunnelAvatar' • lib/chat_screen.dart:1402:7 • unused_element
warning • Unused import: 'core_models.dart'. Try removing the import directive • lib/group_call_service.dart:8:8 • unused_import
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/main.dart:86:42 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/media_studio.dart:2:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/tunnels.dart:1100:20 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/v06.dart:408:7 • use_build_context_synchronously

17 issues found. (ran in 13.1s)
```

## signing-key.txt
```text
Alias name: androiddebugkey
Creation date: Jul 26, 2026
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=Chernogram Prototype, O=Chernogram, C=RU
Issuer: CN=Chernogram Prototype, O=Chernogram, C=RU
Serial number: 967052ca6b03ab0c
Valid from: Sun Jul 26 08:31:07 UTC 2026 until: Thu Dec 11 08:31:07 UTC 2053
Certificate fingerprints:
	 SHA1: 77:F4:C8:E6:D1:BD:16:77:71:73:2B:9E:D3:2F:6A:16:5F:B0:55:69
	 SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
Signature algorithm name: SHA256withRSA
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3

Extensions: 

#1: ObjectId: 2.5.29.14 Criticality=false
SubjectKeyIdentifier [
KeyIdentifier [
0000: 5D 0A 01 66 F4 65 7B D0   A3 7E 37 D0 83 15 C4 E2  ]..f.e....7.....
0010: 5C 63 54 2F                                        \cT/
]
]

```
