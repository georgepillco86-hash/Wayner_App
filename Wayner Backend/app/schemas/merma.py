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

class MermaEstadoUpdate(BaseModel):
    estado: str  # Pendiente, Notificado, Resuelto
    comentario: str # Obligatorio para explicar el cambio
    nota_credito: Optional[str] = None # Requerido si el estado es 'Resuelto'