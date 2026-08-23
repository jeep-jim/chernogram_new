# VeilTalk Privacy Policy

_Last updated: August 23, 2026_

VeilTalk is a Chrome extension for private one-to-one text messaging, peer-to-peer file transfer, and browser-based voice and video calls. This Privacy Policy explains what information the extension processes, why it is needed, and where it is stored.

## 1. Data VeilTalk processes

VeilTalk may process the following information when you use its communication features:

- **Profile information:** the display name, avatar, and local profile identifier that you choose or that the extension creates for your VeilTalk identity.
- **Personal communications:** text messages, files you explicitly send, invitation information, and technical signaling required to establish file transfers and voice or video calls.
- **Local application data:** contacts, conversation history, downloaded files, settings, connection state, and free-call usage counters.
- **Microphone, camera, and screen input:** only after you start or accept a call, enable video or screen sharing, and grant the relevant Chrome permission.

## 2. Local storage

VeilTalk keeps its profile, contacts, conversation history, settings, and usage counters locally in your Chrome profile. Files that you send or receive may be stored locally in IndexedDB or the browser's Origin Private File System so that they can be downloaded again. VeilTalk does not operate its own central account database.

## 3. Message relay and signaling

To deliver messages and exchange the technical signals needed to establish WebRTC calls and file transfers, VeilTalk uses the third-party relay service `ntfy.sh`. Message content, file metadata, and signaling payloads are encrypted by the extension before relay transmission. File contents are transferred over WebRTC and are not uploaded to `ntfy.sh`.

Because `ntfy.sh` is an independent third-party service, network metadata such as IP addresses may be processed by that service according to its own terms and privacy practices.

## 4. Voice, video, and file transfers

Voice calls, video calls, screen sharing, and file transfers use WebRTC. Whenever network conditions allow, data is sent directly between the participants' browsers. When a direct connection cannot be established, VeilTalk may use third-party STUN or TURN infrastructure, including Metered Open Relay, to establish or relay the encrypted WebRTC connection.

VeilTalk does not record calls and does not use call or file content for advertising, profiling, or analytics. WebRTC infrastructure may process IP addresses and other network metadata required to establish or relay a connection.

## 5. Chrome permissions

- **storage:** saves the local VeilTalk profile, contacts, history, settings, and usage counters.
- **unlimitedStorage:** allows larger user-selected files to be kept in local browser storage.
- **notifications:** shows notifications for incoming messages, files, and calls.
- **sidePanel:** provides the main VeilTalk user interface inside Chrome.
- **alarms:** periodically wakes the Manifest V3 service worker so it can check for missed encrypted messages or call signals.
- **Host access to ntfy.sh:** sends and receives encrypted message envelopes and WebRTC signaling.
- **Microphone/camera/screen:** requested by Chrome only when needed for voice, video, or screen sharing.

## 6. Payments

When Pro billing is enabled, payment checkout and subscription management are hosted by the configured payment provider through Monetize.software. VeilTalk does not request or store payment-card numbers. The payment provider may process account, payment, and network information according to its own privacy policy. VeilTalk may store the minimum entitlement state needed to enable Pro features.

## 7. What VeilTalk does not do

- VeilTalk does not sell personal data.
- VeilTalk does not use personal communications for advertising.
- VeilTalk does not collect browsing history.
- VeilTalk does not read the contents of websites you visit.
- VeilTalk does not collect location, medical, credit, or banking information.
- VeilTalk does not use personal data to determine creditworthiness or for lending purposes.

## 8. Data retention and deletion

Local VeilTalk data remains in your Chrome profile until you delete a chat, clear extension storage, or uninstall the extension. Deleting a chat removes its locally stored messages and files from that browser profile. Data temporarily transmitted through third-party relay infrastructure may be subject to that provider's retention rules.

## 9. International use

VeilTalk is intended for international use. Communication may cross national borders depending on the locations of participants and third-party network infrastructure.

## 10. Children

VeilTalk is not specifically directed to children. Users should use the extension in accordance with the age requirements that apply to their Google/Chrome account and local law.

## 11. Changes to this policy

If VeilTalk materially changes how it processes user data, this Privacy Policy will be updated before or together with the relevant product update.

## 12. Contact

For privacy or support questions, use the project's GitHub issue tracker:

https://github.com/jeep-jim/chernogram_new/issues

Do not post passwords, private message content, payment information, or other sensitive personal information in a public GitHub issue.
