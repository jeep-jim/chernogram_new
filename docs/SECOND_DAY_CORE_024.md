# Chernogram 0.24 — second-day core

## Source of truth

The transport baseline is commit `d696e470cb96e61a0e5cc29c9e335b5da5a8f69b` — Chernogram 0.8, where messages and calls were reported working across application screens. The preceding chat/call baseline is `ac41b1417b2818fc847270e015b76475d055e84a`.

## Failure found in later architecture

The current application accumulated more than one hundred commits over that baseline. Chat, the background monitor and call signaling began opening, replacing and closing relay sessions independently. UI materializers repeatedly patched the same files. This created multiple owners for one room transport: one path could reconnect or close a session while another path still displayed or used it. The visible result is a permanent `connecting/not connected` state, messages entering a different session than the listener, and lost call signals.

## 0.24 repair rule

- Preserve the approved current interface, settings, files, music and profile screens.
- Restore the second-day message transport and WebRTC signaling behavior as the base.
- One room has one shared transport session.
- Chat, background monitoring and calls subscribe to the same session instead of opening competing sessions.
- Sending is never blocked by a connection label: messages are stored locally first and queued for retry.
- The interface must not display an endless connection failure. After a short connection attempt it shows an unobtrusive offline queue state and keeps working.
- Calls reuse the room signaling session, buffer offer/answer/ICE in order and cancel immediately.
- Do not publish 0.24 until analyze, tests, Android release and Windows release pass.

## Version

Target: `0.24.0+56`.
