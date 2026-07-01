from __future__ import annotations

from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.usuario_repository import UsuarioRepository
from app.schemas.usuario import UsuarioCreate, UsuarioPasswordUpdate, UsuarioUpdate, ROLES_PERMITIDOS


class UsuarioService:
    def __init__(self, repository: UsuarioRepository) -> None:
        self.repository = repository

    def list_users(self) -> list[dict]:
        return self.repository.list_users()

    def _validar_rol(self, rol: str) -> str:
        rol_normalizado = rol.strip().upper()

        if rol_normalizado not in ROLES_PERMITIDOS:
            raise ValidationError(
                f"Rol no permitido. Roles válidos: {', '.join(sorted(ROLES_PERMITIDOS))}"
            )

        return rol_normalizado

    def create_user(self, payload: UsuarioCreate) -> dict:
        nombre_usuario = payload.nombre_usuario.strip()
        rol = self._validar_rol(payload.rol)

        existing = self.repository.get_user_by_username(nombre_usuario)

        if existing:
            raise ValidationError("Ya existe un usuario con ese nombre")

        usuario_id = self.repository.create_user(
            nombre_usuario=nombre_usuario,
            password_hash=payload.password.strip(),
            nombre_completo=payload.nombre_completo.strip() if payload.nombre_completo else None,
            rol=rol,
            activo=payload.activo,
        )

        return self.repository.get_user_by_id(usuario_id)

    def update_user(self, usuario_id: int, payload: UsuarioUpdate) -> dict:
        user = self.repository.get_user_by_id(usuario_id)

        if not user:
            raise NotFoundError("Usuario no encontrado")

        nuevo_nombre_usuario = (
            payload.nombre_usuario.strip()
            if payload.nombre_usuario is not None
            else user["nombre_usuario"]
        )

        if nuevo_nombre_usuario.lower() != user["nombre_usuario"].lower():
            existing = self.repository.get_user_by_username(nuevo_nombre_usuario)
            if existing:
                raise ValidationError("Ya existe un usuario con ese nombre")

        nuevo_nombre_completo = (
            payload.nombre_completo.strip()
            if payload.nombre_completo is not None
            else user["nombre_completo"]
        )

        nuevo_rol = (
            self._validar_rol(payload.rol)
            if payload.rol is not None
            else user["rol"]
        )

        nuevo_activo = (
            payload.activo
            if payload.activo is not None
            else user["activo"]
        )

        self.repository.update_user(
            usuario_id=usuario_id,
            nombre_usuario=nuevo_nombre_usuario,
            nombre_completo=nuevo_nombre_completo,
            rol=nuevo_rol,
            activo=nuevo_activo,
        )

        return self.repository.get_user_by_id(usuario_id)

    def update_password(self, usuario_id: int, payload: UsuarioPasswordUpdate) -> dict:
        user = self.repository.get_user_by_id(usuario_id)

        if not user:
            raise NotFoundError("Usuario no encontrado")

        self.repository.update_password(
            usuario_id=usuario_id,
            password_hash=payload.password.strip(),
        )

        return self.repository.get_user_by_id(usuario_id)

    def deactivate_user(self, usuario_id: int) -> dict:
        user = self.repository.get_user_by_id(usuario_id)

        if not user:
            raise NotFoundError("Usuario no encontrado")

        self.repository.deactivate_user(usuario_id)

        return self.repository.get_user_by_id(usuario_id)