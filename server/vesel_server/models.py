from pydantic import BaseModel, ConfigDict, Field

SCHEMA_VERSION = 1
MAX_ROWS = 1000
MAX_BODY_BYTES = 5 * 1024 * 1024


class Row(BaseModel):
    model_config = ConfigDict(extra="forbid")

    key: str = Field(min_length=1, max_length=512)
    data: dict[str, object]


class Batch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: int = Field(alias="schema", strict=True)
    table: str = Field(pattern=r"^[a-z_][a-z0-9_]{0,63}$")
    rows: list[Row] = Field(min_length=1)


class Status(BaseModel):
    schema_version: int = Field(serialization_alias="schema")
    rows: int
    last_received_at: str | None


class Stored(BaseModel):
    stored: int
