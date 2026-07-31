# Chernogram 0.23.3 files-first failed

Workflow commit: 3839e379f3d394b6e64ec708879fa773a9449c6f
Source: feature/files-first-0233
Time: 2026-07-31T02:44:48Z

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
Formatted lib/agent_screen.dart
Formatted lib/android_data_first.dart
Formatted lib/brand.dart
Formatted lib/call_service.dart
Formatted lib/chat_screen.dart
Formatted lib/core_models.dart
Formatted lib/group_call_service.dart
Formatted lib/internet_core.dart
Formatted lib/legacy_v16_features.dart
Formatted lib/media_studio.dart
Formatted lib/network_core.dart
Formatted lib/permission_center.dart
Formatted lib/sound_service.dart
Formatted lib/tunnel_extras.dart
Formatted lib/tunnels.dart
Formatted lib/update_service.dart
Formatted lib/v06.dart
Could not format because the source could not be parsed:

line 1, column 6 of tooling/materialize_files_first_0233.py: Expected to find ';'.
  ╷
1 │ from __future__ import annotations
  │      ^^^^^^^^^^
  ╵
line 1, column 17 of tooling/materialize_files_first_0233.py: Directives must appear before any declarations.
  ╷
1 │ from __future__ import annotations
  │                 ^^^^^^
  ╵
line 1, column 24 of tooling/materialize_files_first_0233.py: Expected a string literal.
  ╷
1 │ from __future__ import annotations
  │                        ^^^^^^^^^^^
  ╵
line 1, column 17 of tooling/materialize_files_first_0233.py: Expected to find ';'.
  ╷
1 │ from __future__ import annotations
  │                 ^^^^^^
  ╵
line 3, column 1 of tooling/materialize_files_first_0233.py: Expected to find ';'.
  ╷
3 │ from pathlib import Path
  │ ^^^^
  ╵
line 3, column 14 of tooling/materialize_files_first_0233.py: Expected an identifier.
  ╷
3 │ from pathlib import Path
  │              ^^^^^^
  ╵
line 3, column 6 of tooling/materialize_files_first_0233.py: Expected to find ';'.
  ╷
3 │ from pathlib import Path
  │      ^^^^^^^
  ╵
line 3, column 14 of tooling/materialize_files_first_0233.py: Directives must appear before any declarations.
  ╷
3 │ from pathlib import Path
  │              ^^^^^^
  ╵
line 3, column 21 of tooling/materialize_files_first_0233.py: Expected a string literal.
  ╷
3 │ from pathlib import Path
  │                     ^^^^
  ╵
line 3, column 14 of tooling/materialize_files_first_0233.py: Expected to find ';'.
  ╷
3 │ from pathlib import Path
  │              ^^^^^^
  ╵
(314 more errors...)
Could not format because the source could not be parsed:

line 1, column 6 of tooling/finalize_files_first_0233.py: Expected to find ';'.
  ╷
1 │ from __future__ import annotations
  │      ^^^^^^^^^^
  ╵
line 1, column 17 of tooling/finalize_files_first_0233.py: Directives must appear before any declarations.
  ╷
1 │ from __future__ import annotations
  │                 ^^^^^^
  ╵
line 1, column 24 of tooling/finalize_files_first_0233.py: Expected a string literal.
  ╷
1 │ from __future__ import annotations
  │                        ^^^^^^^^^^^
  ╵
line 1, column 17 of tooling/finalize_files_first_0233.py: Expected to find ';'.
  ╷
1 │ from __future__ import annotations
  │                 ^^^^^^
  ╵
line 3, column 1 of tooling/finalize_files_first_0233.py: Expected to find ';'.
  ╷
3 │ from pathlib import Path
  │ ^^^^
  ╵
line 3, column 14 of tooling/finalize_files_first_0233.py: Expected an identifier.
  ╷
3 │ from pathlib import Path
  │              ^^^^^^
  ╵
line 3, column 6 of tooling/finalize_files_first_0233.py: Expected to find ';'.
  ╷
3 │ from pathlib import Path
  │      ^^^^^^^
  ╵
line 3, column 14 of tooling/finalize_files_first_0233.py: Directives must appear before any declarations.
  ╷
3 │ from pathlib import Path
  │              ^^^^^^
  ╵
line 3, column 21 of tooling/finalize_files_first_0233.py: Expected a string literal.
  ╷
3 │ from pathlib import Path
  │                     ^^^^
  ╵
line 3, column 14 of tooling/finalize_files_first_0233.py: Expected to find ';'.
  ╷
3 │ from pathlib import Path
  │              ^^^^^^
  ╵
(94 more errors...)
Formatted 22 files (17 changed) in 0.47 seconds.
```
