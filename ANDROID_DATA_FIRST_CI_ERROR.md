# Android 0.22.2 release failed

Source head: 92c2f3389511c838d98892b9761b18db90c7ec9c
Workflow commit: 992467b29fbee57517eb6e08f9bd1bd445edddda
Time: 2026-07-29T11:03:26Z

## android-release-0222.log
```text
Alias name: androiddebugkey
Creation date: Jul 26, 2026
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=Chernogram Prototype, O=Chernogram, C=RU
Issuer: CN=Chernogram Prototype, O=Chernogram, C=RU
Serial number: 967052ca6b03ab0c
Valid from: Sun Jul 26 08:31:07 UTC 2026 until: Thu Dec 11 08:31:07 UTC 2053
Certificate fingerprints:
	 SHA1: 77:F4:C8:E6:D1:BD:16:77:71:73:2B:9E:D3:2F:6A:16:5F:B0:55:69
	 SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
Signature algorithm name: SHA256withRSA
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3

Extensions: 

#1: ObjectId: 2.5.29.14 Criticality=false
SubjectKeyIdentifier [
KeyIdentifier [
0000: 5D 0A 01 66 F4 65 7B D0   A3 7E 37 D0 83 15 C4 E2  ]..f.e....7.....
0010: 5C 63 54 2F                                        \cT/
]
]

Applied Chernogram 0.8 app-wide calls, sounds and message ordering fixes
Applied Chernogram 0.9 media library, voice, circles and WebRTC replay fixes
Applied Chernogram 0.9 compile safeguards
Android data-first UI materialized
Android data-first compatibility finalized
Android data-first background realtime materialized
Traceback (most recent call last):
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/restore_android_features_v1.py", line 1043, in <module>
    main()
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/restore_android_features_v1.py", line 1037, in main
    patch_chat_screen()
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/restore_android_features_v1.py", line 72, in patch_chat_screen
    text = replace_once(
           ^^^^^^^^^^^^^
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/restore_android_features_v1.py", line 11, in replace_once
    raise RuntimeError(f"{label}: expected one anchor, found {count}")
RuntimeError: reply state: expected one anchor, found 2
```

## signing-key.txt
```text
Alias name: androiddebugkey
Creation date: Jul 26, 2026
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=Chernogram Prototype, O=Chernogram, C=RU
Issuer: CN=Chernogram Prototype, O=Chernogram, C=RU
Serial number: 967052ca6b03ab0c
Valid from: Sun Jul 26 08:31:07 UTC 2026 until: Thu Dec 11 08:31:07 UTC 2053
Certificate fingerprints:
	 SHA1: 77:F4:C8:E6:D1:BD:16:77:71:73:2B:9E:D3:2F:6A:16:5F:B0:55:69
	 SHA256: F4:A2:C8:36:A8:36:71:19:78:10:FA:6E:98:2D:77:F4:C7:31:D0:9B:18:95:15:C0:13:D0:2D:0D:94:2D:9B:BE
Signature algorithm name: SHA256withRSA
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3

Extensions: 

#1: ObjectId: 2.5.29.14 Criticality=false
SubjectKeyIdentifier [
KeyIdentifier [
0000: 5D 0A 01 66 F4 65 7B D0   A3 7E 37 D0 83 15 C4 E2  ]..f.e....7.....
0010: 5C 63 54 2F                                        \cT/
]
]

```
