# VeilTalk Privacy Policy

_Last updated: August 22, 2026_

VeilTalk is a Chrome extension for private one-to-one text messaging and browser-based voice and video calls. This Privacy Policy explains what information the extension processes, why it is needed, and where it is stored.

## 1. Data VeilTalk processes

VeilTalk may process the following information when you use its communication features:

- **Profile information:** the display name and local profile identifier that you choose or that the extension creates for your VeilTalk identity.
- **Personal communications:** text messages, files you explicitly send, invitation information, and technical signaling required to establish voice or video calls.
- **Local application data:** contacts, conversation history, settings, connection state, and free-call usage counters.
- **Microphone and camera input:** only after you start or accept a voice/video call and grant Chrome permission.

## 2. Local storage

VeilTalk is designed to keep its profile, contacts, conversation history, settings, and usage counters locally in your Chrome profile using Chrome extension storage. VeilTalk does not operate its own central account database for the review version of the extension.

## 3. Message relay and call signaling

To deliver messages and exchange the technical signals needed to establish WebRTC calls, VeilTalk uses the third-party relay service `ntfy.sh`. Message content is encrypted by the extension before relay transmission. The relay receives encrypted payloads and technical routing data needed to transport them.

Because `ntfy.sh` is an independent third-party service, network metadata such as IP addresses may be processed by that service according to its own terms and privacy practices.

## 4. Voice and video calls

Voice and video calls use WebRTC. Whenever network conditions allow, media is sent directly between the participants' browsers. VeilTalk does not record voice or video calls and does not use call content for advertising, profiling, or analytics.

WebRTC connections may expose network information required to establish a peer connection to the other participant and to browser/network infrastructure used by WebRTC.

## 5. Chrome permissions

- **storage:** saves your local VeilTalk profile, contacts, history, settings, and usage counters.
- **notifications:** shows notifications for incoming messages and calls.
- **sidePanel:** provides the main VeilTalk user interface inside Chrome.
- **alarms:** periodically wakes the Manifest V3 service worker so it can check for missed encrypted messages or call signals.
- **Host access to ntfy.sh:** sends and receives encrypted message envelopes and WebRTC signaling.
- **Microphone/camera:** requested by Chrome only when needed for voice or video calling.

## 6. What VeilTalk does not do

- VeilTalk does not sell personal data.
- VeilTalk does not use personal communications for advertising.
- VeilTalk does not collect browsing history.
- VeilTalk does not read the contents of websites you visit.
- VeilTalk does not collect location, medical, credit, banking, or payment-card information in this review version.
- VeilTalk does not use personal data to determine creditworthiness or for lending purposes.

## 7. Data retention and deletion

Local VeilTalk data remains in your Chrome profile until you remove it through the extension, clear the extension's storage, or uninstall the extension. Data temporarily transmitted through third-party relay infrastructure may be subject to that provider's retention rules.

## 8. International use

VeilTalk is intended for international use. Communication may cross national borders depending on the locations of participants and third-party network infrastructure.

## 9. Children

VeilTalk is not specifically directed to children. Users should use the extension in accordance with the age requirements that apply to their Google/Chrome account and local law.

## 10. Changes to this policy

If VeilTalk materially changes how it processes user data, this Privacy Policy will be updated before or together with the relevant product update.

## 11. Contact

For privacy or support questions, use the project's GitHub issue tracker:

https://github.com/jeep-jim/chernogram_new/issues

Do not post passwords, private message content, payment information, or other sensitive personal information in a public GitHub issue.
