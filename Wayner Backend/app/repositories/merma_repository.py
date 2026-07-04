from typing import Any, List
from app.core.database import db 
from app.core.pedidos_database import pedidos_db 

class MermaRepository:
    TABLE_NAME = "ferrotienda.mermas" 
    HISTORY_TABLE = "ferrotienda.reporte_mermas"

    def get_proveedores(self, codigo: str) -> str:
        query = """
        SELECT DISTINCT NombreProveedor 
        FROM v_kardexproductos 
        WHERE Codigo = %s 
        AND NombreProveedor IS NOT NULL 
        AND TRIM(NombreProveedor) <> '' 
        AND UPPER(TRIM(NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
        """
        result = db.fetch_all(query, (codigo,))
        if not result:
            return "SIN PROVEEDOR"
        proveedores = [row["NombreProveedor"] for row in result]
        return " / ".join(proveedores)

    def create(self, data: dict, usuario: str) -> dict:
        proveedor = self.get_proveedores(data["codigo"])
        
        query = f"""
        INSERT INTO {self.TABLE_NAME} 
        (codigo, nombre_producto, cantidad, proveedor, novedad, comentario, estado, usuario, activo)
        VALUES (%s, %s, %s, %s, %s, %s, 'Pendiente', %s, TRUE)
        RETURNING id;
        """
        params = (
            data["codigo"],
            data["nombre_producto"],
            data["cantidad"],
            proveedor,
            data["novedad"],
            data.get("comentario", ""),
            usuario
        )
        merma_id = pedidos_db.execute(query, params)
        
        # Registrar el primer mensaje en el historial automáticamente
        historial_query = f"""
        INSERT INTO {self.HISTORY_TABLE} (merma_id, usuario, estado_anterior, estado_nuevo, comentario)
        VALUES (%s, %s, 'Ninguno', 'Pendiente', 'Ingreso inicial de merma registrado.')
        """
        pedidos_db.execute(historial_query, (merma_id, usuario))
        
        return pedidos_db.fetch_one(f"SELECT * FROM {self.TABLE_NAME} WHERE id = %s", (merma_id,))

    def get_all(self) -> List[dict]:
        query = f"SELECT * FROM {self.TABLE_NAME} ORDER BY fecha_registro DESC"
        return pedidos_db.fetch_all(query)

    def get_historial(self, merma_id: int) -> List[dict]:
        query = f"SELECT * FROM {self.HISTORY_TABLE} WHERE merma_id = %s ORDER BY fecha_registro ASC"
        return pedidos_db.fetch_all(query, (merma_id,))

    def update(self, merma_id: int, data: dict, usuario: str, rol: str) -> dict | None:
        # Si NO es ADMIN, verificamos que sea el dueño y esté dentro de los 3 días
        if rol != 'ADMIN':
            check_query = f"""
            SELECT id FROM {self.TABLE_NAME} 
            WHERE id = %s AND usuario = %s 
            AND fecha_registro >= NOW() - INTERVAL '3 days'
            """
            can_edit = pedidos_db.fetch_one(check_query, (merma_id, usuario))
            if not can_edit:
                raise Exception("No tienes permiso para editar esta merma o ya pasó el límite de 3 días.")

        query = f"""
        UPDATE {self.TABLE_NAME}
        SET cantidad = COALESCE(%s, cantidad),
            novedad = COALESCE(%s, novedad),
            comentario = COALESCE(%s, comentario)
        WHERE id = %s
        RETURNING id;
        """
        pedidos_db.execute(query, (data.get("cantidad"), data.get("novedad"), data.get("comentario"), merma_id))
        return pedidos_db.fetch_one(f"SELECT * FROM {self.TABLE_NAME} WHERE id = %s", (merma_id,))

    def update_estado(self, merma_id: int, estado_nuevo: str, comentario: str, usuario: str, nota_credito: str = None) -> dict | None:
        if not comentario or comentario.strip() == "":
            raise Exception("El comentario justificativo es obligatorio para cambiar el estado.")
            
        if estado_nuevo.upper() == 'RESUELTO' and (not nota_credito or nota_credito.strip() == ""):
            raise Exception("Debe ingresar el número de Nota de Crédito o justificación para resolver la merma.")

        # Obtener estado actual
        merma = pedidos_db.fetch_one(f"SELECT estado FROM {self.TABLE_NAME} WHERE id = %s", (merma_id,))
        if not merma:
            raise Exception("Merma no encontrada.")
        estado_anterior = merma["estado"]

        activo = False if estado_nuevo.upper() == 'RESUELTO' else True
        
        # 1. Actualizar estado en la tabla principal
        query_update = f"""
        UPDATE {self.TABLE_NAME}
        SET estado = %s, activo = %s
        WHERE id = %s
        RETURNING id;
        """
        pedidos_db.execute(query_update, (estado_nuevo, activo, merma_id))
        
        # 2. Guardar en el historial (Chat)
        mensaje_chat = comentario
        if estado_nuevo.upper() == 'RESUELTO':
             mensaje_chat = f"PROCESO FINALIZADO. Justificación/Nota de Crédito: {nota_credito}. Comentario: {comentario}"

        query_historial = f"""
        INSERT INTO {self.HISTORY_TABLE} 
        (merma_id, usuario, estado_anterior, estado_nuevo, comentario, nota_credito)
        VALUES (%s, %s, %s, %s, %s, %s)
        """
        pedidos_db.execute(query_historial, (merma_id, usuario, estado_anterior, estado_nuevo, mensaje_chat, nota_credito))

        return pedidos_db.fetch_one(f"SELECT * FROM {self.TABLE_NAME} WHERE id = %s", (merma_id,))

    def delete(self, merma_id: int, usuario: str, rol: str) -> bool:
        if rol == 'ADMIN':
            query = f"DELETE FROM {self.TABLE_NAME} WHERE id = %s RETURNING id"
            deleted_id = pedidos_db.execute(query, (merma_id,))
        else:
            query = f"DELETE FROM {self.TABLE_NAME} WHERE id = %s AND usuario = %s RETURNING id"
            deleted_id = pedidos_db.execute(query, (merma_id, usuario))
            
        return bool(deleted_id)