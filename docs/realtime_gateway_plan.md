# Cernogram Realtime Gateway

Implementation plan for the encrypted WSS transport described in `docs/realtime_protocol_v1.md`.

- one authenticated WebSocket per client;
- multiplexed rooms;
- opaque ciphertext routing;
- ACK, sequence and resume cursor;
- durable store-and-forward;
- feature-flagged client migration from legacy relay.
