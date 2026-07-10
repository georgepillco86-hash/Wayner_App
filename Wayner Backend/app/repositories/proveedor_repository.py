from typing import List
from app.core.database import db 
from app.core.pedidos_database import pedidos_db

class ProveedorRepository:
    
    def get_proveedores_list(self) -> list[str]:
        # ---> ACTUALIZADO: Solo trae proveedores con productos activos en el último año <---
        query = """
        SELECT DISTINCT proveedor 
        FROM p_proveedores.catalogo_proveedores 
        WHERE proveedor IS NOT NULL 
          AND (ultimo_movimiento >= CURRENT_DATE - INTERVAL '1 year' OR ultimo_movimiento IS NULL)
        ORDER BY proveedor;
        """
        try:
            results = pedidos_db.fetch_all(query)
            return [row["proveedor"] for row in results]
        except Exception as e:
            print("❌ ERROR OBTENIENDO PROVEEDORES:", e)
            return []

    def get_clases_list(self) -> list[str]:
        # ---> ACTUALIZADO: Solo trae clases con productos activos en el último año <---
        query = """
        SELECT DISTINCT clase 
        FROM p_proveedores.catalogo_proveedores 
        WHERE clase IS NOT NULL 
          AND (ultimo_movimiento >= CURRENT_DATE - INTERVAL '1 year' OR ultimo_movimiento IS NULL)
        ORDER BY clase;
        """
        try:
            results = pedidos_db.fetch_all(query)
            return [row["clase"] for row in results]
        except Exception as e:
            print("❌ ERROR OBTENIENDO CLASES:", e)
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
    # ---> BÚSQUEDA RÁPIDA HÍBRIDA POR PYTHON (TIEMPO REAL) <---
    def buscar_rapido_proveedores(self, termino: str, proveedor_especifico: str = None, clase_especifica: str = None) -> list:
        try:
            # 0. NUEVO: Extraer los tiempos de entrega (Lead Time) dinámicos del Calendario
            query_tiempos = """
            SELECT proveedor, 
                   MAX(fecha_entrega - fecha_programada) as lead_time_calculado 
            FROM ferrotienda.cronograma_visitas 
            WHERE estado = 'Pendiente' AND fecha_entrega IS NOT NULL
            GROUP BY proveedor
            """
            tiempos_bd = pedidos_db.fetch_all(query_tiempos)
            # Creamos un diccionario rápido para buscar el tiempo de cada proveedor
            tiempos_map = {row["proveedor"]: int(row["lead_time_calculado"]) for row in tiempos_bd} if tiempos_bd else {}

            # 1. Buscamos en PostgreSQL (Lista de productos activos)
            query_pg = """
            SELECT codigo, codigo_barra, nombre_producto, proveedor, clase 
            FROM p_proveedores.catalogo_proveedores
            WHERE 1=1
              AND (ultimo_movimiento >= CURRENT_DATE - INTERVAL '1 year' OR ultimo_movimiento IS NULL)
            """
            params_pg = []
            
            termino = termino.strip() if termino else ""
            if termino:
                termino_sql = f"%{termino}%"
                query_pg += " AND (nombre_producto ILIKE %s OR codigo ILIKE %s OR codigo_barra ILIKE %s)"
                params_pg.extend([termino_sql, termino_sql, termino_sql])
                
            if proveedor_especifico:
                query_pg += " AND proveedor = %s"
                params_pg.append(proveedor_especifico)
                
            if clase_especifica:
                query_pg += " AND clase = %s"
                params_pg.append(clase_especifica)
                
            if (proveedor_especifico or clase_especifica) and not termino:
                pass 
            else:
                query_pg += " LIMIT 50"
            
            resultados_pg = pedidos_db.fetch_all(query_pg, tuple(params_pg))
            if not resultados_pg:
                return []
                
            codigos = [str(row["codigo"]).strip() for row in resultados_pg if row.get("codigo")]
            if not codigos:
                return []

            # 2. Buscamos en MySQL en LOTES (Cálculo Vivo de Precios y VDP)
            datos_vivos = {}
            lote_size = 100
            
            print(f"🚀 [MYSQL] Calculando VDP y Precios para {len(codigos)} productos en lotes de {lote_size}...")
            
            for i in range(0, len(codigos), lote_size):
                lote = codigos[i:i + lote_size]
                format_strings = ','.join(['%s'] * len(lote))
                
                # ---> QUERY OPTIMIZADO: Agregamos el cálculo VDP de 1 Año en Tiempo Real <---
                query_mysql = f"""
                SELECT 
                    TRIM(k.Codigo) AS Codigo,
                    COALESCE(MAX(s.Stock), 0) AS Stock,
                    CASE 
                        WHEN COALESCE(MAX(k.IVA), 0) > 0 THEN COALESCE(MAX(k.Precio), 0) * (1 + (MAX(k.IVA) / 100.0))
                        ELSE COALESCE(MAX(k.Precio), 0)
                    END AS Precio,
                    COALESCE(MAX(k.IVA), 0) AS IVA,
                    COALESCE(MAX(k.Costo), 0) AS Costo,
                    
                    /* CÁLCULO VDP: Promedio diario de ventas estrictamente del último año (365 días) */
                    COALESCE(SUM(CASE WHEN DATE(k.Fecha) >= DATE_SUB(CURDATE(), INTERVAL 365 DAY) THEN COALESCE(k.Egreso, 0) ELSE 0 END) / 365.0, 0) AS VDP_Calculado
                    
                FROM v_kardexproductos k
                LEFT JOIN v_saldosproductos s ON k.Codigo = s.Codigo
                WHERE k.Codigo IN ({format_strings})
                GROUP BY k.Codigo
                """
                
                res_mysql_lote = db.fetch_all(query_mysql, tuple(lote))
                for r in res_mysql_lote:
                    clean_code = str(r["Codigo"]).strip() if r.get("Codigo") else ""
                    datos_vivos[clean_code] = r
                    
                print(f"   ⏳ Lote procesado: {i + len(lote)} / {len(codigos)}")

            # 3. Combinamos la información y la empaquetamos para Flutter
            respuesta_final = []
            
            def safe_float(val):
                if val is None: return 0.0
                try: return float(val)
                except: return 0.0

            for pg_row in resultados_pg:
                cod = str(pg_row["codigo"]).strip()
                vivo = datos_vivos.get(cod, {})
                proveedor_actual = pg_row.get("proveedor")
                
                # Asignamos el lead time dinámico (Si el proveedor no tiene visita, por defecto asume 3 días)
                tiempo_entrega = tiempos_map.get(proveedor_actual, 3)
                
                respuesta_final.append({
                    "Codigo": cod,
                    "CodigoBarra": pg_row.get("codigo_barra"),
                    "Nombre": pg_row.get("nombre_producto", ""),
                    "Proveedor": proveedor_actual,
                    "Clase": pg_row.get("clase"), 
                    "Stock": safe_float(vivo.get("Stock", 0)),
                    "Precio": safe_float(vivo.get("Precio", 0)),
                    "IVA": safe_float(vivo.get("IVA", 0)),
                    "Costo": safe_float(vivo.get("Costo", 0)),
                    
                    # Inyectamos los datos matemáticos
                    "vdp": safe_float(vivo.get("VDP_Calculado", 0)),
                    "lead_time_dias": tiempo_entrega
                })
                
            print(f"✅ [ÉXITO] {len(respuesta_final)} productos devueltos a Flutter.")
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