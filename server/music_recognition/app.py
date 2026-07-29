from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Annotated, Any

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from pydantic import BaseModel, Field

APP = FastAPI(title="Cernogram Music Recognition", version="0.1.0")
DATA_DIR = Path(os.getenv("CG_MUSIC_DATA_DIR", "data")).resolve()
CHUNK_SIZE = 500
ADMIN_TOKEN = os.getenv("CG_MUSIC_ADMIN_TOKEN", "").strip()
MIN_SCORE = float(os.getenv("CG_MUSIC_MIN_SCORE", "0.54"))
MAX_UPLOAD_BYTES = int(os.getenv("CG_MUSIC_MAX_UPLOAD_BYTES", str(30 * 1024 * 1024)))
FPCALC = os.getenv("CG_FPCALC", "fpcalc")


@dataclass(slots=True)
class CatalogTrack:
    asset_id: str
    title: str
    artist: str
    owner_id: str
    owner_name: str
    public_url: str
    download_allowed: bool
    save_allowed: bool
    duration: float
    fingerprints: list[list[int]]
    updated_at: float

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "CatalogTrack":
        return cls(
            asset_id=str(value.get("asset_id", "")),
            title=str(value.get("title", "")),
            artist=str(value.get("artist", "")),
            owner_id=str(value.get("owner_id", "")),
            owner_name=str(value.get("owner_name", "")),
            public_url=str(value.get("public_url", "")),
            download_allowed=bool(value.get("download_allowed", False)),
            save_allowed=bool(value.get("save_allowed", False)),
            duration=float(value.get("duration", 0)),
            fingerprints=[
                [int(number) for number in chunk]
                for chunk in value.get("fingerprints", [])
                if isinstance(chunk, list)
            ],
            updated_at=float(value.get("updated_at", 0)),
        )


class MatchResult(BaseModel):
    found: bool
    score: float = 0
    asset_id: str = ""
    title: str = ""
    artist: str = ""
    owner_id: str = ""
    owner_name: str = ""
    public_url: str = ""
    download_allowed: bool = False
    save_allowed: bool = False
    duration: float = 0


class IndexResult(BaseModel):
    indexed: bool
    asset_id: str
    duration: float
    chunks: int


