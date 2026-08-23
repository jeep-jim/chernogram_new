import { CONFIG } from './config.js';
import { encryptJson, decryptJson, sha256Base64, randomId } from './crypto.js';

export async function inboxTopic(inboxId) {
  const hash = await sha256Base64(`veiltalk:inbox:${inboxId}`);
  return `vt_${hash.slice(0, 44)}`;
}

export async function sendEnvelope(remoteInboxId, roomId, secret, payload) {
  if (!remoteInboxId) throw new Error('Remote inbox is not known yet');
  const topic = await inboxTopic(remoteInboxId);
  const box = await encryptJson(secret, { roomId, id: randomId(12), sentAt: Date.now(), ...payload });
  const outer = { roomId, box };
  const response = await fetch(`${CONFIG.relayHttp}/${topic}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(outer)
  });
  if (!response.ok) throw new Error(`Relay HTTP ${response.status}`);
}

export async function decodeOuterForContact(contact, outer) {
  if (!outer || outer.roomId !== contact.roomId) return null;
  return decryptJson(contact.secret, outer.box);
}

export async function openInboxSocket(inboxId, onOuter, onStatus) {
  const topic = await inboxTopic(inboxId);
  let socket;
  let closed = false;
  let retry = 0;
  let pingTimer;

  const connect = () => {
    if (closed) return;
    onStatus?.('reconnecting');
    socket = new WebSocket(`${CONFIG.relayWs}/${topic}/ws`);
    socket.onopen = () => {
      retry = 0;
      onStatus?.('online');
      clearInterval(pingTimer);
      pingTimer = setInterval(() => {
        try { socket.send(''); } catch (_) {}
      }, 20000);
    };
    socket.onmessage = event => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.event !== 'message' || !msg.message) return;
        const outer = JSON.parse(msg.message);
        outer.__relayId = msg.id || '';
        onOuter?.(outer);
      } catch (_) {}
    };
    socket.onerror = () => {};
    socket.onclose = () => {
      clearInterval(pingTimer);
      if (closed) return;
      onStatus?.('reconnecting');
      retry += 1;
      setTimeout(connect, Math.min(30000, 1200 + retry * 1800));
    };
  };

  connect();
  return () => {
    closed = true;
    clearInterval(pingTimer);
    try { socket?.close(); } catch (_) {}
  };
}

export async function pollInbox(inboxId, onOuter) {
  const topic = await inboxTopic(inboxId);
  const response = await fetch(`${CONFIG.relayHttp}/${topic}/json?poll=1&since=2m`);
  if (!response.ok) return;
  const text = await response.text();
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.event !== 'message' || !msg.message) continue;
      const outer = JSON.parse(msg.message);
      outer.__relayId = msg.id || '';
      await onOuter?.(outer);
    } catch (_) {}
  }
}
