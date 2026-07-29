# LiveKit Calls v1 CI failed

Commit: b1b15fa8516ac364625ee2ec139421e55a7d6b65
Time: 2026-07-29T07:06:21Z
Broker: success
Android: cancelled
Windows: cancelled

## android-ci.log
```text
LiveKit Calls v1 source materialized
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (6 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (5 days ago) • 2026-07-23 16:11:34.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
Resolving dependencies...
Downloading packages...
+ asn1lib 1.6.5
+ connectivity_plus 7.3.1
+ connectivity_plus_platform_interface 2.1.0
+ convert 3.1.2
+ dart_jsonwebtoken 3.4.1
  dbus 0.7.13 (0.7.14 available)
+ device_info_plus 12.4.0 (13.2.0 available)
+ device_info_plus_platform_interface 7.0.3 (8.1.0 available)
  file_picker 10.3.10 (11.0.2 available)
  flutter_contacts 1.1.9+2 (2.3.0 available)
  flutter_lints 3.0.2 (6.0.0 available)
  hooks 2.0.2 (2.1.0 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  lints 3.0.0 (6.1.0 available)
+ livekit_client 2.9.0
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
+ mime_type 1.0.1
+ nm 0.5.0
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 8.3.1 (10.2.1 available)
  package_info_plus_platform_interface 3.2.1 (4.1.0 available)
+ pointycastle 4.0.0
+ protobuf 6.0.0
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
+ sdp_transform 0.3.2
  share_plus 10.1.4 (13.3.0 available)
  share_plus_platform_interface 5.0.2 (7.2.0 available)
  test_api 0.7.11 (0.7.13 available)
  vector_math 2.2.0 (2.4.1 available)
  win32 5.15.0 (6.3.0 available)
+ win32_registry 2.1.0 (3.0.3 available)
Changed 14 dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Formatted lib/livekit_test_screen.dart
Formatted lib/v12.dart
Formatted 2 files (2 changed) in 0.09 seconds.
Analyzing chernogram_new...                                     

   info • 'localeId' is deprecated and shouldn't be used. Use SpeechListenOptions.localeId instead. Try replacing the use of the deprecated member with the replacement • lib/agent_screen.dart:249:7 • deprecated_member_use
   info • 'listenFor' is deprecated and shouldn't be used. Use SpeechListenOptions.listenFor instead. Try replacing the use of the deprecated member with the replacement • lib/agent_screen.dart:250:7 • deprecated_member_use
   info • 'pauseFor' is deprecated and shouldn't be used. Use SpeechListenOptions.pauseFor instead. Try replacing the use of the deprecated member with the replacement • lib/agent_screen.dart:251:7 • deprecated_member_use
   info • 'partialResults' is deprecated and shouldn't be used. Use SpeechListenOptions.partialResults instead. Try replacing the use of the deprecated member with the replacement • lib/agent_screen.dart:252:7 • deprecated_member_use
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/app_monitor.dart:301:9 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/call_service.dart:147:11 • curly_braces_in_flow_control_structures
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_media.dart:6:8 • unnecessary_import
warning • Unused import: 'dart:typed_data'. Try removing the import directive • lib/chat_screen.dart:4:8 • unused_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/chat_screen.dart:212:7 • curly_braces_in_flow_control_structures
warning • The declaration '_attachmentKind' isn't referenced. Try removing the declaration of '_attachmentKind' • lib/chat_screen.dart:1019:10 • unused_element
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1739:7 • use_build_context_synchronously
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1824:7 • use_build_context_synchronously
warning • Unused import: 'core_models.dart'. Try removing the import directive • lib/group_call_service.dart:8:8 • unused_import
   info • 'roomOptions' is deprecated and shouldn't be used. deprecated, please use roomOptions in Room constructor. Try replacing the use of the deprecated member with the replacement • lib/livekit_test_screen.dart:152:39 • deprecated_member_use
warning • Unused import: 'dart:io'. Try removing the import directive • lib/main.dart:3:8 • unused_import
warning • Unused import: 'desktop_tray_service.dart'. Try removing the import directive • lib/main.dart:15:8 • unused_import
warning • Unused import: 'notification_service.dart'. Try removing the import directive • lib/main.dart:16:8 • unused_import
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/main.dart:152:45 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/media_studio.dart:2:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/network_core.dart:394:9 • curly_braces_in_flow_control_structures
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/notification_service.dart:42:21 • prefer_const_constructors
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/notification_service.dart:116:21 • prefer_const_constructors
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/notification_service.dart:128:16 • prefer_const_constructors
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/permission_center.dart:22:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/tunnels.dart:1133:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:456:7 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:467:7 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/v06.dart:503:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:714:23 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1890:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1937:5 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1959:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1961:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v07.dart:388:11 • curly_braces_in_flow_control_structures
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/foundation.dart'. Try removing the import directive • lib/v12.dart:3:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v12.dart:258:9 • curly_braces_in_flow_control_structures

36 issues found. (ran in 16.4s)

✅ basic smoke test

🎉 1 test passed.
Running Gradle task 'assembleDebug'...                          ```

