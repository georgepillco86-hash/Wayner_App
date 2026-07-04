import asyncio
import logging
import re
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
            
            # 1. Obtener todos los proveedores únicos del Kardex principal
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
                
                # Definir ruta de la tabla con comillas dobles para soportar espacios
                table_path = f'p_proveedores."{prov_limpio}"'
                
                # 2. Extraer los productos vigentes asignados a este proveedor en el Kardex
                query_productos = """
                SELECT 
                    Codigo, 
                    COALESCE(CodigoBarra, '') AS CodigoBarra, 
                    NombreProducto, 
                    COALESCE(Precio, 0) AS Precio, 
                    COALESCE(IVA, 0) AS IVA, 
                    COALESCE(Costo, 0) AS Costo
                FROM v_kardexproductos
                WHERE NombreProveedor = %s
                """
                productos = db.fetch_all(query_productos, (prov_original,))
                
                # 3. Recrear la tabla limpia en Postgres para el proveedor específico
                pedidos_db.execute(f'DROP TABLE IF EXISTS {table_path};')
                pedidos_db.execute(f"""
                    CREATE TABLE {table_path} (
                        codigo VARCHAR(100),
                        codigo_barra VARCHAR(100),
                        nombre_producto VARCHAR(255),
                        precio NUMERIC(12, 4),
                        iva NUMERIC(5, 2),
                        costo NUMERIC(12, 4)
                    );
                """)
                
                # 4. Insertar los productos correspondientes en lote
                for prod in productos:
                    insert_query = f"""
                        INSERT INTO {table_path} (codigo, codigo_barra, nombre_producto, precio, iva, costo)
                        VALUES (%s, %s, %s, %s, %s, %s);
                    """
                    pedidos_db.execute(insert_query, (
                        prod["Codigo"],
                        prod["CodigoBarra"],
                        prod["NombreProducto"],
                        prod["Precio"],
                        prod["IVA"],
                        prod["Costo"]
                    ))
                
                # 5. Crear índices para optimizar búsquedas instantáneas por código o nombre
                idx_name = prov_limpio.lower().replace(" ", "_")
                pedidos_db.execute(f'CREATE INDEX IF NOT EXISTS idx_m_{idx_name}_cod ON {table_path}(codigo);')
                pedidos_db.execute(f'CREATE INDEX IF NOT EXISTS idx_m_{idx_name}_nom ON {table_path}(nombre_producto);')

            logger.info("✅ Sincronización espejo de proveedores completada con éxito.")
        except Exception as e:
            logger.error(f"❌ Error crítico en el servicio espejo de proveedores: {str(e)}")

    @classmethod
    async def iniciar_bucle_cada_hora(cls):
        # Ejecuta la sincronización en bucle infinito cada 1 hora (3600 segundos)
        while True:
            await cls.sincronizar_espejo()
            await asyncio.sleep(3600)