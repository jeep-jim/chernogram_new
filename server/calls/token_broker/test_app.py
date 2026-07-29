from __future__ import annotations

import base64
import hashlib
import hmac
import importlib
import json
import os
import time

from fastapi.testclient import TestClient

SECRET = "access-secret-abcdefghijklmnopqrstuvwxyz"
TICKET_SECRET = "ticket-secret-abcdefghijklmnopqrstuvwxyz"
ISSUER_SECRET = "issuer-secret-abcdefghijklmnopqrstuvwxyz"
LIVEKIT_SECRET = "livekit-secret-abcdefghijklmnopqrstuvwxyz"

os.environ.update(
    {
        "LIVEKIT_PUBLIC_URL": "wss://rtc.example.test",
        "LIVEKIT_API_KEY": "test-key",
        "LIVEKIT_API_SECRET": LIVEKIT_SECRET,
        "CERNOGRAM_ACCESS_TOKEN_SECRET": SECRET,
        "CERNOGRAM_CALL_TICKET_SECRET": TICKET_SECRET,
        "CERNOGRAM_CALL_TICKET_ISSUER_SECRET": ISSUER_SECRET,
        "CALL_TOKEN_TTL": "300",
        "CALL_TICKET_TTL": "90",
    }
)

app_module = importlib.import_module("app")
client = TestClient(app_module.APP)


def b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def access_token(profile_id: str, device_id: str) -> str:
    payload = json.dumps(
        {
            "profileId": profile_id,
            "deviceId": device_id,
            "exp": int(time.time()) + 300,
        },
        separators=(",", ":"),
    ).encode()
    signature = hmac.new(SECRET.encode(), payload, hashlib.sha256).digest()
    return f"{b64(payload)}.{b64(signature)}"


def test_ticket_and_join_token_flow() -> None:
    ticket_response = client.post(
        "/v1/calls/ticket",
        headers={"Authorization": f"Bearer {ISSUER_SECRET}"},
        json={
            "call_id": "call-12345678",
            "room_name": "room-12345678",
            "participant_profile_ids": ["alice", "bob"],
            "video": True,
        },
    )
    assert ticket_response.status_code == 200, ticket_response.text
    ticket = ticket_response.json()["call_ticket"]

    join_response = client.post(
        "/v1/calls/token",
        headers={"Authorization": f"Bearer {access_token('alice', 'phone-a')}"},
        json={
            "call_ticket": ticket,
            "profile_id": "alice",
            "device_id": "phone-a",
            "display_name": "Alice",
        },
    )
    assert join_response.status_code == 200, join_response.text
    body = join_response.json()
    assert body["server_url"] == "wss://rtc.example.test"
    assert body["room_name"] == "room-12345678"
    assert body["call_id"] == "call-12345678"
    assert body["video"] is True
    assert body["participant_token"].count(".") == 2


def test_uninvited_profile_is_rejected() -> None:
    ticket = client.post(
        "/v1/calls/ticket",
        headers={"Authorization": f"Bearer {ISSUER_SECRET}"},
        json={
            "call_id": "call-abcdefgh",
            "room_name": "room-abcdefgh",
            "participant_profile_ids": ["alice"],
        },
    ).json()["call_ticket"]

    response = client.post(
        "/v1/calls/token",
        headers={"Authorization": f"Bearer {access_token('mallory', 'phone-m')}"},
        json={
            "call_ticket": ticket,
            "profile_id": "mallory",
            "device_id": "phone-m",
            "display_name": "Mallory",
        },
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "participant_not_invited"


def test_profile_and_device_must_match_access_token() -> None:
    ticket = client.post(
        "/v1/calls/ticket",
        headers={"Authorization": f"Bearer {ISSUER_SECRET}"},
        json={
            "call_id": "call-mismatch1",
            "room_name": "room-mismatch1",
            "participant_profile_ids": ["alice"],
        },
    ).json()["call_ticket"]

    response = client.post(
        "/v1/calls/token",
        headers={"Authorization": f"Bearer {access_token('alice', 'phone-a')}"},
        json={
            "call_ticket": ticket,
            "profile_id": "alice",
            "device_id": "phone-b",
            "display_name": "Alice",
        },
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "device_mismatch"
