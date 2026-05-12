"""Application configuration helpers."""

from __future__ import annotations

from dataclasses import dataclass
import os
from functools import lru_cache


@dataclass(frozen=True)
class DatabaseConfig:
    """Database connection settings loaded from environment variables."""

    host: str = os.getenv("DB_HOST", "localhost")
    port: int = int(os.getenv("DB_PORT", "3306"))
    user: str = os.getenv("MYSQL_USER", "test_user")
    password: str = os.getenv("MYSQL_PASSWORD", "test_pass")
    database: str = os.getenv("MYSQL_DATABASE", "test_db")
    autocommit: bool = True


@lru_cache(maxsize=1)
def get_database_config() -> DatabaseConfig:
    """Return the cached database configuration."""

    return DatabaseConfig()
