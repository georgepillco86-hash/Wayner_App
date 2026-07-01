from __future__ import annotations

from app.repositories.audit_log_repository import AuditLogRepository


class AuditLogService:
    def __init__(self, repository: AuditLogRepository):
        self.repository = repository

    def create_log(
        self,
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
        return self.repository.create_log(
            usuario_id=usuario_id,
            nombre_usuario=nombre_usuario,
            rol=rol,
            accion=accion,
            modulo=modulo,
            metodo=metodo,
            ruta=ruta,
            estado_http=estado_http,
            detalle=detalle,
            ip=ip,
            user_agent=user_agent,
            duracion_ms=duracion_ms,
        )

    def list_logs(
        self,
        usuario_solicitante_id: int,
        limit: int = 100,
        offset: int = 0,
        accion: str | None = None,
        modulo: str | None = None,
        nombre_usuario: str | None = None,
        desde: str | None = None,
        hasta: str | None = None,
    ):
        self._validar_admin(usuario_solicitante_id)

        return self.repository.list_logs(
            limit=limit,
            offset=offset,
            accion=accion,
            modulo=modulo,
            nombre_usuario=nombre_usuario,
            desde=desde,
            hasta=hasta,
        )

    def count_logs(
        self,
        usuario_solicitante_id: int,
        accion: str | None = None,
        modulo: str | None = None,
        nombre_usuario: str | None = None,
        desde: str | None = None,
        hasta: str | None = None,
    ) -> int:
        self._validar_admin(usuario_solicitante_id)

        return self.repository.count_logs(
            accion=accion,
            modulo=modulo,
            nombre_usuario=nombre_usuario,
            desde=desde,
            hasta=hasta,
        )

    def cleanup_old_logs(
        self,
        usuario_solicitante_id: int,
        fecha_limite: str,
        dry_run: bool = True,
    ) -> int:
        self._validar_admin(usuario_solicitante_id)

        if dry_run:
            return self.repository.count_older_than(fecha_limite)

        return self.repository.delete_older_than(fecha_limite)

    def _validar_admin(self, usuario_solicitante_id: int) -> None:
        rol = self.repository.get_user_role(usuario_solicitante_id)

        if not rol or rol.upper() != "ADMIN":
            raise PermissionError("Solo el administrador puede consultar los logs")