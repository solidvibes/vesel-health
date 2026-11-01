import json
import logging
import os
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from vesel_server.auth import TokenCheck
from vesel_server.models import MAX_BODY_BYTES, MAX_ROWS, SCHEMA_VERSION, Batch, Status, Stored
from vesel_server.storage import Storage

log = logging.getLogger("vesel_server")

Clock = Callable[[], datetime]


def default_home() -> Path:
    override = os.environ.get("VESEL_SERVER_HOME")
    if override:
        return Path(override)
    return Path.home() / "Library" / "Application Support" / "vesel-server"


def _reject_constant(name: str) -> object:
    raise ValueError(name)


def _error(status: int, message: str) -> JSONResponse:
    return JSONResponse({"error": message}, status_code=status)


async def _read_limited(request: Request) -> bytes | None:
    declared = request.headers.get("content-length")
    if declared is not None and declared.isdigit() and int(declared) > MAX_BODY_BYTES:
        return None
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > MAX_BODY_BYTES:
            return None
    return bytes(body)


def build_app(home: Path, clock: Clock) -> FastAPI:
    storage = Storage(home / "vesel.sqlite")
    tokens = TokenCheck(home / "token.sha256")
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def guard_and_log(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        request.state.row_count = 0
        if not tokens.is_valid(request.headers.get("authorization")):
            response: Response = _error(401, "unauthorized")
        else:
            response = await call_next(request)
        log.info(
            "%s %r %d rows=%d",
            request.method,
            request.url.path,
            response.status_code,
            request.state.row_count,
        )
        return response

    @app.get("/v1/status")
    def status() -> JSONResponse:
        rows, last = storage.status()
        body = Status(schema_version=SCHEMA_VERSION, rows=rows, last_received_at=last)
        return JSONResponse(body.model_dump(by_alias=True))

    @app.post("/v1/batches")
    async def batches(request: Request) -> JSONResponse:
        raw = await _read_limited(request)
        if raw is None:
            return _error(413, "body over 5 MB")
        try:
            payload = json.loads(raw, parse_constant=_reject_constant)
        except (ValueError, RecursionError):
            return _error(422, "body is not JSON")
        if not isinstance(payload, dict):
            return _error(422, "body is not a JSON object")
        if payload.get("schema") != SCHEMA_VERSION:
            return _error(409, f"server speaks schema {SCHEMA_VERSION}")
        rows = payload.get("rows")
        if isinstance(rows, list) and len(rows) > MAX_ROWS:
            return _error(413, f"over {MAX_ROWS} rows")
        try:
            batch = Batch.model_validate(payload)
        except ValidationError:
            return _error(422, "batch does not match schema 1")
        storage.upsert(batch.table, batch.rows, clock().isoformat())
        request.state.row_count = len(batch.rows)
        return JSONResponse(Stored(stored=len(batch.rows)).model_dump())

    return app


def create_app() -> FastAPI:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    return build_app(default_home(), lambda: datetime.now(UTC))
