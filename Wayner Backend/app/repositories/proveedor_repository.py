from typing import List
from app.core.pedidos_database import pedidos_db 

class ProveedorRepository:
    def get_proveedores_list(self) -> List[str]:
        query = """
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'p_proveedores'
        ORDER BY tablename;
        """
        try:
            results = pedidos_db.fetch_all(query)
            proveedores = [row["tablename"] for row in results]
            return proveedores
        except Exception as e:
            print("❌ ERROR AL LEER PROVEEDORES:", e)
            return []

    def get_productos_por_proveedor(self, nombre_proveedor: str) -> List[dict]:
        table_path = f'p_proveedores."{nombre_proveedor}"'
        query = f"SELECT * FROM {table_path} ORDER BY nombre_producto"
        try:
            return pedidos_db.fetch_all(query)
        except Exception as e:
            return []

    def obtener_precio_en_vivo(self, codigo_producto: str) -> dict:
        query = """
        SELECT 
            MAX(Precio) as precio_vivo, 
            MAX(IVA) as iva_vivo, 
            MAX(Costo) as costo_vivo
        FROM v_kardexproductos
        WHERE Codigo = %s
        """
        try:
            resultado = pedidos_db.fetch_one(query, (codigo_producto,))
            return resultado if resultado else {"precio_vivo": 0, "iva_vivo": 0, "costo_vivo": 0}
        except Exception as e:
            print(f"❌ ERROR AL BUSCAR PRECIO EN VIVO ({codigo_producto}):", e)
            return {"precio_vivo": 0, "iva_vivo": 0, "costo_vivo": 0}

    def busqueda_profunda_kardex(self, termino: str) -> list:
        termino_sql = f"%{termino}%"
        query = """
        SELECT 
            Codigo as codigo, 
            MAX(CodigoBarra) as codigo_barra, 
            MAX(NombreProducto) as nombre_producto, 
            MAX(NombreProveedor) as proveedor, 
            MAX(Precio) as precio, 
            MAX(IVA) as iva, 
            MAX(Costo) as costo
        FROM v_kardexproductos
        WHERE NombreProducto ILIKE %s OR Codigo ILIKE %s
        GROUP BY Codigo
        LIMIT 50
        """
        try:
            return pedidos_db.fetch_all(query, (termino_sql, termino_sql))
        except Exception as e:
            print("❌ ERROR EN BÚSQUEDA PROFUNDA:", e)
            return []