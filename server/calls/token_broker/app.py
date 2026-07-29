from __future__ import annotations

import base64
import datetime as dt
import hashlib
import hmac
import json
import os
import re
import time
from typing import Annotated, Any

import jwt
from fastapi import FastAPI, Header, HTTPException
from livekit import api
from pydantic import BaseModel, Field

APP = FastAPI(title="Cernogram Calls Token Broker", version="0.1.0")

LIVEKIT_URL = os.getenv("LIVEKIT_PUBLIC_URL", "").strip()
LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY", "").strip()
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET", "").strip()
ACCESS_TOKEN_SECRET = os.getenv("CERNOGRAM_ACCESS_TOKEN_SECRET", "").strip()
CALL_TICKET_SECRET = os.getenv("CERNOGRAM_CALL_TICKET_SECRET", "").strip()
TICKET_ISSUER_SECRET = os.getenv("CERNOGRAM_CALL_TICKET_ISSUER_SECRET", "").strip()
ALLOW_INSECURE_DEV = os.getenv("CG_CALLS_ALLOW_INSECURE_DEV", "0") == "1"
CALL_TOKEN_TTL = max(60, min(900, int(os.getenv("CALL_TOKEN_TTL", "300"))))
CALL_TICKET_TTL = max(30, min(300, int(os.getenv("CALL_TICKET_TTL", "90"))))
ID_PATTERN = re.compile(r"^[A-Za-z0-9_.:@-]{1,160}$")


class AccessClaims(BaseModel):
    profile_id: str
    device_id: str
    expires_at: int


class CallTicketRequest(BaseModel):
    call_id: str = Field(min_length=8, max_length=160)
    room_name: str = Field(min_length=8, max_length=160)
    participant_profile_ids: list[str] = Field(min_length=1, max_length=50)
    video: bool = False
    can_publish: bool = True
    can_subscribe: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class CallTicketResponse(BaseModel):
    call_ticket: str
    expires_at: int


class JoinRequest(BaseModel):
    call_ticket: str = Field(min_length=20)
    profile_id: str = Field(min_length=1, max_length=160)
    device_id: str = Field(min_length=1, max_length=160)
    display_name: str = Field(default="user", max_length=120)
    participant_metadata: dict[str, Any] = Field(default_factory=dict)


class JoinResponse(BaseModel):
    server_url: str
    participant_token: str
    room_name: str
    call_id: str
    video: bool
    expires_at: int


@APP.on_event("startup")
async def validate_configuration() -> None:
    missing = [
        name
        for name, value in {
            "LIVEKIT_PUBLIC_URL": LIVEKIT_URL,
            "LIVEKIT_API_KEY": LIVEKIT_API_KEY,
            "LIVEKIT_API_SECRET": LIVEKIT_API_SECRET,
            "CERNOGRAM_ACCESS_TOKEN_SECRET": ACCESS_TOKEN_SECRET,
            "CERNOGRAM_CALL_TICKET_SECRET": CALL_TICKET_SECRET,
            "CERNOGRAM_CALL_TICKET_ISSUER_SECRET": TICKET_ISSUER_SECRET,
        }.items()
        if not value
    ]
    if missing and not ALLOW_INSECURE_DEV:
        raise RuntimeError(f"Missing required configuration: {', '.join(missing)}")
    if LIVEKIT_API_SECRET and len(LIVEKIT_API_SECRET) < 32:
        raise RuntimeError("LIVEKIT_API_SECRET must contain at least 32 characters")
    if ACCESS_TOKEN_SECRET and len(ACCESS_TOKEN_SECRET) < 32:
        raise RuntimeError("CERNOGRAM_ACCESS_TOKEN_SECRET is too short")
    if CALL_TICKET_SECRET and len(CALL_TICKET_SECRET) < 32:
        raise RuntimeError("CERNOGRAM_CALL_TICKET_SECRET is too short")


@APP.get("/healthz")
async def health() -> dict[str, Any]:
    return {
        "ok": True,
        "livekit_url_configured": bool(LIVEKIT_URL),
        "time": int(time.time()),
    }


@APP.post("/v1/calls/ticket", response_model=CallTicketResponse)
async def create_call_ticket(
    request: CallTicketRequest,
    authorization: Annotated[str | None, Header()] = None,
) -> CallTicketResponse:
    _require_internal_issuer(authorization)
    _validate_id(request.call_id, "call_id")
    _validate_id(request.room_name, "room_name")
    profiles = sorted(set(request.participant_profile_ids))
    if not profiles:
        raise HTTPException(status_code=422, detail="participants_required")
    for profile_id in profiles:
        _validate_id(profile_id, "participant_profile_id")

    now = int(time.time())
    expires_at = now + CALL_TICKET_TTL
    ticket = jwt.encode(
        {
            "iss": "cernogram-calls",
            "aud": "cernogram-livekit-token-broker",
            "iat": now,
            "nbf": now - 2,
            "exp": expires_at,
            "jti": _random_id(request.call_id, now),
            "call_id": request.call_id,
            "room_name": request.room_name,
            "profiles": profiles,
            "video": request.video,
            "can_publish": request.can_publish,
            "can_subscribe": request.can_subscribe,
            "metadata": request.metadata,
        },
        CALL_TICKET_SECRET,
        algorithm="HS256",
    )
    return CallTicketResponse(call_ticket=ticket, expires_at=expires_at)


