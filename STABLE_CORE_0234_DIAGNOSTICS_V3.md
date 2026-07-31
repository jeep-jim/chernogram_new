# Chernogram 0.23.4 stable core diagnostics v3

Flutter outcome: failure
Gateway outcome: cancelled
Time: 2026-07-31T11:13:12Z

## Flutter application
```text
Resolving dependencies...
Downloading packages...
+ _fe_analyzer_shared 99.0.0 (105.0.0 available)
+ analyzer 12.1.0 (14.1.0 available)
+ cli_config 0.2.0
+ convert 3.1.2
+ coverage 1.15.1
  file_picker 10.3.10 (11.0.2 available)
+ flutter_background_service 5.1.0
+ flutter_background_service_android 6.3.1
+ flutter_background_service_ios 5.0.3
+ flutter_background_service_platform_interface 5.1.2
  flutter_contacts 1.1.9+2 (2.3.0 available)
  flutter_lints 3.0.2 (6.0.0 available)
+ flutter_local_notifications 22.2.0
+ flutter_local_notifications_linux 8.0.1
+ flutter_local_notifications_platform_interface 12.1.0
+ flutter_local_notifications_web 1.0.0
+ flutter_local_notifications_windows 3.1.1
+ frontend_server_client 4.0.0
+ glob 2.1.3
  hooks 2.0.2 (2.1.0 available)
+ http_multi_server 3.2.2
+ io 1.0.5
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  lints 3.0.0 (6.1.0 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
+ node_preamble 2.0.2
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
+ pool 1.5.2
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
+ shelf 1.4.2
+ shelf_packages_handler 3.0.2
+ shelf_static 1.1.3
+ shelf_web_socket 3.0.0
+ source_map_stack_trace 2.1.2
+ source_maps 0.10.13
+ test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
+ test_core 0.6.17 (0.6.19 available)
+ timezone 0.11.1
  vector_math 2.2.0 (2.4.1 available)
+ watcher 1.2.1
+ web_socket 1.0.1
+ web_socket_channel 3.0.3
+ webkit_inspection_protocol 1.2.1
  win32 5.15.0 (6.3.0 available)
  xml 6.6.1 (7.0.1 available)
Changed 39 dependencies!
33 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Formatted lib/agent_screen.dart
Formatted lib/android_data_first.dart
Formatted lib/background_realtime_service.dart
Formatted lib/brand.dart
Formatted lib/chat_media.dart
Formatted lib/chat_screen.dart
Formatted lib/core_models.dart
Formatted lib/group_call_service.dart
Formatted lib/install_share_sheet.dart
Formatted lib/legacy_ntfy_transport.dart
Formatted lib/legacy_v16_features.dart
Formatted lib/main.dart
Formatted lib/media_studio.dart
Formatted lib/network_core.dart
Formatted lib/pending_call.dart
Formatted lib/permission_center.dart
Formatted lib/public_file_index.dart
Formatted lib/sound_service.dart
Formatted lib/tunnel_extras.dart
Formatted lib/tunnels.dart
Formatted lib/update_service.dart
Formatted lib/v06.dart
Formatted 33 files (22 changed) in 0.50 seconds.
Analyzing 2 items...                                            

  error • The method 'publishMessage' isn't defined for the type 'ChernogramAppMonitor'. Try correcting the name to the name of an existing method, or defining a method named 'publishMessage' • lib/android_data_first.dart:435:32 • undefined_method
warning • The value of the field '_globalFiles' isn't used. Try removing the field, or using it • lib/android_data_first.dart:1171:28 • unused_field
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/android_data_first.dart:1347:7 • use_build_context_synchronously
  error • The method 'publishMessage' isn't defined for the type 'ChernogramAppMonitor'. Try correcting the name to the name of an existing method, or defining a method named 'publishMessage' • lib/android_data_first.dart:1392:34 • undefined_method
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1421:7 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:1423:7 • curly_braces_in_flow_control_structures
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/android_data_first.dart:1855:27 • prefer_const_constructors
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/android_data_first.dart:2186:7 • curly_braces_in_flow_control_structures
  error • Target of URI doesn't exist: 'call_avatar.dart'. Try creating the file referenced by the URI, or try using a URI for a file that does exist • lib/app_monitor.dart:8:8 • uri_does_not_exist
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/app_monitor.dart:279:7 • use_build_context_synchronously
  error • The method 'CgCallAvatar' isn't defined for the type 'ChernogramAppMonitor'. Try correcting the name to the name of an existing method, or defining a method named 'CgCallAvatar' • lib/app_monitor.dart:282:15 • undefined_method
  error • The named parameter 'myAvatarBase64' isn't defined. Try correcting the name to an existing named parameter's name, or defining a named parameter with the name 'myAvatarBase64' • lib/app_monitor.dart:370:17 • undefined_named_parameter
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/brand.dart:3:8 • unnecessary_import
  error • Target of URI doesn't exist: 'call_avatar.dart'. Try creating the file referenced by the URI, or try using a URI for a file that does exist • lib/call_service.dart:7:8 • uri_does_not_exist
  error • The method 'CgCallAvatar' isn't defined for the type '_ChernogramCallScreenState'. Try correcting the name to the name of an existing method, or defining a method named 'CgCallAvatar' • lib/call_service.dart:462:23 • undefined_method
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_media.dart:5:8 • unnecessary_import
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/chat_screen.dart:4:8 • unnecessary_import
warning • The declaration '_showMessageActions' isn't referenced. Try removing the declaration of '_showMessageActions' • lib/chat_screen.dart:466:16 • unused_element
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1201:7 • use_build_context_synchronously
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/chat_screen.dart:1275:7 • use_build_context_synchronously
warning • The declaration '_TunnelAvatar' isn't referenced. Try removing the declaration of '_TunnelAvatar' • lib/chat_screen.dart:1801:7 • unused_element
warning • The declaration '_AttachmentPreview' isn't referenced. Try removing the declaration of '_AttachmentPreview' • lib/chat_screen.dart:2334:7 • unused_element
warning • Unused import: 'core_models.dart'. Try removing the import directive • lib/group_call_service.dart:8:8 • unused_import
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/install_share_sheet.dart:47:13 • prefer_const_constructors
warning • Unused import: 'brand.dart'. Try removing the import directive • lib/legacy_v16_features.dart:13:8 • unused_import
   info • 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/legacy_v16_features.dart:1005:19 • deprecated_member_use
   info • 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/legacy_v16_features.dart:1007:19 • deprecated_member_use
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/main.dart:102:42 • use_build_context_synchronously
   info • The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/services.dart'. Try removing the import directive • lib/media_studio.dart:2:8 • unnecessary_import
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/network_core.dart:394:9 • curly_braces_in_flow_control_structures
warning • The value of the field '_nickname' isn't used. Try removing the field, or using it • lib/public_file_index.dart:79:11 • unused_field
   info • Use 'const' with the constructor to improve performance. Try adding the 'const' keyword to the constructor invocation • lib/realtime_gateway_config.dart:60:13 • prefer_const_constructors
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/tunnels.dart:1133:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:456:7 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:467:7 • curly_braces_in_flow_control_structures
   info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/v06.dart:503:7 • use_build_context_synchronously
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:714:23 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1890:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1937:5 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1959:9 • curly_braces_in_flow_control_structures
   info • Statements in an if should be enclosed in a block. Try wrapping the statement in a block • lib/v06.dart:1961:9 • curly_braces_in_flow_control_structures

41 issues found. (ran in 13.9s)
```

