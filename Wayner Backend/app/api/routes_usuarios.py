from __future__ import annotations

from fastapi import APIRouter, Request

from app.repositories.usuario_repository import UsuarioRepository
from app.schemas.usuario import UsuarioCreate, UsuarioPasswordUpdate, UsuarioUpdate
from app.services.usuario_service import UsuarioService
from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService

router = APIRouter(prefix="/usuarios", tags=["usuarios"])
service = UsuarioService(UsuarioRepository())

audit_service = AuditLogService(AuditLogRepository())


def registrar_log_usuario(
    request: Request,
    *,
    accion: str,
    detalle: str,
):
    usuario_id_raw = request.headers.get("x-user-id")
    usuario_id = int(usuario_id_raw) if usuario_id_raw and usuario_id_raw.isdigit() else None

    audit_service.create_log(
        usuario_id=usuario_id,
        nombre_usuario=request.headers.get("x-user-name"),
        rol=request.headers.get("x-user-role"),
        accion=accion,
        modulo="SEGURIDAD",
        metodo=request.method,
        ruta=request.url.path,
        estado_http=200,
        detalle=detalle,
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.get("")
def list_users():
    return ok(service.list_users(), "Usuarios obtenidos exitosamente")


@router.post("")
def create_user(payload: UsuarioCreate, request: Request):
    data = service.create_user(payload)

    registrar_log_usuario(
        request,
        accion="USUARIO_CREADO",
        detalle="Usuario creado exitosamente",
    )

    return ok(data, "Usuario creado exitosamente")

@router.patch("/{usuario_id}")
def update_user(usuario_id: int, payload: UsuarioUpdate):
    return ok(service.update_user(usuario_id, payload), "Usuario actualizado exitosamente")


@router.patch("/{usuario_id}/password")
def update_password(usuario_id: int, payload: UsuarioPasswordUpdate, request: Request):
    data = service.update_password(usuario_id, payload)

    registrar_log_usuario(
        request,
        accion="PASSWORD_CAMBIADO",
        detalle=f"Contraseña actualizada para usuario #{usuario_id}",
    )

    return ok(data, "Contraseña actualizada exitosamente")

@router.delete("/{usuario_id}")
def deactivate_user(usuario_id: int, request: Request):
    data = service.deactivate_user(usuario_id)

    registrar_log_usuario(
        request,
        accion="USUARIO_DESACTIVADO",
        detalle=f"Usuario #{usuario_id} desactivado",
    )

    return ok(data, "Usuario desactivado exitosamente")