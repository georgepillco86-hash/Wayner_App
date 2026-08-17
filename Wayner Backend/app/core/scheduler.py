import logging
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler

from app.core.database import db
# Importamos la base de datos de pedidos/promociones
from app.core.pedidos_database import pedidos_db
from app.repositories.cronograma_repository import CronogramaRepository 
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
        SELECT id, proveedor, usuarios_vinculados 
        FROM ferrotienda.cronograma_visitas
        WHERE DATE(fecha_programada) = %s AND estado = 'Pendiente'
    """
    visitas_pendientes = db.fetch_all(query_pendientes, (fecha_objetivo,))
    
    if visitas_pendientes:
        for visita in visitas_pendientes:
            proveedor = visita["proveedor"]
            usuarios = visita["usuarios_vinculados"] 
            
            # enviar_notificacion_push(
            #     usuario=usuarios,
            #     titulo="🔔 Pedido Programado",
            #     mensaje=f"Recuerda: En 2 días debes realizar el pedido a {proveedor}.",
            #     data={"route": "/realizar_pedido_inteligente", "proveedor": proveedor}
            # )
            
            db.execute("UPDATE ferrotienda.cronograma_visitas SET estado = 'NOTIFICADO' WHERE id = %s", (visita["id"],))

    # B. ALERTAR A LOS ADMINS (Resumen general de todos los responsables para ese día)
    query_todos = """
        SELECT proveedor, usuarios_vinculados, estado 
        FROM ferrotienda.cronograma_visitas
        WHERE DATE(fecha_programada) = %s
    """
    visitas_totales = db.fetch_all(query_todos, (fecha_objetivo,))
    
    if visitas_totales:
        admins = db.fetch_all("SELECT username FROM usuarios WHERE rol IN ('ADMIN', 'SUPERADMIN')")
        
        for visita in visitas_totales:
            estado_bd = visita["estado"].upper()
            responsable = visita["usuarios_vinculados"]
            proveedor = visita["proveedor"]
            
            # Formateamos el texto tal como lo solicitaste
            if estado_bd == 'REALIZADO':
                estado_texto = "Enviando ✅"
            else:
                estado_texto = "Pendiente ⏳"
                
            mensaje_admin = f"Responsable: {responsable} | Proveedor: {proveedor} | Estado: {estado_texto}"
            
            if admins:
                for admin in admins:
                    # enviar_notificacion_push(
                    #     usuario=admin["username"],
                    #     titulo=f"📊 Status Pedidos para el {fecha_objetivo}",
                    #     mensaje=mensaje_admin
                    # )
                    pass

def procesar_renovacion_cronogramas():
    """Ejecuta la ventana móvil: extiende cronogramas que están a punto de expirar."""
    logger.info("[SCHEDULER] Verificando cronogramas por expirar (Auto-renovación)...")
    try:
        repo = CronogramaRepository()
        repo.auto_renovar_cronogramas()
        logger.info("[SCHEDULER] Renovación de cronogramas completada exitosamente.")
    except Exception as e:
        logger.error(f"[SCHEDULER] Error crítico al auto-renovar cronogramas: {e}")

# 🔥 NUEVO: Cron Job para revertir promociones vencidas automáticamente
def procesar_promociones_vencidas():
    logger.info("[SCHEDULER] Verificando promociones vencidas para revertir precios...")
    try:
        # Buscar promociones activas cuya fecha de fin ya pasó (hasta ayer)
        query_vencidas = """
            SELECT id, precio_base, codigo_barra 
            FROM promociones 
            WHERE activa = TRUE AND fecha_fin < CURRENT_DATE
        """
        vencidas = pedidos_db.fetch_all(query_vencidas)
        
        if vencidas:
            for promo in vencidas:
                promo_id = promo["id"]
                precio_base = promo["precio_base"]
                codigo = promo["codigo_barra"]
                
                logger.info(f"[SCHEDULER] Desactivando promo vencida (ID: {promo_id}, Código: {codigo})...")
                
                # 1. Apagar la promoción en la base de datos
                pedidos_db.execute(
                    "UPDATE promociones SET activa = FALSE WHERE id = %s", 
                    (promo_id,)
                )
                
                # 2. Enviar la orden al RPA para revertir el precio en BITS
                pedidos_db.execute(
                    """
                    INSERT INTO rpa_tareas_promociones (
                        promocion_id, tipo_tarea, precio_objetivo, estado
                    ) VALUES (%s, %s, %s, %s)
                    """,
                    (promo_id, 'REVERTIR_PROMO', precio_base, 'PENDIENTE')
                )
                
            logger.info(f"[SCHEDULER] Se enviaron a revertir {len(vencidas)} promociones vencidas al RPA.")
        else:
            logger.info("[SCHEDULER] No hay promociones vencidas para revertir hoy.")
            
    except Exception as e:
        logger.error(f"[SCHEDULER] Error al procesar promociones vencidas: {e}")

def start_scheduler():
    scheduler = BackgroundScheduler()
    
    # 1. Alertas de pedidos (Todos los días a las 07:00 AM)
    scheduler.add_job(procesar_alertas_cronograma, 'cron', hour=7, minute=0)
    
    # 2. Renovación de base de datos (Todos los días a las 01:00 AM)
    scheduler.add_job(procesar_renovacion_cronogramas, 'cron', hour=1, minute=0)
    
    # 🔥 3. NUEVO: Revertir promociones caducadas (Todos los días a las 00:01 AM)
    scheduler.add_job(procesar_promociones_vencidas, 'cron', hour=0, minute=1)
    
    scheduler.start()