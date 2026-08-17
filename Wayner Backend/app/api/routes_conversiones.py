from fastapi import APIRouter, Request
from pydantic import BaseModel
from typing import Optional, List
from app.services.conversiones_service import ConversionesService
from app.core.pedidos_database import pedidos_db # Para las consultas del RPA

router = APIRouter(prefix="/conversiones", tags=["conversiones"])
service = ConversionesService()

def ok(data, message="Operación exitosa"):
    return {"success": True, "message": message, "data": data}

class ConversionItemAdd(BaseModel):
    codigo_destino: str
    nombre_destino: str
    cantidad_destino: float

class OrdenTrabajoCreate(BaseModel):
    items: List[ConversionItemAdd]

# ==========================================
# 🔥 NUEVOS ESQUEMAS PARA MÚLTIPLES ORÍGENES
# ==========================================
class OrigenItem(BaseModel):
    codigo: str
    nombre: str
    cantidad: float

class ConversionEjecutar(BaseModel):
    codigo_destino: str
    nombre_destino: str
    cantidad_destino: float
    origenes: List[OrigenItem]  # Acepta el arreglo de múltiples productos de origen
    actividad_completa: bool
    porcentaje: int = 0
    fecha_estimada: Optional[str] = None
    usuario_ejecucion: str      # Recibe el usuario que firma la acción

@router.get("/")
@router.get("")
def listar_conversiones():
    return ok(service.listar_requerimientos(), "Requerimientos obtenidos exitosamente")

@router.post("/")
@router.post("")
def crear_orden_trabajo(payload: OrdenTrabajoCreate, request: Request):
    usuario = request.headers.get("x-user-name", "Desconocido")
    data = service.crear_orden_trabajo([item.dict() for item in payload.items], usuario)
    return ok(data, "Orden de trabajo creada exitosamente")

@router.patch("/{req_id}/ejecutar")
def ejecutar_conversion(req_id: int, payload: ConversionEjecutar, request: Request):
    usuario = request.headers.get("x-user-name", "Desconocido")
    data = service.ejecutar_conversion(req_id, payload.dict(), usuario)
    return ok(data, "Conversión procesada exitosamente")

# ==========================================
# 🔥 RUTAS EXCLUSIVAS PARA EL BOT RPA 🔥
# ==========================================
@router.get("/rpa/pendientes")
def rpa_pendientes():
    # 🔥 AÑADIDO: codigo_origen y cantidad_origen para dar soporte a tareas antiguas
    query = """
    SELECT id, orden_trabajo, origenes_json, 
           codigo_origen, cantidad_origen,
           codigo_destino, nombre_destino, cantidad_destino, usuario_ejecucion
    FROM ferrotienda.conversiones 
    WHERE estado = 'PESADO' AND procesado_rpa = FALSE
    """
    data = pedidos_db.fetch_all(query)
    return ok(data, "Tareas RPA enviadas")

class RPACompletar(BaseModel):
    req_id: int
    estado: str

@router.post("/rpa/completar")
def rpa_completar(payload: RPACompletar):
    query = "UPDATE ferrotienda.conversiones SET estado = %s, procesado_rpa = TRUE WHERE id = %s"
    pedidos_db.execute(query, (payload.estado, payload.req_id))
    return ok(None, "RPA actualizado")