import json
import sqlite3
from pathlib import Path

from vesel_server.models import Row


class Storage:
    def __init__(self, path: Path) -> None:
        self._path = path
        db = self._connect()
        try:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute(
                "CREATE TABLE IF NOT EXISTS row ("
                " table_name TEXT NOT NULL,"
                " row_key TEXT NOT NULL,"
                " json TEXT NOT NULL,"
                " received_at TEXT NOT NULL,"
                " PRIMARY KEY (table_name, row_key))"
            )
        finally:
            db.close()

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self._path)

    def upsert(self, table: str, rows: list[Row], received_at: str) -> None:
        db = self._connect()
        try:
            with db:
                db.executemany(
                    "INSERT INTO row (table_name, row_key, json, received_at)"
                    " VALUES (?, ?, ?, ?)"
                    " ON CONFLICT (table_name, row_key) DO UPDATE SET"
                    " json = excluded.json, received_at = excluded.received_at",
                    [
                        (table, row.key, json.dumps(row.data, separators=(",", ":")), received_at)
                        for row in rows
                    ],
                )
        finally:
            db.close()

    def status(self) -> tuple[int, str | None]:
        db = self._connect()
        try:
            count, last = db.execute("SELECT COUNT(*), MAX(received_at) FROM row").fetchone()
            return count, last
        finally:
            db.close()