class CatalogStore:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.tracks: dict[str, CatalogTrack] = {}
        self._lock = asyncio.Lock()

    async def load(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        loaded: dict[str, CatalogTrack] = {}
        for path in sorted(self.root.glob("catalog_*.json")):
            try:
                values = json.loads(path.read_text(encoding="utf-8"))
                if not isinstance(values, list):
                    continue
                for value in values:
                    if not isinstance(value, dict):
                        continue
                    track = CatalogTrack.from_json(value)
                    if track.asset_id and track.fingerprints:
                        loaded[track.asset_id] = track
            except (OSError, ValueError, TypeError):
                continue
        self.tracks = loaded

    async def upsert(self, track: CatalogTrack) -> None:
        async with self._lock:
            self.tracks[track.asset_id] = track
            await self._persist_locked()

    async def remove(self, asset_id: str) -> bool:
        async with self._lock:
            if self.tracks.pop(asset_id, None) is None:
                return False
            await self._persist_locked()
            return True

    async def _persist_locked(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        ordered = sorted(self.tracks.values(), key=lambda item: item.asset_id)
        temporary: list[tuple[Path, Path]] = []
        for index, offset in enumerate(range(0, len(ordered), CHUNK_SIZE), start=1):
            target = self.root / f"catalog_{index:04d}.json"
            temp = target.with_suffix(".json.tmp")
            payload = [asdict(track) for track in ordered[offset : offset + CHUNK_SIZE]]
            temp.write_text(
                json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
            temporary.append((temp, target))
        for old in self.root.glob("catalog_*.json"):
            old.unlink(missing_ok=True)
        for temp, target in temporary:
            temp.replace(target)


STORE = CatalogStore(DATA_DIR)


@APP.on_event("startup")
async def startup() -> None:
    if shutil.which(FPCALC) is None:
        raise RuntimeError(f"fpcalc executable not found: {FPCALC}")
    await STORE.load()


@APP.get("/healthz")
async def health() -> dict[str, Any]:
    return {
        "ok": True,
        "tracks": len(STORE.tracks),
        "fpcalc": FPCALC,
        "time": time.time(),
    }


@APP.post("/v1/music/index", response_model=IndexResult)
async def index_track(
    file: Annotated[UploadFile, File(...)],
    asset_id: Annotated[str, Form(...)],
    title: Annotated[str, Form(...)],
    artist: Annotated[str, Form("")],
    owner_id: Annotated[str, Form(...)],
    owner_name: Annotated[str, Form("")],
    public_url: Annotated[str, Form("")],
    download_allowed: Annotated[bool, Form(False)],
    save_allowed: Annotated[bool, Form(True)],
    authorization: Annotated[str | None, Header()] = None,
) -> IndexResult:
    _require_admin(authorization)
    _validate_id(asset_id)
    path = await _save_upload(file)
    try:
        duration, fingerprints = await asyncio.to_thread(_fingerprint_chunks, path)
    finally:
        path.unlink(missing_ok=True)
    if not fingerprints:
        raise HTTPException(status_code=422, detail="fingerprint_failed")
    track = CatalogTrack(
        asset_id=asset_id,
        title=title.strip() or file.filename or "track",
        artist=artist.strip(),
        owner_id=owner_id.strip(),
        owner_name=owner_name.strip(),
        public_url=public_url.strip(),
        download_allowed=download_allowed,
        save_allowed=save_allowed,
        duration=duration,
        fingerprints=fingerprints,
        updated_at=time.time(),
    )
    await STORE.upsert(track)
    return IndexResult(
        indexed=True,
        asset_id=track.asset_id,
        duration=track.duration,
        chunks=len(track.fingerprints),
    )


@APP.delete("/v1/music/index/{asset_id}")
async def delete_track(
    asset_id: str,
    authorization: Annotated[str | None, Header()] = None,
) -> dict[str, Any]:
    _require_admin(authorization)
    return {"removed": await STORE.remove(asset_id), "asset_id": asset_id}


@APP.post("/v1/music/recognize", response_model=MatchResult)
async def recognize(file: Annotated[UploadFile, File(...)]) -> MatchResult:
    path = await _save_upload(file)
    try:
        duration, query_chunks = await asyncio.to_thread(_fingerprint_chunks, path)
    finally:
        path.unlink(missing_ok=True)
    if not query_chunks:
        raise HTTPException(status_code=422, detail="fingerprint_failed")

    best_track: CatalogTrack | None = None
    best_score = 0.0
    for track in tuple(STORE.tracks.values()):
        score = _track_similarity(query_chunks, track.fingerprints)
        if score > best_score:
            best_score = score
            best_track = track
    if best_track is None or best_score < MIN_SCORE:
        return MatchResult(found=False, score=round(best_score, 5), duration=duration)
    return MatchResult(
        found=True,
        score=round(best_score, 5),
        asset_id=best_track.asset_id,
        title=best_track.title,
        artist=best_track.artist,
        owner_id=best_track.owner_id,
        owner_name=best_track.owner_name,
        public_url=best_track.public_url,
        download_allowed=best_track.download_allowed,
        save_allowed=best_track.save_allowed,
        duration=best_track.duration,
    )


async def _save_upload(upload: UploadFile) -> Path:
    suffix = Path(upload.filename or "sample.bin").suffix[:12]
    descriptor, raw_path = tempfile.mkstemp(prefix="cg_audio_", suffix=suffix)
    os.close(descriptor)
    path = Path(raw_path)
    size = 0
    try:
        with path.open("wb") as output:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="audio_too_large")
                output.write(chunk)
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    finally:
        await upload.close()
    if size < 1024:
        path.unlink(missing_ok=True)
        raise HTTPException(status_code=422, detail="audio_too_short")
    return path


def _fingerprint_chunks(path: Path) -> tuple[float, list[list[int]]]:
    # fpcalc can emit repeated TIMESTAMP/DURATION/FINGERPRINT blocks in chunk mode.
    command = [
        FPCALC,
        "-raw",
        "-signed",
        "-length",
        "30",
        "-chunk",
        "12",
        "-overlap",
        str(path),
    ]
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=45,
        check=False,
    )
    if result.returncode != 0:
        raise HTTPException(
            status_code=422,
            detail=f"fpcalc_failed:{result.stderr.strip()[:180]}",
        )
    duration = 0.0
    fingerprints: list[list[int]] = []
    for line in result.stdout.splitlines():
        key, separator, value = line.partition("=")
        if not separator:
            continue
        if key == "DURATION":
            try:
                duration = max(duration, float(value))
            except ValueError:
                pass
        elif key == "FINGERPRINT":
            values = [
                int(number)
                for number in re.findall(r"-?\d+", value)
            ]
            if len(values) >= 8:
                fingerprints.append(values)
    if not fingerprints:
        # Some older fpcalc builds do not support chunk output in the same form.
        fallback = subprocess.run(
            [FPCALC, "-raw", "-signed", "-length", "30", str(path)],
            capture_output=True,
            text=True,
            timeout=45,
            check=False,
        )
        if fallback.returncode == 0:
            for line in fallback.stdout.splitlines():
                key, separator, value = line.partition("=")
                if not separator:
                    continue
                if key == "DURATION":
                    try:
                        duration = max(duration, float(value))
                    except ValueError:
                        pass
                elif key == "FINGERPRINT":
                    values = [int(number) for number in re.findall(r"-?\d+", value)]
                    if len(values) >= 8:
                        fingerprints.append(values)
    return duration, fingerprints


def _track_similarity(query: list[list[int]], reference: list[list[int]]) -> float:
    best = 0.0
    for left in query:
        for right in reference:
            best = max(best, _fingerprint_similarity(left, right))
    return best


def _fingerprint_similarity(left: list[int], right: list[int]) -> float:
    length = min(len(left), len(right))
    if length < 8:
        return 0.0
    # Try small temporal offsets because microphone samples rarely start at the
    # same frame as an indexed file.
    best = 0.0
    max_offset = min(24, length // 3)
    for offset in range(-max_offset, max_offset + 1):
        left_start = max(0, offset)
        right_start = max(0, -offset)
        aligned = min(len(left) - left_start, len(right) - right_start)
        if aligned < 8:
            continue
        bit_errors = 0
        for index in range(aligned):
            a = left[left_start + index] & 0xFFFFFFFF
            b = right[right_start + index] & 0xFFFFFFFF
            bit_errors += (a ^ b).bit_count()
        score = 1.0 - bit_errors / float(aligned * 32)
        best = max(best, score)
    return max(0.0, min(1.0, best))


def _require_admin(authorization: str | None) -> None:
    if not ADMIN_TOKEN:
        raise HTTPException(status_code=503, detail="indexing_disabled")
    expected = f"Bearer {ADMIN_TOKEN}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="unauthorized")


def _validate_id(value: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,160}", value):
        raise HTTPException(status_code=422, detail="invalid_asset_id")
