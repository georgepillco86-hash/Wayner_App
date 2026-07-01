from __future__ import annotations

from app.core.exceptions import ValidationError
from app.repositories.auth_repository import AuthRepository
from app.schemas.auth import LoginRequest


class AuthService:
    def __init__(self, repository: AuthRepository) -> None:
        self.repository = repository

    def login(self, payload: LoginRequest) -> dict:
        nombre_usuario = payload.nombre_usuario.strip()
        password = payload.password.strip()

        if not nombre_usuario or not password:
            raise ValidationError("Usuario y contraseña son obligatorios")

        user = self.repository.get_user_by_username(nombre_usuario)

        if not user:
            raise ValidationError("Usuario o contraseña incorrectos")

        if not user.get("activo"):
            raise ValidationError("Usuario inactivo")

        # Temporal: contraseña en texto.
        # Luego lo cambiamos por bcrypt.
        if str(user.get("password_hash")) != password:
            raise ValidationError("Usuario o contraseña incorrectos")

        self.repository.update_last_login(int(user["id"]))

        return {
            "id": user["id"],
            "nombre_usuario": user["nombre_usuario"],
            "nombre_completo": user["nombre_completo"],
            "rol": user["rol"],
            "activo": user["activo"],
        }