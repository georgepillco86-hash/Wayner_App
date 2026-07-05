import asyncio
import logging
import json
from datetime import datetime, timedelta
from app.core.pedidos_database import pedidos_db 

logger = logging.getLogger("uvicorn.error")

class NotificationService:
    @classmethod
    async def generar_alertas_diarias(cls):
        try:
            # Calcular la fecha exacta de mañana (solo el día)
            manana = (datetime.now() + timedelta(days=1)).date()
            
            # NUEVO: Usamos DATE(fecha_programada) para que coincida sin importar la hora
            query_visitas = """
                SELECT id, proveedor, usuarios_vinculados, fecha_programada
                FROM ferrotienda.cronograma_visitas 
                WHERE DATE(fecha_programada) = %s AND estado = 'Pendiente'
            """
            visitas_manana = pedidos_db.fetch_all(query_visitas, (manana,))
            
            for visita in visitas_manana:
                proveedor = visita["proveedor"]
                usuarios = json.loads(visita["usuarios_vinculados"])
                hora_exacta = visita["fecha_programada"].strftime("%H:%M") # Extraemos la hora para el mensaje
                
                # Crear alerta para cada usuario
                for usuario in usuarios:
                    query_notif = """
                        INSERT INTO ferrotienda.notificaciones (usuario, titulo, mensaje)
                        VALUES (%s, %s, %s)
                    """
                    titulo = "Pedido Programado: Mañana"
                    mensaje = f"Recuerda que mañana a las {hora_exacta} está programada la visita/pedido para: {proveedor}."
                    pedidos_db.execute(query_notif, (usuario, titulo, mensaje))
                
                # Marcar como notificada
                pedidos_db.execute("UPDATE ferrotienda.cronograma_visitas SET estado = 'Notificado' WHERE id = %s", (visita["id"],))
                
            if visitas_manana:
                logger.info(f"✅ Se generaron alertas para {len(visitas_manana)} pedidos programados para mañana.")
                
        except Exception as e:
            logger.error(f"❌ Error en el motor de alertas: {str(e)}")

    @classmethod
    async def iniciar_vigilante_alertas(cls):
        while True:
            await cls.generar_alertas_diarias()
            await asyncio.sleep(3600) # Revisa cada hora