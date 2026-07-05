import asyncio
import logging
import re
from datetime import datetime, timedelta
from app.core.database import db 
from app.core.pedidos_database import pedidos_db 

logger = logging.getLogger("uvicorn.error")

class ProviderMirrorService:
    @staticmethod
    def sanitize_table_name(name: str) -> str:
        # Limpia caracteres extraños dejando letras, números y espacios
        cleaned = re.sub(r'[^a-zA-Z0-9_\s]', '', name).strip()
        return cleaned

    @classmethod
    async def sincronizar_espejo(cls):
        try:
            logger.info("🔄 Iniciando sincronización de base de datos espejo de proveedores...")
            
            # Asegurar que el esquema exista
            pedidos_db.execute("CREATE SCHEMA IF NOT EXISTS p_proveedores;")
            
            # 1. Obtener todos los proveedores únicos
            query_proveedores = """
            SELECT DISTINCT NombreProveedor 
            FROM v_kardexproductos 
            WHERE NombreProveedor IS NOT NULL 
            AND TRIM(NombreProveedor) <> '' 
            AND UPPER(TRIM(NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
            """
            providers = db.fetch_all(query_proveedores)
            
            if not providers:
                logger.warning("⚠️ No se encontraron proveedores para sincronizar.")
                return

            for row in providers:
                prov_original = row["NombreProveedor"].strip()
                prov_limpio = cls.sanitize_table_name(prov_original)
                
                if not prov_limpio:
                    continue
                
                table_path = f'p_proveedores."{prov_limpio}"'
                
                # 2. Extraer productos ÚNICOS uniendo Kardex y Saldos (Sin Stock)
                query_productos = """
                SELECT 
                    k.Codigo, 
                    MAX(COALESCE(k.CodigoBarra, '')) AS CodigoBarra, 
                    MAX(k.NombreProducto) AS NombreProducto, 
                    MAX(COALESCE(k.Precio, 0)) AS Precio, 
                    MAX(COALESCE(k.IVA, 0)) AS IVA, 
                    MAX(COALESCE(k.Costo, 0)) AS Costo,
                    MAX(COALESCE(s.Marca, '')) AS Marca,
                    MAX(COALESCE(s.Clase, '')) AS Clase
                FROM v_kardexproductos k
                LEFT JOIN v_saldosproductos s ON TRIM(k.Codigo) = TRIM(s.Codigo)
                WHERE k.NombreProveedor = %s
                GROUP BY k.Codigo
                """
                productos = db.fetch_all(query_productos, (prov_original,))
                
                # 3. Recrear la tabla limpia con las nuevas columnas
                pedidos_db.execute(f'DROP TABLE IF EXISTS {table_path};')
                pedidos_db.execute(f"""
                    CREATE TABLE {table_path} (
                        codigo VARCHAR(100),
                        codigo_barra VARCHAR(100),
                        nombre_producto VARCHAR(255),
                        precio NUMERIC(12, 4),
                        iva NUMERIC(5, 2),
                        costo NUMERIC(12, 4),
                        marca VARCHAR(255),
                        clase VARCHAR(255)
                    );
                """)
                
                # 4. Insertar los productos únicos enriquecidos en lote
                for prod in productos:
                    insert_query = f"""
                        INSERT INTO {table_path} 
                        (codigo, codigo_barra, nombre_producto, precio, iva, costo, marca, clase)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
                    """
                    pedidos_db.execute(insert_query, (
                        prod["Codigo"],
                        prod["CodigoBarra"],
                        prod["NombreProducto"],
                        prod["Precio"],
                        prod["IVA"],
                        prod["Costo"],
                        prod["Marca"],
                        prod["Clase"]
                    ))
                
                # 5. Índices para búsquedas ultrarrápidas
                idx_name = prov_limpio.lower().replace(" ", "_")
                pedidos_db.execute(f'CREATE INDEX IF NOT EXISTS idx_m_{idx_name}_cod ON {table_path}(codigo);')
                pedidos_db.execute(f'CREATE INDEX IF NOT EXISTS idx_m_{idx_name}_nom ON {table_path}(nombre_producto);')

            logger.info("✅ Sincronización espejo de proveedores completada. Catálogos únicos creados.")
        except Exception as e:
            logger.error(f"❌ Error crítico en el servicio espejo de proveedores: {str(e)}")

    @classmethod
    async def iniciar_bucle_sincronizacion(cls):
        """
        Bucle infinito que calcula el tiempo exacto hasta el próximo 
        domingo a las 23:00 (11 PM) y ejecuta la sincronización.
        """
        while True:
            ahora = datetime.now()
            
            # En Python, .weekday() devuelve 0 para Lunes y 6 para Domingo.
            # Calculamos cuántos días faltan para que sea Domingo (6)
            dias_faltantes = 6 - ahora.weekday()
            
            # Si hoy ya es domingo pero pasaron las 23:00, programamos para el próximo domingo (+7 días)
            if dias_faltantes == 0 and ahora.hour >= 23:
                dias_faltantes = 7
                
            # Construimos la fecha y hora exactas de la próxima ejecución (23:00:00)
            proxima_ejecucion = ahora + timedelta(days=dias_faltantes)
            proxima_ejecucion = proxima_ejecucion.replace(hour=23, minute=0, second=0, microsecond=0)
            
            # Calculamos en segundos la diferencia entre la próxima ejecución y este instante
            segundos_espera = (proxima_ejecucion - ahora).total_seconds()
            
            logger.info(f"⏳ Próxima sincronización de proveedores programada para: {proxima_ejecucion.strftime('%Y-%m-%d %H:%M:%S')}")
            
            # Dormimos la tarea hasta que llegue el domingo a las 11 PM
            await asyncio.sleep(segundos_espera)
            
            # Cuando despierta, ejecuta la sincronización pesada
            await cls.sincronizar_espejo()