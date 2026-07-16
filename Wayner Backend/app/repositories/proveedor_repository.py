from typing import List
from app.core.database import db 
from app.core.pedidos_database import pedidos_db

class ProveedorRepository:
    
    def get_proveedores_list(self) -> list[str]:
        # ---> CORRECCIÓN: Eliminamos el filtro de 1 año para que carguen todos los proveedores
        query = """
        SELECT DISTINCT proveedor 
        FROM p_proveedores.catalogo_proveedores 
        WHERE proveedor IS NOT NULL 
          AND proveedor != ''
        ORDER BY proveedor;
        """
        try:
            results = pedidos_db.fetch_all(query)
            return [row["proveedor"] for row in results]
        except Exception as e:
            print("❌ ERROR OBTENIENDO PROVEEDORES:", e)
            return []

    def get_clases_list(self) -> list[str]:
        # ---> CORRECCIÓN: Eliminamos el filtro de 1 año para que carguen todas las clases
        query = """
        SELECT DISTINCT clase 
        FROM p_proveedores.catalogo_proveedores 
        WHERE clase IS NOT NULL 
          AND clase != ''
        ORDER BY clase;
        """
        try:
            results = pedidos_db.fetch_all(query)
            return [row["clase"] for row in results]
        except Exception as e:
            print("❌ ERROR OBTENIENDO CLASES:", e)
            return []
    
    def get_marcas_list(self) -> list[str]:
        query = """
        SELECT DISTINCT marca 
        FROM p_proveedores.catalogo_proveedores 
        WHERE marca IS NOT NULL AND TRIM(marca) != ''
        ORDER BY marca;
        """
        try:
            results = pedidos_db.fetch_all(query)
            return [row["marca"] for row in results]
        except Exception as e:
            print("❌ ERROR OBTENIENDO MARCAS:", e)
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

    def buscar_rapido_proveedores(self, termino: str, proveedor_especifico: str = None, clase_especifica: str = None) -> list:
        print(f"📞 [PASO 1] Petición recibida -> Buscando: '{termino}', Prov: '{proveedor_especifico}', Clase: '{clase_especifica}'")
        
        try:
            query_tiempos = """
            SELECT proveedor, 
                   MAX(fecha_entrega::date - fecha_programada::date) as lead_time_calculado 
            FROM ferrotienda.cronograma_visitas 
            WHERE estado = 'Pendiente' AND fecha_entrega IS NOT NULL
            GROUP BY proveedor
            """
            tiempos_bd = pedidos_db.fetch_all(query_tiempos)
            tiempos_map = {row["proveedor"]: int(row["lead_time_calculado"]) for row in tiempos_bd} if tiempos_bd else {}

            # ---> CORRECCIÓN: Eliminamos el filtro de 1 año aquí también para encontrar productos viejos
            query_pg = """
            SELECT codigo, codigo_barra, nombre_producto, proveedor, clase 
            FROM p_proveedores.catalogo_proveedores
            WHERE 1=1
            """
            params_pg = []
            
            termino = termino.strip() if termino else ""
            if termino:
                termino_sql = f"%{termino}%"
                query_pg += " AND (nombre_producto ILIKE %s OR codigo ILIKE %s OR codigo_barra ILIKE %s)"
                params_pg.extend([termino_sql, termino_sql, termino_sql])
                
            # 🔥 CORRECCIÓN: Uso de ILIKE para que el filtro coincida con fragmentos de texto
            if proveedor_especifico:
                query_pg += " AND proveedor ILIKE %s"
                params_pg.append(f"%{proveedor_especifico.strip()}%")
                
            if clase_especifica:
                query_pg += " AND clase ILIKE %s"
                params_pg.append(f"%{clase_especifica.strip()}%")
                
            if (proveedor_especifico or clase_especifica) and not termino:
                pass 
            else:
                query_pg += " LIMIT 50"
            
            resultados_pg = pedidos_db.fetch_all(query_pg, tuple(params_pg))
            print(f"🔎 [PASO 2] PostgreSQL encontró {len(resultados_pg if resultados_pg else [])} productos en el catálogo espejo.")
            
            if not resultados_pg:
                print("⚠️ [ALERTA] Como Postgres devolvió 0 productos, el sistema cancela la matemática y no va a MySQL.")
                return []
                
            codigos = [str(row["codigo"]).strip() for row in resultados_pg if row.get("codigo")]
            if not codigos:
                return []

            datos_vivos = {}
            lote_size = 100
            
            # 📍 RASTREADOR 3: Entrando a la matemática de MySQL
            print(f"🚀 [PASO 3] Consultando VDP en MySQL para {len(codigos)} productos...")
            
            for i in range(0, len(codigos), lote_size):
                lote = codigos[i:i + lote_size]
                format_strings = ','.join(['%s'] * len(lote))
                
                query_mysql = f"""
                SELECT 
                    TRIM(k.Codigo) AS Codigo,
                    MAX(s.Marca) AS Marca,         -- 🔥 1. AÑADIMOS LA EXTRACCIÓN DE LA MARCA DESDE LA VISTA DE SALDOS
                    COALESCE(MAX(s.Stock), 0) AS Stock,
                    CASE 
                        WHEN COALESCE(MAX(k.IVA), 0) > 0 THEN COALESCE(MAX(k.Precio), 0) * (1 + (MAX(k.IVA) / 100.0))
                        ELSE COALESCE(MAX(k.Precio), 0)
                    END AS Precio,
                    COALESCE(MAX(k.IVA), 0) AS IVA,
                    COALESCE(MAX(k.Costo), 0) AS Costo,
                    
                    MAX(k.Fecha) AS Ejemplo_Fecha,
                    COALESCE(SUM(CASE WHEN DATE(k.Fecha) >= DATE_SUB(CURDATE(), INTERVAL 365 DAY) THEN COALESCE(k.Egreso, 0) ELSE 0 END), 0) AS Suma_Egresos,
                    COALESCE(SUM(CASE WHEN DATE(k.Fecha) >= DATE_SUB(CURDATE(), INTERVAL 365 DAY) THEN COALESCE(k.Egreso, 0) ELSE 0 END) / 365.0, 0) AS VDP_Calculado
                    
                FROM v_kardexproductos k
                LEFT JOIN v_saldosproductos s ON k.Codigo = s.Codigo
                WHERE k.Codigo IN ({format_strings})
                GROUP BY k.Codigo
                """
                
                res_mysql_lote = db.fetch_all(query_mysql, tuple(lote))
                for idx, r in enumerate(res_mysql_lote):
                    clean_code = str(r["Codigo"]).strip() if r.get("Codigo") else ""
                    datos_vivos[clean_code] = r
                    
                    if i == 0 and idx < 3:
                        print(f"🛑 [DEBUG VDP] Producto: {clean_code} | Fecha Cruda: {r.get('Ejemplo_Fecha')} | Egresos: {r.get('Suma_Egresos')} | VDP: {r.get('VDP_Calculado')}")
                    
            respuesta_final = []
            
            def safe_float(val):
                if val is None: return 0.0
                try: return float(val)
                except: return 0.0

            for pg_row in resultados_pg:
                cod = str(pg_row["codigo"]).strip()
                vivo = datos_vivos.get(cod, {})
                proveedor_actual = pg_row.get("proveedor")
                tiempo_entrega = tiempos_map.get(proveedor_actual, 3)
                
                respuesta_final.append({
                    "Codigo": cod,
                    "CodigoBarra": pg_row.get("codigo_barra"),
                    "Nombre": pg_row.get("nombre_producto", ""),
                    "Marca": vivo.get("Marca") or "-",    # 🔥 2. INYECTAMOS LA MARCA AL DICCIONARIO
                    "Proveedor": proveedor_actual,
                    "Clase": pg_row.get("clase"), 
                    "Stock": safe_float(vivo.get("Stock", 0)),
                    "Precio": safe_float(vivo.get("Precio", 0)),
                    "IVA": safe_float(vivo.get("IVA", 0)),
                    "Costo": safe_float(vivo.get("Costo", 0)),
                    "vdp": safe_float(vivo.get("VDP_Calculado", 0)),
                    "lead_time_dias": tiempo_entrega
                })
                
            print(f"✅ [PASO 4] Proceso finalizado. Enviando {len(respuesta_final)} productos a Flutter.")
            return respuesta_final

        except Exception as e:
            import traceback
            print("❌ [ERROR CRÍTICO EN BÚSQUEDA RÁPIDA HÍBRIDA]:", e)
            traceback.print_exc()
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