@APP.post("/v1/calls/token", response_model=JoinResponse)
async def create_livekit_token(
    request: JoinRequest,
    authorization: Annotated[str | None, Header()] = None,
) -> JoinResponse:
    access = _verify_access_header(authorization)
    _validate_id(request.profile_id, "profile_id")
    _validate_id(request.device_id, "device_id")
    if access.profile_id != "*" and access.profile_id != request.profile_id:
        raise HTTPException(status_code=403, detail="profile_mismatch")
    if access.device_id != "*" and access.device_id != request.device_id:
        raise HTTPException(status_code=403, detail="device_mismatch")

    ticket = _decode_call_ticket(request.call_ticket)
    profiles = ticket.get("profiles")
    if not isinstance(profiles, list) or request.profile_id not in profiles:
        raise HTTPException(status_code=403, detail="participant_not_invited")
    room_name = str(ticket.get("room_name", ""))
    call_id = str(ticket.get("call_id", ""))
    _validate_id(room_name, "room_name")
    _validate_id(call_id, "call_id")

    now = int(time.time())
    ticket_exp = int(ticket.get("exp", now))
    expires_at = min(now + CALL_TOKEN_TTL, ticket_exp + 30)
    ttl = max(30, expires_at - now)
    participant_identity = f"{request.profile_id}:{request.device_id}"
    metadata = {
        "profileId": request.profile_id,
        "deviceId": request.device_id,
        "callId": call_id,
        "video": bool(ticket.get("video", False)),
        **request.participant_metadata,
    }
    token = (
        api.AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        .with_identity(participant_identity)
        .with_name(request.display_name.strip() or request.profile_id)
        .with_metadata(json.dumps(metadata, ensure_ascii=False, separators=(",", ":")))
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=room_name,
                can_publish=bool(ticket.get("can_publish", True)),
                can_subscribe=bool(ticket.get("can_subscribe", True)),
                can_publish_data=True,
            )
        )
        .with_ttl(dt.timedelta(seconds=ttl))
        .to_jwt()
    )
    return JoinResponse(
        server_url=LIVEKIT_URL,
        participant_token=token,
        room_name=room_name,
        call_id=call_id,
        video=bool(ticket.get("video", False)),
        expires_at=expires_at,
    )


def _verify_access_header(authorization: str | None) -> AccessClaims:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing_access_token")
    token = authorization.removeprefix("Bearer ").strip()
    if ALLOW_INSECURE_DEV and token == "dev":
        return AccessClaims(
            profile_id="*",
            device_id="*",
            expires_at=int(time.time()) + 3600,
        )
    parts = token.split(".")
    if len(parts) != 2 or not ACCESS_TOKEN_SECRET:
        raise HTTPException(status_code=401, detail="invalid_access_token")
    try:
        payload_bytes = _decode_base64url(parts[0])
        received_mac = _decode_base64url(parts[1])
        expected_mac = hmac.new(
            ACCESS_TOKEN_SECRET.encode("utf-8"),
            payload_bytes,
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(received_mac, expected_mac):
            raise ValueError("bad mac")
        payload = json.loads(payload_bytes.decode("utf-8"))
        profile_id = str(payload.get("profileId", ""))
        device_id = str(payload.get("deviceId", ""))
        expires_at = int(payload.get("exp", 0))
        if expires_at <= int(time.time()):
            raise ValueError("expired")
        _validate_id(profile_id, "profile_id")
        _validate_id(device_id, "device_id")
        return AccessClaims(
            profile_id=profile_id,
            device_id=device_id,
            expires_at=expires_at,
        )
    except (ValueError, TypeError, json.JSONDecodeError, UnicodeDecodeError):
        raise HTTPException(status_code=401, detail="invalid_access_token") from None


def _decode_call_ticket(value: str) -> dict[str, Any]:
    if ALLOW_INSECURE_DEV and value == "dev":
        raise HTTPException(status_code=400, detail="dev_ticket_requires_real_claims")
    try:
        decoded = jwt.decode(
            value,
            CALL_TICKET_SECRET,
            algorithms=["HS256"],
            audience="cernogram-livekit-token-broker",
            issuer="cernogram-calls",
            options={"require": ["exp", "iat", "call_id", "room_name", "profiles"]},
        )
        return dict(decoded)
    except jwt.PyJWTError as error:
        raise HTTPException(status_code=401, detail=f"invalid_call_ticket:{error.__class__.__name__}") from None


def _require_internal_issuer(authorization: str | None) -> None:
    expected = f"Bearer {TICKET_ISSUER_SECRET}"
    if not TICKET_ISSUER_SECRET or not hmac.compare_digest(authorization or "", expected):
        raise HTTPException(status_code=401, detail="unauthorized_ticket_issuer")


def _validate_id(value: str, field: str) -> None:
    if not ID_PATTERN.fullmatch(value):
        raise HTTPException(status_code=422, detail=f"invalid_{field}")


def _decode_base64url(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _random_id(call_id: str, now: int) -> str:
    digest = hashlib.sha256(f"{call_id}:{now}:{os.urandom(12).hex()}".encode()).hexdigest()
    return digest[:32]
