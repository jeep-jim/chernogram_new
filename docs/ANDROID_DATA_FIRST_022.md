# Android Data First 0.22

## Product focus

Chernogram 0.22 for Android is built from the published stable 0.9.1 transport. The product no longer exposes an AI agent. The primary navigation is Chats, Files, Music, and Profile.

## Interface rules

- One approved striped-face mark is used for launcher, splash, header, fallback avatars, and the music equalizer animation.
- Theme switching is always available in the header.
- Tapping the mark opens a prelanding placeholder.
- Contacts are opened from the compact add-person button inside Chats.
- Direct chats do not show redundant avatars. Group messages show the author mark above the bubble.
- Message bubbles use a sharp upper corner and rounded remaining corners.
- Missed calls use a dark card with a compact red call or video accent.
- Chat surfaces use a restrained pattern background.
- Fields, chips, cards, and controls are rounded and borderless; selected chips do not show extra checkmarks.

## Data and access

- Files from joined rooms are indexed in a single local search.
- Public-room files can be published into the room index.
- Current stable inline transport is capped at 20 MB; a separately verified WebRTC data-channel path is required before claiming unrestricted large-file P2P.
- Chernogram ID remains local and can be protected with PIN or Android biometrics.
- A password-encrypted recovery code transfers the local identity, joined rooms, and known contacts to another device.

## Music

Audio from rooms is collected into the Music section. The approved mark animates as an equalizer while playing or recognizing. Real ambient recognition records a short sample and sends it to the configured recognition provider; the provider token stays on the device.

## Release isolation

This branch builds only an isolated Android preview. It must not replace `latest-apk`, publish Windows packages, or merge into `main` before build verification and manual Android testing.
