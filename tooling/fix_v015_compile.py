from pathlib import Path

from fix_v0151_release import (
    patch_chat_screen,
    patch_core_models,
    patch_v12,
    patch_windows_updater,
)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise RuntimeError(f'Expected block was not found: {label}')
    return source.replace(old, new, 1)


def patch_internet_core() -> bool:
    path = Path('lib/internet_core.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    if '_signalHistory' not in source:
        source = replace_once(
            source,
            """  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];
""",
            """  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _signalHistory = <Map<String, dynamic>>[];
  final List<_PendingEnvelope> _outbox = <_PendingEnvelope>[];
""",
            'signal history field',
        )

    if "final signal = <String, dynamic>{" not in source:
        source = replace_once(
            source,
            """      case 'signal':
        _emit('signal', <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
        });
        break;
""",
            """      case 'signal':
        final signal = <String, dynamic>{
          ...data,
          'relaySender': sender,
          'relaySenderName': senderName,
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
        };
        _signalHistory.add(signal);
        if (_signalHistory.length > 200) {
          _signalHistory.removeRange(0, _signalHistory.length - 200);
        }
        _emit('signal', signal);
        break;
""",
            'signal event buffering',
        )

    if 'replaySignals(String callId)' not in source:
        marker = """  Future<void> sendSignal(Map<String, dynamic> signal) async {
    await _sendEnvelope('signal', signal, queueOnFailure: false);
  }

"""
        addition = """  List<Map<String, dynamic>> replaySignals(String callId) {
    if (callId.isEmpty) return const <Map<String, dynamic>>[];
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    return _signalHistory.where((signal) {
      if (signal['callId']?.toString() != callId) return false;
      final receivedAt = DateTime.tryParse(signal['receivedAt']?.toString() ?? '');
      return receivedAt == null || !receivedAt.toUtc().isBefore(cutoff);
    }).map((signal) => Map<String, dynamic>.from(signal)).toList();
  }

"""
        source = replace_once(source, marker, marker + addition, 'replaySignals')

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def patch_chat_media() -> bool:
    path = Path('lib/chat_media.dart')
    source = path.read_text(encoding='utf-8')
    original = source

    if 'purgeTunnelFiles(CgTunnel tunnel)' not in source:
        marker = """  static Future<List<CgTunnel>> purgeAll(List<CgTunnel> tunnels) async {
"""
        addition = """  static Future<void> purgeTunnelFiles(CgTunnel tunnel) async {
    final root = await rootDirectory();
    final visited = <String>{};
    for (final message in tunnel.messages) {
      final attachment = message.attachment;
      if (attachment == null) continue;
      final file = await existingFile(attachment);
      if (file == null || !visited.add(file.path)) continue;
      try {
        if (file.path.startsWith(root.path) && await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

"""
        source = replace_once(source, marker, addition + marker, 'purgeTunnelFiles')

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def main() -> None:
    compile_changed = patch_internet_core() | patch_chat_media()
    release_changed = False
    release_changed |= patch_core_models()
    release_changed |= patch_v12()
    release_changed |= patch_chat_screen()
    release_changed |= patch_windows_updater()
    if compile_changed or release_changed:
        print('Applied Chernogram 0.15.1 compile and release corrections')
    else:
        print('Chernogram 0.15.1 corrections already applied')


if __name__ == '__main__':
    main()
