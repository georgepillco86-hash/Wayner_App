from fastapi import APIRouter, Header, HTTPException
from app.repositories.cronograma_repository import CronogramaRepository
from app.schemas.cronograma import CronogramaCreate
from typing import Optional

router = APIRouter()
crono_repo = CronogramaRepository()

@router.post("/")
async def crear_programacion(crono: CronogramaCreate):
    crono_repo.crear_cronograma(crono.dict())
    return {"success": True, "message": "Cronograma y visitas generadas exitosamente."}

@router.get("/calendario/{anio}/{mes}")
async def ver_calendario(anio: int, mes: int):
    return crono_repo.obtener_visitas_mes(mes, anio)

@router.get("/notificaciones")
async def mis_notificaciones(x_usuario: Optional[str] = Header(None)):
    if not x_usuario:
        raise HTTPException(status_code=400, detail="Usuario no identificado")
    return crono_repo.obtener_notificaciones(x_usuario)

@router.patch("/notificaciones/{id_notif}/leer")
async def leer_notificacion(id_notif: int):
    crono_repo.marcar_notificacion_leida(id_notif)
    return {"success": True}