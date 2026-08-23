const enc = new TextEncoder();
const dec = new TextDecoder();

export function randomId(bytes = 16) {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  return toBase64Url(data);
}

export function toBase64Url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function fromBase64Url(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4);
  const raw = atob(padded);
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}

export async function sha256Base64(value) {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(value));
  return toBase64Url(new Uint8Array(digest));
}

export async function deriveKey(secret) {
  const raw = await crypto.subtle.digest('SHA-256', enc.encode(`veiltalk:v1:${secret}`));
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}

export async function encryptJson(secret, value) {
  const key = await deriveKey(secret);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const clear = enc.encode(JSON.stringify(value));
  const cipher = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, clear);
  return { v: 1, iv: toBase64Url(iv), data: toBase64Url(new Uint8Array(cipher)) };
}

export async function decryptJson(secret, box) {
  if (!box || box.v !== 1) throw new Error('Unsupported encrypted envelope');
  const key = await deriveKey(secret);
  const clear = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: fromBase64Url(box.iv) },
    key,
    fromBase64Url(box.data)
  );
  return JSON.parse(dec.decode(clear));
}

export function encodeInvite(invite) {
  return `VT1.${toBase64Url(enc.encode(JSON.stringify(invite)))}`;
}

export function decodeInvite(value) {
  const raw = value.trim();
  if (!raw.startsWith('VT1.')) throw new Error('Invalid VeilTalk invite');
  return JSON.parse(dec.decode(fromBase64Url(raw.slice(4))));
}
