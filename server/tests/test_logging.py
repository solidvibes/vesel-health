import logging

import pytest
from fastapi.testclient import TestClient

from tests.conftest import TOKEN


def test_logs_only_method_path_status_and_count(
    client: TestClient, auth: dict[str, str], caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    rows = [{"key": "night-secret-key", "data": {"rmssd_ms": 987.654}}]
    client.post("/v1/batches", headers=auth, json={"schema": 1, "table": "night", "rows": rows})
    client.get("/v1/status", headers={"Authorization": "Bearer wrong-guess-token"})

    text = caplog.text
    assert "POST '/v1/batches' 200 rows=1" in text
    assert "GET '/v1/status' 401 rows=0" in text
    for secret in (TOKEN, "wrong-guess-token", "987.654", "rmssd_ms", "night-secret-key"):
        assert secret not in text


def test_query_string_is_not_logged(
    client: TestClient, auth: dict[str, str], caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    client.get("/v1/status?token=query-secret", headers=auth)
    server_side = "\n".join(r.getMessage() for r in caplog.records if not r.name.startswith("httpx"))
    assert "GET '/v1/status' 200 rows=0" in server_side
    assert "query-secret" not in server_side


def test_control_characters_in_the_path_are_escaped(
    client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    client.get("/v1/x%1B[2J%0B")
    server_side = [r.getMessage() for r in caplog.records if r.name == "vesel_server"]
    assert server_side == ["GET '/v1/x\\x1b[2J\\x0b' 401 rows=0"]
