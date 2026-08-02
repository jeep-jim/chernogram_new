interface Env {
  ROOMS: DurableObjectNamespace<Room>;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
}

type Participant = {
  deviceId: string;
  name: string;
  fcmToken?: string;
  lastSeenAt: number;
};

type StoredEnvelope = {
  packetId: string;
  from: string;
  kind: string;
  wake: string;
  ciphertext: string;
  createdAt: number;
};

type SocketAttachment = {
  deviceId: string;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri?: string;
};

let cachedGoogleToken: { value: string; expiresAt: number } | null = null;

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: jsonHeaders });
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function encodeJsonBase64Url(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function bearer(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  return header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
}

async function googleAccessToken(env: Env): Promise<string | null> {
  if (!env.FIREBASE_SERVICE_ACCOUNT_JSON) return null;
  if (cachedGoogleToken && cachedGoogleToken.expiresAt > Date.now() + 60_000) {
    return cachedGoogleToken.value;
  }

  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON) as ServiceAccount;
  const now = Math.floor(Date.now() / 1000);
  const header = encodeJsonBase64Url({ alg: "RS256", typ: "JWT" });
  const payload = encodeJsonBase64Url({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: account.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const unsigned = `${header}.${payload}`;
  const keyBytes = Uint8Array.from(
    atob(account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "")),
    (char) => char.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
  const response = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) return null;
  const body = (await response.json()) as { access_token?: string; expires_in?: number };
  if (!body.access_token) return null;
  cachedGoogleToken = {
    value: body.access_token,
    expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000,
  };
  return body.access_token;
}

async function sendPush(
  env: Env,
  participant: Participant,
  envelope: StoredEnvelope,
  roomKey: string,
): Promise<void> {
  if (!participant.fcmToken) return;
  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || "{}") as Partial<ServiceAccount>;
  if (!account.project_id) return;
  const accessToken = await googleAccessToken(env);
  if (!accessToken) return;

  const call = envelope.wake === "call";
  const title = call ? "Входящий звонок" : "Чернограм";
  const body = call ? "Кто-то звонит вам в Чернограме" : "Новое сообщение";
  await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
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
          priority: "HIGH",
          ttl: call ? "60s" : "86400s",
          notification: {
            channel_id: call ? "chernogram_calls" : "chernogram_messages",
            priority: call ? "PRIORITY_MAX" : "PRIORITY_HIGH",
            visibility: "PRIVATE",
            sound: "default",
          },
        },
      },
    }),
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return json({ ok: true, service: "chernogram-impulse", version: 1 });
    }
    const match = url.pathname.match(/^\/v1\/rooms\/([A-Za-z0-9_-]{20,})\/(register|ws|envelopes|pull|ack)$/);
    if (!match) return json({ error: "not_found" }, 404);

    const [, roomKey, action] = match;
    const object = env.ROOMS.get(env.ROOMS.idFromName(roomKey));
    const target = new URL(request.url);
    target.pathname = `/${action}`;
    target.searchParams.set("roomKey", roomKey);
    return object.fetch(new Request(target.toString(), request));
  },
} satisfies ExportedHandler<Env>;

