# Build 60 failure diagnostic

Run id: 30683463822

Status: completed

Conclusion: failure

URL: https://github.com/jeep-jim/chernogram_new/actions/runs/30683463822

## Failed jobs

- Собрать APK, создать отдельный Release и включить обновле... — failure — job id 91324791149
  - failed step: Переключить обновление приложения на build 60

## Failed log tail

```text
2026-08-01T04:12:32.0149180Z env:
2026-08-01T04:12:32.0149443Z   WORKING_REF: 6847a3d4e6ade48ca139c6560c036540865b8bf8
2026-08-01T04:12:32.0149783Z   SOURCE_VERSION: 0.24.0+56
2026-08-01T04:12:32.0150035Z   VERSION_FULL: 0.24.0+60
2026-08-01T04:12:32.0150266Z   VERSION_NAME: 0.24.0
2026-08-01T04:12:32.0150492Z   VERSION_CODE: 60
2026-08-01T04:12:32.0150726Z   RELEASE_TAG: chernogram-0.24.0-build60
2026-08-01T04:12:32.0151027Z   FLUTTER_VERSION: 3.44.8
2026-08-01T04:12:32.0151420Z   CERT_SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
2026-08-01T04:12:32.0151991Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:12:32.0152524Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:12:32.0153026Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.44.8-x64/flutter
2026-08-01T04:12:32.0153427Z   PUB_CACHE: /home/runner/.pub-cache
2026-08-01T04:12:32.0153707Z   CHERNOGRAM_KEYSTORE_B64: 
2026-08-01T04:12:32.0153956Z ##[endgroup]
2026-08-01T04:12:35.2143686Z ##[group]Run set -o pipefail
2026-08-01T04:12:35.2144079Z [36;1mset -o pipefail[0m
2026-08-01T04:12:35.2144329Z [36;1m([0m
2026-08-01T04:12:35.2144549Z [36;1m  set -euo pipefail[0m
2026-08-01T04:12:35.2144807Z [36;1m  flutter pub get[0m
2026-08-01T04:12:35.2145079Z [36;1m  flutter build apk --release[0m
2026-08-01T04:12:35.2145455Z [36;1m  SOURCE_APK=build/app/outputs/flutter-apk/app-release.apk[0m
2026-08-01T04:12:35.2145844Z [36;1m  test -s "$SOURCE_APK"[0m
2026-08-01T04:12:35.2146097Z [36;1m[0m
2026-08-01T04:12:35.2146501Z [36;1m  APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -n 1)[0m
2026-08-01T04:12:35.2147141Z [36;1m  AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -n 1)[0m
2026-08-01T04:12:35.2147573Z [36;1m[0m
2026-08-01T04:12:35.2147779Z [36;1m  "$APKSIGNER" sign \[0m
2026-08-01T04:12:35.2148078Z [36;1m    --ks "$HOME/.android/debug.keystore" \[0m
2026-08-01T04:12:35.2148457Z [36;1m    --ks-key-alias androiddebugkey \[0m
2026-08-01T04:12:35.2148772Z [36;1m    --ks-pass pass:android \[0m
2026-08-01T04:12:35.2149406Z [36;1m    --key-pass pass:android \[0m
2026-08-01T04:12:35.2149702Z [36;1m    --out chernogram.apk \[0m
2026-08-01T04:12:35.2149978Z [36;1m    "$SOURCE_APK"[0m
2026-08-01T04:12:35.2150215Z [36;1m[0m
2026-08-01T04:12:35.2150553Z [36;1m  "$APKSIGNER" verify --print-certs chernogram.apk | tee apk-signature.txt[0m
2026-08-01T04:12:35.2150989Z [36;1m  APK_CERT=$(sed -n \[0m
2026-08-01T04:12:35.2151319Z [36;1m    -e 's/^Signer #1 certificate SHA-256 digest: //p' \[0m
2026-08-01T04:12:35.2151730Z [36;1m    -e 's/^V2 Signer: certificate SHA-256 digest: //p' \[0m
2026-08-01T04:12:35.2152137Z [36;1m    -e 's/^V3.0 Signer: certificate SHA-256 digest: //p' \[0m
2026-08-01T04:12:35.2152988Z [36;1m    apk-signature.txt | head -n 1 | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')[0m
2026-08-01T04:12:35.2153574Z [36;1m  EXPECTED=$(printf '%s' "$CERT_SHA256" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')[0m
2026-08-01T04:12:35.2154037Z [36;1m  test "$APK_CERT" = "$EXPECTED"[0m
2026-08-01T04:12:35.2154331Z [36;1m[0m
2026-08-01T04:12:35.2154616Z [36;1m  "$AAPT" dump badging chernogram.apk | tee apk-badging.txt[0m
2026-08-01T04:12:35.2155041Z [36;1m  grep -q "versionCode='$VERSION_CODE'" apk-badging.txt[0m
2026-08-01T04:12:35.2155449Z [36;1m  grep -q "versionName='$VERSION_NAME'" apk-badging.txt[0m
2026-08-01T04:12:35.2155835Z [36;1m  sha256sum chernogram.apk | tee apk-sha256.txt[0m
2026-08-01T04:12:35.2156188Z [36;1m) 2>&1 | tee publish-0240-build60.log[0m
2026-08-01T04:12:35.2213344Z shell: /usr/bin/bash --noprofile --norc -e -o pipefail {0}
2026-08-01T04:12:35.2213723Z env:
2026-08-01T04:12:35.2213982Z   WORKING_REF: 6847a3d4e6ade48ca139c6560c036540865b8bf8
2026-08-01T04:12:35.2214330Z   SOURCE_VERSION: 0.24.0+56
2026-08-01T04:12:35.2214582Z   VERSION_FULL: 0.24.0+60
2026-08-01T04:12:35.2214813Z   VERSION_NAME: 0.24.0
2026-08-01T04:12:35.2215046Z   VERSION_CODE: 60
2026-08-01T04:12:35.2215281Z   RELEASE_TAG: chernogram-0.24.0-build60
2026-08-01T04:12:35.2215576Z   FLUTTER_VERSION: 3.44.8
2026-08-01T04:12:35.2215965Z   CERT_SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
2026-08-01T04:12:35.2216516Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:12:35.2217032Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:12:35.2217535Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.44.8-x64/flutter
2026-08-01T04:12:35.2217931Z   PUB_CACHE: /home/runner/.pub-cache
2026-08-01T04:12:35.2218208Z ##[endgroup]
2026-08-01T04:12:35.4756412Z Resolving dependencies...
2026-08-01T04:12:35.6875311Z Downloading packages...
2026-08-01T04:12:35.8406372Z   dbus 0.7.13 (0.7.14 available)
2026-08-01T04:12:35.8407080Z   file_picker 10.3.10 (11.0.2 available)
2026-08-01T04:12:35.8407737Z   flutter_contacts 1.1.9+2 (2.3.1 available)
2026-08-01T04:12:35.8409217Z   flutter_lints 3.0.2 (6.0.0 available)
2026-08-01T04:12:35.8409914Z   hooks 2.0.2 (2.1.0 available)
2026-08-01T04:12:35.8410254Z   jni 1.0.0 (1.0.2 available)
2026-08-01T04:12:35.8410601Z   jni_flutter 1.0.1 (1.0.2 available)
2026-08-01T04:12:35.8410959Z   lints 3.0.0 (6.1.0 available)
2026-08-01T04:12:35.8411315Z   matcher 0.12.19 (0.12.20 available)
2026-08-01T04:12:35.8411686Z   meta 1.18.0 (1.19.0 available)
2026-08-01T04:12:35.8412039Z   objective_c 9.4.1 (9.5.0 available)
2026-08-01T04:12:35.8412416Z   package_config 2.2.0 (3.0.0 available)
2026-08-01T04:12:35.8412809Z   package_info_plus 8.3.1 (10.2.1 available)
2026-08-01T04:12:35.8413291Z   package_info_plus_platform_interface 3.2.1 (4.1.0 available)
2026-08-01T04:12:35.8413751Z   qr 3.0.2 (4.0.0 available)
2026-08-01T04:12:35.8414081Z   record 6.2.1 (7.1.1 available)
2026-08-01T04:12:35.8414424Z   record_android 1.5.2 (2.1.2 available)
2026-08-01T04:12:35.8414907Z   record_ios 1.2.1 (2.1.1 available)
2026-08-01T04:12:35.8415272Z   record_linux 1.3.1 (2.1.1 available)
2026-08-01T04:12:35.8415630Z   record_macos 1.2.2 (2.1.1 available)
2026-08-01T04:12:35.8416026Z   record_platform_interface 1.6.0 (2.1.0 available)
2026-08-01T04:12:35.8416438Z   record_use 0.6.0 (1.0.0 available)
2026-08-01T04:12:35.8416778Z   record_web 1.3.0 (2.1.1 available)
2026-08-01T04:12:35.8417129Z   record_windows 1.0.7 (2.2.2 available)
2026-08-01T04:12:35.8417597Z   share_plus 10.1.4 (13.3.0 available)
2026-08-01T04:12:35.8418565Z   share_plus_platform_interface 5.0.2 (7.2.0 available)
2026-08-01T04:12:35.8419614Z   test_api 0.7.11 (0.7.13 available)
2026-08-01T04:12:35.8420364Z   vector_math 2.2.0 (2.4.1 available)
2026-08-01T04:12:35.8420826Z   win32 5.15.0 (6.3.0 available)
2026-08-01T04:12:35.8438009Z Got dependencies!
2026-08-01T04:12:35.8439168Z 29 packages have newer versions incompatible with dependency constraints.
2026-08-01T04:12:35.8439877Z Try `flutter pub outdated` for more information.
2026-08-01T04:12:36.4502175Z Resolving dependencies...
2026-08-01T04:12:36.6510656Z Downloading packages...
2026-08-01T04:12:36.6962339Z   dbus 0.7.13 (0.7.14 available)
2026-08-01T04:12:36.6962894Z   file_picker 10.3.10 (11.0.2 available)
2026-08-01T04:12:36.6963404Z   flutter_contacts 1.1.9+2 (2.3.1 available)
2026-08-01T04:12:36.6963922Z   flutter_lints 3.0.2 (6.0.0 available)
2026-08-01T04:12:36.6964426Z   hooks 2.0.2 (2.1.0 available)
2026-08-01T04:12:36.6964862Z   jni 1.0.0 (1.0.2 available)
2026-08-01T04:12:36.6965312Z   jni_flutter 1.0.1 (1.0.2 available)
2026-08-01T04:12:36.6965782Z   lints 3.0.0 (6.1.0 available)
2026-08-01T04:12:36.6966412Z   matcher 0.12.19 (0.12.20 available)
2026-08-01T04:12:36.6967000Z   meta 1.18.0 (1.19.0 available)
2026-08-01T04:12:36.6967542Z   objective_c 9.4.1 (9.5.0 available)
2026-08-01T04:12:36.6968127Z   package_config 2.2.0 (3.0.0 available)
2026-08-01T04:12:36.6968756Z   package_info_plus 8.3.1 (10.2.1 available)
2026-08-01T04:12:36.6969618Z   package_info_plus_platform_interface 3.2.1 (4.1.0 available)
2026-08-01T04:12:36.6970238Z   qr 3.0.2 (4.0.0 available)
2026-08-01T04:12:36.6970676Z   record 6.2.1 (7.1.1 available)
2026-08-01T04:12:36.6971136Z   record_android 1.5.2 (2.1.2 available)
2026-08-01T04:12:36.6971607Z   record_ios 1.2.1 (2.1.1 available)
2026-08-01T04:12:36.6972066Z   record_linux 1.3.1 (2.1.1 available)
2026-08-01T04:12:36.6972539Z   record_macos 1.2.2 (2.1.1 available)
2026-08-01T04:12:36.6973110Z   record_platform_interface 1.6.0 (2.1.0 available)
2026-08-01T04:12:36.6973650Z   record_use 0.6.0 (1.0.0 available)
2026-08-01T04:12:36.6974092Z   record_web 1.3.0 (2.1.1 available)
2026-08-01T04:12:36.6974553Z   record_windows 1.0.7 (2.2.2 available)
2026-08-01T04:12:36.6975026Z   share_plus 10.1.4 (13.3.0 available)
2026-08-01T04:12:36.6975563Z   share_plus_platform_interface 5.0.2 (7.2.0 available)
2026-08-01T04:12:36.6976113Z   test_api 0.7.11 (0.7.13 available)
2026-08-01T04:12:36.6976577Z   vector_math 2.2.0 (2.4.1 available)
2026-08-01T04:12:36.6977048Z   win32 5.15.0 (6.3.0 available)
2026-08-01T04:12:36.6977785Z Got dependencies!
2026-08-01T04:12:36.6978421Z 29 packages have newer versions incompatible with dependency constraints.
2026-08-01T04:12:36.6979455Z Try `flutter pub outdated` for more information.
2026-08-01T04:13:03.2040115Z Running Gradle task 'assembleRelease'...                        
2026-08-01T04:13:03.2059337Z WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): desktop_drop, file_picker, flutter_contacts, flutter_webrtc, mobile_scanner, package_info_plus, photo_manager, record_android, share_plus
2026-08-01T04:13:03.2061912Z Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
2026-08-01T04:13:03.2062664Z 
2026-08-01T04:13:03.2063331Z Please check the changelogs of these plugins and upgrade to a version that supports Built-in Kotlin.
2026-08-01T04:13:03.2064733Z If no such version exists, report the issue to the plugin. If necessary, here is a guide on filing 
2026-08-01T04:13:03.2067047Z an issue against a plugin: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#report-incompatible-kotlin-gradle-plugin-usage-to-plugin-authors
2026-08-01T04:13:03.2068833Z 
2026-08-01T04:13:03.2070381Z If you are a plugin author, please migrate your plugin to Built-in Kotlin using this guide: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
2026-08-01T04:13:47.9921091Z Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 16112 bytes (99.0% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
2026-08-01T04:14:34.3920249Z Note: Some input files use or override a deprecated API.
2026-08-01T04:14:34.3953279Z Note: Recompile with -Xlint:deprecation for details.
2026-08-01T04:14:40.3930289Z Note: Some input files use or override a deprecated API.
2026-08-01T04:14:40.3974913Z Note: Recompile with -Xlint:deprecation for details.
2026-08-01T04:14:40.4020908Z Note: Some input files use unchecked or unsafe operations.
2026-08-01T04:14:40.4059939Z Note: Recompile with -Xlint:unchecked for details.
2026-08-01T04:15:02.3911298Z Caught exception: Already watching path: /home/runner/work/chernogram_new/chernogram_new/android
2026-08-01T04:18:22.0980036Z Running Gradle task 'assembleRelease'...                          345.0s
2026-08-01T04:18:23.1393202Z ✓ Built build/app/outputs/flutter-apk/app-release.apk (115.9MB)
2026-08-01T04:18:25.3269367Z V3.0 Signer: certificate DN: CN=Chernogram Prototype, O=Chernogram, C=RU
2026-08-01T04:18:25.3271550Z V3.0 Signer: certificate SHA-256 digest: f4a2c836a83671197810fa6e982d77f4c731d09b189515c013d02d0d942d9bbe
2026-08-01T04:18:25.3274165Z V3.0 Signer: certificate SHA-1 digest: 77f4c8e6d1bd167771732b9ed32f6a165fb05569
2026-08-01T04:18:25.3282870Z V3.0 Signer: certificate MD5 digest: d1e0d79a6a21f0fe759cce0e81ba5062
2026-08-01T04:18:25.6791794Z package: name='com.example.chernogram' versionCode='60' versionName='0.24.0' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'
2026-08-01T04:18:25.6793297Z sdkVersion:'24'
2026-08-01T04:18:25.6793681Z targetSdkVersion:'36'
2026-08-01T04:18:25.6794182Z uses-permission: name='android.permission.INTERNET'
2026-08-01T04:18:25.6794856Z uses-permission: name='android.permission.CAMERA'
2026-08-01T04:18:25.6795519Z uses-permission: name='android.permission.RECORD_AUDIO'
2026-08-01T04:18:25.6796197Z uses-permission: name='android.permission.VIBRATE'
2026-08-01T04:18:25.6796945Z uses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'
2026-08-01T04:18:25.6797722Z uses-permission: name='android.permission.READ_CONTACTS'
2026-08-01T04:18:25.6798436Z uses-permission: name='android.permission.READ_MEDIA_IMAGES'
2026-08-01T04:18:25.6799405Z uses-permission: name='android.permission.READ_MEDIA_VIDEO'
2026-08-01T04:18:25.6800157Z uses-permission: name='android.permission.READ_MEDIA_AUDIO'
2026-08-01T04:18:25.6801227Z uses-permission: name='android.permission.BLUETOOTH' maxSdkVersion='30'
2026-08-01T04:18:25.6802160Z uses-permission: name='android.permission.BLUETOOTH_ADMIN' maxSdkVersion='30'
2026-08-01T04:18:25.6803010Z uses-permission: name='android.permission.BLUETOOTH_SCAN'
2026-08-01T04:18:25.6803735Z uses-permission: name='android.permission.BLUETOOTH_CONNECT'
2026-08-01T04:18:25.6804520Z uses-permission: name='android.permission.NEARBY_WIFI_DEVICES'
2026-08-01T04:18:25.6805263Z uses-permission: name='android.permission.ACCESS_WIFI_STATE'
2026-08-01T04:18:25.6806012Z uses-permission: name='android.permission.CHANGE_WIFI_STATE'
2026-08-01T04:18:25.6806762Z uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
2026-08-01T04:18:25.6807618Z uses-permission: name='android.permission.READ_EXTERNAL_STORAGE' maxSdkVersion='32'
2026-08-01T04:18:25.6808466Z uses-permission: name='android.permission.WAKE_LOCK'
2026-08-01T04:18:25.6809344Z uses-permission: name='android.permission.FOREGROUND_SERVICE'
2026-08-01T04:18:25.6810136Z uses-permission: name='android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'
2026-08-01T04:18:25.6811086Z uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='28'
2026-08-01T04:18:25.6811986Z uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'
2026-08-01T04:18:25.6812762Z uses-permission: name='android.permission.POST_NOTIFICATIONS'
2026-08-01T04:18:25.6813490Z uses-permission: name='android.permission.INSTALL_PACKAGES'
2026-08-01T04:18:25.6814352Z uses-permission: name='com.example.chernogram.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
2026-08-01T04:18:25.6815312Z uses-permission: name='android.permission.MODIFY_AUDIO_SETTINGS'
2026-08-01T04:18:25.6816234Z application-label:'Чернограм'
2026-08-01T04:18:25.6816766Z application-label-af:'Чернограм'
2026-08-01T04:18:25.6817292Z application-label-am:'Чернограм'
2026-08-01T04:18:25.6818105Z application-label-ar:'Чернограм'
2026-08-01T04:18:25.6818591Z application-label-as:'Чернограм'
2026-08-01T04:18:25.6819295Z application-label-az:'Чернограм'
2026-08-01T04:18:25.6819825Z application-label-be:'Чернограм'
2026-08-01T04:18:25.6820345Z application-label-bg:'Чернограм'
2026-08-01T04:18:25.6820864Z application-label-bn:'Чернограм'
2026-08-01T04:18:25.6821399Z application-label-bs:'Чернограм'
2026-08-01T04:18:25.6821933Z application-label-ca:'Чернограм'
2026-08-01T04:18:25.6822455Z application-label-cs:'Чернограм'
2026-08-01T04:18:25.6822978Z application-label-da:'Чернограм'
2026-08-01T04:18:25.6823502Z application-label-de:'Чернограм'
2026-08-01T04:18:25.6824053Z application-label-el:'Чернограм'
2026-08-01T04:18:25.6824622Z application-label-en-AU:'Чернограм'
2026-08-01T04:18:25.6825183Z application-label-en-CA:'Чернограм'
2026-08-01T04:18:25.6825737Z application-label-en-GB:'Чернограм'
2026-08-01T04:18:25.6826324Z application-label-en-IN:'Чернограм'
2026-08-01T04:18:25.6826885Z application-label-en-XC:'Чернограм'
2026-08-01T04:18:25.6827417Z application-label-es:'Чернограм'
2026-08-01T04:18:25.6827938Z application-label-es-US:'Чернограм'
2026-08-01T04:18:25.6828549Z application-label-et:'Чернограм'
2026-08-01T04:18:25.6829361Z application-label-eu:'Чернограм'
2026-08-01T04:18:25.6829886Z application-label-fa:'Чернограм'
2026-08-01T04:18:25.6830408Z application-label-fi:'Чернограм'
2026-08-01T04:18:25.6830917Z application-label-fr:'Чернограм'
2026-08-01T04:18:25.6831432Z application-label-fr-CA:'Чернограм'
2026-08-01T04:18:25.6831963Z application-label-gl:'Чернограм'
2026-08-01T04:18:25.6832571Z application-label-gu:'Чернограм'
2026-08-01T04:18:25.6833138Z application-label-hi:'Чернограм'
2026-08-01T04:18:25.6833671Z application-label-hr:'Чернограм'
2026-08-01T04:18:25.6834192Z application-label-hu:'Чернограм'
2026-08-01T04:18:25.6834719Z application-label-hy:'Чернограм'
2026-08-01T04:18:25.6835241Z application-label-in:'Чернограм'
2026-08-01T04:18:25.6835861Z application-label-is:'Чернограм'
2026-08-01T04:18:25.6836438Z application-label-it:'Чернограм'
2026-08-01T04:18:25.6836969Z application-label-iw:'Чернограм'
2026-08-01T04:18:25.6837723Z application-label-ja:'Чернограм'
2026-08-01T04:18:25.6838279Z application-label-ka:'Чернограм'
2026-08-01T04:18:25.6838803Z application-label-kk:'Чернограм'
2026-08-01T04:18:25.6839584Z application-label-km:'Чернограм'
2026-08-01T04:18:25.6840099Z application-label-kn:'Чернограм'
2026-08-01T04:18:25.6840614Z application-label-ko:'Чернограм'
2026-08-01T04:18:25.6841125Z application-label-ky:'Чернограм'
2026-08-01T04:18:25.6841639Z application-label-lo:'Чернограм'
2026-08-01T04:18:25.6842142Z application-label-lt:'Чернограм'
2026-08-01T04:18:25.6842640Z application-label-lv:'Чернограм'
2026-08-01T04:18:25.6843142Z application-label-mk:'Чернограм'
2026-08-01T04:18:25.6843631Z application-label-ml:'Чернограм'
2026-08-01T04:18:25.6844290Z application-label-mn:'Чернограм'
2026-08-01T04:18:25.6844813Z application-label-mr:'Чернограм'
2026-08-01T04:18:25.6845343Z application-label-ms:'Чернограм'
2026-08-01T04:18:25.6845859Z application-label-my:'Чернограм'
2026-08-01T04:18:25.6846357Z application-label-nb:'Чернограм'
2026-08-01T04:18:25.6846882Z application-label-ne:'Чернограм'
2026-08-01T04:18:25.6847390Z application-label-nl:'Чернограм'
2026-08-01T04:18:25.6847904Z application-label-or:'Чернограм'
2026-08-01T04:18:25.6848412Z application-label-pa:'Чернограм'
2026-08-01T04:18:25.6849661Z application-label-pl:'Чернограм'
2026-08-01T04:18:25.6850259Z application-label-pt:'Чернограм'
2026-08-01T04:18:25.6850805Z application-label-pt-BR:'Чернограм'
2026-08-01T04:18:25.6855413Z application-label-pt-PT:'Чернограм'
2026-08-01T04:18:25.6855980Z application-label-ro:'Чернограм'
2026-08-01T04:18:25.6856529Z application-label-ru:'Чернограм'
2026-08-01T04:18:25.6857063Z application-label-si:'Чернограм'
2026-08-01T04:18:25.6857596Z application-label-sk:'Чернограм'
2026-08-01T04:18:25.6858129Z application-label-sl:'Чернограм'
2026-08-01T04:18:25.6859178Z application-label-sq:'Чернограм'
2026-08-01T04:18:25.6859728Z application-label-sr:'Чернограм'
2026-08-01T04:18:25.6860263Z application-label-sr-Latn:'Чернограм'
2026-08-01T04:18:25.6860842Z application-label-sv:'Чернограм'
2026-08-01T04:18:25.6861370Z application-label-sw:'Чернограм'
2026-08-01T04:18:25.6861896Z application-label-ta:'Чернограм'
2026-08-01T04:18:25.6862431Z application-label-te:'Чернограм'
2026-08-01T04:18:25.6862969Z application-label-th:'Чернограм'
2026-08-01T04:18:25.6863489Z application-label-tl:'Чернограм'
2026-08-01T04:18:25.6863999Z application-label-tr:'Чернограм'
2026-08-01T04:18:25.6864535Z application-label-uk:'Чернограм'
2026-08-01T04:18:25.6865085Z application-label-ur:'Чернограм'
2026-08-01T04:18:25.6865622Z application-label-uz:'Чернограм'
2026-08-01T04:18:25.6866154Z application-label-vi:'Чернограм'
2026-08-01T04:18:25.6866704Z application-label-zh-CN:'Чернограм'
2026-08-01T04:18:25.6867292Z application-label-zh-HK:'Чернограм'
2026-08-01T04:18:25.6867870Z application-label-zh-TW:'Чернограм'
2026-08-01T04:18:25.6868474Z application-label-zu:'Чернограм'
2026-08-01T04:18:25.6869203Z application-icon-160:'res/Cf.xml'
2026-08-01T04:18:25.6869757Z application-icon-240:'res/Cf.xml'
2026-08-01T04:18:25.6870243Z application-icon-320:'res/Cf.xml'
2026-08-01T04:18:25.6870710Z application-icon-480:'res/Cf.xml'
2026-08-01T04:18:25.6871172Z application-icon-640:'res/Cf.xml'
2026-08-01T04:18:25.6871781Z application: label='Чернограм' icon='res/Cf.xml'
2026-08-01T04:18:25.6872608Z launchable-activity: name='com.example.chernogram.MainActivity'  label='' icon=''
2026-08-01T04:18:25.6873521Z uses-library-not-required:'androidx.window.extensions'
2026-08-01T04:18:25.6874237Z uses-library-not-required:'androidx.window.sidecar'
2026-08-01T04:18:25.6874834Z feature-group: label=''
2026-08-01T04:18:25.6875391Z   uses-feature-not-required: name='android.hardware.camera'
2026-08-01T04:18:25.6876117Z   uses-feature: name='android.hardware.camera.any'
2026-08-01T04:18:25.6876771Z   uses-feature: name='android.hardware.bluetooth'
2026-08-01T04:18:25.6878744Z   uses-implied-feature: name='android.hardware.bluetooth' reason='requested android.permission.BLUETOOTH permission, requested android.permission.BLUETOOTH_ADMIN permission, and targetSdkVersion > 4'
2026-08-01T04:18:25.6880727Z   uses-feature: name='android.hardware.faketouch'
2026-08-01T04:18:25.6881711Z   uses-implied-feature: name='android.hardware.faketouch' reason='default feature for all apps'
2026-08-01T04:18:25.6882692Z   uses-feature: name='android.hardware.microphone'
2026-08-01T04:18:25.6883831Z   uses-implied-feature: name='android.hardware.microphone' reason='requested android.permission.RECORD_AUDIO permission'
2026-08-01T04:18:25.6884972Z   uses-feature: name='android.hardware.wifi'
2026-08-01T04:18:25.6886502Z   uses-implied-feature: name='android.hardware.wifi' reason='requested android.permission.ACCESS_WIFI_STATE permission, and requested android.permission.CHANGE_WIFI_STATE permission'
2026-08-01T04:18:25.6887962Z main
2026-08-01T04:18:25.6888302Z other-activities
2026-08-01T04:18:25.6888676Z other-receivers
2026-08-01T04:18:25.6889235Z other-services
2026-08-01T04:18:25.6889693Z supports-screens: 'small' 'normal' 'large' 'xlarge'
2026-08-01T04:18:25.6890294Z supports-any-density: 'true'
2026-08-01T04:18:25.6896988Z locales: '--_--' 'af' 'am' 'ar' 'as' 'az' 'be' 'bg' 'bn' 'bs' 'ca' 'cs' 'da' 'de' 'el' 'en-AU' 'en-CA' 'en-GB' 'en-IN' 'en-XC' 'es' 'es-US' 'et' 'eu' 'fa' 'fi' 'fr' 'fr-CA' 'gl' 'gu' 'hi' 'hr' 'hu' 'hy' 'in' 'is' 'it' 'iw' 'ja' 'ka' 'kk' 'km' 'kn' 'ko' 'ky' 'lo' 'lt' 'lv' 'mk' 'ml' 'mn' 'mr' 'ms' 'my' 'nb' 'ne' 'nl' 'or' 'pa' 'pl' 'pt' 'pt-BR' 'pt-PT' 'ro' 'ru' 'si' 'sk' 'sl' 'sq' 'sr' 'sr-Latn' 'sv' 'sw' 'ta' 'te' 'th' 'tl' 'tr' 'uk' 'ur' 'uz' 'vi' 'zh-CN' 'zh-HK' 'zh-TW' 'zu'
2026-08-01T04:18:25.6899482Z densities: '160' '240' '320' '480' '640'
2026-08-01T04:18:25.6900035Z native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'
2026-08-01T04:18:26.1368368Z 377a7e495d9dc8a545c152c69c21d9a5f445d363774221ff651f6ec85b27ed97  chernogram.apk
2026-08-01T04:18:26.1487799Z ##[group]Run set -euo pipefail
2026-08-01T04:18:26.1488419Z [36;1mset -euo pipefail[0m
2026-08-01T04:18:26.1489196Z [36;1mAPK_SHA=$(awk '{print $1}' apk-sha256.txt)[0m
2026-08-01T04:18:26.1489754Z [36;1mcat > update.json <<EOF[0m
2026-08-01T04:18:26.1490180Z [36;1m{[0m
2026-08-01T04:18:26.1490546Z [36;1m  "versionName": "${VERSION_NAME}",[0m
2026-08-01T04:18:26.1491061Z [36;1m  "versionCode": ${VERSION_CODE},[0m
2026-08-01T04:18:26.1492106Z [36;1m  "apkUrl": "https://github.com/jeep-jim/chernogram_new/releases/download/${RELEASE_TAG}/chernogram.apk?v=${VERSION_CODE}",[0m
2026-08-01T04:18:26.1493127Z [36;1m  "sha256": "${APK_SHA}",[0m
2026-08-01T04:18:26.1493632Z [36;1m  "certificateSha256": "${CERT_SHA256}",[0m
2026-08-01T04:18:26.1497514Z [36;1m  "notesRu": "Чернограм 0.24.0 возвращает проверенный сервер-независимый чат и аудио- и видеозвонки. Собственный сервер, Gateway и VPS не требуются. Сохранены текущий интерфейс, локальная история, файлы и плеер.",[0m
2026-08-01T04:18:26.1500360Z [36;1m  "notesEn": "Chernogram 0.24.0 restores verified server-independent chat and audio/video calls. No private server, Gateway or VPS is required. The current interface, local history, files and player are preserved."[0m
2026-08-01T04:18:26.1502016Z [36;1m}[0m
2026-08-01T04:18:26.1502351Z [36;1mEOF[0m
2026-08-01T04:18:26.1502792Z [36;1mpython -m json.tool update.json >/dev/null[0m
2026-08-01T04:18:26.1503409Z [36;1mgrep -q '"versionCode": 60' update.json[0m
2026-08-01T04:18:26.1504087Z [36;1mcp update.json /tmp/chernogram-update-build60.json[0m
2026-08-01T04:18:26.2259755Z shell: /usr/bin/bash --noprofile --norc -e -o pipefail {0}
2026-08-01T04:18:26.2260156Z env:
2026-08-01T04:18:26.2260434Z   WORKING_REF: 6847a3d4e6ade48ca139c6560c036540865b8bf8
2026-08-01T04:18:26.2260781Z   SOURCE_VERSION: 0.24.0+56
2026-08-01T04:18:26.2261032Z   VERSION_FULL: 0.24.0+60
2026-08-01T04:18:26.2261278Z   VERSION_NAME: 0.24.0
2026-08-01T04:18:26.2261507Z   VERSION_CODE: 60
2026-08-01T04:18:26.2261788Z   RELEASE_TAG: chernogram-0.24.0-build60
2026-08-01T04:18:26.2262088Z   FLUTTER_VERSION: 3.44.8
2026-08-01T04:18:26.2262492Z   CERT_SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
2026-08-01T04:18:26.2263068Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:26.2263602Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:26.2264107Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.44.8-x64/flutter
2026-08-01T04:18:26.2264494Z   PUB_CACHE: /home/runner/.pub-cache
2026-08-01T04:18:26.2264763Z ##[endgroup]
2026-08-01T04:18:26.3399311Z ##[group]Run set -euo pipefail
2026-08-01T04:18:26.3400119Z [36;1mset -euo pipefail[0m
2026-08-01T04:18:26.3400758Z [36;1mgh release delete "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --cleanup-tag --yes || true[0m
2026-08-01T04:18:26.3401721Z [36;1mgh release create "$RELEASE_TAG" \[0m
2026-08-01T04:18:26.3402318Z [36;1m  chernogram.apk \[0m
2026-08-01T04:18:26.3402811Z [36;1m  update.json \[0m
2026-08-01T04:18:26.3403334Z [36;1m  apk-sha256.txt \[0m
2026-08-01T04:18:26.3403880Z [36;1m  apk-signature.txt \[0m
2026-08-01T04:18:26.3404468Z [36;1m  apk-badging.txt \[0m
2026-08-01T04:18:26.3405124Z [36;1m  --repo "$GITHUB_REPOSITORY" \[0m
2026-08-01T04:18:26.3405758Z [36;1m  --target "$WORKING_REF" \[0m
2026-08-01T04:18:26.3406203Z [36;1m  --title "Чернограм 0.24.0+60 — локальный чат и видеозвонки" \[0m
2026-08-01T04:18:26.3406906Z [36;1m  --notes "Рабочая сервер-независимая версия. Собственный сервер, Gateway и VPS не требуются." \[0m
2026-08-01T04:18:26.3407807Z [36;1m  --prerelease[0m
2026-08-01T04:18:26.3408517Z [36;1mgh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null[0m
2026-08-01T04:18:26.3479859Z shell: /usr/bin/bash --noprofile --norc -e -o pipefail {0}
2026-08-01T04:18:26.3480480Z env:
2026-08-01T04:18:26.3480926Z   WORKING_REF: 6847a3d4e6ade48ca139c6560c036540865b8bf8
2026-08-01T04:18:26.3481775Z   SOURCE_VERSION: 0.24.0+56
2026-08-01T04:18:26.3482038Z   VERSION_FULL: 0.24.0+60
2026-08-01T04:18:26.3482282Z   VERSION_NAME: 0.24.0
2026-08-01T04:18:26.3482502Z   VERSION_CODE: 60
2026-08-01T04:18:26.3482736Z   RELEASE_TAG: chernogram-0.24.0-build60
2026-08-01T04:18:26.3483021Z   FLUTTER_VERSION: 3.44.8
2026-08-01T04:18:26.3483415Z   CERT_SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
2026-08-01T04:18:26.3484223Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:26.3485153Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:26.3485999Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.44.8-x64/flutter
2026-08-01T04:18:26.3486637Z   PUB_CACHE: /home/runner/.pub-cache
2026-08-01T04:18:26.3493130Z   GH_TOKEN: ***
2026-08-01T04:18:26.3493410Z ##[endgroup]
2026-08-01T04:18:26.7000238Z release not found
2026-08-01T04:18:30.8403660Z https://github.com/jeep-jim/chernogram_new/releases/tag/chernogram-0.24.0-build60
2026-08-01T04:18:31.0336555Z ##[group]Run set -euo pipefail
2026-08-01T04:18:31.0337143Z [36;1mset -euo pipefail[0m
2026-08-01T04:18:31.0337606Z [36;1mSUCCESS=0[0m
2026-08-01T04:18:31.0338002Z [36;1mfor ATTEMPT in 1 2 3 4 5; do[0m
2026-08-01T04:18:31.0338481Z [36;1m  git fetch origin main[0m
2026-08-01T04:18:31.0339287Z [36;1m  git checkout -B publish-build60 origin/main[0m
2026-08-01T04:18:31.0340006Z [36;1m  cp /tmp/chernogram-update-build60.json update.json[0m
2026-08-01T04:18:31.0340696Z [36;1m  cat > WORKING_SERVERLESS_024_STATUS.md <<EOF[0m
2026-08-01T04:18:31.0341431Z [36;1mChernogram server-independent Android release published[0m
2026-08-01T04:18:31.0342097Z [36;1mVersion: ${VERSION_FULL}[0m
2026-08-01T04:18:31.0342598Z [36;1mSource: ${WORKING_REF}[0m
2026-08-01T04:18:31.0342971Z [36;1mRelease tag: ${RELEASE_TAG}[0m
2026-08-01T04:18:31.0343303Z [36;1mChat: encrypted public HTTPS/WSS relay[0m
2026-08-01T04:18:31.0343662Z [36;1mCalls: WebRTC with public STUN/TURN[0m
2026-08-01T04:18:31.0344020Z [36;1mPrivate server or Gateway: not required[0m
2026-08-01T04:18:31.0344339Z [36;1mUpdate channel: main/update.json[0m
2026-08-01T04:18:31.0344652Z [36;1mTime: $(date -u +'%Y-%m-%dT%H:%M:%SZ')[0m
2026-08-01T04:18:31.0344936Z [36;1mEOF[0m
2026-08-01T04:18:31.0345186Z [36;1m  git config user.name "github-actions[bot]"[0m
2026-08-01T04:18:31.0345646Z [36;1m  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"[0m
2026-08-01T04:18:31.0346136Z [36;1m  git add update.json WORKING_SERVERLESS_024_STATUS.md[0m
2026-08-01T04:18:31.0346582Z [36;1m  git commit -m "Включить обновление Чернограма 0.24.0+60 [skip ci]"[0m
2026-08-01T04:18:31.0346987Z [36;1m  if git push origin HEAD:main; then[0m
2026-08-01T04:18:31.0347281Z [36;1m    SUCCESS=1[0m
2026-08-01T04:18:31.0347510Z [36;1m    break[0m
2026-08-01T04:18:31.0347713Z [36;1m  fi[0m
2026-08-01T04:18:31.0347998Z [36;1m  echo "main изменился во время публикации, повтор ${ATTEMPT}/5"[0m
2026-08-01T04:18:31.0348592Z [36;1m  sleep 3[0m
2026-08-01T04:18:31.0348804Z [36;1mdone[0m
2026-08-01T04:18:31.0349293Z [36;1mtest "$SUCCESS" = "1"[0m
2026-08-01T04:18:31.0404941Z shell: /usr/bin/bash --noprofile --norc -e -o pipefail {0}
2026-08-01T04:18:31.0405300Z env:
2026-08-01T04:18:31.0405562Z   WORKING_REF: 6847a3d4e6ade48ca139c6560c036540865b8bf8
2026-08-01T04:18:31.0405887Z   SOURCE_VERSION: 0.24.0+56
2026-08-01T04:18:31.0406131Z   VERSION_FULL: 0.24.0+60
2026-08-01T04:18:31.0406360Z   VERSION_NAME: 0.24.0
2026-08-01T04:18:31.0406580Z   VERSION_CODE: 60
2026-08-01T04:18:31.0406812Z   RELEASE_TAG: chernogram-0.24.0-build60
2026-08-01T04:18:31.0407092Z   FLUTTER_VERSION: 3.44.8
2026-08-01T04:18:31.0407478Z   CERT_SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
2026-08-01T04:18:31.0408006Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:31.0408534Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:31.0409250Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.44.8-x64/flutter
2026-08-01T04:18:31.0409640Z   PUB_CACHE: /home/runner/.pub-cache
2026-08-01T04:18:31.0409918Z ##[endgroup]
2026-08-01T04:18:31.1732003Z From https://github.com/jeep-jim/chernogram_new
2026-08-01T04:18:31.1732623Z  * branch            main       -> FETCH_HEAD
2026-08-01T04:18:31.5758079Z error: Your local changes to the following files would be overwritten by checkout:
2026-08-01T04:18:31.5759153Z 	pubspec.yaml
2026-08-01T04:18:31.5759572Z 	update.json
2026-08-01T04:18:31.5760147Z Please commit your changes or stash them before you switch branches.
2026-08-01T04:18:31.5760841Z Aborting
2026-08-01T04:18:31.5776836Z ##[error]Process completed with exit code 1.
2026-08-01T04:18:31.5853390Z Node 20 is being deprecated. This workflow is running with Node 24 by default. If you need to temporarily use Node 20, you can set the ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true environment variable. For more information see: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/
2026-08-01T04:18:31.5854707Z ##[group]Run actions/upload-artifact@v4
2026-08-01T04:18:31.5854990Z with:
2026-08-01T04:18:31.5855223Z   name: chernogram-0.24.0-build60-published
2026-08-01T04:18:31.5855869Z   path: chernogram.apk
update.json
published-update.json
apk-signature.txt
apk-badging.txt
apk-sha256.txt
publish-0240-build60.log

2026-08-01T04:18:31.5856481Z   if-no-files-found: warn
2026-08-01T04:18:31.5856723Z   retention-days: 14
2026-08-01T04:18:31.5856949Z   compression-level: 6
2026-08-01T04:18:31.5857183Z   overwrite: false
2026-08-01T04:18:31.5857412Z   include-hidden-files: false
2026-08-01T04:18:31.5857656Z env:
2026-08-01T04:18:31.5857916Z   WORKING_REF: 6847a3d4e6ade48ca139c6560c036540865b8bf8
2026-08-01T04:18:31.5858241Z   SOURCE_VERSION: 0.24.0+56
2026-08-01T04:18:31.5858479Z   VERSION_FULL: 0.24.0+60
2026-08-01T04:18:31.5858712Z   VERSION_NAME: 0.24.0
2026-08-01T04:18:31.5859150Z   VERSION_CODE: 60
2026-08-01T04:18:31.5859405Z   RELEASE_TAG: chernogram-0.24.0-build60
2026-08-01T04:18:31.5859695Z   FLUTTER_VERSION: 3.44.8
2026-08-01T04:18:31.5860068Z   CERT_SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
2026-08-01T04:18:31.5860602Z   JAVA_HOME: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:31.5861101Z   JAVA_HOME_17_X64: /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk/17.0.19-10/x64
2026-08-01T04:18:31.5861584Z   FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.44.8-x64/flutter
2026-08-01T04:18:31.5861960Z   PUB_CACHE: /home/runner/.pub-cache
2026-08-01T04:18:31.5862222Z ##[endgroup]
2026-08-01T04:18:31.9317517Z (node:3622) [DEP0040] DeprecationWarning: The `punycode` module is deprecated. Please use a userland alternative instead.
2026-08-01T04:18:31.9319108Z (Use `node --trace-deprecation ...` to show where the warning was created)
2026-08-01T04:18:31.9444438Z Multiple search paths detected. Calculating the least common ancestor of all paths
2026-08-01T04:18:31.9449761Z The least common ancestor is /home/runner/work/chernogram_new/chernogram_new. This will be the root directory of the artifact
2026-08-01T04:18:31.9450866Z With the provided path, there will be 6 files uploaded
2026-08-01T04:18:31.9451686Z Artifact name is valid!
2026-08-01T04:18:31.9452088Z Root directory input is valid!
2026-08-01T04:18:32.0906015Z Beginning upload of artifact content to blob storage
2026-08-01T04:18:32.6145611Z (node:3622) [DEP0169] DeprecationWarning: `url.parse()` behavior is not standardized and prone to errors that have security implications. Use the WHATWG URL API instead. CVEs are not issued for `url.parse()` vulnerabilities.
2026-08-01T04:18:32.7574619Z Uploaded bytes 8388608
2026-08-01T04:18:33.3317621Z Uploaded bytes 16777216
2026-08-01T04:18:33.9127719Z Uploaded bytes 25165824
2026-08-01T04:18:34.3581143Z Uploaded bytes 33554432
2026-08-01T04:18:34.9657817Z Uploaded bytes 41943040
2026-08-01T04:18:35.6481071Z Uploaded bytes 50331648
2026-08-01T04:18:36.0099655Z Uploaded bytes 55873405
2026-08-01T04:18:36.0629851Z Finished uploading artifact content to blob storage!
2026-08-01T04:18:36.0634368Z SHA256 digest of uploaded artifact zip is 12bb6fde1fa54074ca9d960f77c660168b06a868bf87fe30b0e1c46147d08b15
2026-08-01T04:18:36.0637596Z Finalizing artifact upload
2026-08-01T04:18:36.2103049Z Artifact chernogram-0.24.0-build60-published.zip successfully finalized. Artifact ID 8813155803
2026-08-01T04:18:36.2104502Z Artifact chernogram-0.24.0-build60-published has been successfully uploaded! Final size is 55873405 bytes. Artifact ID is 8813155803
2026-08-01T04:18:36.2113245Z Artifact download URL: https://github.com/jeep-jim/chernogram_new/actions/runs/30683463822/artifacts/8813155803
2026-08-01T04:18:36.2413568Z Post job cleanup.
2026-08-01T04:18:36.2417709Z ##[start-action display=Cache pub dependencies;id=__b716b3e5-2328-4c7c-8805-e6a2bf82ca9e.cache-pub]
2026-08-01T04:18:36.2420254Z ##[end-action id=__b716b3e5-2328-4c7c-8805-e6a2bf82ca9e.cache-pub;outcome=skipped;conclusion=skipped;duration_ms=0]
2026-08-01T04:18:36.2422215Z ##[start-action display=Cache Flutter;id=__b716b3e5-2328-4c7c-8805-e6a2bf82ca9e.cache-flutter]
2026-08-01T04:18:36.2424185Z ##[end-action id=__b716b3e5-2328-4c7c-8805-e6a2bf82ca9e.cache-flutter;outcome=skipped;conclusion=skipped;duration_ms=0]
2026-08-01T04:18:36.2487836Z Node 20 is being deprecated. This workflow is running with Node 24 by default. If you need to temporarily use Node 20, you can set the ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true environment variable. For more information see: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/
2026-08-01T04:18:36.2489489Z Post job cleanup.
2026-08-01T04:18:36.4156113Z (node:3634) [DEP0040] DeprecationWarning: The `punycode` module is deprecated. Please use a userland alternative instead.
2026-08-01T04:18:36.4157818Z (Use `node --trace-deprecation ...` to show where the warning was created)
2026-08-01T04:18:36.4417032Z Node 20 is being deprecated. This workflow is running with Node 24 by default. If you need to temporarily use Node 20, you can set the ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION=true environment variable. For more information see: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/
2026-08-01T04:18:36.4419458Z Post job cleanup.
2026-08-01T04:18:36.5581687Z [command]/usr/bin/git version
2026-08-01T04:18:36.5653938Z git version 2.54.0
2026-08-01T04:18:36.5706235Z Temporarily overriding HOME='/home/runner/work/_temp/73f13670-3c30-4142-a50d-1b18757b54d2' before making global git config changes
2026-08-01T04:18:36.5707751Z Adding repository directory to the temporary git global config as a safe directory
2026-08-01T04:18:36.5713530Z [command]/usr/bin/git config --global --add safe.directory /home/runner/work/chernogram_new/chernogram_new
2026-08-01T04:18:36.5775384Z [command]/usr/bin/git config --local --name-only --get-regexp core\.sshCommand
2026-08-01T04:18:36.5863805Z [command]/usr/bin/git submodule foreach --recursive sh -c "git config --local --name-only --get-regexp 'core\.sshCommand' && git config --local --unset-all 'core.sshCommand' || :"
2026-08-01T04:18:36.6305911Z [command]/usr/bin/git config --local --name-only --get-regexp http\.https\:\/\/github\.com\/\.extraheader
2026-08-01T04:18:36.6339505Z http.https://github.com/.extraheader
2026-08-01T04:18:36.6353253Z [command]/usr/bin/git config --local --unset-all http.https://github.com/.extraheader
2026-08-01T04:18:36.6406297Z [command]/usr/bin/git submodule foreach --recursive sh -c "git config --local --name-only --get-regexp 'http\.https\:\/\/github\.com\/\.extraheader' && git config --local --unset-all 'http.https://github.com/.extraheader' || :"
2026-08-01T04:18:36.6770792Z [command]/usr/bin/git config --local --name-only --get-regexp ^includeIf\.gitdir:
2026-08-01T04:18:36.6819746Z [command]/usr/bin/git submodule foreach --recursive git config --local --show-origin --name-only --get-regexp remote.origin.url
2026-08-01T04:18:36.7282135Z Cleaning up orphan processes
2026-08-01T04:18:36.7757323Z Terminate orphan process: pid (2628) (java)
2026-08-01T04:18:36.7799941Z Terminate orphan process: pid (3091) (java)
2026-08-01T04:18:36.7825646Z ##[warning]Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to run on Node.js 24: actions/cache/restore@v4, actions/checkout@v4, actions/setup-java@v4, actions/upload-artifact@v4. For more information see: https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/
```
