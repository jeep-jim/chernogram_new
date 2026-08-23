# VeilTalk Privacy Policy

_Last updated: August 23, 2026_

VeilTalk is a free Chrome extension for private one-to-one text messaging, peer-to-peer file transfer, and browser-based voice and video calls. This Privacy Policy explains what information the extension processes, why it is needed, and where it is stored.

## 1. Data VeilTalk processes

- **Profile information:** the display name, avatar, and local profile identifier that you choose or that the extension creates.
- **Personal communications:** text messages, files you explicitly send, invitation information, and technical signaling required to establish file transfers and calls.
- **Local application data:** contacts, conversation history, downloaded files, settings, and connection state.
- **Microphone, camera, and screen input:** only after you use the corresponding calling feature and grant Chrome permission.

## 2. Local storage

VeilTalk keeps its profile, contacts, conversation history, settings, and transferred files locally in your Chrome profile. Files may be stored in IndexedDB or the browser's Origin Private File System so they can be downloaded again. VeilTalk does not operate its own central account database.

## 3. Message relay and signaling

VeilTalk uses the third-party relay service `ntfy.sh` to deliver messages and exchange WebRTC signaling. Message content, file metadata, and signaling payloads are encrypted by the extension before relay transmission. File contents are transferred over WebRTC and are not uploaded to `ntfy.sh`.

Because `ntfy.sh` is independent, network metadata such as IP addresses may be processed according to its own terms and privacy practices.

## 4. Voice, video, and file transfers

Voice calls, video calls, screen sharing, and file transfers use WebRTC. Data is sent directly between participants whenever network conditions allow. If a direct connection cannot be established, VeilTalk may use third-party STUN or TURN infrastructure, including Metered Open Relay, to establish or relay the encrypted WebRTC connection.

VeilTalk does not record calls and does not use call or file content for advertising, profiling, or analytics. WebRTC infrastructure may process IP addresses and other network metadata required to establish or relay a connection.

## 5. Chrome permissions

- **storage:** saves the local profile, contacts, history, and settings.
- **unlimitedStorage:** allows larger user-selected files to be kept in local browser storage.
- **notifications:** shows notifications for incoming messages, files, and calls.
- **sidePanel:** provides the main interface inside Chrome.
- **alarms:** checks for missed encrypted messages and call signals.
- **Host access to ntfy.sh:** sends and receives encrypted message envelopes and signaling.
- **Microphone/camera/screen:** requested only for voice, video, or screen sharing.

## 6. What VeilTalk does not do

- VeilTalk does not sell personal data or use communications for advertising.
- VeilTalk does not collect browsing history or read websites you visit.
- VeilTalk does not collect location, medical, credit, banking, or payment-card information.
- VeilTalk does not use personal data for creditworthiness or lending.

## 7. Data retention and deletion

Local data remains in your Chrome profile until you delete a chat, clear extension storage, or uninstall the extension. Deleting a chat removes its locally stored messages and files from that browser profile. Third-party relay data may be subject to that provider's retention rules.

## 8. International use

Communication may cross national borders depending on the locations of participants and third-party network infrastructure.

## 9. Children

VeilTalk is not specifically directed to children. Users should follow the age requirements for their Google/Chrome account and local law.

## 10. Changes to this policy

If VeilTalk materially changes how it processes data, this policy will be updated before or together with the relevant product update.

## 11. Contact

For privacy or support questions, use the project's GitHub issue tracker:

https://github.com/jeep-jim/chernogram_new/issues

Do not post passwords, private message content, payment information, or other sensitive personal information in a public GitHub issue.
