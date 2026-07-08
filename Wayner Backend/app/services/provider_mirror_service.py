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
            
            # 1. Asegurar que el esquema y la TABLA ÚNICA existan
            pedidos_db.execute("CREATE SCHEMA IF NOT EXISTS p_proveedores;")
            
            pedidos_db.execute("""
                CREATE TABLE IF NOT EXISTS p_proveedores.catalogo_proveedores (
                    id SERIAL PRIMARY KEY,
                    codigo VARCHAR(50),
                    codigo_barra VARCHAR(100),
                    nombre_producto VARCHAR(255) NOT NULL,
                    precio NUMERIC(12, 4) DEFAULT 0.0000,
                    iva NUMERIC(5, 2) DEFAULT 0.00,
                    costo NUMERIC(12, 4) DEFAULT 0.0000,
                    marca VARCHAR(255),
                    clase VARCHAR(255),
                    proveedor VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            
            # 2. VACIAR la tabla antes de llenarla con los datos actualizados de esta semana
            pedidos_db.execute("TRUNCATE TABLE p_proveedores.catalogo_proveedores RESTART IDENTITY;")
            
            # 3. Obtener todos los proveedores únicos
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

            # 4. Procesar y guardar productos de todos los proveedores en la MISMA tabla
            for row in providers:
                prov_original = row["NombreProveedor"].strip()
                prov_limpio = cls.sanitize_table_name(prov_original)
                
                if not prov_limpio:
                    continue
                
                # Extraer productos ÚNICOS uniendo Kardex y Saldos
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
                
                # Insertar los productos en la nueva tabla unificada catalogo_proveedores
                for prod in productos:
                    insert_query = """
                        INSERT INTO p_proveedores.catalogo_proveedores 
                        (codigo, codigo_barra, nombre_producto, precio, iva, costo, marca, clase, proveedor)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);
                    """
                    pedidos_db.execute(insert_query, (
                        prod["Codigo"],
                        prod["CodigoBarra"],
                        prod["NombreProducto"],
                        prod["Precio"],
                        prod["IVA"],
                        prod["Costo"],
                        prod["Marca"],
                        prod["Clase"],
                        prov_original
                    ))
            
            # 5. Asegurarnos de que los índices existan para búsquedas instantáneas
            pedidos_db.execute('CREATE INDEX IF NOT EXISTS idx_cat_prov_nombre ON p_proveedores.catalogo_proveedores(nombre_producto);')
            pedidos_db.execute('CREATE INDEX IF NOT EXISTS idx_cat_prov_codigo ON p_proveedores.catalogo_proveedores(codigo);')
            pedidos_db.execute('CREATE INDEX IF NOT EXISTS idx_cat_prov_codbarra ON p_proveedores.catalogo_proveedores(codigo_barra);')
            pedidos_db.execute('CREATE INDEX IF NOT EXISTS idx_cat_prov_proveedor ON p_proveedores.catalogo_proveedores(proveedor);')

            logger.info("✅ Sincronización espejo completada. Tabla unificada 'catalogo_proveedores' actualizada con éxito.")
        except Exception as e:
            logger.error(f"❌ Error crítico en el servicio espejo de proveedores: {str(e)}")

    @classmethod
    async def iniciar_bucle_sincronizacion(cls):
        """
        Bucle infinito que calcula el tiempo exacto hasta el próximo 
        domingo a las 23:00 (11 PM) y ejecuta la sincronización masiva.
        """
        while True:
            ahora = datetime.now()
            
            # En Python, .weekday() devuelve 0 para Lunes y 6 para Domingo.
            dias_faltantes = 6 - ahora.weekday()
            
            # Si hoy ya es domingo pero pasaron las 23:00, programamos para el próximo domingo (+7 días)
            if dias_faltantes == 0 and ahora.hour >= 23:
                dias_faltantes = 7
                
            # Construimos la fecha y hora exactas de la próxima ejecución (23:00:00)
            proxima_ejecucion = ahora + timedelta(days=dias_faltantes)
            proxima_ejecucion = proxima_ejecucion.replace(hour=23, minute=0, second=0, microsecond=0)
            
            # Calculamos en segundos la diferencia entre la próxima ejecución y este instante
            segundos_espera = (proxima_ejecucion - ahora).total_seconds()
            
            logger.info(f"⏳ Próxima sincronización masiva de proveedores programada para: {proxima_ejecucion.strftime('%Y-%m-%d %H:%M:%S')}")
            
            # Dormimos la tarea de fondo sin bloquear el servidor hasta que llegue el momento
            await asyncio.sleep(segundos_espera)
            
            # Al despertar, ejecuta la tarea pesada
            await cls.sincronizar_espejo()