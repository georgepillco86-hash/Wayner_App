from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey
from app.core.database import Base # Ajusta si tu 'Base' está en otro lado dentro de core
import datetime

# ==========================================
# MODELO SQLALCHEMY
# ==========================================
class RpaTareaPromocion(Base):
    __tablename__ = "rpa_tareas_promociones"
    __table_args__ = {"schema": "ferrotienda"} # Apuntando a tu esquema

    id = Column(Integer, primary_key=True, index=True)
    promocion_id = Column(Integer, ForeignKey("ferrotienda.promociones.id", ondelete="CASCADE"), nullable=False)
    tipo_tarea = Column(String(50), nullable=False)
    precio_objetivo = Column(Numeric(10, 4), nullable=False)
    estado = Column(String(50), default="PENDIENTE")
    mensaje_rpa = Column(String)
    intentos = Column(Integer, default=0)
    fecha_creacion = Column(DateTime, default=datetime.datetime.utcnow)
    fecha_procesamiento = Column(DateTime)
    fecha_completado = Column(DateTime)

# Aquí abajo podrías agregar métodos futuros como crear_tarea_rpa(), etc.