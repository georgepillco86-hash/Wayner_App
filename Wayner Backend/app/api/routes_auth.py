from __future__ import annotations

from fastapi import APIRouter, Request

from app.repositories.auth_repository import AuthRepository
from app.schemas.auth import LoginRequest
from app.services.auth_service import AuthService
from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService

router = APIRouter(prefix="/auth", tags=["auth"])
service = AuthService(AuthRepository())
audit_service = AuditLogService(AuditLogRepository())

def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.post("/login")
def login(payload: LoginRequest, request: Request):
    data = service.login(payload)

    usuario_id = None
    nombre_usuario = None
    rol = None

    if isinstance(data, dict):
        usuario_id = data.get("id") or data.get("usuario_id")
        nombre_usuario = data.get("nombre_usuario") or data.get("username") or data.get("usuario")
        rol = data.get("rol")

    audit_service.create_log(
        usuario_id=usuario_id,
        nombre_usuario=nombre_usuario,
        rol=rol,
        accion="LOGIN_EXITOSO",
        modulo="SEGURIDAD",
        metodo=request.method,
        ruta=request.url.path,
        estado_http=200,
        detalle=f"Inicio de sesión exitoso: {nombre_usuario or 'usuario no identificado'}",
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    return ok(data, "Login exitoso")