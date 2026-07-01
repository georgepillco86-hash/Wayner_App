from __future__ import annotations

from fastapi import APIRouter, Query, Request

from app.repositories.audit_log_repository import AuditLogRepository
from app.repositories.promocion_repository import PromocionRepository
from app.schemas.promocion import PromocionCreate, PromocionUpdate
from app.services.audit_log_service import AuditLogService
from app.services.promocion_service import PromocionService


router = APIRouter(prefix="/promociones", tags=["promociones"])

service = PromocionService(PromocionRepository())
audit_service = AuditLogService(AuditLogRepository())


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


def registrar_log_promocion(
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
        modulo="PROMOCIONES",
        metodo=request.method,
        ruta=request.url.path,
        estado_http=200,
        detalle=detalle,
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


@router.get("")
def listar_promociones(
    texto: str | None = Query(default=None),
    codigo_barra: str | None = Query(default=None),
    estado: str | None = Query(default=None),
    fecha_desde: str | None = Query(default=None),
    fecha_hasta: str | None = Query(default=None),
):
    return ok(
        service.listar(
            texto=texto,
            codigo_barra=codigo_barra,
            estado=estado,
            fecha_desde=fecha_desde,
            fecha_hasta=fecha_hasta,
        ),
        "Promociones obtenidas exitosamente",
    )

@router.get("/activa/{codigo_barra}")
def obtener_promocion_activa(codigo_barra: str):
    return ok(
        service.obtener_activa_por_codigo(codigo_barra),
        "Promoción activa obtenida exitosamente",
    )


@router.get("/{promocion_id}")
def obtener_promocion(promocion_id: int):
    return ok(
        service.obtener(promocion_id),
        "Promoción obtenida exitosamente",
    )


@router.post("")
def crear_promocion(payload: PromocionCreate, request: Request):
    data = service.crear(payload)

    registrar_log_promocion(
        request,
        accion="PROMOCION_CREADA",
        detalle=f"Promoción creada para producto {payload.codigo_barra}",
    )

    return ok(data, "Promoción creada exitosamente")


@router.patch("/{promocion_id}")
def actualizar_promocion(
    promocion_id: int,
    payload: PromocionUpdate,
    request: Request,
):
    data = service.actualizar(promocion_id, payload)

    registrar_log_promocion(
        request,
        accion="PROMOCION_ACTUALIZADA",
        detalle=f"Promoción #{promocion_id} actualizada",
    )

    return ok(data, "Promoción actualizada exitosamente")


@router.delete("/{promocion_id}")
def desactivar_promocion(promocion_id: int, request: Request):
    data = service.desactivar(promocion_id)

    registrar_log_promocion(
        request,
        accion="PROMOCION_DESACTIVADA",
        detalle=f"Promoción #{promocion_id} desactivada",
    )

    return ok(data, "Promoción desactivada exitosamente")