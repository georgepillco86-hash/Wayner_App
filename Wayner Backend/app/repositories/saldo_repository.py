from __future__ import annotations

from typing import Any

from app.core.database import db


class SaldoProductRepository:
    TABLE_NAME = "v_saldosproductos"
    PRECIOS_TABLE = "v_kardexproductos"
    COLUMNA_PRECIO = "Precio"

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
            s.Clase,
            COALESCE(p.PrecioFinal, 0) AS Precio
        FROM {self.TABLE_NAME} s
        LEFT JOIN (
            SELECT 
                TRIM(Codigo) AS CodigoClean, 
                MAX(
                    CASE 
                        WHEN COALESCE(IVA, 0) > 0 THEN {self.COLUMNA_PRECIO} * 1.15 
                        ELSE {self.COLUMNA_PRECIO} 
                    END
                ) AS PrecioFinal
            FROM {self.PRECIOS_TABLE}
            GROUP BY TRIM(Codigo)
        ) p ON TRIM(s.Codigo) = p.CodigoClean
        """

        params: list[Any] = []

        if proveedor:
            query = f"""
            SELECT
                s.Codigo,
                s.Nombre,
                s.Stock,
                s.Marca,
                s.Clase,
                COALESCE(p.PrecioFinal, 0) AS Precio
            FROM {self.TABLE_NAME} s
            LEFT JOIN (
                SELECT 
                    TRIM(Codigo) AS CodigoClean, 
                    MAX(
                        CASE 
                            WHEN COALESCE(IVA, 0) > 0 THEN {self.COLUMNA_PRECIO} * 1.15 
                            ELSE {self.COLUMNA_PRECIO} 
                        END
                    ) AS PrecioFinal
                FROM {self.PRECIOS_TABLE}
                GROUP BY TRIM(Codigo)
            ) p ON TRIM(s.Codigo) = p.CodigoClean
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
            s.Codigo,
            s.Nombre,
            s.Stock,
            s.Marca,
            s.Clase,
            COALESCE(p.PrecioFinal, 0) AS Precio
        FROM {self.TABLE_NAME} s
        LEFT JOIN (
            SELECT 
                TRIM(Codigo) AS CodigoClean, 
                MAX(
                    CASE 
                        WHEN COALESCE(IVA, 0) > 0 THEN {self.COLUMNA_PRECIO} * 1.15 
                        ELSE {self.COLUMNA_PRECIO} 
                    END
                ) AS PrecioFinal
            FROM {self.PRECIOS_TABLE}
            GROUP BY TRIM(Codigo)
        ) p ON TRIM(s.Codigo) = p.CodigoClean
        WHERE (
            s.Codigo LIKE %s
            OR s.Nombre LIKE %s
            OR s.Marca LIKE %s
            OR s.Clase LIKE %s
        )
        """

        params: list[Any] = [pattern, pattern, pattern, pattern]

        if clase:
            query += " AND s.Clase = %s"
            params.append(clase)
        
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
            s.Clase,
            COALESCE(p.PrecioFinal, 0) AS Precio
        FROM {self.TABLE_NAME} s
        LEFT JOIN (
            SELECT 
                TRIM(Codigo) AS CodigoClean, 
                MAX(
                    CASE 
                        WHEN COALESCE(IVA, 0) > 0 THEN {self.COLUMNA_PRECIO} * 1.15 
                        ELSE {self.COLUMNA_PRECIO} 
                    END
                ) AS PrecioFinal
            FROM {self.PRECIOS_TABLE}
            GROUP BY TRIM(Codigo)
        ) p ON TRIM(s.Codigo) = p.CodigoClean
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
            s.Codigo,
            s.Nombre,
            s.Stock,
            s.Marca,
            s.Clase,
            COALESCE(p.PrecioFinal, 0) AS Precio
        FROM {self.TABLE_NAME} s
        LEFT JOIN (
            SELECT 
                TRIM(Codigo) AS CodigoClean, 
                MAX(
                    CASE 
                        WHEN COALESCE(IVA, 0) > 0 THEN {self.COLUMNA_PRECIO} * 1.15 
                        ELSE {self.COLUMNA_PRECIO} 
                    END
                ) AS PrecioFinal
            FROM {self.PRECIOS_TABLE}
            GROUP BY TRIM(Codigo)
        ) p ON TRIM(s.Codigo) = p.CodigoClean
        WHERE s.Codigo = %s
        LIMIT 1
        """
        return db.fetch_one(query, (codigo,))