# Chat-only test v2 failed

Time: 2026-07-29T17:35:20Z
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

Resolving dependencies...
Downloading packages...
  flutter_lints 3.0.2 (6.0.0 available)
  hooks 2.0.2 (2.1.0 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  lints 3.0.0 (6.1.0 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 8.3.1 (10.2.1 available)
  package_info_plus_platform_interface 3.2.1 (4.1.0 available)
  path_provider 2.1.6 (from direct dependency to transitive dependency)
  record_use 0.6.0 (1.0.0 available)
  share_plus 10.1.4 (13.3.0 available)
  share_plus_platform_interface 5.0.2 (7.2.0 available)
  test_api 0.7.11 (0.7.13 available)
  vector_math 2.2.0 (2.4.1 available)
  win32 5.15.0 (6.3.0 available)
These packages are no longer being depended on:
- archive 4.0.9
- audio_service 0.18.19
- audio_service_platform_interface 0.1.3
- audio_service_web 0.1.4
- audio_session 0.2.4
- camera 0.12.0+2
- camera_android_camerax 0.7.4+2
- camera_avfoundation 0.10.2
- camera_platform_interface 2.13.1
- camera_web 0.3.5+4
- charcode 1.4.0
- csslib 1.0.2
- dart_webrtc 1.8.1
- dbus 0.7.13
- file_picker 10.3.10
- flutter_cache_manager 3.4.2
- flutter_contacts 1.1.9+2
- flutter_plugin_android_lifecycle 2.0.35
- flutter_webrtc 1.5.2
- html 0.15.6
- image 4.9.1
- js 0.7.2
- just_audio 0.10.6
- just_audio_background 0.0.1-beta.17
- just_audio_platform_interface 4.6.0
- just_audio_web 0.4.16
- logger 2.7.0
- mobile_scanner 7.4.0
- open_filex 4.7.0
- petitparser 7.0.2
- photo_manager 3.11.0
- posix 6.5.2
- qr 3.0.2
- qr_flutter 4.1.0
- record 6.2.1
- record_android 1.5.2
- record_ios 1.2.1
- record_linux 1.3.1
- record_macos 1.2.2
- record_platform_interface 1.6.0
- record_web 1.3.0
- record_windows 1.0.7
- rxdart 0.28.0
- sqflite 2.4.3
- sqflite_android 2.4.3
- sqflite_common 2.5.11
- sqflite_darwin 2.4.3+1
- sqflite_platform_interface 2.4.1
- stream_transform 2.1.1
- synchronized 3.4.1+1
- url_launcher 6.3.2
- url_launcher_android 6.3.32
- url_launcher_ios 6.4.1
- url_launcher_macos 3.2.5
- video_player 2.13.0
- video_player_android 2.12.0
- video_player_avfoundation 2.11.0
- video_player_platform_interface 6.9.0
- video_player_web 2.4.0
- webrtc_interface 1.5.1
- xml 7.0.1
- zxing2 0.2.4
Changed 63 dependencies!
17 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Formatted lib/chat_only_app.dart
Formatted lib/chat_only_transport.dart
Formatted 3 files (2 changed) in 0.02 seconds.
Analyzing 3 items...                                            
No issues found! (ran in 10.7s)
Running Gradle task 'assembleRelease'...                        
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): package_info_plus, share_plus
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.

Please check the changelogs of these plugins and upgrade to a version that supports Built-in Kotlin.
If no such version exists, report the issue to the plugin. If necessary, here is a guide on filing 
an issue against a plugin: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#report-incompatible-kotlin-gradle-plugin-usage-to-plugin-authors

If you are a plugin author, please migrate your plugin to Built-in Kotlin using this guide: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 1748 bytes (99.9% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Caught exception: Already watching path: /home/runner/work/chernogram_new/chernogram_new/android
Running Gradle task 'assembleRelease'...                          170.2s
✓ Built build/app/outputs/flutter-apk/app-release.apk (50.9MB)
V3.0 Signer: certificate DN: CN=Chernogram Prototype, O=Chernogram, C=RU
V3.0 Signer: certificate SHA-256 digest: f4a2c836a83671197810fa6e982d77f4c731d09b189515c013d02d0d942d9bbe
V3.0 Signer: certificate SHA-1 digest: 77f4c8e6d1bd167771732b9ed32f6a165fb05569
V3.0 Signer: certificate MD5 digest: d1e0d79a6a21f0fe759cce0e81ba5062
c24580a4187456c1ceb0003e51dfd467350595f91c877fea391b3d9e213d3767  chernogram.apk
```
