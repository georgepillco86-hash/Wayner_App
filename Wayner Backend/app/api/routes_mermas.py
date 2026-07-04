from fastapi import APIRouter, HTTPException, Depends, Header
from app.repositories.merma_repository import MermaRepository
from app.schemas.merma import MermaCreate, MermaUpdate, MermaEstadoUpdate
from typing import Optional

router = APIRouter()
merma_repo = MermaRepository()

async def get_current_user_headers(
    x_usuario: Optional[str] = Header("Desconocido"), 
    x_rol: Optional[str] = Header("")
):
    return {"username": x_usuario, "rol": x_rol}

@router.get("/")
async def listar_mermas():
    return merma_repo.get_all()

@router.get("/{merma_id}/historial")
async def obtener_historial(merma_id: int):
    return merma_repo.get_historial(merma_id)

@router.post("/")
async def crear_merma(merma: MermaCreate, current_user: dict = Depends(get_current_user_headers)):
    usuario = current_user.get("username")
    nueva_merma = merma_repo.create(merma.dict(), usuario)
    return {"success": True, "data": nueva_merma}

@router.put("/{merma_id}")
async def actualizar_merma(merma_id: int, merma: MermaUpdate, current_user: dict = Depends(get_current_user_headers)):
    usuario = current_user.get("username")
    rol = current_user.get("rol", "").upper()
    try:
        actualizada = merma_repo.update(merma_id, merma.dict(exclude_unset=True), usuario, rol)
        return {"success": True, "data": actualizada}
    except Exception as e:
        raise HTTPException(status_code=403, detail=str(e))

@router.patch("/{merma_id}/estado")
async def cambiar_estado(merma_id: int, estado_data: MermaEstadoUpdate, current_user: dict = Depends(get_current_user_headers)):
    usuario = current_user.get("username")
    rol = current_user.get("rol", "").upper()
    
    if rol not in ["ADMIN", "BODEGUERO"]:
        raise HTTPException(status_code=403, detail="No tienes permisos para dar seguimiento a mermas.")
    
    try:
        actualizada = merma_repo.update_estado(
            merma_id=merma_id, 
            estado_nuevo=estado_data.estado, 
            comentario=estado_data.comentario, 
            usuario=usuario,
            nota_credito=estado_data.nota_credito
        )
        return {"success": True, "data": actualizada}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.delete("/{merma_id}")
async def eliminar_merma(merma_id: int, current_user: dict = Depends(get_current_user_headers)):
    usuario = current_user.get("username")
    rol = current_user.get("rol", "").upper()
    
    eliminado = merma_repo.delete(merma_id, usuario, rol)
    if not eliminado:
        raise HTTPException(status_code=400, detail="No se pudo eliminar. Solo el creador original o un ADMIN puede hacerlo.")
    return {"success": True, "message": "Merma eliminada"}