from __future__ import annotations

import time

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService


class AuditLogMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.service = AuditLogService(AuditLogRepository())

    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        response = None

        try:
            response = await call_next(request)
            return response

        finally:
            path = request.url.path

            if self._should_ignore_path(path):
                return response

            try:
                duration_ms = int((time.perf_counter() - start) * 1000)
                status_code = response.status_code if response is not None else 500
                method = request.method.upper()

                if not self._should_log(method, path, status_code):
                    return response

                usuario_id_raw = request.headers.get("x-user-id")
                usuario_id = None

                if usuario_id_raw and usuario_id_raw.isdigit():
                    usuario_id = int(usuario_id_raw)

                self.service.create_log(
                    usuario_id=usuario_id,
                    nombre_usuario=request.headers.get("x-user-name"),
                    rol=request.headers.get("x-user-role"),
                    accion=self._build_action(method, path, status_code),
                    modulo=self._build_module(path),
                    metodo=method,
                    ruta=path,
                    estado_http=status_code,
                    detalle=f"{method} {path} respondió HTTP {status_code}",
                    ip=request.client.host if request.client else None,
                    user_agent=request.headers.get("user-agent"),
                    duracion_ms=duration_ms,
                )

            except Exception:
                pass

    def _should_ignore_path(self, path: str) -> bool:
        return (
            not path.startswith("/api")
            or path.startswith("/api/logs")
            or path in {"/docs", "/redoc", "/openapi.json", "/favicon.ico"}
        )

    def _should_log(self, method: str, path: str, status_code: int) -> bool:
        if path.endswith("/auth/login"):
            return True

        if status_code >= 400:
            return True

        if method in {"POST", "PUT", "PATCH", "DELETE"}:
            return True

        return False

    def _build_module(self, path: str) -> str:
        parts = [part for part in path.split("/") if part]
        if len(parts) >= 2:
            return parts[1].upper()
        return "GENERAL"

    def _build_action(self, method: str, path: str, status_code: int) -> str:
        if path.endswith("/auth/login"):
            return "LOGIN_EXITOSO" if 200 <= status_code < 300 else "LOGIN_FALLIDO"

        if status_code >= 400:
            return "ERROR"

        if method == "POST":
            return "CREACION"
        if method in {"PUT", "PATCH"}:
            return "ACTUALIZACION"
        if method == "DELETE":
            return "ELIMINACION"

        return method