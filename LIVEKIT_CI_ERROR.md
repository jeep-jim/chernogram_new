# LiveKit Calls v1 CI failed

Commit: b410b9cb0473cb612858aa1a15400eeb124a92bf
Time: 2026-07-29T06:51:47Z
Broker: success
Android: failure
Windows: failure

## android-ci.log
```text
LiveKit Calls v1 source materialized
Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 058e0af2c2 (6 days ago) • 2026-07-23 10:56:21 -0700
Engine • hash 13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939 (revision 0cd610717b) (5 days ago) • 2026-07-23 16:11:34.000Z
Tools • Dart 3.12.2 • DevTools 2.57.0
Resolving dependencies...
Because livekit_client >=2.7.0 <2.9.0-dev.0 depends on flutter_webrtc 1.4.0 and chernogram depends on flutter_webrtc ^1.5.2, livekit_client >=2.7.0 <2.9.0-dev.0 is forbidden.
So, because chernogram depends on livekit_client 2.8.1, version solving failed.


You can try one of the following suggestions to make the pubspec resolve:
* Try upgrading your constraint on livekit_client: flutter pub add livekit_client:^2.9.0
* Consider downgrading your constraint on flutter_webrtc: flutter pub add flutter_webrtc:^1.4.0
Failed to update packages.
```

