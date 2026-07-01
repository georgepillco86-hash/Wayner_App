from __future__ import annotations

from typing import Any

from app.core.pedidos_database import pedidos_db


class UsuarioRepository:
    def list_users(self) -> list[dict[str, Any]]:
        query = """
        SELECT
            id,
            nombre_usuario,
            nombre_completo,
            rol,
            activo,
            fecha_creacion,
            ultimo_login
        FROM usuarios
        ORDER BY id ASC
        """
        return pedidos_db.fetch_all(query)

    def get_user_by_id(self, usuario_id: int) -> dict[str, Any] | None:
        query = """
        SELECT
            id,
            nombre_usuario,
            nombre_completo,
            rol,
            activo,
            fecha_creacion,
            ultimo_login
        FROM usuarios
        WHERE id = %s
        """
        return pedidos_db.fetch_one(query, (usuario_id,))

    def get_user_by_username(self, nombre_usuario: str) -> dict[str, Any] | None:
        query = """
        SELECT id
        FROM usuarios
        WHERE LOWER(nombre_usuario) = LOWER(%s)
        LIMIT 1
        """
        return pedidos_db.fetch_one(query, (nombre_usuario,))

    def create_user(
        self,
        nombre_usuario: str,
        password_hash: str,
        nombre_completo: str | None,
        rol: str,
        activo: bool,
    ) -> int:
        query = """
        INSERT INTO usuarios (
            nombre_usuario,
            password_hash,
            nombre_completo,
            rol,
            activo,
            fecha_creacion
        )
        VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        RETURNING id
        """
        return pedidos_db.execute(
            query,
            (
                nombre_usuario,
                password_hash,
                nombre_completo,
                rol,
                activo,
            ),
        )

    def update_user(
        self,
        usuario_id: int,
        nombre_usuario: str,
        nombre_completo: str | None,
        rol: str,
        activo: bool,
    ) -> None:
        query = """
        UPDATE usuarios
        SET
            nombre_usuario = %s,
            nombre_completo = %s,
            rol = %s,
            activo = %s
        WHERE id = %s
        """
        pedidos_db.execute(
            query,
            (
                nombre_usuario,
                nombre_completo,
                rol,
                activo,
                usuario_id,
            ),
        )

    def update_password(self, usuario_id: int, password_hash: str) -> None:
        query = """
        UPDATE usuarios
        SET password_hash = %s
        WHERE id = %s
        """
        pedidos_db.execute(query, (password_hash, usuario_id))

    def deactivate_user(self, usuario_id: int) -> None:
        query = """
        UPDATE usuarios
        SET activo = false
        WHERE id = %s
        """
        pedidos_db.execute(query, (usuario_id,))