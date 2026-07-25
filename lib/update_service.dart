import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class RemoteUpdate {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final String notesRu;
  final String notesEn;

  const RemoteUpdate({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.notesRu,
    required this.notesEn,
  });

  factory RemoteUpdate.fromJson(Map<String, dynamic> json) {
    return RemoteUpdate(
      versionName: json['versionName']?.toString() ?? '0.0.0',
      versionCode: int.tryParse(json['versionCode']?.toString() ?? '') ?? 0,
      apkUrl: json['apkUrl']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
      notesRu: json['notesRu']?.toString() ?? '',
      notesEn: json['notesEn']?.toString() ?? '',
    );
  }
}

class ChernogramUpdater {
  static const _manifestUrl =
      'https://github.com/jeep-jim/chernogram_new/releases/download/latest-apk/update.json';

  static bool _automaticCheckDone = false;
  static bool _checking = false;
  static bool _installing = false;

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<RemoteUpdate?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    final response = await http
        .get(
          Uri.parse('$_manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'),
          headers: const {'Cache-Control': 'no-cache'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw HttpException('Update server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid update manifest');
    }

    final remote = RemoteUpdate.fromJson(decoded);
    final current = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(current.buildNumber) ?? 0;

    if (remote.versionCode <= currentCode || remote.apkUrl.isEmpty) return null;
    return remote;
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    required bool ru,
    bool manual = false,
  }) async {
    if (!Platform.isAndroid || _checking || _installing) return;
    if (!manual && _automaticCheckDone) return;

    if (!manual) _automaticCheckDone = true;
    _checking = true;

    try {
      final update = await checkForUpdate();
      if (!context.mounted) return;

      if (update == null) {
        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ru
                    ? 'У вас уже установлена последняя версия.'
                    : 'You already have the latest version.',
              ),
            ),
          );
        }
        return;
      }

      final shouldInstall = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final notes = ru ? update.notesRu : update.notesEn;
          return AlertDialog(
            icon: const Icon(Icons.system_update_alt_rounded, size: 38),
            title: Text(
              ru
                  ? 'Доступно обновление ${update.versionName}'
                  : 'Update ${update.versionName} is available',
            ),
            content: Text(
              notes.isEmpty
                  ? (ru
                        ? 'Новая версия Чернограма готова к установке.'
                        : 'A new Chernogram version is ready to install.')
                  : notes,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(ru ? 'Позже' : 'Later'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.download_rounded),
                label: Text(ru ? 'Обновить' : 'Update'),
              ),
            ],
          );
        },
      );

      if (shouldInstall == true && context.mounted) {
        await _downloadAndInstall(context, update, ru: ru);
      }
    } on TimeoutException {
      if (manual && context.mounted) {
        _showError(
          context,
          ru,
          ru
              ? 'Сервер обновлений не ответил.'
              : 'The update server did not respond.',
        );
      }
    } catch (_) {
      if (manual && context.mounted) {
        _showError(
          context,
          ru,
          ru
              ? 'Не удалось проверить обновления. Проверьте интернет.'
              : 'Could not check for updates. Check your connection.',
        );
      }
    } finally {
      _checking = false;
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    RemoteUpdate update, {
    required bool ru,
  }) async {
    if (_installing) return;
    _installing = true;

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>(
      ru ? 'Подготовка обновления…' : 'Preparing the update…',
    );
    bool dialogOpen = true;
    StreamSubscription<OtaEvent>? subscription;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      navigator.pop();
    }

    void fail(String message) {
      closeDialog();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(ru ? 'Обновление Чернограма' : 'Updating Chernogram'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: value <= 0 ? null : value / 100),
                const SizedBox(height: 14),
                ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (_, text, __) => Text(text),
                ),
                if (value > 0) ...[
                  const SizedBox(height: 6),
                  Text('${value.toStringAsFixed(0)}%'),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final stream = update.sha256.isEmpty
          ? OtaUpdate().execute(
              update.apkUrl,
              destinationFilename: 'chernogram-${update.versionName}.apk',
              usePackageInstaller: true,
            )
          : OtaUpdate().execute(
              update.apkUrl,
              destinationFilename: 'chernogram-${update.versionName}.apk',
              sha256checksum: update.sha256,
              usePackageInstaller: true,
            );

      final completed = Completer<void>();
      subscription = stream.listen(
        (event) {
          final eventName = event.status.toString().split('.').last;
          if (eventName == 'DOWNLOADING') {
            final value = double.tryParse(event.value ?? '') ?? 0;
            progress.value = value.clamp(0, 100).toDouble();
            status.value = ru
                ? 'Скачиваем новую версию…'
                : 'Downloading the new version…';
            return;
          }

          if (eventName == 'INSTALLING') {
            // CHERNOGRAM_05_INSTALL_FLOW
            closeDialog();
            messenger.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 10),
                content: Text(
                  ru
                      ? 'APK скачан. Подтвердите установку в системном окне Android. Если появится запрос — разрешите установку из Чернограма и вернитесь назад.'
                      : 'APK downloaded. Confirm installation in Android. If asked, allow installs from Chernogram and return.',
                ),
              ),
            );
            return;
          }

          if (eventName == 'INSTALLATION_DONE') {
            closeDialog();
            if (!completed.isCompleted) completed.complete();
            return;
          }

          if (eventName == 'PERMISSION_NOT_GRANTED_ERROR') {
            fail(
              ru
                  ? 'Разрешите Чернограму устанавливать обновления в настройках Android и повторите попытку.'
                  : 'Allow Chernogram to install updates in Android settings and try again.',
            );
            if (!completed.isCompleted) completed.complete();
            return;
          }

          const errors = {
            'DOWNLOAD_ERROR',
            'CHECKSUM_ERROR',
            'INSTALLATION_ERROR',
            'INTERNAL_ERROR',
            'ALREADY_RUNNING_ERROR',
          };
          if (errors.contains(eventName)) {
            fail(
              ru
                  ? 'Не удалось установить обновление. Повторите попытку.'
                  : 'The update could not be installed. Please try again.',
            );
            if (!completed.isCompleted) completed.complete();
            return;
          }

          if (eventName == 'CANCELED') {
            closeDialog();
            if (!completed.isCompleted) completed.complete();
          }
        },
        onError: (_) {
          fail(
            ru ? 'Ошибка скачивания обновления.' : 'Update download failed.',
          );
          if (!completed.isCompleted) completed.complete();
        },
        onDone: () {
          if (!completed.isCompleted) completed.complete();
        },
      );

      await completed.future.timeout(
        const Duration(minutes: 4),
        onTimeout: () {
          closeDialog();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                ru
                    ? 'Установка передана Android. Проверьте системное окно или повторите обновление.'
                    : 'Installation was handed to Android. Check the system window or retry.',
              ),
            ),
          );
        },
      );
    } catch (_) {
      fail(
        ru ? 'Не удалось запустить обновление.' : 'Could not start the update.',
      );
    } finally {
      await subscription?.cancel();
      progress.dispose();
      status.dispose();
      _installing = false;
    }
  }

  static void _showError(BuildContext context, bool ru, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: ru ? 'Повторить' : 'Retry',
          onPressed: () => checkAndPrompt(context, ru: ru, manual: true),
        ),
      ),
    );
  }
}
