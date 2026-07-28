# Cernogram Realtime Protocol v1

Status: draft for implementation in issue #4.

## Goals

- One authenticated WebSocket connection per running client.
- Multiplex encrypted events for all rooms/tunnels over one connection.
- The gateway never receives room plaintext or room encryption keys.
- At-least-once delivery with client-side idempotency.
- Durable store-and-forward, ACK and resume cursor.
- Message delivery must not block the Flutter UI thread.

## Transport

- `wss://<host>/v1/realtime`
- JSON text frames for v1. Binary frames can be introduced later for encrypted file chunks.
- Every frame has `type`, `requestId` and `protocol: 1` where applicable.
- Client reconnect uses exponential backoff with jitter, but an OS network-change event may trigger an immediate attempt.

## Session handshake

Client:

```json
{
  "type": "hello",
  "protocol": 1,
  "requestId": "random-id",
  "deviceId": "stable-device-id",
  "profileId": "public-profile-id",
  "accessToken": "short-lived-server-token",
  "resume": {
    "lastServerSeq": 12044
  },
  "rooms": [
    {
      "roomId": "routing-room-id",
      "lastRoomSeq": 818
    }
  ]
}
```

Server:

```json
{
  "type": "hello_ack",
  "protocol": 1,
  "requestId": "random-id",
  "sessionId": "server-session-id",
  "serverTime": "2026-07-28T12:00:00Z",
  "heartbeatSeconds": 20,
  "maxFrameBytes": 65536
}
```

Authentication tokens are minted by the Cernogram backend. Long-lived backend secrets are never embedded in APK/EXE.

## Encrypted event

The gateway routes by `roomId`, but `ciphertext`, nonce and MAC are opaque.

```json
{
  "type": "event",
  "protocol": 1,
  "requestId": "client-request-id",
  "packetId": "stable-id-across-retries",
  "roomId": "routing-room-id",
  "kind": "message",
  "priority": "normal",
  "createdAt": "2026-07-28T12:00:01Z",
  "ttlSeconds": 604800,
  "crypto": {
    "algorithm": "AES-256-GCM",
    "keyVersion": 1,
    "nonce": "base64url",
    "ciphertext": "base64url",
    "mac": "base64url"
  }
}
```

Allowed priorities:

- `realtime`: call signaling and typing state; short TTL.
- `high`: control operations and read receipts.
- `normal`: text messages.
- `bulk`: file metadata and chunk coordination.

## Server acceptance ACK

```json
{
  "type": "ack",
  "protocol": 1,
  "requestId": "client-request-id",
  "packetId": "stable-id-across-retries",
  "serverSeq": 12045,
  "roomSeq": 819,
  "acceptedAt": "2026-07-28T12:00:01Z"
}
```

The sender removes an item from persistent outbox only after this ACK.

## Delivery to recipients

```json
{
  "type": "delivery",
  "protocol": 1,
  "serverSeq": 12045,
  "roomSeq": 819,
  "packetId": "stable-id-across-retries",
  "roomId": "routing-room-id",
  "senderProfileId": "public-profile-id",
  "kind": "message",
  "createdAt": "2026-07-28T12:00:01Z",
  "crypto": {
    "algorithm": "AES-256-GCM",
    "keyVersion": 1,
    "nonce": "base64url",
    "ciphertext": "base64url",
    "mac": "base64url"
  }
}
```

Recipient:

```json
{
  "type": "delivery_ack",
  "protocol": 1,
  "packetId": "stable-id-across-retries",
  "serverSeq": 12045,
  "state": "stored"
}
```

Application-level delivered/read receipts are separate encrypted room events so the gateway does not learn message semantics.

## Presence

Presence is ephemeral and never stored as normal history.

```json
{
  "type": "presence",
  "protocol": 1,
  "roomId": "routing-room-id",
  "state": "online",
  "expiresInSeconds": 35
}
```

The server emits a room presence snapshot/delta. Current device is not counted as another participant.

## Resume and replay

After `hello_ack`, the gateway replays deliveries with `serverSeq > lastServerSeq`. The client deduplicates by `packetId`, stores the highest contiguous cursor, and periodically sends:

```json
{
  "type": "cursor_ack",
  "protocol": 1,
  "lastServerSeq": 12045
}
```

## Heartbeat

- Server sends `ping` every negotiated interval.
- Client answers `pong` immediately.
- A missed heartbeat does not delete the persistent outbox.
- Presence expires independently if heartbeats stop.

## Error frame

```json
{
  "type": "error",
  "protocol": 1,
  "requestId": "optional-request-id",
  "code": "rate_limited",
  "retryAfterMs": 1500,
  "message": "safe-human-readable-message"
}
```

## Required server guarantees

- `(deviceId, packetId)` is idempotent.
- ACK is returned only after durable storage for store-and-forward events.
- Expired events are deleted.
- The server cannot decrypt room content.
- Per-device and per-room limits prevent abuse without leaking plaintext.
- Disconnecting one slow client cannot block other sessions.

## Migration

The Flutter client exposes a transport interface:

- `GatewayRealtimeTransport` — new protocol.
- `LegacyNtfyTransport` — temporary fallback behind a feature flag.

New messages use the gateway when configured. Legacy fallback is removed after real-device acceptance tests pass.
