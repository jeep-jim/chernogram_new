# OSMINOG Chrome 3.8.63

Base: 3.8.62

- Google AI chat redesigned from the supplied OSMINOG widget specification.
- Duplicate request/response rendering is blocked with request IDs and a busy lock.
- Google AI traffic is routed through a dedicated inactive authenticated service tab, not the visible user conversation.
- DeepSeek's proven direct authenticated web-session transport is unchanged.
- Ctrl+V can attach clipboard images and falls back to the most recent cached screenshot.
- Obsolete INSTALL_BRIEFCRAFT_DEV.cmd text is removed.

Static verification passed. Runtime verification is pending on the owner's Windows/Chrome installation.
