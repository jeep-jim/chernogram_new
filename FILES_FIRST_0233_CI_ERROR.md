# Chernogram 0.23.3 files-first v2 failed

Workflow commit: 6baf6c4d8d807bdd376b65949d3b61d96b326c0f
Time: 2026-07-31T02:54:51Z
```text
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (7 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (7 days ago) • 2026-07-23 16:11:34.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
Resolving dependencies...
Downloading packages...
  file_picker 10.3.10 (11.0.2 available)
  flutter_contacts 1.1.9+2 (2.3.0 available)
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
  share_plus 10.1.4 (13.3.0 available)
  share_plus_platform_interface 5.0.2 (7.2.0 available)
  test_api 0.7.11 (0.7.13 available)
  vector_math 2.2.0 (2.4.1 available)
  win32 5.15.0 (6.3.0 available)
  xml 6.6.1 (7.0.1 available)
Changed 6 dependencies!
29 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Formatted lib/android_data_first.dart
Formatted lib/chat_screen.dart
Formatted lib/internet_core.dart
Formatted lib/call_service.dart
Formatted lib/group_call_service.dart
Formatted lib/core_models.dart
Formatted lib/brand.dart
Formatted 11 files (7 changed) in 0.28 seconds.
Analyzing chernogram_new...                                     

   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/android_data_first.dart:1337:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1431:7 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1433:7 • curly_braces_in_flow_control_structures
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/android_data_first.dart:1802:27 • prefer_const_constructors
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:2133:7 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/app_monitor.dart:286:7 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/brand.dart:3:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/call_service.dart:262:11 • curly_braces_in_flow_control_structures
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_media.dart:5:8 • unnecessary_import
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_screen.dart:4:8 • unnecessary_import
warning • The declaration '_showMessageActions' isn't referenced. Try removing the declaration of '_showMessageActions' • lib/chat_screen.dart:489:16 • unused_element
warning • The declaration '_showNotConnected' isn't referenced. Try removing the declaration of '_showNotConnected' • lib/chat_screen.dart:1168:8 • unused_element
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1235:7 • use_build_context_synchronously
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1309:7 • use_build_context_synchronously
warning • The declaration '_TunnelAvatar' isn't referenced. Try removing the declaration of '_TunnelAvatar' • lib/chat_screen.dart:1794:7 • unused_element
warning • The declaration '_AttachmentPreview' isn't referenced. Try removing the declaration of '_AttachmentPreview' • lib/chat_screen.dart:2327:7 • unused_element
warning • Unused import: 'core_models.dart'. Try removing the import directive • lib/group_call_service.dart:8:8 • unused_import
warning • Unused import: 'brand.dart'. Try removing the import directive • lib/legacy_v16_features.dart:13:8 • unused_import
   info • 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/legacy_v16_features.dart:964:19 • deprecated_member_use
   info • 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/legacy_v16_features.dart:966:19 • deprecated_member_use
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/main.dart:93:42 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/media_studio.dart:2:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/tunnels.dart:1100:20 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/v06.dart:408:7 • use_build_context_synchronously

24 issues found. (ran in 12.6s)

✅ basic smoke test

🎉 1 test passed.
Running Gradle task 'assembleRelease'...                        
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker, flutter_contacts, flutter_webrtc, mobile_scanner, package_info_plus, photo_manager, record_android, share_plus
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.

Please check the changelogs of these plugins and upgrade to a version that supports Built-in Kotlin.
If no such version exists, report the issue to the plugin. If necessary, here is a guide on filing 
an issue against a plugin: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#report-incompatible-kotlin-gradle-plugin-usage-to-plugin-authors

If you are a plugin author, please migrate your plugin to Built-in Kotlin using this guide: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 18364 bytes (98.9% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Note: Some input files use or override a deprecated API.
Note: Recompile with -Xlint:deprecation for details.
Note: Some input files use unchecked or unsafe operations.
Note: Recompile with -Xlint:unchecked for details.
Caught exception: Already watching path: /home/runner/work/chernogram_new/chernogram_new/android
Running Gradle task 'assembleRelease'...                          342.2s
✓ Built build/app/outputs/flutter-apk/app-release.apk (112.7MB)
V3.0 Signer: certificate DN: CN=Chernogram Prototype, O=Chernogram, C=RU
V3.0 Signer: certificate SHA-256 digest: f4a2c836a83671197810fa6e982d77f4c731d09b189515c013d02d0d942d9bbe
V3.0 Signer: certificate SHA-1 digest: 77f4c8e6d1bd167771732b9ed32f6a165fb05569
V3.0 Signer: certificate MD5 digest: d1e0d79a6a21f0fe759cce0e81ba5062
package: name='com.example.chernogram' versionCode='58' versionName='0.23.3' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'
sdkVersion:'24'
targetSdkVersion:'36'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.RECORD_AUDIO'
uses-permission: name='android.permission.VIBRATE'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
uses-permission: name='android.permission.ACCESS_COARSE_LOCATION'
uses-permission: name='android.permission.ACCESS_FINE_LOCATION'
uses-permission: name='android.permission.USE_BIOMETRIC'
uses-permission: name='android.permission.USE_FINGERPRINT'
uses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'
uses-permission: name='android.permission.READ_CONTACTS'
uses-permission: name='android.permission.READ_MEDIA_IMAGES'
uses-permission: name='android.permission.READ_MEDIA_VIDEO'
uses-permission: name='android.permission.READ_MEDIA_AUDIO'
uses-permission: name='android.permission.BLUETOOTH' maxSdkVersion='30'
uses-permission: name='android.permission.BLUETOOTH_ADMIN' maxSdkVersion='30'
uses-permission: name='android.permission.BLUETOOTH_SCAN'
uses-permission: name='android.permission.BLUETOOTH_CONNECT'
uses-permission: name='android.permission.NEARBY_WIFI_DEVICES'
uses-permission: name='android.permission.ACCESS_WIFI_STATE'
uses-permission: name='android.permission.CHANGE_WIFI_STATE'
uses-permission: name='android.permission.READ_EXTERNAL_STORAGE' maxSdkVersion='32'
uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='28'
uses-permission: name='android.permission.INSTALL_PACKAGES'
uses-permission: name='com.example.chernogram.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
uses-permission: name='android.permission.MODIFY_AUDIO_SETTINGS'
application-label:'Чернограм'
application-label-af:'Чернограм'
application-label-am:'Чернограм'
application-label-ar:'Чернограм'
application-label-as:'Чернограм'
application-label-az:'Чернограм'
application-label-be:'Чернограм'
application-label-bg:'Чернограм'
application-label-bn:'Чернограм'
application-label-bs:'Чернограм'
application-label-ca:'Чернограм'
application-label-cs:'Чернограм'
application-label-da:'Чернограм'
application-label-de:'Чернограм'
application-label-el:'Чернограм'
application-label-en-AU:'Чернограм'
application-label-en-CA:'Чернограм'
application-label-en-GB:'Чернограм'
application-label-en-IN:'Чернограм'
application-label-en-XC:'Чернограм'
application-label-es:'Чернограм'
application-label-es-US:'Чернограм'
application-label-et:'Чернограм'
application-label-eu:'Чернограм'
application-label-fa:'Чернограм'
application-label-fi:'Чернограм'
application-label-fr:'Чернограм'
application-label-fr-CA:'Чернограм'
application-label-gl:'Чернограм'
application-label-gu:'Чернограм'
application-label-hi:'Чернограм'
application-label-hr:'Чернограм'
application-label-hu:'Чернограм'
application-label-hy:'Чернограм'
application-label-in:'Чернограм'
application-label-is:'Чернограм'
application-label-it:'Чернограм'
application-label-iw:'Чернограм'
application-label-ja:'Чернограм'
application-label-ka:'Чернограм'
application-label-kk:'Чернограм'
application-label-km:'Чернограм'
application-label-kn:'Чернограм'
application-label-ko:'Чернограм'
application-label-ky:'Чернограм'
application-label-lo:'Чернограм'
application-label-lt:'Чернограм'
application-label-lv:'Чернограм'
application-label-mk:'Чернограм'
application-label-ml:'Чернограм'
application-label-mn:'Чернограм'
application-label-mr:'Чернограм'
application-label-ms:'Чернограм'
application-label-my:'Чернограм'
application-label-nb:'Чернограм'
application-label-ne:'Чернограм'
application-label-nl:'Чернограм'
application-label-or:'Чернограм'
application-label-pa:'Чернограм'
application-label-pl:'Чернограм'
application-label-pt:'Чернограм'
application-label-pt-BR:'Чернограм'
application-label-pt-PT:'Чернограм'
application-label-ro:'Чернограм'
application-label-ru:'Чернограм'
application-label-si:'Чернограм'
application-label-sk:'Чернограм'
application-label-sl:'Чернограм'
application-label-sq:'Чернограм'
application-label-sr:'Чернограм'
application-label-sr-Latn:'Чернограм'
application-label-sv:'Чернограм'
application-label-sw:'Чернограм'
application-label-ta:'Чернограм'
application-label-te:'Чернограм'
application-label-th:'Чернограм'
application-label-tl:'Чернограм'
application-label-tr:'Чернограм'
application-label-uk:'Чернограм'
application-label-ur:'Чернограм'
application-label-uz:'Чернограм'
application-label-vi:'Чернограм'
application-label-zh-CN:'Чернограм'
application-label-zh-HK:'Чернограм'
application-label-zh-TW:'Чернограм'
application-label-zu:'Чернограм'
application-icon-120:'res/Cf.xml'
application-icon-160:'res/Cf.xml'
application-icon-240:'res/Cf.xml'
application-icon-320:'res/Cf.xml'
application-icon-480:'res/Cf.xml'
application-icon-640:'res/Cf.xml'
application-icon-65534:'res/Cf.xml'
application: label='Чернограм' icon='res/Cf.xml'
launchable-activity: name='com.example.chernogram.MainActivity'  label='' icon=''
uses-library-not-required:'androidx.window.extensions'
uses-library-not-required:'androidx.window.sidecar'
feature-group: label=''
  uses-feature-not-required: name='android.hardware.camera'
  uses-feature: name='android.hardware.camera.any'
  uses-feature: name='android.hardware.bluetooth'
  uses-implied-feature: name='android.hardware.bluetooth' reason='requested android.permission.BLUETOOTH permission, requested android.permission.BLUETOOTH_ADMIN permission, and targetSdkVersion > 4'
  uses-feature: name='android.hardware.faketouch'
  uses-implied-feature: name='android.hardware.faketouch' reason='default feature for all apps'
  uses-feature: name='android.hardware.location'
  uses-implied-feature: name='android.hardware.location' reason='requested android.permission.ACCESS_COARSE_LOCATION permission, and requested android.permission.ACCESS_FINE_LOCATION permission'
  uses-feature: name='android.hardware.microphone'
  uses-implied-feature: name='android.hardware.microphone' reason='requested android.permission.RECORD_AUDIO permission'
  uses-feature: name='android.hardware.wifi'
  uses-implied-feature: name='android.hardware.wifi' reason='requested android.permission.ACCESS_WIFI_STATE permission, and requested android.permission.CHANGE_WIFI_STATE permission'
main
other-activities
other-receivers
other-services
supports-screens: 'small' 'normal' 'large' 'xlarge'
supports-any-density: 'true'
locales: '--_--' 'af' 'am' 'ar' 'as' 'az' 'be' 'bg' 'bn' 'bs' 'ca' 'cs' 'da' 'de' 'el' 'en-AU' 'en-CA' 'en-GB' 'en-IN' 'en-XC' 'es' 'es-US' 'et' 'eu' 'fa' 'fi' 'fr' 'fr-CA' 'gl' 'gu' 'hi' 'hr' 'hu' 'hy' 'in' 'is' 'it' 'iw' 'ja' 'ka' 'kk' 'km' 'kn' 'ko' 'ky' 'lo' 'lt' 'lv' 'mk' 'ml' 'mn' 'mr' 'ms' 'my' 'nb' 'ne' 'nl' 'or' 'pa' 'pl' 'pt' 'pt-BR' 'pt-PT' 'ro' 'ru' 'si' 'sk' 'sl' 'sq' 'sr' 'sr-Latn' 'sv' 'sw' 'ta' 'te' 'th' 'tl' 'tr' 'uk' 'ur' 'uz' 'vi' 'zh-CN' 'zh-HK' 'zh-TW' 'zu'
densities: '120' '160' '240' '320' '480' '640' '65534'
native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'
2746ad9a7047077f2f9b7b92354f20c91bc63decec8ad242bf77f0a566f210e3  chernogram.apk
```
