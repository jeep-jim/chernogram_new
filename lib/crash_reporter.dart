import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ChernogramCrashReporter {
  static File? _dartLog;
  static Directory? _supportDirectory;
  static bool _initialized = false;
  static Future<void> _writeQueue = Future<void>.value();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _supportDirectory = await getApplicationSupportDirectory();
      _dartLog = File(
        '${_supportDirectory!.path}${Platform.pathSeparator}chernogram_crash.log',
      );
      await breadcrumb('application process started');
      await _trimLog();
    } catch (_) {
      // Diagnostics must never prevent the application from starting.
    }
  }

  static Future<void> breadcrumb(String message) =>
      _append('BREADCRUMB', message, null);

  static Future<void> recordFlutterError(FlutterErrorDetails details) =>
      _append('FLUTTER', details.exceptionAsString(), details.stack);

  static Future<void> recordError(
    Object error,
    StackTrace stack, {
    String source = 'DART',
  }) => _append(source, error.toString(), stack);

  static Future<void> _append(
    String source,
    String message,
    StackTrace? stack,
  ) async {
    if (!_initialized) await initialize();
    final file = _dartLog;
    if (file == null) return;
    final entry = StringBuffer()
      ..writeln(
        '===== ${DateTime.now().toUtc().toIso8601String()} $source =====',
      )
      ..writeln(message);
    if (stack != null) entry.writeln(stack);
    entry.writeln();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          entry.toString(),
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    });
    await _writeQueue;
  }

  static Future<void> _trimLog() async {
    final file = _dartLog;
    if (file == null || !await file.exists()) return;
    try {
      final text = await file.readAsString();
      const maximumCharacters = 240000;
      if (text.length <= maximumCharacters) return;
      await file.writeAsString(
        text.substring(text.length - maximumCharacters),
        flush: true,
      );
    } catch (_) {}
  }

  static Future<File> createDiagnosticReport() async {
    await initialize();
    final package = await PackageInfo.fromPlatform();
    final temporary = await getTemporaryDirectory();
    final report = File(
      '${temporary.path}${Platform.pathSeparator}'
      'cernogram-diagnostics-${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    final output = StringBuffer()
      ..writeln('CERNOGRAM DIAGNOSTIC REPORT')
      ..writeln('Created UTC: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('Version: ${package.version}+${package.buildNumber}')
      ..writeln('Platform: ${Platform.operatingSystem}')
      ..writeln('OS: ${Platform.operatingSystemVersion}')
      ..writeln('Locale: ${Platform.localeName}')
      ..writeln('Processors: ${Platform.numberOfProcessors}')
      ..writeln();

    final dartLog = _dartLog;
    if (dartLog != null && await dartLog.exists()) {
      output
        ..writeln('===== DART / FLUTTER LOG =====')
        ..writeln(await dartLog.readAsString())
        ..writeln();
    } else {
      output.writeln('Dart / Flutter crash log is empty.\n');
    }

    final support = _supportDirectory ?? await getApplicationSupportDirectory();
    final nativeLog = File(
      '${support.path}${Platform.pathSeparator}chernogram_native_crash.log',
    );
    if (await nativeLog.exists()) {
      output
        ..writeln('===== ANDROID NATIVE LOG =====')
        ..writeln(await nativeLog.readAsString())
        ..writeln();
    } else {
      output.writeln('Android native crash log is empty.\n');
    }

    await report.writeAsString(output.toString(), flush: true);
    return report;
  }

  static Future<bool> shareDiagnosticReport({required bool ru}) async {
    try {
      final report = await createDiagnosticReport();
      await Share.shareXFiles(
        <XFile>[XFile(report.path)],
        text: ru
            ? 'Диагностический отчёт Cernogram после аварийного закрытия.'
            : 'Cernogram diagnostic report after an unexpected closure.',
      );
      return true;
    } catch (error, stack) {
      await recordError(error, stack, source: 'DIAGNOSTIC_SHARE');
      return false;
    }
  }
}
