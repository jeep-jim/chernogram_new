from __future__ import annotations

import os
import re
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENV_FILE = ROOT / ".env"
GENERATED = ROOT / "generated"
REQUIRED = {
    "LIVEKIT_DOMAIN",
    "TURN_DOMAIN",
    "LIVEKIT_API_KEY",
    "LIVEKIT_API_SECRET",
    "CERNOGRAM_ACCESS_TOKEN_SECRET",
    "CERNOGRAM_CALL_TICKET_SECRET",
    "CERNOGRAM_CALL_TICKET_ISSUER_SECRET",
    "TURN_SHARED_SECRET",
    "TURN_EXTERNAL_IP",
    "LIVEKIT_PUBLIC_URL",
}
DEFAULTS = {
    "LIVEKIT_RTC_TCP_PORT": "7881",
    "LIVEKIT_RTC_UDP_START": "50000",
    "LIVEKIT_RTC_UDP_END": "50100",
    "TURN_PORT": "3478",
    "TURN_TLS_PORT": "5349",
    "TURN_RELAY_START": "49160",
    "TURN_RELAY_END": "49260",
    "TURN_CERT_FILE": "/certs/fullchain.pem",
    "TURN_KEY_FILE": "/certs/privkey.pem",
}
PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        raise SystemExit("Create server/calls/.env from .env.example first")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return {**DEFAULTS, **values}


def validate(values: dict[str, str]) -> None:
    missing = sorted(name for name in REQUIRED if not values.get(name))
    if missing:
        raise SystemExit(f"Missing .env values: {', '.join(missing)}")
    weak = [
        name
        for name in (
            "LIVEKIT_API_SECRET",
            "CERNOGRAM_ACCESS_TOKEN_SECRET",
            "CERNOGRAM_CALL_TICKET_SECRET",
            "CERNOGRAM_CALL_TICKET_ISSUER_SECRET",
            "TURN_SHARED_SECRET",
        )
        if len(values.get(name, "")) < 32 or "replace_with" in values.get(name, "")
    ]
    if weak:
        raise SystemExit(f"Generate strong secrets for: {', '.join(weak)}")
    if values["LIVEKIT_API_KEY"].startswith("replace_"):
        raise SystemExit("Set a real LIVEKIT_API_KEY")


def render(template: Path, target: Path, values: dict[str, str]) -> None:
    text = template.read_text(encoding="utf-8")

    def replacement(match: re.Match[str]) -> str:
        key = match.group(1)
        value = values.get(key)
        if value is None:
            raise SystemExit(f"No value for {key} used by {template.name}")
        return value

    rendered = PATTERN.sub(replacement, text)
    target.write_text(rendered, encoding="utf-8")
    try:
        os.chmod(target, 0o600)
    except OSError:
        pass


def main() -> None:
    values = parse_env(ENV_FILE)
    validate(values)
    GENERATED.mkdir(parents=True, exist_ok=True)
    render(ROOT / "config/livekit.yaml.template", GENERATED / "livekit.yaml", values)
    render(
        ROOT / "config/turnserver.conf.template",
        GENERATED / "turnserver.conf",
        values,
    )
    print("Generated LiveKit and coturn configuration in server/calls/generated")


if __name__ == "__main__":
    main()
