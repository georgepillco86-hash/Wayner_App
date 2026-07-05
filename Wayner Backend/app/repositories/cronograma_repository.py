import json
from datetime import timedelta, datetime
from typing import List
from app.core.pedidos_database import pedidos_db 

class CronogramaRepository:
    def crear_cronograma(self, data: dict) -> bool:
        proveedor = data["proveedor"]
        frecuencia = data["frecuencia"]
        fecha_inicio = data["fecha_inicio"] # Ahora es un objeto datetime completo
        usuarios = json.dumps(data["usuarios_vinculados"])
        
        # 1. Guardar la regla maestra
        query_regla = """
            INSERT INTO ferrotienda.cronograma_pedidos 
            (proveedor, frecuencia, fecha_inicio, usuarios_vinculados)
            VALUES (%s, %s, %s, %s) RETURNING id;
        """
        cronograma_id = pedidos_db.execute(query_regla, (proveedor, frecuencia, fecha_inicio, usuarios))
        
        # 2. Calcular automáticamente las fechas (manteniendo la hora exacta)
        fechas_calculadas = [fecha_inicio]
        
        if frecuencia == 2:
            # Cada 15 días, a la misma hora
            fechas_calculadas.append(fecha_inicio + timedelta(days=15))
        elif frecuencia == 4:
            # 1 cada semana, a la misma hora
            fechas_calculadas.append(fecha_inicio + timedelta(days=7))
            fechas_calculadas.append(fecha_inicio + timedelta(days=14))
            fechas_calculadas.append(fecha_inicio + timedelta(days=21))
            
        # 3. Guardar las visitas programadas
        for fecha in fechas_calculadas:
            query_visita = """
                INSERT INTO ferrotienda.cronograma_visitas 
                (cronograma_id, proveedor, fecha_programada, usuarios_vinculados)
                VALUES (%s, %s, %s, %s);
            """
            pedidos_db.execute(query_visita, (cronograma_id, proveedor, fecha, usuarios))
            
        return True

    def obtener_visitas_mes(self, mes: int, anio: int) -> List[dict]:
        # El EXTRACT funciona perfecto con TIMESTAMP
        query = """
            SELECT id, proveedor, fecha_programada, estado, usuarios_vinculados
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