export class Room extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  private async authorized(request: Request): Promise<boolean> {
    const token = bearer(request);
    if (!token || token.length < 20) return false;
    const hash = await sha256Hex(token);
    const existing = await this.ctx.storage.get<string>("authHash");
    if (!existing) {
      await this.ctx.storage.put("authHash", hash);
      return true;
    }
    return existing === hash;
  }

  private async participants(): Promise<Record<string, Participant>> {
    return (await this.ctx.storage.get<Record<string, Participant>>("participants")) ?? {};
  }

  private async saveParticipants(value: Record<string, Participant>): Promise<void> {
    await this.ctx.storage.put("participants", value);
  }

  private async registerParticipant(input: Participant): Promise<void> {
    const participants = await this.participants();
    participants[input.deviceId] = {
      deviceId: input.deviceId,
      name: input.name || participants[input.deviceId]?.name || "Устройство",
      fcmToken: input.fcmToken || participants[input.deviceId]?.fcmToken,
      lastSeenAt: Date.now(),
    };
    await this.saveParticipants(participants);
  }

  private broadcast(envelope: StoredEnvelope): void {
    const payload = JSON.stringify({ type: "envelope", envelope });
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (attachment?.deviceId === envelope.from) continue;
      try {
        socket.send(payload);
      } catch {
        try {
          socket.close(1011, "send_failed");
        } catch {}
      }
    }
  }

  private async storeEnvelope(envelope: StoredEnvelope, roomKey: string): Promise<void> {
    if (!envelope.packetId || !envelope.from || !envelope.ciphertext) {
      throw new Error("invalid_envelope");
    }
    if (envelope.ciphertext.length > 1_800_000) throw new Error("envelope_too_large");
    envelope.createdAt = envelope.createdAt || Date.now();
    await this.ctx.storage.put(`env:${envelope.packetId}`, envelope);
    await this.ctx.storage.setAlarm(Date.now() + 60_000);
    this.broadcast(envelope);

    const participants = await this.participants();
    const pushes = Object.values(participants)
      .filter((participant) => participant.deviceId !== envelope.from)
      .map((participant) => sendPush(this.env, participant, envelope, roomKey).catch(() => undefined));
    await Promise.all(pushes);
  }

  async fetch(request: Request): Promise<Response> {
    if (!(await this.authorized(request))) return json({ error: "unauthorized" }, 401);
    const url = new URL(request.url);
    const roomKey = url.searchParams.get("roomKey") ?? "";

    if (url.pathname === "/register" && request.method === "POST") {
      const body = (await request.json()) as Partial<Participant>;
      if (!body.deviceId) return json({ error: "device_required" }, 400);
      await this.registerParticipant({
        deviceId: body.deviceId,
        name: body.name ?? "Устройство",
        fcmToken: body.fcmToken,
        lastSeenAt: Date.now(),
      });
      return json({ ok: true });
    }

    if (url.pathname === "/ws") {
      if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
        return json({ error: "websocket_required" }, 426);
      }
      const deviceId = url.searchParams.get("device") ?? "";
      const name = url.searchParams.get("name") ?? "Устройство";
      if (!deviceId) return json({ error: "device_required" }, 400);
      await this.registerParticipant({ deviceId, name, lastSeenAt: Date.now() });

      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      server.serializeAttachment({ deviceId } satisfies SocketAttachment);
      this.ctx.acceptWebSocket(server);
      return new Response(null, { status: 101, webSocket: client });
    }

    if (url.pathname === "/envelopes" && request.method === "POST") {
      const body = (await request.json()) as StoredEnvelope;
      try {
        await this.storeEnvelope(body, roomKey);
      } catch (error) {
        return json({ error: String(error) }, 400);
      }
      return json({ ok: true, packetId: body.packetId }, 202);
    }

    if (url.pathname === "/pull" && request.method === "GET") {
      const deviceId = url.searchParams.get("device") ?? "";
      if (!deviceId) return json({ error: "device_required" }, 400);
      const list = await this.ctx.storage.list<StoredEnvelope>({ prefix: "env:" });
      const envelopes = [...list.values()]
        .filter((item) => item.from !== deviceId)
        .sort((a, b) => a.createdAt - b.createdAt)
        .slice(0, 200);
      return json({ envelopes, serverTime: Date.now() });
    }

    if (url.pathname === "/ack" && request.method === "POST") {
      const body = (await request.json()) as { packetIds?: string[] };
      const packetIds = (body.packetIds ?? []).filter((id) => id.length > 0).slice(0, 200);
      await Promise.all(packetIds.map((packetId) => this.ctx.storage.delete(`env:${packetId}`)));
      return json({ ok: true, removed: packetIds.length });
    }

    return json({ error: "method_not_allowed" }, 405);
  }

  async webSocketMessage(socket: WebSocket, message: ArrayBuffer | string): Promise<void> {
    try {
      const parsed = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message)) as {
        type?: string;
        envelope?: StoredEnvelope;
        roomKey?: string;
      };
      if (parsed.type !== "envelope" || !parsed.envelope) return;
      const attachment = socket.deserializeAttachment() as SocketAttachment | null;
      if (!attachment || parsed.envelope.from !== attachment.deviceId) return;
      await this.storeEnvelope(parsed.envelope, parsed.roomKey ?? "");
      socket.send(JSON.stringify({ type: "accepted", packetId: parsed.envelope.packetId }));
    } catch {
      socket.send(JSON.stringify({ type: "error", error: "invalid_message" }));
    }
  }

  async webSocketClose(socket: WebSocket, code: number, reason: string): Promise<void> {
    socket.close(code, reason);
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    try {
      socket.close(1011, "socket_error");
    } catch {}
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    const envelopes = await this.ctx.storage.list<StoredEnvelope>({ prefix: "env:" });
    const oldEnvelopeKeys = [...envelopes.entries()]
      .filter(([, envelope]) => now - envelope.createdAt > 24 * 60 * 60 * 1000)
      .map(([key]) => key);
    await Promise.all(oldEnvelopeKeys.map((key) => this.ctx.storage.delete(key)));

    const participants = await this.participants();
    let changed = false;
    for (const [deviceId, participant] of Object.entries(participants)) {
      if (now - participant.lastSeenAt > 30 * 24 * 60 * 60 * 1000) {
        delete participants[deviceId];
        changed = true;
      }
    }
    if (changed) await this.saveParticipants(participants);
    if (envelopes.size > oldEnvelopeKeys.length) {
      await this.ctx.storage.setAlarm(now + 60 * 60 * 1000);
    }
  }
}
