from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator


class PromocionCreate(BaseModel):
    codigo_barra: str = Field(..., min_length=1, max_length=50)
    nombre_producto: str = Field(..., min_length=1, max_length=255)

    precio_base: Decimal = Field(default=Decimal("0.00"), ge=0)
    precio_anterior: Decimal = Field(..., gt=0)
    precio_actual_prom: Decimal = Field(..., ge=0)

    encabezado: str | None = Field(default=None, max_length=255)
    mecanica: str | None = Field(default=None, max_length=255)

    fecha_inicio: date
    fecha_fin: date
    activa: bool = True

    @field_validator("fecha_fin")
    @classmethod
    def validar_fechas(cls, value: date, info):
        fecha_inicio = info.data.get("fecha_inicio")
        if fecha_inicio and value < fecha_inicio:
            raise ValueError("La fecha fin no puede ser menor que la fecha inicio")
        return value


class PromocionUpdate(BaseModel):
    nombre_producto: str | None = Field(default=None, max_length=255)

    precio_base: Decimal | None = Field(default=None, ge=0)
    precio_anterior: Decimal | None = Field(default=None, gt=0)
    precio_actual_prom: Decimal | None = Field(default=None, ge=0)

    encabezado: str | None = Field(default=None, max_length=255)
    mecanica: str | None = Field(default=None, max_length=255)

    fecha_inicio: date | None = None
    fecha_fin: date | None = None
    activa: bool | None = None


class PromocionResponse(BaseModel):
    id: int
    codigo_barra: str
    nombre_producto: str
    precio_base: Decimal
    precio_anterior: Decimal
    precio_actual_prom: Decimal
    ahorro: Decimal
    encabezado: str | None
    mecanica: str | None
    fecha_inicio: date
    fecha_fin: date
    activa: bool
    created_at: datetime
    updated_at: datetime | None