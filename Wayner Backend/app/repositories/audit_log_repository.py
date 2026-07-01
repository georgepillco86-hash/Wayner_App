from __future__ import annotations

from typing import Any

from app.core.pedidos_database import pedidos_db


class AuditLogRepository:
    def create_log(
        self,
        *,
        usuario_id: int | None,
        nombre_usuario: str | None,
        rol: str | None,
        accion: str,
        modulo: str,
        metodo: str | None = None,
        ruta: str | None = None,
        estado_http: int | None = None,
        detalle: str | None = None,
        ip: str | None = None,
        user_agent: str | None = None,
        duracion_ms: int | None = None,
    ) -> int:
        query = """
        INSERT INTO ferrotienda.audit_logs (
            usuario_id,
            nombre_usuario,
            rol,
            accion,
            modulo,
            metodo,
            ruta,
            estado_http,
            detalle,
            ip,
            user_agent,
            duracion_ms
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING id
        """
        return pedidos_db.execute(
            query,
            (
                usuario_id,
                nombre_usuario,
                rol,
                accion,
                modulo,
                metodo,
                ruta,
                estado_http,
                detalle,
                ip,
                user_agent,
                duracion_ms,
            ),
        )

    def list_logs(
        self,
        *,
        limit: int = 100,
        offset: int = 0,
        accion: str | None = None,
        modulo: str | None = None,
        nombre_usuario: str | None = None,
        desde: str | None = None,
        hasta: str | None = None,
    ) -> list[dict[str, Any]]:
        where_sql, params = self._build_filters(
            accion=accion,
            modulo=modulo,
            nombre_usuario=nombre_usuario,
            desde=desde,
            hasta=hasta,
        )

        query = """
        SELECT
            id,
            usuario_id,
            nombre_usuario,
            rol,
            accion,
            modulo,
            metodo,
            ruta,
            estado_http,
            detalle,
            ip,
            user_agent,
            duracion_ms,
            fecha_creacion
        FROM ferrotienda.audit_logs
        """ + where_sql + """
        ORDER BY fecha_creacion DESC
        LIMIT %s OFFSET %s
        """

        params.extend([limit, offset])
        return pedidos_db.fetch_all(query, tuple(params))

    def count_logs(
        self,
        *,
        accion: str | None = None,
        modulo: str | None = None,
        nombre_usuario: str | None = None,
        desde: str | None = None,
        hasta: str | None = None,
    ) -> int:
        where_sql, params = self._build_filters(
            accion=accion,
            modulo=modulo,
            nombre_usuario=nombre_usuario,
            desde=desde,
            hasta=hasta,
        )

        query = """
        SELECT COUNT(*) AS total
        FROM ferrotienda.audit_logs
        """ + where_sql

        row = pedidos_db.fetch_one(query, tuple(params))
        if not row:
            return 0
        return int(row.get("total") or 0)

    def count_older_than(self, fecha_limite: str) -> int:
        query = """
        SELECT COUNT(*) AS total
        FROM ferrotienda.audit_logs
        WHERE fecha_creacion < %s
        """
        row = pedidos_db.fetch_one(query, (fecha_limite,))
        if not row:
            return 0
        return int(row.get("total") or 0)

    def delete_older_than(self, fecha_limite: str) -> int:
        query = """
        DELETE FROM ferrotienda.audit_logs
        WHERE fecha_creacion < %s
        """
        return pedidos_db.execute(query, (fecha_limite,))

    def get_user_role(self, usuario_id: int) -> str | None:
        query = """
        SELECT rol
        FROM ferrotienda.usuarios
        WHERE id = %s AND activo = TRUE
        LIMIT 1
        """
        row = pedidos_db.fetch_one(query, (usuario_id,))
        if not row:
            return None
        return str(row.get("rol") or "")

    def _build_filters(
        self,
        *,
        accion: str | None = None,
        modulo: str | None = None,
        nombre_usuario: str | None = None,
        desde: str | None = None,
        hasta: str | None = None,
    ) -> tuple[str, list[Any]]:
        conditions: list[str] = []
        params: list[Any] = []

        if accion:
            conditions.append("LOWER(accion) LIKE LOWER(%s)")
            params.append(f"%{accion}%")

        if modulo:
            conditions.append("LOWER(modulo) LIKE LOWER(%s)")
            params.append(f"%{modulo}%")

        if nombre_usuario:
            conditions.append("LOWER(nombre_usuario) LIKE LOWER(%s)")
            params.append(f"%{nombre_usuario}%")

        if desde:
            conditions.append("fecha_creacion >= %s")
            params.append(f"{desde} 00:00:00")

        if hasta:
            conditions.append("fecha_creacion <= %s")
            params.append(f"{hasta} 23:59:59")

        if not conditions:
            return "", params

        return "WHERE " + " AND ".join(conditions), params