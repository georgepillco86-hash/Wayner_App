from __future__ import annotations

import time
from contextlib import contextmanager
from typing import Any, Iterator

import mysql.connector
from mysql.connector import Error
from mysql.connector.pooling import MySQLConnectionPool

from app.core.config import settings
from app.core.exceptions import DatabaseConnectionError


class Database:
    def __init__(self) -> None:
        self._pool: MySQLConnectionPool | None = None

    def _create_pool(self) -> MySQLConnectionPool:
        # Límite máximo de conexiones
        pool_size = min(settings.db_pool_size, 32) if hasattr(settings, 'db_pool_size') else 32
        
        return MySQLConnectionPool(
            pool_name=settings.db_pool_name,
            pool_size=pool_size,
            host=settings.db_host,
            port=settings.db_port,
            user=settings.db_user,
            password=settings.db_password,
            database=settings.db_name,
            use_pure=settings.db_use_pure,
            connect_timeout=settings.db_connect_timeout,
            autocommit=True,
        )

    @property
    def pool(self) -> MySQLConnectionPool:
        if self._pool is None:
            self._pool = self._create_pool()
        return self._pool

    @contextmanager
    def connection(self) -> Iterator[Any]:
        conn = None
        max_retries = 5
        retry_delay = 0.5  # Espera 0.5 segundos entre intentos

        for attempt in range(max_retries):
            try:
                # 1. Obtener conexión del pool
                conn = self.pool.get_connection()
                
                # 2. Hacer Ping para evitar conexiones "Zombis"
                try:
                    conn.ping(reconnect=True, attempts=3, delay=1)
                except Error:
                    if conn is not None and conn.is_connected():
                        conn.close()
                    raise # Si el ping falla, forzamos que sea atrapado por el except de abajo
                
                # Si llegamos aquí, la conexión está viva y lista
                break
                
            except Error as exc:
                error_msg = str(exc).lower()
                # Si el pool está lleno o la conexión se perdió, esperamos y reintentamos
                if ("pool exhausted" in error_msg or "lost connection" in error_msg) and attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                # Si es otro error o se acabaron los intentos, lanzamos la excepción
                raise DatabaseConnectionError(str(exc)) from exc

        try:
            yield conn
        finally:
            # 3. Devolver siempre la conexión al pool
            if conn is not None and conn.is_connected():
                conn.close()

    def fetch_all(self, query: str, params: tuple[Any, ...] | None = None) -> list[dict[str, Any]]:
        with self.connection() as conn:
            cursor = conn.cursor(dictionary=True)
            try:
                cursor.execute(query, params or ())
                return list(cursor.fetchall())
            finally:
                cursor.close()

    def fetch_one(self, query: str, params: tuple[Any, ...] | None = None) -> dict[str, Any] | None:
        rows = self.fetch_all(query, params)
        return rows[0] if rows else None

    def execute(self, query: str, params: tuple[Any, ...] | None = None) -> int:
        """Ejecuta INSERT/UPDATE/DELETE y retorna el id generado si existe."""
        with self.connection() as conn:
            cursor = conn.cursor()
            try:
                cursor.execute(query, params or ())
                conn.commit()
                return int(cursor.lastrowid or 0)
            finally:
                cursor.close()

db = Database()