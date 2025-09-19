"""Database connection utilities."""

from __future__ import annotations

from contextlib import contextmanager

import mysql.connector

from .config import get_database_config


@contextmanager
def get_connection(*, dictionary: bool = False):
    """Yield a MySQL cursor and close resources afterwards."""

    config = get_database_config()
    connection = mysql.connector.connect(
        host=config.host,
        port=config.port,
        user=config.user,
        password=config.password,
        database=config.database,
        autocommit=config.autocommit,
    )
    cursor = connection.cursor(dictionary=dictionary)

    try:
        yield connection, cursor
    finally:
        cursor.close()
        connection.close()
