from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class MermaCreate(BaseModel):
    codigo: str
    nombre_producto: str
    cantidad: float
    novedad: str
    comentario: Optional[str] = ""

class MermaUpdate(BaseModel):
    cantidad: Optional[float] = None
    novedad: Optional[str] = None
    comentario: Optional[str] = None
    proveedor: Optional[str] = None      # 🔥 AÑADIDO: Permite recibir el proveedor limpio
    ultimo_costo: Optional[float] = None # 🔥 AÑADIDO: Permite recibir el costo seleccionado

class MermaEstadoUpdate(BaseModel):
    estado: str  # Pendiente, Notificado, Resuelto
    comentario: str # Obligatorio para explicar el cambio
    nota_credito: Optional[str] = None # Requerido si el estado es 'Resuelto'

class DespachoCreate(BaseModel):
    nota_credito: str
    persona_retira: str
    cedula_retira: str
    cantidad_retirada: float
    firma_base64: str
