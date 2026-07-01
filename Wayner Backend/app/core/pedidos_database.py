from __future__ import annotations

from contextlib import contextmanager
from typing import Any, Iterator

import psycopg2
from psycopg2.extras import RealDictCursor

from app.core.config import settings
from app.core.exceptions import DatabaseConnectionError


class PedidosDatabase:
    @contextmanager
    def connection(self) -> Iterator[Any]:
        conn = None
        try:
            conn = psycopg2.connect(
                host=settings.pedidos_db_host,
                port=settings.pedidos_db_port,
                dbname=settings.pedidos_db_name,
                user=settings.pedidos_db_user,
                password=settings.pedidos_db_password,
                connect_timeout=settings.db_connect_timeout,
                options=f"-c search_path={settings.pedidos_db_schema},public",
            )
            yield conn
        except Exception as exc:
            if conn is not None:
                conn.rollback()
            raise DatabaseConnectionError(str(exc)) from exc
        finally:
            if conn is not None:
                conn.close()

    def fetch_all(
        self,
        query: str,
        params: tuple[Any, ...] | None = None,
    ) -> list[dict[str, Any]]:
        with self.connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute(query, params or ())
                return list(cursor.fetchall())

    def fetch_one(
        self,
        query: str,
        params: tuple[Any, ...] | None = None,
    ) -> dict[str, Any] | None:
        rows = self.fetch_all(query, params)
        return rows[0] if rows else None

    def execute(
        self,
        query: str,
        params: tuple[Any, ...] | None = None,
    ) -> int:
        with self.connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                try:
                    cursor.execute(query, params or ())

                    result_id = 0

                    try:
                        row = cursor.fetchone()
                        if row and "id" in row:
                            result_id = int(row["id"])
                    except psycopg2.ProgrammingError:
                        pass

                    conn.commit()
                    return result_id

                except Exception:
                    conn.rollback()
                    raise


pedidos_db = PedidosDatabase()