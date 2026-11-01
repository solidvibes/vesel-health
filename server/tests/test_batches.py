import json
import sqlite3
from collections.abc import Iterator
from pathlib import Path

from fastapi.testclient import TestClient

from tests.conftest import FakeClock, RowFactory


def _post(client: TestClient, auth: dict[str, str], body: object) -> int:
    return client.post("/v1/batches", headers=auth, json=body).status_code


def test_stores_rows_and_reports_status(
    client: TestClient, auth: dict[str, str], make_rows: RowFactory
) -> None:
    response = client.post(
        "/v1/batches", headers=auth, json={"schema": 1, "table": "night", "rows": make_rows(3)}
    )
    assert response.status_code == 200
    assert response.json() == {"stored": 3}
    status = client.get("/v1/status", headers=auth).json()
    assert status == {"schema": 1, "rows": 3, "last_received_at": "2026-10-26T07:00:00+00:00"}


def test_upsert_is_idempotent(
    client: TestClient, auth: dict[str, str], home: Path, clock: FakeClock, make_rows: RowFactory
) -> None:
    batch = {"schema": 1, "table": "night", "rows": make_rows(2)}
    assert _post(client, auth, batch) == 200
    clock.advance(60)
    assert _post(client, auth, batch) == 200
    changed = {"schema": 1, "table": "night", "rows": [{"key": "2026-10-0000", "data": {"rmssd_ms": 50}}]}
    assert _post(client, auth, changed) == 200

    status = client.get("/v1/status", headers=auth).json()
    assert status["rows"] == 2
    assert status["last_received_at"] == "2026-10-26T08:00:00+00:00"
    db = sqlite3.connect(home / "vesel.sqlite")
    stored = db.execute("SELECT json FROM row WHERE row_key = '2026-10-0000'").fetchone()[0]
    assert json.loads(stored) == {"rmssd_ms": 50}


def test_same_key_in_different_tables_are_separate_rows(
    client: TestClient, auth: dict[str, str], make_rows: RowFactory
) -> None:
    assert _post(client, auth, {"schema": 1, "table": "night", "rows": make_rows(1)}) == 200
    assert _post(client, auth, {"schema": 1, "table": "day", "rows": make_rows(1)}) == 200
    assert client.get("/v1/status", headers=auth).json()["rows"] == 2


def test_database_uses_wal(client: TestClient, home: Path) -> None:
    db = sqlite3.connect(home / "vesel.sqlite")
    assert db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"


def test_unknown_schema_is_409(client: TestClient, auth: dict[str, str], make_rows: RowFactory) -> None:
    assert _post(client, auth, {"schema": 2, "table": "night", "rows": make_rows(1)}) == 409
    assert _post(client, auth, {"table": "night", "rows": make_rows(1)}) == 409


def test_over_1000_rows_is_413(client: TestClient, auth: dict[str, str], make_rows: RowFactory) -> None:
    assert _post(client, auth, {"schema": 1, "table": "night", "rows": make_rows(1001)}) == 413
    assert _post(client, auth, {"schema": 1, "table": "night", "rows": make_rows(1000)}) == 200


def test_over_5_mb_is_413(client: TestClient, auth: dict[str, str]) -> None:
    big = {"schema": 1, "table": "night", "rows": [{"key": "a", "data": {"blob": "x" * (5 * 1024 * 1024)}}]}
    assert _post(client, auth, big) == 413
    assert client.get("/v1/status", headers=auth).json()["rows"] == 0


def test_malformed_batches_are_422(client: TestClient, auth: dict[str, str]) -> None:
    bad = [
        {"schema": 1, "table": "Night; DROP", "rows": [{"key": "a", "data": {}}]},
        {"schema": 1, "table": "night", "rows": []},
        {"schema": 1, "table": "night", "rows": [{"key": "", "data": {}}]},
        {"schema": 1, "table": "night", "rows": [{"key": "a", "data": [1]}]},
        {"schema": 1, "table": "night", "rows": [{"key": "a", "data": {}, "extra": 1}]},
        [1, 2],
    ]
    for body in bad:
        assert _post(client, auth, body) == 422
    response = client.post("/v1/batches", headers=auth, content=b"not json")
    assert response.status_code == 422


def test_over_5_mb_without_content_length_is_413(client: TestClient, auth: dict[str, str]) -> None:
    def chunks() -> Iterator[bytes]:
        for _ in range(6):
            yield b"x" * (1024 * 1024)

    response = client.post("/v1/batches", headers=auth, content=chunks())
    assert response.status_code == 413


def test_bad_values_are_422(client: TestClient, auth: dict[str, str]) -> None:
    nan = b'{"schema": 1, "table": "night", "rows": [{"key": "a", "data": {"x": NaN}}]}'
    assert client.post("/v1/batches", headers=auth, content=nan).status_code == 422
    deep = b"[" * 100_000
    assert client.post("/v1/batches", headers=auth, content=deep).status_code == 422
    assert _post(client, auth, {"schema": True, "table": "night", "rows": [{"key": "a", "data": {}}]}) == 422


def test_422_does_not_echo_the_body(client: TestClient, auth: dict[str, str]) -> None:
    body = {"schema": 1, "table": "night", "rows": [{"key": "echo-key", "data": [987.654]}]}
    response = client.post("/v1/batches", headers=auth, json=body)
    assert response.status_code == 422
    assert "echo-key" not in response.text
    assert "987.654" not in response.text


def test_profile_rows_keep_waist_and_outside_vo2max_and_older_rows_still_store(
    client: TestClient, auth: dict[str, str], home: Path
) -> None:
    older = {"birth_year": 1990, "sex": "male", "height_cm": 180.0, "weight_kg": 75.0, "sleep_goal_minutes": 480, "id": 1}
    assert _post(client, auth, {"schema": 1, "table": "profile", "rows": [{"key": "1", "data": older}]}) == 200
    db = sqlite3.connect(home / "vesel.sqlite")
    stored = json.loads(db.execute("SELECT json FROM row WHERE table_name = 'profile'").fetchone()[0])
    assert stored == older

    newer = {**older, "waist_cm": 84.0, "measured_vo2max": 46.0}
    assert _post(client, auth, {"schema": 1, "table": "profile", "rows": [{"key": "1", "data": newer}]}) == 200
    stored = json.loads(db.execute("SELECT json FROM row WHERE table_name = 'profile'").fetchone()[0])
    assert stored["waist_cm"] == 84.0
    assert stored["measured_vo2max"] == 46.0

    cleared = {**older, "waist_cm": None, "measured_vo2max": None}
    assert _post(client, auth, {"schema": 1, "table": "profile", "rows": [{"key": "1", "data": cleared}]}) == 200
    stored = json.loads(db.execute("SELECT json FROM row WHERE table_name = 'profile'").fetchone()[0])
    assert stored == cleared
    assert client.get("/v1/status", headers=auth).json()["rows"] == 1
