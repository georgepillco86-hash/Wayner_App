from __future__ import annotations

from typing import ClassVar

from pydantic import BaseModel, Field, field_validator


ROLES_PERMITIDOS = {"ADMIN", "USER", "BODEGUERO", "ESCANER", "TRABAJADOR"}


class UsuarioCreate(BaseModel):
    nombre_usuario: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=3, max_length=100)
    nombre_completo: str | None = Field(default=None, max_length=120)
    rol: str = Field(..., min_length=3, max_length=30)
    
    # 🔥 NUEVO CAMPO: celular
    celular: str | None = Field(default=None, max_length=15)
    
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

    # 🔥 VALIDADOR: Asegura que sean 10 dígitos
    @field_validator("celular")
    @classmethod
    def validar_celular(cls, value: str | None) -> str | None:
        if not value or value.strip() == "":
            return None
        # Limpiamos espacios o guiones por si el usuario los tecleó
        cel = value.replace(" ", "").replace("-", "")
        if not cel.isdigit() or len(cel) != 10:
            raise ValueError("El número de celular debe tener exactamente 10 dígitos")
        return cel


class UsuarioUpdate(BaseModel):
    nombre_usuario: str | None = Field(default=None, min_length=3, max_length=50)
    nombre_completo: str | None = Field(default=None, max_length=120)
    rol: str | None = Field(default=None, min_length=3, max_length=30)
    
    # 🔥 NUEVO CAMPO: celular
    celular: str | None = Field(default=None, max_length=15)
    
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

    # 🔥 VALIDADOR: Asegura que sean 10 dígitos también al editar
    @field_validator("celular")
    @classmethod
    def validar_celular(cls, value: str | None) -> str | None:
        if not value or value.strip() == "":
            return None
        cel = value.replace(" ", "").replace("-", "")
        if not cel.isdigit() or len(cel) != 10:
            raise ValueError("El número de celular debe tener exactamente 10 dígitos")
        return cel


class UsuarioPasswordUpdate(BaseModel):
    password: str = Field(..., min_length=3, max_length=100)