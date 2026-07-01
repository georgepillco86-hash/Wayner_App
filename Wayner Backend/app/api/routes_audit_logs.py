from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, HTTPException, Query, Request

from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService

router = APIRouter(prefix="/logs", tags=["logs"])
service = AuditLogService(AuditLogRepository())


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.get("")
def list_logs(
    usuario_solicitante_id: int = Query(..., description="ID del usuario admin que consulta"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    accion: str | None = None,
    modulo: str | None = None,
    nombre_usuario: str | None = None,
    desde: str | None = None,
    hasta: str | None = None,
):
    try:
        logs = service.list_logs(
            usuario_solicitante_id=usuario_solicitante_id,
            limit=limit,
            offset=offset,
            accion=accion,
            modulo=modulo,
            nombre_usuario=nombre_usuario,
            desde=desde,
            hasta=hasta,
        )

        total = service.count_logs(
            usuario_solicitante_id=usuario_solicitante_id,
            accion=accion,
            modulo=modulo,
            nombre_usuario=nombre_usuario,
            desde=desde,
            hasta=hasta,
        )

        return ok(
            {
                "items": logs,
                "total": total,
                "limit": limit,
                "offset": offset,
            },
            "Logs obtenidos exitosamente",
        )

    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc


@router.post("")
def create_frontend_log(payload: dict, request: Request):
    service.create_log(
        usuario_id=payload.get("usuario_id"),
        nombre_usuario=payload.get("nombre_usuario"),
        rol=payload.get("rol"),
        accion=payload.get("accion"),
        modulo=payload.get("modulo", "APP"),
        metodo=request.method,
        ruta=request.url.path,
        estado_http=200,
        detalle=payload.get("detalle"),
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )

    return ok(None, "Log registrado exitosamente")


@router.delete("/cleanup")
def cleanup_logs(
    usuario_solicitante_id: int = Query(..., description="ID del usuario admin que ejecuta limpieza"),
    dias_retencion: int = Query(180, ge=30, le=3650),
    dry_run: bool = Query(True, description="Si es true solo calcula, no elimina"),
):
    try:
        fecha_limite = datetime.now() - timedelta(days=dias_retencion)
        fecha_limite_str = fecha_limite.strftime("%Y-%m-%d %H:%M:%S")

        afectados = service.cleanup_old_logs(
            usuario_solicitante_id=usuario_solicitante_id,
            fecha_limite=fecha_limite_str,
            dry_run=dry_run,
        )

        return ok(
            {
                "dry_run": dry_run,
                "dias_retencion": dias_retencion,
                "fecha_limite": fecha_limite_str,
                "registros_afectados": afectados,
            },
            "Limpieza evaluada exitosamente" if dry_run else "Limpieza ejecutada exitosamente",
        )

    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc