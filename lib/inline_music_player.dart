import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'core_models.dart';
import 'music_library.dart';
import 'music_player.dart';

class CgInlineMusicPlayer extends StatefulWidget {
  final CgAttachment attachment;
  final String subtitle;

  const CgInlineMusicPlayer({
    super.key,
    required this.attachment,
    required this.subtitle,
  });

  @override
  State<CgInlineMusicPlayer> createState() => _CgInlineMusicPlayerState();
}

class _CgInlineMusicPlayerState extends State<CgInlineMusicPlayer> {
  final CgMusicHub _hub = CgMusicHub.instance;
  bool _loading = false;

  Future<File?> _ensureFile() async {
    final local = widget.attachment.localPath;
    if (local != null && local.isNotEmpty) {
      final file = File(local);
      if (await file.exists()) return file;
    }
    final raw = widget.attachment.dataBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}/chernogram_music_cache');
      if (!await directory.exists()) await directory.create(recursive: true);
      final safeName = widget.attachment.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]+'),
        '_',
      );
      final file = File(
        '${directory.path}/${widget.attachment.id}_$safeName',
      );
      if (!await file.exists()) {
        await file.writeAsBytes(base64Decode(raw), flush: true);
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggle() async {
    setState(() => _loading = true);
    final file = await _ensureFile();
    if (file != null) {
      await _hub.playSingle(
        CgMusicTrack(
          id: 'chat-inline:${widget.attachment.id}',
          title: widget.attachment.name,
          subtitle: widget.subtitle,
          path: file.path,
          source: CgMusicSource.chats,
          addedAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: _hub.activeTrackId,
      builder: (context, activeId, _) {
        final active = activeId == 'chat-inline:${widget.attachment.id}';
        return Container(
          width: 286,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .64),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: _hub.player.playerStateStream,
                builder: (context, state) => IconButton.filled(
                  onPressed: _loading ? null : _toggle,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          active && state.data?.playing == true
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    StreamBuilder<Duration>(
                      stream: _hub.player.positionStream,
                      builder: (context, positionSnapshot) =>
                          StreamBuilder<Duration?>(
                        stream: _hub.player.durationStream,
                        builder: (context, durationSnapshot) {
                          final total = active
                              ? durationSnapshot.data ?? Duration.zero
                              : Duration.zero;
                          final position = active
                              ? positionSnapshot.data ?? Duration.zero
                              : Duration.zero;
                          final maxValue =
                              math.max(1, total.inMilliseconds).toDouble();
                          return Slider(
                            min: 0,
                            max: maxValue,
                            value: position.inMilliseconds
                                .clamp(0, maxValue.toInt())
                                .toDouble(),
                            onChanged: !active || total == Duration.zero
                                ? null
                                : (value) => _hub.player.seek(
                                      Duration(milliseconds: value.round()),
                                    ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