## broker-ci.log
```text
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
#2 DONE 0.8s

#4 [internal] load .dockerignore
#4 transferring context: 2B done
#4 DONE 0.0s

#5 [internal] load build context
#5 transferring context: 8.56kB done
#5 DONE 0.0s

#6 [1/5] FROM docker.io/library/python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de
#6 resolve docker.io/library/python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de done
#6 sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 7.34MB / 29.78MB 0.1s
#6 sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea 0B / 1.29MB 0.1s
#6 sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 0B / 12.11MB 0.1s
#6 sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de 10.37kB / 10.37kB done
#6 sha256:cab2dbf575e971934a81e4622f5aba17aa7929719bd7e31033a3a83b97fd0464 1.75kB / 1.75kB done
#6 sha256:25c5b8011a3425a140bf5fa73be0feabd3c0d5b323eecb19dc02437a368ae075 5.66kB / 5.66kB done
#6 sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 29.78MB / 29.78MB 0.3s
#6 sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea 1.29MB / 1.29MB 0.2s done
#6 sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 12.11MB / 12.11MB 0.3s
#6 sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e 250B / 250B 0.3s
#6 sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 29.78MB / 29.78MB 0.4s done
#6 sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 12.11MB / 12.11MB 0.4s done
#6 sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e 250B / 250B 0.4s done
#6 extracting sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 0.1s
#6 extracting sha256:062e450697faa5f02a3a74eba9864ee4d79bc9cfbd65769fc6cdff2c05c6a053 0.7s done
#6 extracting sha256:98db2485a0d07a8914586b02387e3813aa7e9fed79ab252898d3e96e21c717ea 0.1s done
#6 extracting sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9
#6 extracting sha256:48347b15c85fd6dde9c5b0259f378fbaee3ce231b30a42f2f2bcc4ea0285cbc9 0.4s done
#6 extracting sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e
#6 extracting sha256:fd079632edc0ab4e9d10c77ec348d5057a976e6fc508e93855548096dec2ae1e done
#6 DONE 8.6s

#7 [2/5] WORKDIR /app
#7 DONE 0.0s

#8 [3/5] COPY requirements.txt ./
#8 DONE 0.0s

#9 [4/5] RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt
#9 1.078 Collecting livekit-api==1.2.0 (from -r requirements.txt (line 1))
#9 1.118   Downloading livekit_api-1.2.0-py3-none-any.whl.metadata (1.4 kB)
#9 1.482 Collecting aiohttp>=3.9.0 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.492   Downloading aiohttp-3.14.3-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (8.3 kB)
#9 1.510 Collecting livekit-protocol<2.0.0,>=1.1.19 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.521   Downloading livekit_protocol-1.1.21-py3-none-any.whl.metadata (988 bytes)
#9 1.619 Collecting protobuf>=4 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.628   Downloading protobuf-7.35.1-cp310-abi3-manylinux2014_x86_64.whl.metadata (595 bytes)
#9 1.645 Collecting pyjwt>=2.0.0 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.654   Downloading pyjwt-2.13.0-py3-none-any.whl.metadata (3.4 kB)
#9 1.678 Collecting types-protobuf>=4 (from livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.687   Downloading types_protobuf-7.34.1.20260518-py3-none-any.whl.metadata (2.2 kB)
#9 1.703 Collecting aiohappyeyeballs>=2.5.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.713   Downloading aiohappyeyeballs-2.7.1-py3-none-any.whl.metadata (5.9 kB)
#9 1.725 Collecting aiosignal>=1.4.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.734   Downloading aiosignal-1.4.0-py3-none-any.whl.metadata (3.7 kB)
#9 1.750 Collecting attrs>=17.3.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.760   Downloading attrs-26.1.0-py3-none-any.whl.metadata (8.8 kB)
#9 1.803 Collecting frozenlist>=1.1.1 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.813   Downloading frozenlist-1.8.0-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl.metadata (20 kB)
#9 1.971 Collecting multidict<7.0,>=4.5 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 1.981   Downloading multidict-6.7.1-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (5.3 kB)
#9 2.022 Collecting propcache>=0.2.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.049   Downloading propcache-0.5.2-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (16 kB)
#9 2.067 Collecting typing_extensions>=4.4 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.078   Downloading typing_extensions-4.16.0-py3-none-any.whl.metadata (3.3 kB)
#9 2.234 Collecting yarl<2.0,>=1.17.0 (from aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.244   Downloading yarl-1.24.5-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl.metadata (103 kB)
#9 2.299 Collecting idna>=2.0 (from yarl<2.0,>=1.17.0->aiohttp>=3.9.0->livekit-api==1.2.0->-r requirements.txt (line 1))
#9 2.309   Downloading idna-3.18-py3-none-any.whl.metadata (6.1 kB)
#9 2.330 Downloading livekit_api-1.2.0-py3-none-any.whl (26 kB)
#9 2.339 Downloading aiohttp-3.14.3-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (1.8 MB)
#9 2.379    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 1.8/1.8 MB 52.7 MB/s eta 0:00:00
#9 2.390 Downloading livekit_protocol-1.1.21-py3-none-any.whl (149 kB)
#9 2.399 Downloading protobuf-7.35.1-cp310-abi3-manylinux2014_x86_64.whl (327 kB)
#9 2.409 Downloading pyjwt-2.13.0-py3-none-any.whl (31 kB)
#9 2.418 Downloading types_protobuf-7.34.1.20260518-py3-none-any.whl (85 kB)
#9 2.427 Downloading aiohappyeyeballs-2.7.1-py3-none-any.whl (15 kB)
#9 2.436 Downloading aiosignal-1.4.0-py3-none-any.whl (7.5 kB)
#9 2.449 Downloading attrs-26.1.0-py3-none-any.whl (67 kB)
#9 2.458 Downloading frozenlist-1.8.0-cp312-cp312-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl (242 kB)
#9 2.468 Downloading multidict-6.7.1-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (256 kB)
#9 2.478 Downloading propcache-0.5.2-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (61 kB)
#9 2.487 Downloading typing_extensions-4.16.0-py3-none-any.whl (45 kB)
#9 2.497 Downloading yarl-1.24.5-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl (109 kB)
#9 2.506 Downloading idna-3.18-py3-none-any.whl (65 kB)
#9 2.537 Installing collected packages: typing_extensions, types-protobuf, pyjwt, protobuf, propcache, multidict, idna, frozenlist, attrs, aiohappyeyeballs, yarl, livekit-protocol, aiosignal, aiohttp, livekit-api
#9 3.006 Successfully installed aiohappyeyeballs-2.7.1 aiohttp-3.14.3 aiosignal-1.4.0 attrs-26.1.0 frozenlist-1.8.0 idna-3.18 livekit-api-1.2.0 livekit-protocol-1.1.21 multidict-6.7.1 propcache-0.5.2 protobuf-7.35.1 pyjwt-2.13.0 types-protobuf-7.34.1.20260518 typing_extensions-4.16.0 yarl-1.24.5
#9 3.007 WARNING: Running pip as the 'root' user can result in broken permissions and conflicting behaviour with the system package manager, possibly rendering your system unusable. It is recommended to use a virtual environment instead: https://pip.pypa.io/warnings/venv. Use the --root-user-action option if you know what you are doing and want to suppress this warning.
#9 DONE 3.2s

#10 [5/5] COPY broker.py ./
#10 DONE 0.0s

#11 exporting to image
#11 exporting layers
#11 exporting layers 1.0s done
#11 writing image sha256:6769bdc7904e24028a2321654ca3683e69d7c8686c6aacbe52700d7f1c7d1a93 done
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
Because livekit_client >=2.7.0 <2.9.0-dev.0 depends on flutter_webrtc 1.4.0 and chernogram depends on flutter_webrtc ^1.5.2, livekit_client >=2.7.0 <2.9.0-dev.0 is forbidden.
So, because chernogram depends on livekit_client 2.8.1, version solving failed.


You can try one of the following suggestions to make the pubspec resolve:
* Try upgrading your constraint on livekit_client: flutter pub add livekit_client:^2.9.0
* Consider downgrading your constraint on flutter_webrtc: flutter pub add flutter_webrtc:^1.4.0
Failed to update packages.
ERROR: Flutter pub get failed with exit code 1
```

