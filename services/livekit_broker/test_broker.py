from __future__ import annotations

import unittest

from broker import BrokerRequestError, BrokerSettings, issue_join_token


class LiveKitBrokerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.settings = BrokerSettings(
            api_key="devkey",
            api_secret="secret",
            ws_url="wss://livekit.example.test",
            shared_secret="test-broker-key",
            cors_origin="*",
            token_ttl_minutes=30,
            bind_host="127.0.0.1",
            bind_port=8090,
        )

    def test_issues_room_join_token(self) -> None:
        result = issue_join_token(
            self.settings,
            {
                "room": "android-windows-test",
                "identity": "android-user-01",
                "displayName": "Android user",
            },
        )

        self.assertEqual(result["url"], "wss://livekit.example.test")
        self.assertEqual(result["room"], "android-windows-test")
        self.assertEqual(result["identity"], "android-user-01")
        self.assertEqual(result["expiresIn"], 1800)
        self.assertEqual(result["token"].count("."), 2)

    def test_rejects_invalid_room(self) -> None:
        with self.assertRaises(BrokerRequestError):
            issue_join_token(
                self.settings,
                {"room": "bad room", "identity": "android-user-01"},
            )

    def test_rejects_invalid_identity(self) -> None:
        with self.assertRaises(BrokerRequestError):
            issue_join_token(
                self.settings,
                {"room": "valid-room", "identity": "bad identity"},
            )

    def test_empty_display_name_falls_back_to_identity(self) -> None:
        result = issue_join_token(
            self.settings,
            {
                "room": "valid-room",
                "identity": "windows-user-01",
                "displayName": "   ",
            },
        )
        self.assertEqual(result["identity"], "windows-user-01")
        self.assertEqual(result["token"].count("."), 2)


if __name__ == "__main__":
    unittest.main()
