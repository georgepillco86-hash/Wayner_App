from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import List
import time

# 🔥 Importamos tu conector directo a la BD
from app.core.pedidos_database import pedidos_db

router = APIRouter(prefix="/api/promociones/rpa", tags=["RPA Promociones"])

# ==========================================
# SCHEMAS
# ==========================================
class RpaCompletarRequest(BaseModel):
    promocion_id: int
    estado: str
    tipo_tarea: str

# ==========================================
# TAREAS EN SEGUNDO PLANO
# ==========================================
def borrar_promocion_diferida(promocion_id: int):
    """
    Espera 5 segundos antes de hacer el DELETE real. 
    Esto le da tiempo a Flutter de leer que el estado es 'COMPLETADO' 
    antes de que el ON DELETE CASCADE destruya el registro de la tarea.
    """
    time.sleep(5)
    query_eliminar = "DELETE FROM promociones WHERE id = %s"
    pedidos_db.execute(query_eliminar, (promocion_id,))


# ==========================================
# ENDPOINTS
# ==========================================

@router.get("/pendientes")
def obtener_tareas_pendientes():
    """
    Entrega al bot RPA las tareas que debe procesar (Aplicar o Revertir precios).
    Solo entrega las que están en estado PENDIENTE.
    """
    # 1. Hacemos un JOIN directo en SQL para traer la tarea y los datos del producto a la vez
    query = """
        SELECT r.id as tarea_id, r.promocion_id, r.tipo_tarea, 
               p.codigo_barra, p.nombre_producto, p.precio_base, p.precio_actual_prom
        FROM rpa_tareas_promociones r
        JOIN promociones p ON r.promocion_id = p.id
        WHERE r.estado = 'PENDIENTE'
    """
    tareas = pedidos_db.fetch_all(query)

    resultado = []
    for tarea in tareas:
        # 2. Marcamos la tarea como PROCESANDO para que otro bot no la tome
        query_update = """
            UPDATE rpa_tareas_promociones
            SET estado = 'PROCESANDO', fecha_procesamiento = CURRENT_TIMESTAMP
            WHERE id = %s
        """
        pedidos_db.execute(query_update, (tarea["tarea_id"],))
        
        # 3. Preparamos el resultado
        resultado.append({
            "id": tarea["promocion_id"],
            "codigo_barra": tarea["codigo_barra"],
            "nombre_producto": tarea["nombre_producto"],
            "precio_base": float(tarea["precio_base"]),
            "precio_actual_prom": float(tarea["precio_actual_prom"]),
            "tipo_tarea": tarea["tipo_tarea"]
        })
            
    return {"data": resultado}


@router.post("/completar")
def completar_tarea(payload: RpaCompletarRequest, bg_tasks: BackgroundTasks):
    """
    El bot RPA llama a este endpoint cuando termina de digitar en BITS o si encuentra un error.
    Agregamos BackgroundTasks para no bloquear a Flutter al eliminar.
    """
    # 1. Verificamos que la tarea exista y esté en estado PROCESANDO
    query_check = """
        SELECT id 
        FROM rpa_tareas_promociones
        WHERE promocion_id = %s 
          AND tipo_tarea = %s 
          AND estado = 'PROCESANDO'
        LIMIT 1
    """
    tarea = pedidos_db.fetch_one(query_check, (payload.promocion_id, payload.tipo_tarea))

    if not tarea:
        raise HTTPException(status_code=404, detail="Tarea no encontrada o ya fue procesada.")

    tarea_id = tarea["id"]
    estado_final = ""

    # 2. Evaluamos la respuesta del RPA
    if payload.estado in ["EXITO_CAMBIO_REALIZADO", "EXITO_SIN_CAMBIOS"]:
        estado_final = 'COMPLETADO'
        
        # 🔥 MANEJO DE LAS DOS ACCIONES: ELIMINAR (Manual) y REVERTIR (Automático por fecha)
        if payload.tipo_tarea == 'ELIMINAR':
            # Delegamos el borrado a un hilo secundario que esperará 5 segundos.
            bg_tasks.add_task(borrar_promocion_diferida, payload.promocion_id)
            
        elif payload.tipo_tarea == 'REVERTIR_PROMO':
            # Solo la apaga porque su fecha expiró (se mantiene en el historial)
            query_desactivar = "UPDATE promociones SET activa = FALSE WHERE id = %s"
            pedidos_db.execute(query_desactivar, (payload.promocion_id,))
                
    else:
        # El RPA reportó un error 
        estado_final = 'ERROR'

    # 3. Actualizamos el registro de la tarea con el resultado final (Flutter leerá esto de inmediato)
    query_update_tarea = """
        UPDATE rpa_tareas_promociones
        SET estado = %s, 
            mensaje_rpa = %s, 
            fecha_completado = CURRENT_TIMESTAMP
        WHERE id = %s
    """
    pedidos_db.execute(query_update_tarea, (estado_final, payload.estado, tarea_id))
    
    return {"message": "Estado actualizado correctamente", "estado_final": estado_final}

@router.get("/estado/{promocion_id}")
def verificar_estado_tarea(promocion_id: int):
    """Flutter llama aquí cada 2 segundos para ver si el RPA ya terminó."""
    query = """
        SELECT estado, mensaje_rpa 
        FROM rpa_tareas_promociones 
        WHERE promocion_id = %s 
        ORDER BY id DESC LIMIT 1
    """
    tarea = pedidos_db.fetch_one(query, (promocion_id,))
    
    if not tarea:
        return {"estado": "NO_ENCONTRADA"}
        
    return {
        "estado": tarea["estado"], 
        "mensaje": tarea["mensaje_rpa"]
    }