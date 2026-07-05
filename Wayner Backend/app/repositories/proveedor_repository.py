from typing import List
from app.core.pedidos_database import pedidos_db 

class ProveedorRepository:
    def get_proveedores_list(self) -> List[str]:
        # Consultamos el esquema de información de Postgres para listar todas las tablas creadas
        query = """
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'p_proveedores'
        ORDER BY tablename;
        """
        try:
            results = pedidos_db.fetch_all(query)
            # Devolvemos solo la lista de nombres
            proveedores = [row["tablename"] for row in results]
            return proveedores
        except Exception as e:
            print("❌ ERROR AL LEER PROVEEDORES:", e)
            return []

    def get_productos_por_proveedor(self, nombre_proveedor: str) -> List[dict]:
        # Apuntamos exactamente a la tabla del proveedor envuelta en comillas dobles
        table_path = f'p_proveedores."{nombre_proveedor}"'
        
        # Hacemos la consulta directa usando el índice de la tabla espejo
        query = f"SELECT * FROM {table_path} ORDER BY nombre_producto"
        try:
            return pedidos_db.fetch_all(query)
        except Exception as e:
            return []