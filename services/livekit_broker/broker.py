from __future__ import annotations

import datetime as dt
import hmac
import json
import os
import re
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from livekit import api

_MAX_BODY_BYTES = 16_384
_ROOM_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{1,79}$")
_IDENTITY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:@-]{1,95}$")


class BrokerRequestError(ValueError):
    """A client-visible request validation error."""


@dataclass(frozen=True)
class BrokerSettings:
    api_key: str
    api_secret: str
    ws_url: str
    shared_secret: str
    cors_origin: str
    token_ttl_minutes: int
    bind_host: str
    bind_port: int

    @classmethod
    def from_env(cls) -> "BrokerSettings":
        api_key = os.getenv("LIVEKIT_API_KEY", "devkey").strip()
        api_secret = os.getenv("LIVEKIT_API_SECRET", "secret").strip()
        ws_url = os.getenv("LIVEKIT_WS_URL", "ws://127.0.0.1:7880").strip()
        shared_secret = os.getenv("BROKER_SHARED_SECRET", "").strip()
        cors_origin = os.getenv("BROKER_CORS_ORIGIN", "*").strip() or "*"
        token_ttl_minutes = _bounded_int(
            os.getenv("BROKER_TOKEN_TTL_MINUTES", "30"),
            minimum=5,
            maximum=60,
            field="BROKER_TOKEN_TTL_MINUTES",
        )
        bind_host = os.getenv("BROKER_BIND_HOST", "0.0.0.0").strip()
        bind_port = _bounded_int(
            os.getenv("BROKER_PORT", "8090"),
            minimum=1,
            maximum=65_535,
            field="BROKER_PORT",
        )
        if not api_key or not api_secret:
            raise RuntimeError("LIVEKIT_API_KEY and LIVEKIT_API_SECRET are required")
        if not ws_url.startswith(("ws://", "wss://")):
            raise RuntimeError("LIVEKIT_WS_URL must start with ws:// or wss://")
        return cls(
            api_key=api_key,
            api_secret=api_secret,
            ws_url=ws_url,
            shared_secret=shared_secret,
            cors_origin=cors_origin,
            token_ttl_minutes=token_ttl_minutes,
            bind_host=bind_host,
            bind_port=bind_port,
        )


def _bounded_int(value: str, *, minimum: int, maximum: int, field: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise RuntimeError(f"{field} must be an integer") from error
    if parsed < minimum or parsed > maximum:
        raise RuntimeError(f"{field} must be between {minimum} and {maximum}")
    return parsed


def _validated_string(
    payload: dict[str, Any],
    field: str,
    pattern: re.Pattern[str],
) -> str:
    value = payload.get(field)
    if not isinstance(value, str):
        raise BrokerRequestError(f"{field} must be a string")
    value = value.strip()
    if not pattern.fullmatch(value):
        raise BrokerRequestError(f"invalid {field}")
    return value


def issue_join_token(
    settings: BrokerSettings,
    payload: dict[str, Any],
) -> dict[str, Any]:
    room = _validated_string(payload, "room", _ROOM_RE)
    identity = _validated_string(payload, "identity", _IDENTITY_RE)
    display_name_value = payload.get("displayName", identity)
    if not isinstance(display_name_value, str):
        raise BrokerRequestError("displayName must be a string")
    display_name = display_name_value.strip()[:80] or identity

    token = (
        api.AccessToken(settings.api_key, settings.api_secret)
        .with_identity(identity)
        .with_name(display_name)
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=room,
                can_publish=True,
                can_subscribe=True,
                can_publish_data=True,
            )
        )
        .with_ttl(dt.timedelta(minutes=settings.token_ttl_minutes))
        .to_jwt()
    )
    return {
        "url": settings.ws_url,
        "token": token,
        "room": room,
        "identity": identity,
        "expiresIn": settings.token_ttl_minutes * 60,
    }


class BrokerHandler(BaseHTTPRequestHandler):
    server_version = "CernogramLiveKitBroker/1.0"

    @property
    def settings(self) -> BrokerSettings:
        return self.server.settings  # type: ignore[attr-defined]

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._send_common_headers(content_length=0)
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if self.path.rstrip("/") == "/healthz":
            self._send_json(
                200,
                {
                    "ok": True,
                    "service": "cernogram-livekit-broker",
                    "time": dt.datetime.now(dt.timezone.utc).isoformat(),
                },
            )
            return
        self._send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") != "/v1/token":
            self._send_json(404, {"error": "not_found"})
            return
        if not self._authorized():
            self._send_json(401, {"error": "unauthorized"})
            return
        try:
            payload = self._read_json_body()
            response = issue_join_token(self.settings, payload)
        except BrokerRequestError as error:
            self._send_json(400, {"error": "invalid_request", "detail": str(error)})
            return
        except Exception:
            self._send_json(500, {"error": "token_generation_failed"})
            return
        self._send_json(200, response)

    def _authorized(self) -> bool:
        expected = self.settings.shared_secret
        if not expected:
            return True
        supplied = self.headers.get("X-Cernogram-Broker-Key", "")
        return hmac.compare_digest(supplied, expected)

    def _read_json_body(self) -> dict[str, Any]:
        raw_length = self.headers.get("Content-Length", "")
        try:
            length = int(raw_length)
        except ValueError as error:
            raise BrokerRequestError("invalid Content-Length") from error
        if length <= 0 or length > _MAX_BODY_BYTES:
            raise BrokerRequestError("request body size is invalid")
        raw = self.rfile.read(length)
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BrokerRequestError("body must be valid UTF-8 JSON") from error
        if not isinstance(decoded, dict):
            raise BrokerRequestError("body must be a JSON object")
        return decoded

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        encoded = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self._send_common_headers(content_length=len(encoded))
        self.end_headers()
        self.wfile.write(encoded)

    def _send_common_headers(self, *, content_length: int) -> None:
        self.send_header("Content-Length", str(content_length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", self.settings.cors_origin)
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Cernogram-Broker-Key")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("X-Content-Type-Options", "nosniff")

    def log_message(self, format_string: str, *args: object) -> None:
        # Keep logs useful without ever printing request bodies or generated tokens.
        print(f"{self.address_string()} - {format_string % args}", flush=True)


class BrokerServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, settings: BrokerSettings) -> None:
        self.settings = settings
        super().__init__((settings.bind_host, settings.bind_port), BrokerHandler)


def main() -> None:
    settings = BrokerSettings.from_env()
    server = BrokerServer(settings)
    print(
        f"Cernogram LiveKit broker listening on "
        f"http://{settings.bind_host}:{settings.bind_port}",
        flush=True,
    )
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
