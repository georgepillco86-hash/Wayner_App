from pydantic import BaseModel
from typing import List
from datetime import datetime

# ---> NUEVO: Sub-molde para validar los pares de fechas relacionales
class ParVisitaEntrega(BaseModel):
    visita: datetime
    entrega: datetime

class CronogramaCreate(BaseModel):
    proveedor: str
    frecuencia: str                     # <-- Cambiado de int a str ("Semanal", etc.)
    repetir_meses: int                  # <-- NUEVO: Duración del cronograma
    pares: List[ParVisitaEntrega]       # <-- NUEVO: Lista infinita de fechas
    usuarios_vinculados: List[str]

class NotificacionResponse(BaseModel):
    id: int
    titulo: str
    mensaje: str
    leido: bool
    fecha_creacion: datetime