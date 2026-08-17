from __future__ import annotations
from typing import Any
from app.core.pedidos_database import pedidos_db

class ConversionesRepository:
    def get_next_orden_trabajo(self) -> str:
        query = "SELECT COUNT(DISTINCT orden_trabajo) as total FROM ferrotienda.conversiones WHERE orden_trabajo IS NOT NULL"
        row = pedidos_db.fetch_one(query)
        total = row["total"] if row and row["total"] else 0
        return f"001-001-{(total + 1):06d}"

    def listar_requerimientos(self) -> list[dict[str, Any]]:
        query = """
        SELECT 
            c.id, c.orden_trabajo, c.descripcion_tarea, c.estado, 
            TO_CHAR(c.fecha_creacion, 'YYYY-MM-DD HH24:MI') as fecha_creacion, 
            TO_CHAR(c.fecha_actualizacion, 'YYYY-MM-DD HH24:MI') as fecha_actualizacion,
            c.porcentaje_avance, c.fecha_estimada_fin,
            c.codigo_origen, c.nombre_origen, c.cantidad_origen,
            c.origenes_json, c.usuario_ejecucion,
            c.codigo_destino, c.nombre_destino, c.cantidad_destino, c.procesado_rpa,
            (SELECT usuario FROM ferrotienda.conversiones_historial WHERE conversion_id = c.id ORDER BY id ASC LIMIT 1) as usuario_creacion,
            (SELECT usuario FROM ferrotienda.conversiones_historial WHERE conversion_id = c.id ORDER BY id DESC LIMIT 1) as usuario_actualizacion
        FROM ferrotienda.conversiones c
        ORDER BY CASE WHEN c.estado = 'PENDIENTE' THEN 1 ELSE 2 END ASC, c.fecha_actualizacion DESC
        """
        return pedidos_db.fetch_all(query)

    def get_requerimiento(self, req_id: int) -> dict[str, Any] | None:
        query = "SELECT * FROM ferrotienda.conversiones WHERE id = %s"
        return pedidos_db.fetch_one(query, (req_id,))

    def crear_requerimiento_item(self, orden: str, cod_destino: str, nom_destino: str, cant_destino: float) -> int:
        desc = f"Conversión a {nom_destino}"
        query = """
        INSERT INTO ferrotienda.conversiones 
        (orden_trabajo, descripcion_tarea, estado, codigo_destino, nombre_destino, cantidad_destino) 
        VALUES (%s, %s, 'PENDIENTE', %s, %s, %s) 
        RETURNING id
        """
        return pedidos_db.execute(query, (orden, desc, cod_destino, nom_destino, cant_destino))

    def ejecutar_conversion(self, req_id: int, datos: dict) -> None:
        # 🔥 AQUÍ ESTABA EL BUG: Simplemente leemos el JSON que el Service ya preparó
        origenes_str = datos.get('origenes_json', '[]')
        
        query = """
        UPDATE ferrotienda.conversiones
        SET porcentaje_avance = %s,
            fecha_estimada_fin = %s,
            origenes_json = %s,
            cantidad_destino = %s,
            estado = %s,
            usuario_ejecucion = %s,
            fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE id = %s
        """
        pedidos_db.execute(query, (
            datos.get('porcentaje_avance', 0),
            datos.get('fecha_estimada_fin'),
            origenes_str,
            datos.get('cantidad_destino'),
            datos.get('estado', 'PENDIENTE'),
            datos.get('usuario_ejecucion'),
            req_id
        ))

    def registrar_historial(self, req_id: int, usuario: str, accion: str) -> None:
        query = "INSERT INTO ferrotienda.conversiones_historial (conversion_id, usuario, accion) VALUES (%s, %s, %s)"
        pedidos_db.execute(query, (req_id, usuario, accion))