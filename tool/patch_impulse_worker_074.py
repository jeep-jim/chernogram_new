from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


worker = Path('worker/impulse/src/index.ts')
text = worker.read_text(encoding='utf-8')
if not text.startswith('import { DurableObject }'):
    text = 'import { DurableObject } from "cloudflare:workers";\n\n' + text

text = replace_once(
    text,
    """  wake: string;
  ciphertext: string;
""",
    """  wake: string;
  video?: boolean;
  ciphertext: string;
""",
    'video metadata type',
)

text = replace_once(
    text,
    """  if (!participant.fcmToken) return;
  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || \"{}\") as Partial<ServiceAccount>;
""",
    """  if (!participant.fcmToken || envelope.wake === \"none\") return;
  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || \"{}\") as Partial<ServiceAccount>;
""",
    'skip non-wake push',
)

old_message = """    body: JSON.stringify({
      message: {
        token: participant.fcmToken,
        notification: { title, body },
        data: {
          roomKey,
          packetId: envelope.packetId,
          kind: envelope.kind,
          wake: envelope.wake,
        },
        android: {
          priority: \"HIGH\",
          ttl: call ? \"60s\" : \"86400s\",
          notification: {
            channel_id: call ? \"chernogram_calls\" : \"chernogram_messages\",
            priority: call ? \"PRIORITY_MAX\" : \"PRIORITY_HIGH\",
            visibility: \"PRIVATE\",
            sound: \"default\",
          },
        },
      },
    }),
"""
new_message = """    body: JSON.stringify({
      message: {
        token: participant.fcmToken,
        ...(!call ? { notification: { title, body } } : {}),
        data: {
          roomKey,
          packetId: envelope.packetId,
          kind: envelope.kind,
          wake: envelope.wake,
          video: envelope.video === true ? \"true\" : \"false\",
        },
        android: call
          ? {
              priority: \"HIGH\",
              ttl: \"60s\",
            }
          : {
              priority: \"HIGH\",
              ttl: \"86400s\",
              notification: {
                channel_id: \"chernogram_messages\",
                priority: \"PRIORITY_HIGH\",
                visibility: \"PRIVATE\",
                sound: \"default\",
              },
            },
      },
    }),
"""
text = replace_once(text, old_message, new_message, 'data-only call push')

text = replace_once(
    text,
    """    envelope.createdAt = envelope.createdAt || Date.now();
    await this.ctx.storage.put(`env:${envelope.packetId}`, envelope);
""",
    """    envelope.createdAt = envelope.createdAt || Date.now();
    if (envelope.kind === \"presence\") {
      this.broadcast(envelope);
      return;
    }
    await this.ctx.storage.put(`env:${envelope.packetId}`, envelope);
""",
    'do not persist presence',
)

worker.write_text(text, encoding='utf-8')

core = Path('lib/internet_core.dart')
text = core.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    if (_closed || _connecting || connected) return;
""",
    """    if (_closed || _connecting || (_httpReady && _socket != null)) return;
""",
    'websocket reconnect condition',
)
text = replace_once(
    text,
    """              'wake': _wakeFor(envelope),
              'ciphertext': encrypted,
""",
    """              'wake': _wakeFor(envelope),
              if (_wakeFor(envelope) == 'call')
                'video': envelope.data['video'] == true,
              'ciphertext': encrypted,
""",
    'call video metadata',
)
core.write_text(text, encoding='utf-8')

monitor = Path('lib/app_monitor.dart')
text = monitor.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    final monitored = recent.take(8).toList(growable: false);
""",
    """    // Every saved direct contact must be registered with Impulse/FCM,
    // otherwise a quiet old dialog could not wake the phone.
    final monitored = recent.toList(growable: false);
""",
    'monitor every saved contact',
)
monitor.write_text(text, encoding='utf-8')

print('Impulse Worker, reconnect and registration patches applied.')