## broker-ci.log
```text
        target: 50049
        published: "50049"
        protocol: udp
      - mode: ingress
        target: 50050
        published: "50050"
        protocol: udp
      - mode: ingress
        target: 50051
        published: "50051"
        protocol: udp
      - mode: ingress
        target: 50052
        published: "50052"
        protocol: udp
      - mode: ingress
        target: 50053
        published: "50053"
        protocol: udp
      - mode: ingress
        target: 50054
        published: "50054"
        protocol: udp
      - mode: ingress
        target: 50055
        published: "50055"
        protocol: udp
      - mode: ingress
        target: 50056
        published: "50056"
        protocol: udp
      - mode: ingress
        target: 50057
        published: "50057"
        protocol: udp
      - mode: ingress
        target: 50058
        published: "50058"
        protocol: udp
      - mode: ingress
        target: 50059
        published: "50059"
        protocol: udp
      - mode: ingress
        target: 50060
        published: "50060"
        protocol: udp
      - mode: ingress
        target: 50061
        published: "50061"
        protocol: udp
      - mode: ingress
        target: 50062
        published: "50062"
        protocol: udp
      - mode: ingress
        target: 50063
        published: "50063"
        protocol: udp
      - mode: ingress
        target: 50064
        published: "50064"
        protocol: udp
      - mode: ingress
        target: 50065
        published: "50065"
        protocol: udp
      - mode: ingress
        target: 50066
        published: "50066"
        protocol: udp
      - mode: ingress
        target: 50067
        published: "50067"
        protocol: udp
      - mode: ingress
        target: 50068
        published: "50068"
        protocol: udp
      - mode: ingress
        target: 50069
        published: "50069"
        protocol: udp
      - mode: ingress
        target: 50070
        published: "50070"
        protocol: udp
      - mode: ingress
        target: 50071
        published: "50071"
        protocol: udp
      - mode: ingress
        target: 50072
        published: "50072"
        protocol: udp
      - mode: ingress
        target: 50073
        published: "50073"
        protocol: udp
      - mode: ingress
        target: 50074
        published: "50074"
        protocol: udp
      - mode: ingress
        target: 50075
        published: "50075"
        protocol: udp
      - mode: ingress
        target: 50076
        published: "50076"
        protocol: udp
      - mode: ingress
        target: 50077
        published: "50077"
        protocol: udp
      - mode: ingress
        target: 50078
        published: "50078"
        protocol: udp
      - mode: ingress
        target: 50079
        published: "50079"
        protocol: udp
      - mode: ingress
        target: 50080
        published: "50080"
        protocol: udp
      - mode: ingress
        target: 50081
        published: "50081"
        protocol: udp
      - mode: ingress
        target: 50082
        published: "50082"
        protocol: udp
      - mode: ingress
        target: 50083
        published: "50083"
        protocol: udp
      - mode: ingress
        target: 50084
        published: "50084"
        protocol: udp
      - mode: ingress
        target: 50085
        published: "50085"
        protocol: udp
      - mode: ingress
        target: 50086
        published: "50086"
        protocol: udp
      - mode: ingress
        target: 50087
        published: "50087"
        protocol: udp
      - mode: ingress
        target: 50088
        published: "50088"
        protocol: udp
      - mode: ingress
        target: 50089
        published: "50089"
        protocol: udp
      - mode: ingress
        target: 50090
        published: "50090"
        protocol: udp
      - mode: ingress
        target: 50091
        published: "50091"
        protocol: udp
      - mode: ingress
        target: 50092
        published: "50092"
        protocol: udp
      - mode: ingress
        target: 50093
        published: "50093"
        protocol: udp
      - mode: ingress
        target: 50094
        published: "50094"
        protocol: udp
      - mode: ingress
        target: 50095
        published: "50095"
        protocol: udp
      - mode: ingress
        target: 50096
        published: "50096"
        protocol: udp
      - mode: ingress
        target: 50097
        published: "50097"
        protocol: udp
      - mode: ingress
        target: 50098
        published: "50098"
        protocol: udp
      - mode: ingress
        target: 50099
        published: "50099"
        protocol: udp
      - mode: ingress
        target: 50100
        published: "50100"
        protocol: udp
    restart: unless-stopped
    volumes:
      - type: bind
        source: /home/runner/work/chernogram_new/chernogram_new/infra/livekit/livekit.yaml
        target: /etc/livekit.yaml
        read_only: true
        bind:
          create_host_path: true
  redis:
    command:
      - redis-server
      - --save
      - ""
      - --appendonly
      - "no"
    healthcheck:
      test:
        - CMD
        - redis-cli
        - ping
      timeout: 3s
      interval: 5s
      retries: 10
    image: redis:7.4-alpine
    networks:
      default: null
    restart: unless-stopped
networks:
  default:
    name: chernogram_new_default
#0 building with "default" instance using docker driver

#1 [internal] load build definition from Dockerfile
#1 transferring dockerfile: 508B done
#1 DONE 0.0s

#2 [internal] load metadata for docker.io/library/python:3.12-slim
#2 ...

#3 [auth] library/python:pull token for registry-1.docker.io
#3 DONE 0.0s

#2 [internal] load metadata for docker.io/library/python:3.12-slim
#2 DONE 1.2s

#4 [internal] load .dockerignore
#4 transferring context: 2B done
#4 DONE 0.0s

#5 [internal] load build context
#5 transferring context: 8.56kB done
#5 DONE 0.0s

#6 [1/5] FROM docker.io/library/python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de
#6 resolve docker.io/library/python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de done
#6 sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de 10.37kB / 10.37kB done
#6 sha256:cab2dbf575e971934a81e4622f5aba17aa7929719bd7e31033a3a83b97fd0464 1.75kB / 1.75kB done
#6 sha256:25c5b8011a3425a140bf5fa73be0feabd3c0d5b323eecb19dc02437a368ae075 5.66kB / 5.66kB done
#6 sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 0B / 29.78MB 0.1s
#6 sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea 0B / 1.29MB 0.1s
#6 sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 7.34MB / 12.11MB 0.1s
#6 sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 14.68MB / 29.78MB 0.2s
#6 sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 12.11MB / 12.11MB 0.1s done
#6 sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e 0B / 250B 0.2s
#6 extracting sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053
#6 sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 29.78MB / 29.78MB 0.2s done
#6 sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea 1.29MB / 1.29MB 0.2s done
#6 sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e 250B / 250B 0.2s done
#6 extracting sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 0.9s done
#6 extracting sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea
#6 extracting sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea 0.1s done
#6 extracting sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9
#6 extracting sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 0.5s done
#6 extracting sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e done
#6 DONE 2.4s

#7 [2/5] WORKDIR /app
#7 DONE 0.0s

#8 [3/5] COPY requirements.txt ./
#8 DONE 0.0s

#9 [4/5] RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt
#9 1.488 Collecting livekit-api==1.2.0 (from -r requirements.txt (line 1))
#9 1.561   Downloading livekit_api-1.2.0-py3-none-any.whl.metadata (1.4 kB)
#9 2.252 Collecting aiohttp>=3.9.0 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.273   Downloading aiohttp-3.14.3-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (8.3 kB)
#9 2.326 Collecting livekit-protocol<2.0.0,>=1.1.19 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.348   Downloading livekit_protocol-1.1.21-py3-none-any.whl.metadata (988 bytes)
#9 2.519 Collecting protobuf>=4 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.540   Downloading protobuf-7.35.1-cp310-abi3-manylinux2014_x86_64.whl.metadata (595 bytes)
#9 2.594 Collecting pyjwt>=2.0.0 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.615   Downloading pyjwt-2.13.0-py3-none-any.whl.metadata (3.4 kB)
#9 2.676 Collecting types-protobuf>=4 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.697   Downloading types_protobuf-7.34.1.20260518-py3-none-any.whl.metadata (2.2 kB)
#9 2.749 Collecting aiohappyeyeballs>=2.5.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.770   Downloading aiohappyeyeballs-2.7.1-py3-none-any.whl.metadata (5.9 kB)
#9 2.816 Collecting aiosignal>=1.4.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.839   Downloading aiosignal-1.4.0-py3-none-any.whl.metadata (3.7 kB)
#9 2.890 Collecting attrs>=17.3.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.911   Downloading attrs-26.1.0-py3-none-any.whl.metadata (8.8 kB)
#9 3.002 Collecting frozenlist>=1.1.1 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 3.024   Downloading frozenlist-1.8.0-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl.metadata (20 kB)
#9 3.275 Collecting multidict<7.0,>=4.5 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 3.296   Downloading multidict-6.7.1-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (5.3 kB)
#9 3.380 Collecting propcache>=0.2.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 3.402   Downloading propcache-0.5.2-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (16 kB)
#9 3.457 Collecting typing_extensions>=4.4 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 3.479   Downloading typing_extensions-4.16.0-py3-none-any.whl.metadata (3.3 kB)
#9 3.730 Collecting yarl<2.0,>=1.17.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 3.751   Downloading yarl-1.24.5-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (103 kB)
#9 3.868 Collecting idna>=2.0 (from yarl<2.0,>=1.17.0->aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 3.889   Downloading idna-3.18-py3-none-any.whl.metadata (6.1 kB)
#9 3.925 Downloading livekit_api-1.2.0-py3-none-any.whl (26 kB)
#9 3.946 Downloading aiohttp-3.14.3-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (1.8 MB)
#9 4.062    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 1.8/1.8 MB 20.3 MB/s eta 0:00:00
#9 4.085 Downloading livekit_protocol-1.1.21-py3-none-any.whl (149 kB)
#9 4.106 Downloading protobuf-7.35.1-cp310-abi3-manylinux2014_x86_64.whl (327 kB)
#9 4.128 Downloading pyjwt-2.13.0-py3-none-any.whl (31 kB)
#9 4.149 Downloading types_protobuf-7.34.1.20260518-py3-none-any.whl (85 kB)
#9 4.171 Downloading aiohappyeyeballs-2.7.1-py3-none-any.whl (15 kB)
#9 4.192 Downloading aiosignal-1.4.0-py3-none-any.whl (7.5 kB)
#9 4.214 Downloading attrs-26.1.0-py3-none-any.whl (67 kB)
#9 4.235 Downloading frozenlist-1.8.0-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl (242 kB)
#9 4.258 Downloading multidict-6.7.1-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (256 kB)
#9 4.279 Downloading propcache-0.5.2-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (61 kB)
#9 4.301 Downloading typing_extensions-4.16.0-py3-none-any.whl (45 kB)
#9 4.322 Downloading yarl-1.24.5-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (109 kB)
#9 4.342 Downloading idna-3.18-py3-none-any.whl (65 kB)
#9 4.386 Installing collected packages: typing_extensions, types-protobuf, pyjwt, protobuf, propcache, multidict, idna, frozenlist, attrs, aiohappyeyeballs, yarl, livekit-protocol, aiosignal, aiohttp, livekit-api
#9 4.983 Successfully installed aiohappyeyeballs-2.7.1 aiohttp-3.14.3 aiosignal-1.4.0 attrs-26.1.0 frozenlist-1.8.0 idna-3.18 livekit-api-1.2.0 livekit-protocol-1.1.21 multidict-6.7.1 propcache-0.5.2 protobuf-7.35.1 pyjwt-2.13.0 types-protobuf-7.34.1.20260518 typing_extensions-4.16.0 yarl-1.24.5
#9 4.983 WARNING: Running pip as the 'root' user can result in broken permissions and conflicting behaviour with the system package manager, possibly rendering your system unusable. It is recommended to use a virtual environment instead: https://pip.pypa.io/warnings/venv. Use the --root-user-action option if you know what you are doing and want to suppress this warning.
#9 DONE 5.1s

#10 [5/5] COPY broker.py ./
#10 DONE 0.0s

#11 exporting to image
#11 exporting layers
#11 exporting layers 0.9s done
#11 writing image sha256:609cbbf57031889716e5bc43739f814ee56ff9b910e3415ae50ee1f336eb56ab done
#11 naming to docker.io/library/cernogram-livekit-broker-ci done
#11 DONE 1.0s
```

