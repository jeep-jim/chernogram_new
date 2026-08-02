import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CgSimplexLabCard extends StatefulWidget {
  final bool ru;

  const CgSimplexLabCard({super.key, required this.ru});

  @override
  State<CgSimplexLabCard> createState() => _CgSimplexLabCardState();
}

class _CgSimplexLabCardState extends State<CgSimplexLabCard> {
  static const MethodChannel _channel = MethodChannel(
    'chernogram/simplex_lab',
  );

  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _initialize() async {
    if (_loading || !_supported) return;
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'initialize',
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? error.code;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _result?['state'] == 'ready';
    final migration = _result?['migration']?.toString();

    return Material(
      color: scheme.primaryContainer.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready
                      ? Icons.verified_rounded
                      : Icons.science_outlined,
                  color: ready ? scheme.primary : scheme.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.ru
                        ? 'Лаборатория нового ядра'
                        : 'New core laboratory',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              !_supported
                  ? (widget.ru
                        ? 'Проверка доступна только в Android-сборке Lab.'
                        : 'The probe is available only in the Android Lab build.')
                  : ready
                  ? (widget.ru
                        ? 'Официальное ядро SimpleX загружено, локальная база открыта.'
                        : 'The official SimpleX core is loaded and its local database is open.')
                  : (widget.ru
                        ? 'Проверяет загрузку libsimplex и создание локальной базы. Чаты пока не переключаются автоматически.'
                        : 'Checks libsimplex loading and local database creation. Chats are not switched automatically yet.'),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: .68),
              ),
            ),
            if (migration != null && migration.isNotEmpty) ...[
              const SizedBox(height: 9),
              SelectableText(
                migration,
                style: const TextStyle(fontSize: 10),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 9),
              SelectableText(
                _error!,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading || !_supported ? null : _initialize,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        ready
                            ? Icons.refresh_rounded
                            : Icons.play_arrow_rounded,
                      ),
                label: Text(
                  ready
                      ? (widget.ru ? 'Проверить повторно' : 'Check again')
                      : (widget.ru ? 'Запустить проверку' : 'Run probe'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
