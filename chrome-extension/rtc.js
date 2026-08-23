import { CONFIG } from './config.js';

const enc = new TextEncoder();

function toBase64(bytes) {
  let value = '';
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value);
}

async function createOpenRelayCredential() {
  const expires = Math.floor(Date.now() / 1000) + (CONFIG.openRelay.credentialHours * 60 * 60);
  const username = String(expires);
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(CONFIG.openRelay.sharedSecret),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign']
  );
  const signature = await crypto.subtle.sign('HMAC', key, enc.encode(username));
  return { username, credential: toBase64(new Uint8Array(signature)) };
}

export async function getIceServers() {
  const servers = [...CONFIG.iceServers];
  if (!CONFIG.openRelay.enabled) return servers;
  const auth = await createOpenRelayCredential();
  const host = CONFIG.openRelay.host;
  servers.push({
    urls: [
      `turn:${host}:80?transport=udp`,
      `turn:${host}:80?transport=tcp`,
      `turn:${host}:443?transport=tcp`,
      `turns:${host}:443?transport=tcp`
    ],
    ...auth
  });
  return servers;
}

export async function createPeerConnection() {
  return new RTCPeerConnection({
    iceServers: await getIceServers(),
    iceCandidatePoolSize: 4,
    bundlePolicy: 'max-bundle'
  });
}

export async function addIceOrQueue(session, candidate) {
  if (!candidate) return;
  if (!session.pc.remoteDescription) {
    session.pendingIce ||= [];
    session.pendingIce.push(candidate);
    return;
  }
  await session.pc.addIceCandidate(candidate);
}

export async function flushIce(session) {
  const pending = session.pendingIce || [];
  session.pendingIce = [];
  for (const candidate of pending) await session.pc.addIceCandidate(candidate);
}
