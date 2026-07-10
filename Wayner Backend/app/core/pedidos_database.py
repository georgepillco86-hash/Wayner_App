from __future__ import annotations

import time
from contextlib import contextmanager
from typing import Any, Iterator

import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool

from app.core.config import settings
from app.core.exceptions import DatabaseConnectionError


class PedidosDatabase:
    def __init__(self) -> None:
        self._pool: ThreadedConnectionPool | None = None

    def _create_pool(self) -> ThreadedConnectionPool:
        # Usaremos el mismo límite del pool de configuraciones (o 20 por defecto)
        pool_size = getattr(settings, 'db_pool_size', 20)
        
        return ThreadedConnectionPool(
            minconn=1,
            maxconn=pool_size,
            host=settings.pedidos_db_host,
            port=settings.pedidos_db_port,
            dbname=settings.pedidos_db_name,
            user=settings.pedidos_db_user,
            password=settings.pedidos_db_password,
            options=f"-c search_path={settings.pedidos_db_schema},public",
        )

    @property
    def pool(self) -> ThreadedConnectionPool:
        if self._pool is None:
            self._pool = self._create_pool()
        return self._pool

    @contextmanager
    def connection(self) -> Iterator[Any]:
        conn = None
        max_retries = 5
        retry_delay = 0.5  # Espera 0.5 segundos entre intentos

        # Sala de espera: Intenta obtener una conexión del pool
        for attempt in range(max_retries):
            try:
                conn = self.pool.getconn()
                break  # Conexión obtenida con éxito
            except Exception as exc:
                # Si el pool está lleno, psycopg2 lanza una excepción. 
                # Esperamos y reintentamos.
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                    continue
                raise DatabaseConnectionError(str(exc)) from exc

        try:
            yield conn
        except Exception as exc:
            # Si hubo un error en la ejecución, revertimos la transacción
            if conn is not None:
                conn.rollback()
            raise DatabaseConnectionError(str(exc)) from exc
        finally:
            # Devolvemos la conexión al pool en lugar de destruirla
            if conn is not None:
                # Es buena práctica hacer rollback antes de devolverla para limpiar 
                # cualquier transacción que haya quedado colgada (solo lectura)
                try:
                    conn.rollback() 
                except:
                    pass
                self.pool.putconn(conn)

    def fetch_all(
        self,
        query: str,
        params: tuple[Any, ...] | None = None,
    ) -> list[dict[str, Any]]:
        # --- NUEVO: Imprimir consulta SQL en la terminal para depurar ---
        print("\n" + "="*50)
        print("🔍 [EJECUTANDO QUERY POSTGRESQL]")
        print(f"📜 Query: {query.strip()}")
        print(f"📦 Params: {params}")
        # ---------------------------------------------------------------
        
        with self.connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                try:
                    cursor.execute(query, params or ())
                    resultados = list(cursor.fetchall())
                    
                    # Imprimir cuántos resultados encontró
                    print(f"✅ [RESULTADOS ENCONTRADOS]: {len(resultados)}")
                    print("="*50 + "\n")
                    
                    return resultados
                except Exception as e:
                    # Si PostgreSQL lanza un error, lo veremos en rojo aquí
                    print(f"❌ [ERROR SQL POSTGRESQL]: {e}")
                    print("="*50 + "\n")
                    raise

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