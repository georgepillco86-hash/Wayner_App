from __future__ import annotations

from typing import Any

from app.core.pedidos_database import pedidos_db


class AuthRepository:
    def get_user_by_username(self, nombre_usuario: str) -> dict[str, Any] | None:
        query = """
        SELECT
            id,
            nombre_usuario,
            password_hash,
            nombre_completo,
            rol,
            activo
        FROM usuarios
        WHERE LOWER(nombre_usuario) = LOWER(%s)
        LIMIT 1
        """

        return pedidos_db.fetch_one(query, (nombre_usuario,))

    def update_last_login(self, usuario_id: int) -> None:
        query = """
        UPDATE usuarios
        SET ultimo_login = CURRENT_TIMESTAMP
        WHERE id = %s
        """

        pedidos_db.execute(query, (usuario_id,))