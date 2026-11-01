from fastapi.testclient import TestClient

from tests.conftest import TOKEN


def test_status_with_token(client: TestClient, auth: dict[str, str]) -> None:
    response = client.get("/v1/status", headers=auth)
    assert response.status_code == 200
    assert response.json() == {"schema": 1, "rows": 0, "last_received_at": None}


def test_missing_token_is_401(client: TestClient) -> None:
    assert client.get("/v1/status").status_code == 401
    assert client.post("/v1/batches", json={"schema": 1}).status_code == 401


def test_wrong_token_is_401(client: TestClient) -> None:
    response = client.get("/v1/status", headers={"Authorization": "Bearer wrong"})
    assert response.status_code == 401


def test_token_without_bearer_scheme_is_401(client: TestClient) -> None:
    response = client.get("/v1/status", headers={"Authorization": TOKEN})
    assert response.status_code == 401


def test_unknown_path_still_needs_token(client: TestClient) -> None:
    assert client.get("/docs").status_code == 401


def test_large_body_without_token_is_401(client: TestClient) -> None:
    response = client.post("/v1/batches", content=b"x" * (6 * 1024 * 1024))
    assert response.status_code == 401