## Realtime gateway
```text
Resolving dependencies...
Downloading packages...
+ _fe_analyzer_shared 105.0.0
+ analyzer 14.1.0
+ args 2.7.0
+ async 2.13.1
+ boolean_selector 2.1.2
+ cli_config 0.2.0
+ collection 1.19.1
+ convert 3.1.2
+ coverage 1.15.1
+ crypto 3.0.7
+ cryptography 2.9.0
+ ffi 2.2.0
+ file 7.0.1
+ frontend_server_client 4.0.0
+ glob 2.1.3
+ http_multi_server 3.2.2
+ http_parser 4.1.2
+ io 1.0.5
+ lints 5.1.1 (6.1.0 available)
+ logging 1.3.0
+ matcher 0.12.20
+ meta 1.19.0
+ mime 2.0.0
+ node_preamble 2.0.2
+ package_config 3.0.0
+ path 1.9.1
+ pool 1.5.2
+ pub_semver 2.2.0
+ shelf 1.4.2
+ shelf_packages_handler 3.0.2
+ shelf_static 1.1.3
+ shelf_web_socket 3.0.0
+ source_map_stack_trace 2.1.2
+ source_maps 0.10.13
+ source_span 1.10.2
+ stack_trace 1.12.1
+ stream_channel 2.1.4
+ string_scanner 1.4.1
+ term_glyph 1.2.2
+ test 1.31.2
+ test_api 0.7.13
+ test_core 0.6.19
+ typed_data 1.4.0
+ vm_service 15.2.0
+ watcher 1.2.1
+ web 1.1.1
+ web_socket 1.0.1
+ web_socket_channel 3.0.3
+ webkit_inspection_protocol 1.2.1
+ yaml 3.1.3
Changed 50 dependencies!
1 package has newer versions incompatible with dependency constraints.
Try `dart pub outdated` for more information.
Warning: Package resolution error when reading "analysis_options.yaml" file:
Failed to resolve package URI "package:flutter_lints/flutter.yaml" in include at "/home/runner/work/chernogram_new/chernogram_new/analysis_options.yaml".
Formatted bin/mint_token.dart
Formatted bin/server.dart
Warning: Package resolution error when reading "analysis_options.yaml" file:
Failed to resolve package URI "package:flutter_lints/flutter.yaml" in include at "/home/runner/work/chernogram_new/chernogram_new/analysis_options.yaml".
Formatted test/gateway_core_test.dart
Warning: Package resolution error when reading "analysis_options.yaml" file:
Failed to resolve package URI "package:flutter_lints/flutter.yaml" in include at "/home/runner/work/chernogram_new/chernogram_new/analysis_options.yaml".
Formatted tool/integration_smoke.dart
Formatted 4 files (4 changed) in 0.03 seconds.
Analyzing realtime_gateway...
No issues found!

::group::✅ Passing tests
✅ test/gateway_core_test.dart: development token is accepted only in explicit development mode
✅ test/gateway_core_test.dart: event store persists, deduplicates and replays by room cursor
::endgroup::

🎉 2 tests passed.
{"ok":true,"sessions":0,"time":"2026-07-31T10:08:48.747997Z"}gateway smoke passed: live, file_chunk, replay, signal
```
