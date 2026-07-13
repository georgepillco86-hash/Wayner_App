from __future__ import annotations
import logging
from datetime import datetime
from typing import Any

from app.core.config import settings
from app.core.database import db

logger = logging.getLogger(__name__)


class ProductRepository:
    def health(self) -> dict[str, Any]:
        row = db.fetch_one("SELECT NOW() AS server_time")
        return {
            "app_name": settings.app_name,
            "environment": settings.app_env,
            "database": settings.db_name,
            "server_time": row["server_time"] if row else datetime.utcnow(),
            "remote_source": "v_kardexproductos",
        }

    def catalog_stats(self) -> dict[str, Any]:
        query = """
        SELECT
            COUNT(*) AS total_registros,
            COUNT(DISTINCT CodigoBarra) AS total_productos,
            COUNT(DISTINCT Codigo) AS total_codigos
        FROM v_kardexproductos
        WHERE CodigoBarra IS NOT NULL AND TRIM(CodigoBarra) <> ''
        """
        row = db.fetch_one(query)
        return row or {"total_registros": 0, "total_productos": 0, "total_codigos": 0}

    def dataset_scanner(self, limit: int | None = None) -> list[dict[str, Any]]:
        clause = f"LIMIT {int(limit)}" if limit else ""
        query = f"""
        SELECT
            CodigoBarra,
            MIN(Codigo) AS Codigo,
            MIN(NombreProducto) AS NombreProducto,
            MIN(NombreProveedor) AS proveedor, -- ---> CORREGIDO: Mapea el proveedor para las alertas <---
            CAST(MAX(Precio) AS DECIMAL(18,6)) AS Precio,
            CAST(MAX(IVA) AS DECIMAL(10,2)) AS IVA,
            CAST(ROUND(MAX(Precio) * (1 + MAX(IVA)/100), 2) AS DECIMAL(18,2)) AS PrecioConIVA
        FROM v_kardexproductos
        WHERE CodigoBarra IS NOT NULL
          AND TRIM(CodigoBarra) <> ''
        GROUP BY CodigoBarra
        ORDER BY NombreProducto
        {clause}
        """
        return db.fetch_all(query)

    def search_products(self, text: str, limit: int | None = None) -> list[dict[str, Any]]:
        safe_limit = min(limit or settings.product_search_limit, settings.max_page_size)
        pattern = f"%{text}%"
        query = """
        SELECT
            CodigoBarra,
            MIN(Codigo) AS Codigo,
            MIN(NombreProducto) AS NombreProducto,
            MIN(NombreProveedor) AS proveedor, -- ---> CORREGIDO: El buscador también inyecta el proveedor <---
            CAST(MAX(Precio) AS DECIMAL(18,6)) AS Precio,
            CAST(MAX(IVA) AS DECIMAL(10,2)) AS IVA,
            CAST(ROUND(MAX(Precio) * (1 + MAX(IVA)/100), 2) AS DECIMAL(18,2)) AS PrecioConIVA
        FROM v_kardexproductos
        WHERE (CodigoBarra LIKE %s OR Codigo LIKE %s OR NombreProducto LIKE %s)
          AND CodigoBarra IS NOT NULL
          AND TRIM(CodigoBarra) <> ''
        GROUP BY CodigoBarra
        ORDER BY NombreProducto
        LIMIT %s
        """
        return db.fetch_all(query, (pattern, pattern, pattern, safe_limit))

    def get_product_summary(self, barcode: str) -> dict[str, Any] | None:
        query = """
        SELECT
            CodigoBarra,
            MIN(Codigo) AS Codigo,
            MIN(NombreProducto) AS NombreProducto,
            CAST(MAX(Precio) AS DECIMAL(18,6)) AS Precio,
            CAST(MAX(IVA) AS DECIMAL(10,2)) AS IVA,
            CAST(ROUND(MAX(Precio) * (1 + MAX(IVA)/100), 2) AS DECIMAL(18,2)) AS PrecioConIVA
        FROM v_kardexproductos
        WHERE CodigoBarra = %s
        GROUP BY CodigoBarra
        """
        return db.fetch_one(query, (barcode,))

    def get_stock(self, barcode: str) -> dict[str, Any] | None:
        query = """
        SELECT
            CodigoBarra,
            MIN(Codigo) AS Codigo,
            MIN(NombreProducto) AS NombreProducto,
            CAST(SUM(IFNULL(Ingreso, 0)) AS DECIMAL(18,3)) AS TotalIngreso,
            CAST(SUM(IFNULL(Egreso, 0)) AS DECIMAL(18,3)) AS TotalEgreso,
            CAST(SUM(IFNULL(Ingreso, 0) - IFNULL(Egreso, 0)) AS DECIMAL(18,3)) AS StockEstimado,
            CAST(MAX(Precio) AS DECIMAL(18,6)) AS PrecioActualRef,
            CAST(MAX(IVA) AS DECIMAL(10,2)) AS IVA,
            CAST(ROUND(MAX(Precio) * (1 + MAX(IVA)/100), 2) AS DECIMAL(18,2)) AS PrecioConIVA
        FROM v_kardexproductos
        WHERE CodigoBarra = %s
        GROUP BY CodigoBarra
        """
        return db.fetch_one(query, (barcode,))

    def get_history(self, barcode: str, limit: int | None = None) -> list[dict[str, Any]]:
        safe_limit = min(limit or settings.history_limit, 500)
        query = """
        SELECT
            Fecha,
            Documento,
            NombreDocumento,
            CAST(Precio AS DECIMAL(18,6)) AS Precio,
            CAST(IVA AS DECIMAL(10,2)) AS IVA,
            CAST(Costo AS DECIMAL(18,6)) AS Costo,
            CAST(IFNULL(Ingreso, 0) AS DECIMAL(18,3)) AS TabIngreso,
            CAST(IFNULL(Egreso, 0) AS DECIMAL(18,3)) AS Egreso,
            CAST(IFNULL(ValorIngreso, 0) AS DECIMAL(18,2)) AS ValorIngreso,
            CAST(IFNULL(ValorEgreso, 0) AS DECIMAL(18,2)) AS ValorEgreso,
            Factura,
            NombreProveedor
        FROM v_kardexproductos
        WHERE CodigoBarra = %s
        ORDER BY Fecha DESC, Documento DESC, Factura DESC
        LIMIT %s
        """
        return db.fetch_all(query, (barcode, safe_limit))

    def get_last_movement(self, barcode: str) -> dict[str, Any] | None:
        query = """
        SELECT
            Fecha,
            Documento,
            NombreDocumento,
            CAST(Precio AS DECIMAL(18,6)) AS Precio,
            CAST(IVA AS DECIMAL(10,2)) AS IVA,
            CAST(Costo AS DECIMAL(18,6)) AS Costo,
            CAST(IFNULL(Ingreso, 0) AS DECIMAL(18,3)) AS Ingreso,
            CAST(IFNULL(Egreso, 0) AS DECIMAL(18,3)) AS Egreso,
            CAST(IFNULL(ValorIngreso, 0) AS DECIMAL(18,2)) AS ValorIngreso,
            CAST(IFNULL(ValorEgreso, 0) AS DECIMAL(18,2)) AS ValorEgreso,
            Factura,
            NombreProveedor
        FROM v_kardexproductos
        WHERE CodigoBarra = %s
        ORDER BY Fecha DESC, Documento DESC, Factura DESC
        LIMIT 1
        """
        return db.fetch_one(query, (barcode,))
    
    def get_sales_summary(
        self,
        barcode: str,
        desde: str,
        hasta: str,
    ) -> list[dict[str, Any]]:
        query = """
        SELECT
            Fecha,
            CAST(SUM(IFNULL(Egreso, 0)) AS DECIMAL(18,3)) AS cantidad_vendida,
            CAST(SUM(IFNULL(ValorEgreso, 0)) AS DECIMAL(18,2)) AS total_vendido
        FROM v_kardexproductos
        WHERE CodigoBarra = %s
        AND Fecha BETWEEN %s AND %s
        AND IFNULL(Egreso, 0) > 0
        GROUP BY Fecha
        ORDER BY Fecha ASC
        """
        return db.fetch_all(query, (barcode, desde, hasta))
    
    def get_kardex_table(
        self,
        barcode: str,
        desde: str,
        hasta: str,
    ) -> list[dict[str, Any]]:
        query = """
        SELECT
            NombreDocumento AS tipo_documento,
            CAST(IFNULL(Ingreso, 0) AS DECIMAL(18,3)) AS ingreso,
            CAST(IFNULL(Egreso, 0) AS DECIMAL(18,3)) AS egreso,
            Fecha AS fecha
        FROM v_kardexproductos
        WHERE CodigoBarra = %s
        AND Fecha BETWEEN %s AND %s
        ORDER BY Fecha ASC, Documento ASC, Factura ASC
        """
        return db.fetch_all(query, (barcode, desde, hasta))

    def get_ventas_en_bloque(
        self,
        codigos: list[str],
        desde: str,
        hasta: str
    ) -> dict[str, float]:
        """
        Devuelve la suma total de egresos (ventas) agrupados por código de barras.
        Permite hacer un cálculo masivo en una sola petición a la base de datos.
        """
        if not codigos:
            logger.warning("[REPO] get_ventas_en_bloque fue llamado con una lista vacía de códigos.")
            return {}

        logger.info(f"[REPO] Ejecutando Bulk Query para {len(codigos)} códigos. Desde: {desde} Hasta: {hasta}")
        formato = ','.join(['%s'] * len(codigos))
        
        query = f"""
        SELECT 
            CodigoBarra,
            CAST(SUM(IFNULL(Egreso, 0)) AS DECIMAL(18,3)) AS total_egreso
        FROM v_kardexproductos
        WHERE CodigoBarra IN ({formato})
        AND Fecha BETWEEN %s AND %s
        GROUP BY CodigoBarra
        """
        
        parametros = tuple(codigos) + (desde, hasta)
        try:
            resultados = db.fetch_all(query, parametros)
            logger.info(f"[REPO] La BD devolvió {len(resultados) if resultados else 0} registros coincidentes.")
        except Exception as e:
            logger.error(f"[REPO] Error ejecutando la consulta en bloque: {str(e)}")
            return {}

        ventas_agrupadas = {}
        if resultados:
            for fila in resultados:
                codigo = fila.get("CodigoBarra")
                total = fila.get("total_egreso")
                if codigo:
                    ventas_agrupadas[codigo] = float(total) if total else 0.0

        logger.info(f"[REPO] Diccionario de ventas procesado: {ventas_agrupadas}")
        return ventas_agrupadas
    
    def get_ventas_diarias_en_bloque(self, codigos: list[str], desde: str, hasta: str) -> dict:
        """
        Devuelve el historial diario de egresos reales desde v_kardexproductos en MySQL.
        """
        if not codigos:
            return {}

        format_strings = ','.join(['%s'] * len(codigos))
        query = f"""
            SELECT 
                TRIM(CodigoBarra) AS codigo, 
                DATE(Fecha) AS fecha_venta, 
                SUM(COALESCE(Egreso, 0)) AS cantidad
            FROM v_kardexproductos
            WHERE CodigoBarra IN ({format_strings})
              AND Fecha >= %s AND Fecha <= %s
            GROUP BY CodigoBarra, DATE(Fecha)
        """
        
        # Conexión limpia usando la variable estructural de tu módulo
        resultados = db.fetch_all(query, tuple(codigos) + (desde, hasta))
        
        bulk = {}
        for row in resultados:
            cod = str(row['codigo']).strip()
            if cod not in bulk:
                bulk[cod] = []
                
            bulk[cod].append({
                "fecha": str(row['fecha_venta']),
                "cantidad": float(row['cantidad'])
            })
            
        return bulk