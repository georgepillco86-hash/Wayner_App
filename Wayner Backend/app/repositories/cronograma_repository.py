import json
import datetime
from typing import List
from app.core.pedidos_database import pedidos_db 

class CronogramaRepository:

    def eliminar_cronograma_proveedor(self, proveedor: str):
        """Elimina el cronograma anterior de un proveedor para permitir la edición."""
        query = "DELETE FROM ferrotienda.cronograma_visitas WHERE proveedor = %s"
        pedidos_db.execute(query, (proveedor,))

    def crear_cronograma(self, data: dict) -> bool:
        proveedor = data["proveedor"]
        frecuencia = data["frecuencia"] # "Semanal", "Quincenal", "Mensual"
        pares = data["pares"] # [{'visita': datetime, 'entrega': datetime}]
        repetir_meses = data["repetir_meses"] # 1, 6, 12, 60
        usuarios = json.dumps(data["usuarios_vinculados"])
        
        # 1. ELIMINACIÓN INTELIGENTE (Editar): Borramos el historial futuro de este proveedor
        self.eliminar_cronograma_proveedor(proveedor)
        
        # 2. CONFIGURACIÓN DE LA MATEMÁTICA DE SALTOS
        if frecuencia == 'Semanal':
            semanas_salto = 1
        elif frecuencia == 'Quincenal':
            semanas_salto = 2
        elif frecuencia == 'Mensual':
            semanas_salto = 4
        else:
            semanas_salto = 1

        # Calculamos cuántas semanas en total dura este cronograma
        # 1 mes = 4 semanas de duración
        total_semanas_duracion = repetir_meses * 4 
        
        # 3. CLONACIÓN DE LOS PARES
        fechas_a_insertar = []
        for par in pares:
            # En FastAPI/Pydantic estos ya vienen como objetos datetime si el schema está bien, 
            # pero por seguridad los parseamos si vienen como string ISO:
            visita_str = par['visita'].replace('Z', '') if isinstance(par['visita'], str) else par['visita']
            entrega_str = par['entrega'].replace('Z', '') if isinstance(par['entrega'], str) else par['entrega']
            
            visita_base = datetime.datetime.fromisoformat(str(visita_str)) if isinstance(visita_str, str) else visita_str
            entrega_base = datetime.datetime.fromisoformat(str(entrega_str)) if isinstance(entrega_str, str) else entrega_str
            
            semanas_avanzadas = 0
            while semanas_avanzadas < total_semanas_duracion:
                # Proyectar al futuro manteniendo el mismo día de la semana y la misma hora
                visita_futura = visita_base + datetime.timedelta(weeks=semanas_avanzadas)
                entrega_futura = entrega_base + datetime.timedelta(weeks=semanas_avanzadas)
                fechas_a_insertar.append((visita_futura, entrega_futura))
                
                # Avanzamos según la frecuencia
                semanas_avanzadas += semanas_salto
                
        # 4. GUARDADO EN LA BASE DE DATOS (Usando ÚNICAMENTE cronograma_visitas)
        for visita_dt, entrega_dt in fechas_a_insertar:
            query_visita = """
                INSERT INTO ferrotienda.cronograma_visitas 
                (proveedor, fecha_programada, fecha_entrega, estado, usuarios_vinculados)
                VALUES (%s, %s, %s, %s, %s);
            """
            pedidos_db.execute(query_visita, (proveedor, visita_dt, entrega_dt, 'Pendiente', usuarios))
            
        return True

    def obtener_visitas_mes(self, mes: int, anio: int) -> List[dict]:
        query = """
            SELECT id, proveedor, fecha_programada, fecha_entrega, estado, usuarios_vinculados
            FROM ferrotienda.cronograma_visitas
            WHERE EXTRACT(MONTH FROM fecha_programada) = %s 
            AND EXTRACT(YEAR FROM fecha_programada) = %s
            ORDER BY fecha_programada ASC
        """
        return pedidos_db.fetch_all(query, (mes, anio))

    def obtener_notificaciones(self, usuario: str) -> List[dict]:
        query = "SELECT * FROM ferrotienda.notificaciones WHERE usuario = %s ORDER BY fecha_creacion DESC LIMIT 20"
        return pedidos_db.fetch_all(query, (usuario,))
        
    def marcar_notificacion_leida(self, notificacion_id: int):
        pedidos_db.execute("UPDATE ferrotienda.notificaciones SET leido = TRUE WHERE id = %s", (notificacion_id,))

    def obtener_lead_time_proveedor(self, nombre_proveedor: str) -> int | None:
        query = """
            SELECT (fecha_entrega::date - fecha_programada::date) as lead_time
            FROM ferrotienda.cronograma_visitas
            WHERE proveedor = %s AND fecha_entrega IS NOT NULL
            ORDER BY fecha_programada DESC
            LIMIT 1;
        """
        resultados = pedidos_db.fetch_all(query, (nombre_proveedor,))
        if resultados and len(resultados) > 0:
            lead_time = resultados[0].get('lead_time')
            if lead_time is not None:
                return max(0, int(lead_time))
        return None
    
    def marcar_visita_realizada(self, usuario: str, proveedor: str) -> None:
        """
        Cambia el estado a 'REALIZADO' solo si el pedido se hace ANTES o el mismo día de la visita.
        """
        query = """
        UPDATE cronograma_visitas
        SET estado = 'REALIZADO'
        WHERE LOWER(proveedor) = LOWER(%s)
          AND LOWER(usuario_responsable) = LOWER(%s)
          AND estado IN ('PENDIENTE', 'NOTIFICADO')
          AND fecha_visita >= CURDATE() 
          AND fecha_visita <= DATE_ADD(CURDATE(), INTERVAL 5 DAY)
        """
        from app.core.database import db
        db.execute(query, (proveedor, usuario))