## windows-ci.log
```text
===== Materialize LiveKit source =====
LiveKit Calls v1 source materialized
===== Flutter version =====
Building flutter tool... 
Running pub upgrade... 
Resolving dependencies...
Downloading packages...
Got dependencies.
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (6 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (5 days ago) • 2026-07-23 16:11:34.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
===== Enable Windows desktop =====
Setting "enable-windows-desktop" value to "true".

You may need to restart any open editors for them to read new settings.
===== Create Windows runner =====
Recreating project ....
  .idea\libraries\Dart_SDK.xml (created)
  .idea\libraries\KotlinJavaRuntime.xml (created)
  .idea\modules.xml (created)
  .idea\runConfigurations\main_dart.xml (created)
  .idea\workspace.xml (created)
  chernogram.iml (created)
  windows\.gitignore (created)
  windows\CMakeLists.txt (created)
  windows\flutter\CMakeLists.txt (created)
  windows\runner\CMakeLists.txt (created)
  windows\runner\flutter_window.cpp (created)
  windows\runner\flutter_window.h (created)
  windows\runner\main.cpp (created)
  windows\runner\resource.h (created)
  windows\runner\resources\app_icon.ico (created)
  windows\runner\runner.exe.manifest (created)
  windows\runner\Runner.rc (created)
  windows\runner\utils.cpp (created)
  windows\runner\utils.h (created)
  windows\runner\win32_window.cpp (created)
  windows\runner\win32_window.h (created)
Wrote 21 files.

All done!
You can find general documentation for Flutter at: https://docs.flutter.dev/
Detailed API documentation is available at: https://api.flutter.dev/
If you prefer video documentation, consider: https://www.youtube.com/c/flutterdev

In order to run your application, type:

  $ flutter run

Your application code is in .\lib\main.dart.

===== Flutter pub get =====
Resolving dependencies...
Downloading packages...
+ app_links 7.2.1
+ app_links_linux 1.0.3
+ app_links_platform_interface 2.0.4
+ app_links_web 1.0.4
+ archive 4.0.9
+ args 2.7.0
+ asn1lib 1.6.5
+ async 2.13.1
+ audio_service 0.18.19
+ audio_service_platform_interface 0.1.3
+ audio_service_web 0.1.4
+ audio_session 0.2.4
+ boolean_selector 2.1.2
+ camera 0.12.0+2
+ camera_android_camerax 0.7.4+2
+ camera_avfoundation 0.10.2
+ camera_platform_interface 2.13.1
+ camera_web 0.3.5+4
  characters 1.4.1 (from direct dependency to transitive dependency)
+ charcode 1.4.0
+ clock 1.1.2
+ code_assets 1.2.1
  collection 1.19.1 (from direct dependency to transitive dependency)
+ connectivity_plus 7.3.1
+ connectivity_plus_platform_interface 2.1.0
+ convert 3.1.2
+ cross_file 0.3.5+4
+ crypto 3.0.7
+ cryptography 2.9.0
+ csslib 1.0.2
+ dart_jsonwebtoken 3.4.1
+ dart_webrtc 1.8.1
+ dbus 0.7.13 (0.7.14 available)
+ desktop_drop 0.7.1
+ device_info_plus 12.4.0 (13.2.0 available)
+ device_info_plus_platform_interface 7.0.3 (8.1.0 available)
+ fake_async 1.3.3
+ ffi 2.2.0
+ file 7.0.1
+ file_picker 10.3.10 (11.0.2 available)
+ fixnum 1.1.1
+ flutter 0.0.0 from sdk flutter
+ flutter_background_service 5.1.0
+ flutter_background_service_android 6.3.1
+ flutter_background_service_ios 5.0.3
+ flutter_background_service_platform_interface 5.1.2
+ flutter_cache_manager 3.4.2
+ flutter_contacts 1.1.9+2 (2.3.0 available)
+ flutter_lints 3.0.2 (6.0.0 available)
+ flutter_local_notifications 22.2.0
+ flutter_local_notifications_linux 8.0.1
+ flutter_local_notifications_platform_interface 12.1.0
+ flutter_local_notifications_web 1.0.0
+ flutter_local_notifications_windows 3.1.1
+ flutter_plugin_android_lifecycle 2.0.35
+ flutter_test 0.0.0 from sdk flutter
+ flutter_tts 4.2.5
+ flutter_web_plugins 0.0.0 from sdk flutter
+ flutter_webrtc 1.5.2
+ gtk 2.2.0
+ hooks 2.0.2 (2.1.0 available)
+ html 0.15.6
+ http 1.6.0
+ http_parser 4.1.2
+ image 4.9.1
+ jni 1.0.2
+ jni_flutter 1.0.2
+ jni_util 1.0.0
+ js 0.7.2
+ json_annotation 4.12.0
+ just_audio 0.10.6
+ just_audio_background 0.0.1-beta.17
+ just_audio_platform_interface 4.6.0
+ just_audio_web 0.4.16
+ leak_tracker 11.0.2
+ leak_tracker_flutter_testing 3.0.10
+ leak_tracker_testing 3.0.2
+ lints 3.0.0 (6.1.0 available)
+ livekit_client 2.9.0
+ logger 2.7.0
+ logging 1.3.0
+ matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (from direct dependency to transitive dependency)
+ menu_base 0.1.1
  meta 1.18.0 (from direct dependency to transitive dependency) (1.19.0 available)
+ mime 2.0.0
+ mime_type 1.0.1
+ mobile_scanner 7.4.0
+ nm 0.5.0
+ objective_c 9.5.0
+ open_filex 4.7.0
+ ota_update 7.1.0
+ package_config 3.0.0
+ package_info_plus 8.3.1 (10.2.1 available)
+ package_info_plus_platform_interface 3.2.1 (4.1.0 available)
+ path 1.9.1
+ path_provider 2.1.6
+ path_provider_android 2.3.1
+ path_provider_foundation 2.6.0
+ path_provider_linux 2.2.2
+ path_provider_platform_interface 2.1.3
+ path_provider_windows 2.3.0
+ permission_handler 12.0.3
+ permission_handler_android 13.0.1
+ permission_handler_apple 9.4.10
+ permission_handler_html 0.1.3+5
+ permission_handler_platform_interface 4.3.0
+ permission_handler_windows 0.2.1
+ petitparser 7.0.2
+ photo_manager 3.11.0
+ platform 3.1.6
+ plugin_platform_interface 2.1.8
+ pointycastle 4.0.0
+ posix 6.5.2
+ protobuf 6.0.0
+ pub_semver 2.2.0
+ qr 3.0.2 (4.0.0 available)
+ qr_flutter 4.1.0
+ record 6.2.1 (7.1.1 available)
+ record_android 1.5.2 (2.1.2 available)
+ record_ios 1.2.1 (2.1.1 available)
+ record_linux 1.3.1 (2.1.1 available)
+ record_macos 1.2.2 (2.1.1 available)
+ record_platform_interface 1.6.0 (2.1.0 available)
+ record_use 0.6.0 (1.0.0 available)
+ record_web 1.3.0 (2.1.1 available)
+ record_windows 1.0.7 (2.2.2 available)
+ rxdart 0.28.0
+ screen_retriever 0.2.2
+ screen_retriever_linux 0.2.2
+ screen_retriever_macos 0.2.2
+ screen_retriever_platform_interface 0.2.2
+ screen_retriever_windows 0.2.2
+ sdp_transform 0.3.2
+ share_plus 10.1.4 (13.3.0 available)
+ share_plus_platform_interface 5.0.2 (7.2.0 available)
+ shared_preferences 2.5.5
+ shared_preferences_android 2.4.27
+ shared_preferences_foundation 2.5.6
+ shared_preferences_linux 2.4.1
+ shared_preferences_platform_interface 2.4.2
+ shared_preferences_web 2.4.3
+ shared_preferences_windows 2.4.1
+ shortid 0.1.2
+ sky_engine 0.0.0 from sdk flutter
+ source_span 1.10.2
+ speech_to_text 7.4.0
+ speech_to_text_platform_interface 2.4.0
+ speech_to_text_windows 1.0.1
+ sqflite 2.4.3
+ sqflite_android 2.4.3
+ sqflite_common 2.5.11
+ sqflite_darwin 2.4.3+1
+ sqflite_platform_interface 2.4.1
+ stack_trace 1.12.1
+ stream_channel 2.1.4
+ stream_transform 2.1.1
+ string_scanner 1.4.1
+ synchronized 3.4.1+1
+ term_glyph 1.2.2
+ test_api 0.7.11 (0.7.13 available)
+ timezone 0.11.1
+ tray_manager 0.5.3
+ typed_data 1.4.0
+ universal_platform 1.1.0
+ url_launcher 6.3.2
+ url_launcher_android 6.3.32
+ url_launcher_ios 6.4.1
+ url_launcher_linux 3.2.2
+ url_launcher_macos 3.2.5
+ url_launcher_platform_interface 2.3.2
+ url_launcher_web 2.4.3
+ url_launcher_windows 3.1.5
+ uuid 4.6.0
  vector_math 2.2.0 (from direct dependency to transitive dependency) (2.4.1 available)
+ video_player 2.13.0
+ video_player_android 2.12.0
+ video_player_avfoundation 2.11.0
+ video_player_platform_interface 6.9.0
+ video_player_web 2.4.0
+ vm_service 15.2.0
+ web 1.1.1
+ webrtc_interface 1.5.1
+ win32 5.15.0 (6.3.0 available)
+ win32_registry 2.1.0 (3.0.3 available)
+ window_manager 0.5.2
+ xdg_directories 1.1.0
+ xml 7.0.1
+ yaml 3.1.3
+ zxing2 0.2.4
Changed 190 dependencies!
28 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
===== Dart format =====
Formatted lib/livekit_test_screen.dart
Formatted lib/v12.dart
Formatted 2 files (2 changed) in 0.07 seconds.
===== Flutter analyze =====
```

