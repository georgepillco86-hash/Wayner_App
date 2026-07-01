from __future__ import annotations

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    nombre_usuario: str = Field(..., min_length=1, max_length=50)
    password: str = Field(..., min_length=1, max_length=100)


class LoginResponse(BaseModel):
    id: int
    nombre_usuario: str
    nombre_completo: str | None = None
    rol: str
    activo: bool