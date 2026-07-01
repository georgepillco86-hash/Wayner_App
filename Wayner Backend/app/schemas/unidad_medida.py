from __future__ import annotations

from pydantic import BaseModel, Field, field_validator


class UnidadMedidaCreate(BaseModel):
    nombre: str = Field(..., min_length=1, max_length=50)

    @field_validator("nombre")
    @classmethod
    def clean_nombre(cls, value: str) -> str:
        return value.strip().upper()


class UnidadMedidaUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=1, max_length=50)
    activo: bool | None = None

    @field_validator("nombre")
    @classmethod
    def clean_nombre(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip().upper()