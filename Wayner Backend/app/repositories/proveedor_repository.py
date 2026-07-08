from typing import List
from app.core.database import db 
from app.core.pedidos_database import pedidos_db

class ProveedorRepository:
    
    def get_proveedores_list(self) -> List[str]:
        query = "SELECT DISTINCT proveedor FROM p_proveedores.catalogo_proveedores ORDER BY proveedor;"
        try:
            results = pedidos_db.fetch_all(query)
            return [row["proveedor"] for row in results]
        except Exception as e:
            return []

    def get_productos_por_proveedor(self, nombre_proveedor: str) -> List[dict]:
        query = """
        SELECT codigo AS "Codigo", codigo_barra AS "CodigoBarra", nombre_producto AS "NombreProducto", 
               precio AS "Precio", iva AS "IVA", costo AS "Costo", marca AS "Marca", 
               clase AS "Clase", proveedor AS "Proveedor"
        FROM p_proveedores.catalogo_proveedores 
        WHERE proveedor = %s 
        ORDER BY nombre_producto
        """
        try:
            return pedidos_db.fetch_all(query, (nombre_proveedor,))
        except Exception as e:
            return []

    def obtener_precio_en_vivo(self, codigo_producto: str) -> dict:
        query = """
        SELECT 
            CASE 
                WHEN MAX(IVA) > 0 THEN MAX(Precio) * (1 + (MAX(IVA) / 100.0))
                ELSE MAX(Precio)
            END as precio_vivo, 
            MAX(IVA) as iva_vivo, 
            MAX(Costo) as costo_vivo
        FROM v_kardexproductos 
        WHERE Codigo = %s
        """
        try:
            res = db.fetch_one(query, (codigo_producto,))
            return res if res else {"precio_vivo": 0, "iva_vivo": 0, "costo_vivo": 0}
        except Exception as e:
            return {"precio_vivo": 0, "iva_vivo": 0, "costo_vivo": 0}

    # ---> BÚSQUEDA RÁPIDA HÍBRIDA POR PYTHON <---
    def buscar_rapido_proveedores(self, termino: str, proveedor_especifico: str = None) -> list:
        # 1. Buscamos en PostgreSQL (pedidos_db) los códigos y nombres ultra rápido
        query_pg = """
        SELECT codigo, codigo_barra, nombre_producto, proveedor 
        FROM p_proveedores.catalogo_proveedores
        WHERE 1=1
        """
        params_pg = []
        
        # Si el usuario escribió un término, lo agregamos
        termino = termino.strip() if termino else ""
        if termino:
            termino_sql = f"%{termino}%"
            query_pg += " AND (nombre_producto ILIKE %s OR codigo ILIKE %s OR codigo_barra ILIKE %s)"
            params_pg.extend([termino_sql, termino_sql, termino_sql])
            
        # Si el usuario seleccionó un proveedor, lo agregamos
        if proveedor_especifico:
            query_pg += " AND proveedor = %s"
            params_pg.append(proveedor_especifico)
            
        # 🚨 AQUÍ ELIMINAMOS EL LÍMITE PARA PROVEEDORES 🚨
        if proveedor_especifico and not termino:
            # Si cargamos un proveedor entero, NO ponemos límite.
            # El servidor envía todos los registros a la memoria del celular.
            pass 
        else:
            # Si es una búsqueda libre (sin proveedor elegido), 
            # limitamos a 50 para que sea instantáneo.
            query_pg += " LIMIT 50"
        
        try:
            resultados_pg = pedidos_db.fetch_all(query_pg, tuple(params_pg))
            if not resultados_pg:
                return []
                
            # Extraemos los códigos encontrados para llevarlos a MySQL
            codigos = [row["codigo"] for row in resultados_pg]
            format_strings = ','.join(['%s'] * len(codigos))
            
            # 2. Buscamos los datos financieros en vivo en MySQL (db)
            query_mysql = f"""
            SELECT 
                TRIM(k.Codigo) AS Codigo,
                COALESCE(MAX(s.Stock), 0) AS Stock,
                CASE 
                    WHEN COALESCE(MAX(k.IVA), 0) > 0 THEN COALESCE(MAX(k.Precio), 0) * (1 + (MAX(k.IVA) / 100.0))
                    ELSE COALESCE(MAX(k.Precio), 0)
                END AS Precio,
                COALESCE(MAX(k.IVA), 0) AS IVA,
                COALESCE(MAX(k.Costo), 0) AS Costo
            FROM v_kardexproductos k
            LEFT JOIN v_saldosproductos s ON TRIM(k.Codigo) = TRIM(s.Codigo)
            WHERE TRIM(k.Codigo) IN ({format_strings})
            GROUP BY TRIM(k.Codigo)
            """
            
            resultados_mysql = db.fetch_all(query_mysql, tuple(codigos))
            
            # Convertimos la respuesta de MySQL en un diccionario para inyectarlo fácil
            datos_vivos = {row["Codigo"]: row for row in resultados_mysql}
            
            # 3. Combinamos ambos mundos y devolvemos la lista completa
            respuesta_final = []
            for pg_row in resultados_pg:
                cod = pg_row["codigo"]
                vivo = datos_vivos.get(cod, {})
                
                respuesta_final.append({
                    "Codigo": cod,
                    "CodigoBarra": pg_row["codigo_barra"],
                    "Nombre": pg_row["nombre_producto"],
                    "Proveedor": pg_row["proveedor"],
                    "Stock": float(vivo.get("Stock", 0)),
                    "Precio": float(vivo.get("Precio", 0)),
                    "IVA": float(vivo.get("IVA", 0)),
                    "Costo": float(vivo.get("Costo", 0))
                })
                
            return respuesta_final

        except Exception as e:
            print("❌ ERROR EN BÚSQUEDA RÁPIDA HÍBRIDA:", e)
            return []

    # ---> BÚSQUEDA PROFUNDA (KARDEX) <---
    def busqueda_profunda_kardex(self, termino: str) -> list:
        termino_sql = f"%{termino}%"
        query = """
        SELECT 
            Codigo AS "Codigo", 
            MAX(CodigoBarra) AS "CodigoBarra", 
            MAX(NombreProducto) AS "Nombre", 
            MAX(NombreProveedor) AS "Proveedor", 
            0 AS "Stock", 
            CASE 
                WHEN MAX(IVA) > 0 THEN MAX(Precio) * (1 + (MAX(IVA) / 100.0))
                ELSE MAX(Precio)
            END AS "Precio", 
            MAX(IVA) AS "IVA", 
            MAX(Costo) AS "Costo"
        FROM v_kardexproductos
        WHERE NombreProducto LIKE %s OR Codigo LIKE %s OR CodigoBarra LIKE %s
        GROUP BY Codigo LIMIT 50
        """
        try:
            return db.fetch_all(query, (termino_sql, termino_sql, termino_sql))
        except Exception as e:
            print("❌ ERROR EN BÚSQUEDA PROFUNDA:", e)
            return []