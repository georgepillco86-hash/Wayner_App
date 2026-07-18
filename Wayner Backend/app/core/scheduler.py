import logging
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler

from app.core.database import db
# from app.services.notification_service import enviar_notificacion_push

logger = logging.getLogger(__name__)

def procesar_alertas_cronograma():
    logger.info("[SCHEDULER] Iniciando revisión del calendario de pedidos...")
    
    # ---------------------------------------------------------
    # LA REGLA: TODO OCURRE 2 DÍAS ANTES DE LA VISITA
    # ---------------------------------------------------------
    fecha_objetivo = (datetime.now() + timedelta(days=2)).date()
    
    # A. NOTIFICAR AL RESPONSABLE (Solo los que faltan por hacer)
    query_pendientes = """
        SELECT id, proveedor, usuario_responsable 
        FROM cronograma_visitas
        WHERE fecha_visita = %s AND estado = 'PENDIENTE'
    """
    visitas_pendientes = db.fetch_all(query_pendientes, (fecha_objetivo,))
    
    for visita in visitas_pendientes:
        usuario = visita["usuario_responsable"]
        proveedor = visita["proveedor"]
        
        # enviar_notificacion_push(
        #     usuario=usuario,
        #     titulo="🔔 Pedido Programado",
        #     mensaje=f"Recuerda: En 2 días debes realizar el pedido a {proveedor}.",
        #     data={"route": "/realizar_pedido_inteligente", "proveedor": proveedor}
        # )
        
        db.execute("UPDATE cronograma_visitas SET estado = 'NOTIFICADO' WHERE id = %s", (visita["id"],))

    # B. ALERTAR A LOS ADMINS (Resumen general de todos los responsables para ese día)
    query_todos = """
        SELECT proveedor, usuario_responsable, estado 
        FROM cronograma_visitas
        WHERE fecha_visita = %s
    """
    visitas_totales = db.fetch_all(query_todos, (fecha_objetivo,))
    
    if visitas_totales:
        admins = db.fetch_all("SELECT username FROM usuarios WHERE rol IN ('ADMIN', 'SUPERADMIN')")
        
        for visita in visitas_totales:
            estado_bd = visita["estado"].upper()
            responsable = visita["usuario_responsable"]
            proveedor = visita["proveedor"]
            
            # Formateamos el texto tal como lo solicitaste
            if estado_bd == 'REALIZADO':
                estado_texto = "Enviando ✅"
            else:
                estado_texto = "Pendiente ⏳"
                
            mensaje_admin = f"Responsable: {responsable} | Proveedor: {proveedor} | Estado: {estado_texto}"
            
            for admin in admins:
                # enviar_notificacion_push(
                #     usuario=admin["username"],
                #     titulo=f"📊 Status Pedidos para el {fecha_objetivo}",
                #     mensaje=mensaje_admin
                # )
                pass

def start_scheduler():
    scheduler = BackgroundScheduler()
    scheduler.add_job(procesar_alertas_cronograma, 'cron', hour=7, minute=0)
    scheduler.start()