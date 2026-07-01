from __future__ import annotations

from typing import Any

from app.core.pedidos_database import pedidos_db


class UnidadMedidaRepository:
    def list_active(self) -> list[dict[str, Any]]:
        query = """
        SELECT id, nombre, activo, fecha_creacion
        FROM unidades_medida
        WHERE activo = true
        ORDER BY nombre ASC
        """
        return pedidos_db.fetch_all(query)

    def list_all(self) -> list[dict[str, Any]]:
        query = """
        SELECT id, nombre, activo, fecha_creacion
        FROM unidades_medida
        ORDER BY nombre ASC
        """
        return pedidos_db.fetch_all(query)

    def get_by_id(self, unidad_id: int) -> dict[str, Any] | None:
        query = """
        SELECT id, nombre, activo, fecha_creacion
        FROM unidades_medida
        WHERE id = %s
        LIMIT 1
        """
        return pedidos_db.fetch_one(query, (unidad_id,))

    def get_by_name(self, nombre: str) -> dict[str, Any] | None:
        query = """
        SELECT id, nombre, activo, fecha_creacion
        FROM unidades_medida
        WHERE LOWER(nombre) = LOWER(%s)
        LIMIT 1
        """
        return pedidos_db.fetch_one(query, (nombre,))

    def create(self, nombre: str) -> int:
        query = """
        INSERT INTO unidades_medida (
            nombre,
            activo,
            fecha_creacion
        )
        VALUES (
            %s,
            true,
            CURRENT_TIMESTAMP
        )
        RETURNING id
        """
        return pedidos_db.execute(query, (nombre,))

    def update(
        self,
        unidad_id: int,
        nombre: str,
        activo: bool,
    ) -> None:
        query = """
        UPDATE unidades_medida
        SET nombre = %s,
            activo = %s
        WHERE id = %s
        """
        pedidos_db.execute(query, (nombre, activo, unidad_id))

    def deactivate(self, unidad_id: int) -> None:
        query = """
        UPDATE unidades_medida
        SET activo = false
        WHERE id = %s
        """
        pedidos_db.execute(query, (unidad_id,))