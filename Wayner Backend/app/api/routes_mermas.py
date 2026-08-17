from fastapi import APIRouter, HTTPException, Depends, Header
from typing import Optional, List
from app.repositories.merma_repository import MermaRepository
from app.schemas.merma import MermaCreate, MermaUpdate, MermaEstadoUpdate, DespachoCreate 

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

# 🔥 NUEVO ENDPOINT: Recibe una lista de mermas y las guarda en lote
@router.post("/lote")
async def crear_mermas_en_lote(mermas: List[MermaCreate], current_user: dict = Depends(get_current_user_headers)):
    usuario = current_user.get("username")
    try:
        # Convertimos la lista de esquemas a una lista de diccionarios
        mermas_data = [m.dict() for m in mermas]
        merma_repo.crear_en_lote(mermas_data, usuario)
        return {"success": True, "message": f"{len(mermas)} mermas creadas exitosamente."}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

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

@router.get("/proveedores-producto")
def obtener_proveedores_producto(codigo: str):
    try:
        repo = MermaRepository()
        proveedores = repo.obtener_proveedores_por_producto(codigo)
        return {"success": True, "data": proveedores}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/costos-historicos")
def obtener_costos_historicos(codigo: str, proveedor: str):
    try:
        repo = MermaRepository()
        costos = repo.obtener_costos_producto(codigo, proveedor)
        return {"success": True, "data": costos}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/{merma_id}/despacho")
async def registrar_despacho_merma(merma_id: int, despacho: DespachoCreate, current_user: dict = Depends(get_current_user_headers)):
    usuario = current_user.get("username")
    try:
        actualizada = merma_repo.registrar_despacho(merma_id, despacho.dict(), usuario)
        return {"success": True, "data": actualizada, "message": "Despacho registrado correctamente"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/proveedores-pendientes")
def obtener_proveedores_mermas_pendientes():
    try:
        repo = MermaRepository()
        proveedores = repo.obtener_proveedores_con_mermas_pendientes()
        return {"success": True, "data": proveedores}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))