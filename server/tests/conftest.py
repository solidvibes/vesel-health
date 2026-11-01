import hashlib
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from vesel_server.app import build_app

TOKEN = "test-token-not-a-secret"


class FakeClock:
    def __init__(self) -> None:
        self.now = datetime(2026, 10, 26, 7, 0, tzinfo=UTC)

    def __call__(self) -> datetime:
        return self.now

    def advance(self, minutes: int) -> None:
        self.now += timedelta(minutes=minutes)


@pytest.fixture
def home(tmp_path: Path) -> Path:
    (tmp_path / "token.sha256").write_text(hashlib.sha256(TOKEN.encode()).hexdigest() + "\n")
    return tmp_path


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock()


@pytest.fixture
def client(home: Path, clock: FakeClock) -> TestClient:
    return TestClient(build_app(home, clock))


@pytest.fixture
def auth() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


RowFactory = Callable[[int], list[dict[str, object]]]


@pytest.fixture
def make_rows() -> RowFactory:
    def make(count: int) -> list[dict[str, object]]:
        return [{"key": f"2026-10-{i:04d}", "data": {"rmssd_ms": 41.5 + i}} for i in range(count)]

    return make
