from __future__ import annotations

from typing import Any

from app.core.database import db


class SaldoProductRepository:
    TABLE_NAME = "v_saldosproductos"

    def _safe_limit(self, limit: int | None = None) -> int:
        return int(limit or 100)

    def columns(self) -> list[dict[str, Any]]:
        return db.fetch_all(f"DESCRIBE {self.TABLE_NAME}")

    def health(self) -> dict[str, Any]:
        row = db.fetch_one("SELECT NOW() AS server_time")
        return {
            "status": "ok",
            "remote_source": self.TABLE_NAME,
            "server_time": row["server_time"] if row else None,
        }

    def summary(self) -> dict[str, Any]:
        query = f"""
        SELECT 
            COUNT(*) AS total_productos,
            COUNT(DISTINCT Clase) AS total_clases,
            SUM(COALESCE(Stock, 0)) AS stock_total,
            MIN(COALESCE(Stock, 0)) AS stock_minimo,
            MAX(COALESCE(Stock, 0)) AS stock_maximo
        FROM {self.TABLE_NAME}
        """
        return db.fetch_one(query) or {}

    def dataset(
        self,
        limit: int | None = None,
        proveedor: str | None = None,
    ) -> list[dict[str, Any]]:
        safe_limit = self._safe_limit(limit)

        query = f"""
        SELECT 
            s.Codigo,
            s.Nombre,
            s.Stock,
            s.Marca,
            s.Clase
        FROM {self.TABLE_NAME} s
        """

        params: list[Any] = []

        if proveedor:
            query = f"""
            SELECT
                s.Codigo,
                s.Nombre,
                s.Stock,
                s.Marca,
                s.Clase
            FROM {self.TABLE_NAME} s
            WHERE (
                s.Codigo LIKE %s
                OR s.Nombre LIKE %s
                OR s.Marca LIKE %s
                OR s.Clase LIKE %s
            )
            """
            params.append(proveedor)

        query += """
        ORDER BY s.Nombre
        LIMIT %s
        """
        params.append(safe_limit)

        return db.fetch_all(query, tuple(params))

    def search_products(
        self,
        text: str,
        clase: str | None = None,
        categoria: str | None = None,
        proveedor: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        safe_limit = self._safe_limit(limit)
        pattern = f"%{text}%"

        query = f"""
        SELECT 
            Codigo,
            Nombre,
            Stock,
            Marca,
            Clase
        FROM {self.TABLE_NAME}
        WHERE (
            Codigo LIKE %s
            OR Nombre LIKE %s
            OR Marca LIKE %s
            OR Clase LIKE %s
        )
        """

        params: list[Any] = [pattern, pattern, pattern, pattern]

        if clase:
            query += " AND Clase = %s"
            params.append(clase)
        
        if proveedor:
            query += """
            AND EXISTS (
                SELECT 1
                FROM v_kardexproductos k
                WHERE k.Codigo = v_saldosproductos.Codigo
                AND k.NombreProveedor IS NOT NULL
                AND TRIM(k.NombreProveedor) <> ''
                AND UPPER(TRIM(k.NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
                AND k.NombreProveedor = %s
            )
            """
            params.append(proveedor)

        # categoria se mantiene por compatibilidad con saldo_service.py,
        # pero no se usa porque v_saldosproductos no tiene columna Categoria.

        query += """
        ORDER BY Nombre
        LIMIT %s
        """
        params.append(safe_limit)

        return db.fetch_all(query, tuple(params))

    def list_classes(self) -> list[dict[str, Any]]:
        query = f"""
        SELECT DISTINCT Clase
        FROM {self.TABLE_NAME}
        WHERE Clase IS NOT NULL
          AND TRIM(Clase) <> ''
        ORDER BY Clase
        """
        return db.fetch_all(query)
    
    def list_providers(self) -> list[dict[str, Any]]:
        query = """
        SELECT DISTINCT NombreProveedor AS proveedor
        FROM v_kardexproductos
        WHERE NombreProveedor IS NOT NULL
        AND TRIM(NombreProveedor) <> ''
        AND UPPER(TRIM(NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
        ORDER BY NombreProveedor
        """
        return db.fetch_all(query)

    def get_by_class(
        self,
        clase: str,
        limit: int | None = None,
        proveedor: str | None = None,
    ) -> list[dict[str, Any]]:
        safe_limit = self._safe_limit(limit)

        query = f"""
        SELECT 
            s.Codigo,
            s.Nombre,
            s.Stock,
            s.Marca,
            s.Clase
        FROM {self.TABLE_NAME} s
        WHERE s.Clase = %s
        """
        params: list[Any] = [clase]

        if proveedor:
            query += """
            AND EXISTS (
                SELECT 1
                FROM v_kardexproductos k
                WHERE k.Codigo = s.Codigo
                AND k.NombreProveedor IS NOT NULL
                AND TRIM(k.NombreProveedor) <> ''
                AND UPPER(TRIM(k.NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
                AND k.NombreProveedor = %s
            )
            """
            params.append(proveedor)

        query += """
        ORDER BY s.Nombre
        LIMIT %s
        """
        params.append(safe_limit)

        return db.fetch_all(query, tuple(params))

    def get_by_code(self, codigo: str) -> dict[str, Any] | None:
        query = f"""
        SELECT 
            Codigo,
            Nombre,
            Stock,
            Marca,
            Clase
        FROM {self.TABLE_NAME}
        WHERE Codigo = %s
        LIMIT 1
        """
        return db.fetch_one(query, (codigo,))