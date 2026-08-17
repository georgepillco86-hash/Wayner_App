from typing import Any, List
from app.core.database import db 
from app.core.pedidos_database import pedidos_db 
import datetime

class MermaRepository:
    TABLE_NAME = "ferrotienda.mermas" 
    HISTORY_TABLE = "ferrotienda.reporte_mermas"

    def _get_merma_con_contacto(self, merma_id: int) -> dict:
        query = f"""
        SELECT m.*, cp.contacto AS contacto_proveedor
        FROM {self.TABLE_NAME} m
        LEFT JOIN ferrotienda.cronograma_pedidos cp 
          ON UPPER(TRIM(m.proveedor)) = UPPER(TRIM(cp.proveedor))
        WHERE m.id = %s
        """
        return pedidos_db.fetch_one(query, (merma_id,))

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
        
        historial_query = f"""
        INSERT INTO {self.HISTORY_TABLE} (merma_id, usuario, estado_anterior, estado_nuevo, comentario)
        VALUES (%s, %s, 'Ninguno', 'Pendiente', 'Ingreso inicial de merma registrado.')
        """
        pedidos_db.execute(historial_query, (merma_id, usuario))
        
        return self._get_merma_con_contacto(merma_id)

    # 🔥 NUEVO MÉTODO: Guarda múltiples mermas en un solo proceso
    def crear_en_lote(self, mermas: List[dict], usuario: str) -> bool:
        query = f"""
        INSERT INTO {self.TABLE_NAME} 
        (codigo, nombre_producto, cantidad, proveedor, novedad, comentario, estado, usuario, activo, cantidad_despachada)
        VALUES (%s, %s, %s, %s, %s, %s, 'Pendiente', %s, TRUE, %s)
        RETURNING id;
        """
        
        historial_query = f"""
        INSERT INTO {self.HISTORY_TABLE} (merma_id, usuario, estado_anterior, estado_nuevo, comentario)
        VALUES (%s, %s, 'Ninguno', 'Pendiente', 'Ingreso inicial de merma registrado en lote.')
        """
        
        for data in mermas:
            # Obtenemos el proveedor sugerido si no viene en la data
            proveedor = data.get("proveedor")
            if not proveedor:
                proveedor = self.get_proveedores(data["codigo"])
                
            params = (
                data["codigo"],
                data["nombre_producto"],
                data["cantidad"],
                proveedor,
                data["novedad"],
                data.get("comentario", ""),
                usuario,
                data.get("cantidad_despachada", 0.0)
            )
            merma_id = pedidos_db.execute(query, params)
            
            if merma_id:
                pedidos_db.execute(historial_query, (merma_id, usuario))
                
        return True

    def get_all(self) -> List[dict]:
        query = f"""
        SELECT m.*, cp.contacto AS contacto_proveedor
        FROM {self.TABLE_NAME} m
        LEFT JOIN ferrotienda.cronograma_pedidos cp 
          ON UPPER(TRIM(m.proveedor)) = UPPER(TRIM(cp.proveedor))
        ORDER BY m.fecha_registro DESC
        """
        return pedidos_db.fetch_all(query)

    def get_historial(self, merma_id: int) -> List[dict]:
        query = f"SELECT * FROM {self.HISTORY_TABLE} WHERE merma_id = %s ORDER BY fecha_registro ASC"
        return pedidos_db.fetch_all(query, (merma_id,))

    def update(self, merma_id: int, data: dict, usuario: str, rol: str) -> dict | None:
        print("\n" + "="*50)
        print(f"🚨 DEBUG ACTUALIZAR MERMA ID: {merma_id} 🚨")
        print(f"Datos crudos que llegaron al repositorio:")
        print(data)
        print("="*50 + "\n")

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
            comentario = COALESCE(%s, comentario),
            proveedor = COALESCE(%s, proveedor)
        WHERE id = %s
        RETURNING id;
        """
        pedidos_db.execute(
            query, 
            (
                data.get("cantidad"), 
                data.get("novedad"), 
                data.get("comentario"), 
                data.get("proveedor"),
                merma_id
            )
        )
        return self._get_merma_con_contacto(merma_id)

    def update_estado(self, merma_id: int, estado_nuevo: str, comentario: str, usuario: str, nota_credito: str = None) -> dict | None:
        if not comentario or comentario.strip() == "":
            raise Exception("El comentario justificativo es obligatorio para cambiar el estado.")
            
        if estado_nuevo.upper() == 'RESUELTO' and (not nota_credito or nota_credito.strip() == ""):
            raise Exception("Debe ingresar el número de Nota de Crédito o justificación para resolver la merma.")

        merma = pedidos_db.fetch_one(f"SELECT estado FROM {self.TABLE_NAME} WHERE id = %s", (merma_id,))
        if not merma:
            raise Exception("Merma no encontrada.")
        estado_anterior = merma["estado"]

        activo = False if estado_nuevo.upper() == 'RESUELTO' else True
        
        query_update = f"""
        UPDATE {self.TABLE_NAME}
        SET estado = %s, activo = %s
        WHERE id = %s
        RETURNING id;
        """
        pedidos_db.execute(query_update, (estado_nuevo, activo, merma_id))
        
        mensaje_chat = comentario
        if estado_nuevo.upper() == 'RESUELTO':
             mensaje_chat = f"PROCESO FINALIZADO. Justificación/Nota de Crédito: {nota_credito}. Comentario: {comentario}"

        query_historial = f"""
        INSERT INTO {self.HISTORY_TABLE} 
        (merma_id, usuario, estado_anterior, estado_nuevo, comentario, nota_credito)
        VALUES (%s, %s, %s, %s, %s, %s)
        """
        pedidos_db.execute(query_historial, (merma_id, usuario, estado_anterior, estado_nuevo, mensaje_chat, nota_credito))

        return self._get_merma_con_contacto(merma_id)

    def delete(self, merma_id: int, usuario: str, rol: str) -> bool:
        if rol == 'ADMIN':
            query = f"DELETE FROM {self.TABLE_NAME} WHERE id = %s RETURNING id"
            deleted_id = pedidos_db.execute(query, (merma_id,))
        else:
            query = f"DELETE FROM {self.TABLE_NAME} WHERE id = %s AND usuario = %s RETURNING id"
            deleted_id = pedidos_db.execute(query, (merma_id, usuario))
            
        return bool(deleted_id)
    
    def obtener_proveedores_por_producto(self, codigo_producto: str) -> list:
        query = """
        SELECT DISTINCT NombreProveedor 
        FROM v_kardexproductos 
        WHERE Codigo = %s 
        AND NombreProveedor IS NOT NULL 
        AND TRIM(NombreProveedor) <> '' 
        AND UPPER(TRIM(NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
        ORDER BY NombreProveedor ASC
        """
        resultados = db.fetch_all(query, (codigo_producto,))
        return [res['NombreProveedor'] for res in resultados] if resultados else []

    def obtener_costos_producto(self, codigo_producto: str, proveedor: str) -> list:
        query = """
            SELECT 
                CASE 
                    WHEN COALESCE(IVA, 0) > 0 THEN Costo * (1 + (COALESCE(IVA, 0) / 100.0))
                    ELSE Costo 
                END AS costo_calculado,
                MAX(Fecha) as ultima_fecha
            FROM v_kardexproductos
            WHERE Codigo = %s 
              AND UPPER(TRIM(NombreProveedor)) = UPPER(TRIM(%s))
              AND UPPER(TRIM(Documento)) = 'FACTURA DE COMPRA'
            GROUP BY 1
            ORDER BY ultima_fecha DESC;
        """
        resultados = db.fetch_all(query, (codigo_producto, proveedor))
        return [float(res['costo_calculado']) for res in resultados] if resultados else []

    def registrar_despacho(self, merma_id: int, data: dict, usuario: str) -> dict:
        merma = pedidos_db.fetch_one(f"SELECT cantidad, cantidad_despachada, nombre_producto, estado FROM {self.TABLE_NAME} WHERE id = %s", (merma_id,))
        if not merma:
            raise Exception("Merma no encontrada.")
            
        nueva_cantidad_despachada = float(merma["cantidad_despachada"]) + float(data["cantidad_retirada"])
        
        if nueva_cantidad_despachada > float(merma["cantidad"]):
            raise Exception("No puedes despachar más cantidad de la que existe en la merma.")

        query_despacho = """
        INSERT INTO ferrotienda.despacho_mermas 
        (merma_id, nota_credito, persona_retira, cedula_retira, cantidad_retirada, firma_base64, usuario_registra)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """
        pedidos_db.execute(query_despacho, (
            merma_id, 
            data["nota_credito"], 
            data["persona_retira"], 
            data["cedula_retira"], 
            data["cantidad_retirada"], 
            data["firma_base64"], 
            usuario
        ))

        query_update_merma = f"""
        UPDATE {self.TABLE_NAME}
        SET cantidad_despachada = %s,
            estado = 'Notificado'
        WHERE id = %s
        """
        pedidos_db.execute(query_update_merma, (nueva_cantidad_despachada, merma_id))

        fecha_hora_actual = datetime.datetime.now().strftime('%d/%m/%Y %H:%M')
        
        mensaje_chat = f"Hoy {fecha_hora_actual} se realiza el retiro de los productos: {merma['nombre_producto']} en estado: {merma['estado']} por parte de la persona: {data['persona_retira']} Nro de cedula: {data['cedula_retira']}."
        
        query_historial = f"""
        INSERT INTO {self.HISTORY_TABLE} 
        (merma_id, usuario, estado_anterior, estado_nuevo, comentario, nota_credito)
        VALUES (%s, %s, %s, 'Notificado', %s, %s)
        """
        pedidos_db.execute(query_historial, (merma_id, usuario, merma["estado"], mensaje_chat, data["nota_credito"]))

        return self._get_merma_con_contacto(merma_id)

    def obtener_proveedores_con_mermas_pendientes(self) -> list:
        query = """
        SELECT DISTINCT UPPER(TRIM(proveedor)) AS proveedor
        FROM ferrotienda.mermas 
        WHERE estado IN ('Pendiente', 'Notificado') 
          AND activo = TRUE 
          AND proveedor IS NOT NULL
        """
        resultados = pedidos_db.fetch_all(query)
        return [res['proveedor'] for res in resultados if res['proveedor']]