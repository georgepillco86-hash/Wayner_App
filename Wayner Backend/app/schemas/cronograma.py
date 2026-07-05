from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class CronogramaCreate(BaseModel):
    proveedor: str
    frecuencia: int
    fecha_inicio: datetime
    usuarios_vinculados: List[str]

class NotificacionResponse(BaseModel):
    id: int
    titulo: str
    mensaje: str
    leido: bool
    fecha_creacion: datetime