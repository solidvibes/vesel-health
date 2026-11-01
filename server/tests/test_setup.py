import base64
import hashlib
import os
import re
import shutil
import stat
import subprocess
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi.testclient import TestClient

from vesel_server.app import create_app

SETUP = Path(__file__).resolve().parent.parent / "setup.sh"
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


@pytest.fixture(params=["system", "path"])
def search_path(request: pytest.FixtureRequest) -> str:
    if request.param == "system":
        return SYSTEM_PATH
    return os.environ["PATH"]


@pytest.fixture
def script(tmp_path: Path) -> Path:
    server = tmp_path / "server"
    server.mkdir()
    shutil.copy(SETUP, server / "setup.sh")
    return server / "setup.sh"


def run_setup(
    script: Path, home: Path, search_path: str, *args: str
) -> subprocess.CompletedProcess[str]:
    env = {
        "HOME": os.environ["HOME"],
        "PATH": search_path,
        "VESEL_SERVER_HOME": str(home),
        "VESEL_SERVER_HOST": "localhost",
    }
    return subprocess.run(
        ["/bin/bash", str(script), *args], env=env, capture_output=True, text=True, check=False
    )


def openssl(search_path: str) -> str:
    found = shutil.which("openssl", path=search_path)
    assert found is not None
    return found


def readme_pin(cert: Path, search_path: str) -> str:
    tool = openssl(search_path)
    pubkey = subprocess.run(
        [tool, "x509", "-in", str(cert), "-pubkey", "-noout"], capture_output=True, check=True
    ).stdout
    der = subprocess.run(
        [tool, "pkey", "-pubin", "-outform", "DER"], input=pubkey, capture_output=True, check=True
    ).stdout
    digest = subprocess.run(
        [tool, "dgst", "-sha256", "-binary"], input=der, capture_output=True, check=True
    ).stdout
    return base64.b64encode(digest).decode()


def parse_qr(line: str) -> tuple[str, str, str]:
    parts = urlsplit(line)
    assert parts.scheme == "vesel-backup"
    assert parts.hostname == "localhost"
    assert parts.port == 8443
    query = parse_qs(parts.query)
    return parts.query, query["token"][0], query["pin"][0]


def mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def test_qr_text_matches_the_contract(script: Path, tmp_path: Path, search_path: str) -> None:
    home = tmp_path / "home"
    result = run_setup(script, home, search_path, "--qr-text")
    assert result.returncode == 0, result.stderr

    lines = result.stdout.splitlines()
    assert len(lines) == 1
    raw_query, token, pin = parse_qr(lines[0])

    assert re.fullmatch(r"[A-Za-z0-9_-]{43}", token)
    assert token not in result.stderr
    assert (home / "token.sha256").read_text().strip() == hashlib.sha256(
        token.encode()
    ).hexdigest()
    assert re.fullmatch(r"[0-9a-f]{64}", (home / "token.sha256").read_text().strip())

    cert = home / "certs" / "cert.pem"
    assert pin == readme_pin(cert, search_path)
    encoded_pin = raw_query.split("pin=", 1)[1]
    assert not set("+/=") & set(encoded_pin)
    assert len(base64.b64decode(pin)) == 32

    text = subprocess.run(
        [openssl(search_path), "x509", "-in", str(cert), "-noout", "-text"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert "DNS:localhost" in text
    assert "CA:FALSE" in text
    assert "TLS Web Server Authentication" in text
    assert "prime256v1" in text or "P-256" in text

    def valid_for(days: int) -> bool:
        check = subprocess.run(
            [openssl(search_path), "x509", "-in", str(cert), "-noout", "-checkend", str(days * 86400)],
            capture_output=True,
            check=False,
        )
        return check.returncode == 0

    assert valid_for(3649)
    assert not valid_for(3651)

    assert mode(home) == 0o700
    assert mode(home / "certs") == 0o700
    for file in (cert, home / "certs" / "key.pem", home / "token.sha256"):
        assert mode(file) == 0o600

    assert sorted(p.name for p in home.iterdir()) == ["certs", "token.sha256"]
    assert sorted(p.name for p in script.parent.iterdir()) == ["setup.sh"]


def test_second_qr_text_keeps_certificate_and_changes_token(
    script: Path, tmp_path: Path, search_path: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    home = tmp_path / "home"
    first = run_setup(script, home, search_path, "--qr-text")
    assert first.returncode == 0, first.stderr
    cert_before = (home / "certs" / "cert.pem").read_bytes()
    key_before = (home / "certs" / "key.pem").read_bytes()
    _, old_token, old_pin = parse_qr(first.stdout.strip())

    second = run_setup(script, home, search_path, "--qr-text")
    assert second.returncode == 0, second.stderr
    _, new_token, new_pin = parse_qr(second.stdout.strip())

    assert new_pin == old_pin
    assert new_token != old_token
    assert (home / "certs" / "cert.pem").read_bytes() == cert_before
    assert (home / "certs" / "key.pem").read_bytes() == key_before

    monkeypatch.setenv("VESEL_SERVER_HOME", str(home))
    client = TestClient(create_app())
    ok = client.get("/v1/status", headers={"Authorization": f"Bearer {new_token}"})
    assert ok.status_code == 200
    refused = client.get("/v1/status", headers={"Authorization": f"Bearer {old_token}"})
    assert refused.status_code == 401


def test_qr_text_with_force_is_a_usage_error(script: Path, tmp_path: Path) -> None:
    home = tmp_path / "home"
    result = run_setup(script, home, SYSTEM_PATH, "--qr-text", "--force")
    assert result.returncode != 0
    assert result.stdout == ""
    assert not home.exists()
