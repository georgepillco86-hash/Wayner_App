from __future__ import annotations

from typing import ClassVar

from pydantic import BaseModel, Field, field_validator


ROLES_PERMITIDOS = {"ADMIN", "USER", "BODEGUERO", "ESCANER", "TRABAJADOR"}


class UsuarioCreate(BaseModel):
    nombre_usuario: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=3, max_length=100)
    nombre_completo: str | None = Field(default=None, max_length=120)
    rol: str = Field(..., min_length=3, max_length=30)
    activo: bool = True

    _roles_permitidos: ClassVar[set[str]] = ROLES_PERMITIDOS

    @field_validator("rol")
    @classmethod
    def validar_rol(cls, value: str) -> str:
        rol = value.strip().upper()
        if rol not in cls._roles_permitidos:
            raise ValueError(
                f"Rol no permitido. Roles válidos: {', '.join(sorted(cls._roles_permitidos))}"
            )
        return rol


class UsuarioUpdate(BaseModel):
    nombre_usuario: str | None = Field(default=None, min_length=3, max_length=50)
    nombre_completo: str | None = Field(default=None, max_length=120)
    rol: str | None = Field(default=None, min_length=3, max_length=30)
    activo: bool | None = None

    _roles_permitidos: ClassVar[set[str]] = ROLES_PERMITIDOS

    @field_validator("rol")
    @classmethod
    def validar_rol(cls, value: str | None) -> str | None:
        if value is None:
            return value

        rol = value.strip().upper()
        if rol not in cls._roles_permitidos:
            raise ValueError(
                f"Rol no permitido. Roles válidos: {', '.join(sorted(cls._roles_permitidos))}"
            )
        return rol


class UsuarioPasswordUpdate(BaseModel):
    password: str = Field(..., min_length=3, max_length=100)