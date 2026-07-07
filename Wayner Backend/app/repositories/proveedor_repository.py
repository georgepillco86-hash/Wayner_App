from typing import List
from app.core.database import db # <--- ¡NUEVO IMPORT! Conexión a ferrotienda
from app.core.pedidos_database import pedidos_db

class ProveedorRepository:
    def get_proveedores_list(self) -> List[str]:
        query = "SELECT tablename FROM pg_tables WHERE schemaname = 'p_proveedores' ORDER BY tablename;"
        try:
            results = pedidos_db.fetch_all(query)
            return [row["tablename"] for row in results]
        except Exception as e:
            return []

    def get_productos_por_proveedor(self, nombre_proveedor: str) -> List[dict]:
        table_path = f'p_proveedores."{nombre_proveedor}"'
        query = f'SELECT * FROM {table_path} ORDER BY "NombreProducto"'
        try:
            return pedidos_db.fetch_all(query)
        except Exception as e:
            return []

    def obtener_precio_en_vivo(self, codigo_producto: str) -> dict:
        query = """
        SELECT MAX(Precio) as precio_vivo, MAX(IVA) as iva_vivo, MAX(Costo) as costo_vivo
        FROM v_kardexproductos WHERE Codigo = %s
        """
        try:
            res = pedidos_db.fetch_one(query, (codigo_producto,))
            return res if res else {"precio_vivo": 0, "iva_vivo": 0, "costo_vivo": 0}
        except Exception as e:
            return {"precio_vivo": 0, "iva_vivo": 0, "costo_vivo": 0}

    # ---> NUEVA BÚSQUEDA RÁPIDA (ESPEJO) <---
    # ---> NUEVA BÚSQUEDA RÁPIDA (ESPEJO) <---
    def buscar_rapido_proveedores(self, termino: str, proveedor_especifico: str = None) -> list:
        tablas = [proveedor_especifico] if proveedor_especifico else self.get_proveedores_list()
        if not tablas: return []
        
        termino_sql = f"%{termino}%"
        queries = []
        for tabla in tablas:
            # CORRECCIÓN: Se usan los nombres exactos creados en el servicio espejo (codigo_barra, nombre_producto, etc)
            queries.append(f"""
            SELECT codigo AS "Codigo", codigo_barra AS "CodigoBarra", nombre_producto AS "Nombre", 
                   '{tabla}' AS "Proveedor", 0 AS "Stock", precio AS "Precio", iva AS "IVA", costo AS "Costo"
            FROM p_proveedores."{tabla}"
            WHERE nombre_producto ILIKE %s OR codigo ILIKE %s OR codigo_barra ILIKE %s
            """)
        
        full_query = " UNION ALL ".join(queries) + " LIMIT 50"
        
        # CORRECCIÓN: Como ahora buscamos en 3 columnas (nombre, codigo, codigo_barra), pasamos el parámetro 3 veces por cada tabla
        params = tuple([termino_sql, termino_sql, termino_sql] * len(tablas))
        
        try:
            return pedidos_db.fetch_all(full_query, params)
        except Exception as e:
            print("❌ ERROR EN BÚSQUEDA RÁPIDA:", e)
            return []

    # ---> BÚSQUEDA PROFUNDA (KARDEX) <---
    # ---> BÚSQUEDA PROFUNDA (KARDEX) <---
    # ---> BÚSQUEDA PROFUNDA (KARDEX) <---
    def busqueda_profunda_kardex(self, termino: str) -> list:
        termino_sql = f"%{termino}%"
        query = """
        SELECT Codigo AS "Codigo", MAX(CodigoBarra) AS "CodigoBarra", MAX(NombreProducto) AS "Nombre", 
               MAX(NombreProveedor) AS "Proveedor", 0 AS "Stock", MAX(Precio) AS "Precio", 
               MAX(IVA) AS "IVA", MAX(Costo) AS "Costo"
        FROM v_kardexproductos
        WHERE NombreProducto LIKE %s OR Codigo LIKE %s OR CodigoBarra LIKE %s
        GROUP BY Codigo LIMIT 50
        """
        try:
            # CORRECCIÓN: Se utiliza LIKE en lugar de ILIKE para compatibilidad con MySQL
            return db.fetch_all(query, (termino_sql, termino_sql, termino_sql))
        except Exception as e:
            print("❌ ERROR EN BÚSQUEDA PROFUNDA:", e)
            return []