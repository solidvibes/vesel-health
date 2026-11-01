import hashlib
import hmac
from pathlib import Path


class TokenCheck:
    def __init__(self, hash_file: Path) -> None:
        self._expected = hash_file.read_text().strip().lower()

    def is_valid(self, authorization: str | None) -> bool:
        if authorization is None or not authorization.startswith("Bearer "):
            return False
        token = authorization.removeprefix("Bearer ")
        presented = hashlib.sha256(token.encode()).hexdigest()
        return hmac.compare_digest(presented, self._expected)
