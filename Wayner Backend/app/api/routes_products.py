from __future__ import annotations

from fastapi import APIRouter, Query, Request

from app.repositories.product_repository import ProductRepository
from app.services.product_service import ProductService
from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService


router = APIRouter(tags=["productos"])
service = ProductService(ProductRepository())

audit_service = AuditLogService(AuditLogRepository())


def registrar_log_producto(
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
        modulo="PRODUCTOS",
        metodo=request.method,
        ruta=request.url.path,
        estado_http=200,
        detalle=detalle,
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.get("/health")
def health():
    return ok(service.health(), "API funcionando correctamente")


@router.get("/productos/resumen")
def catalog_summary():
    return ok(service.catalog_stats(), "Resumen del catálogo obtenido exitosamente")


@router.get("/productos/dataset-scanner")
def dataset_scanner(limit: int | None = Query(default=None, ge=1, le=5000)):
    return ok(service.dataset_scanner(limit=limit), "Dataset de scanner obtenido exitosamente")


@router.get("/productos/buscar")
def search_products(texto: str = Query(..., min_length=2), limit: int | None = Query(default=None, ge=1, le=100)):
    return ok(service.search_products(texto, limit=limit), "Búsqueda de productos completada")


@router.get("/productos/escanear/{codigo_barra}")
def get_product_for_scanner(codigo_barra: str, request: Request):
    data = service.get_by_barcode(codigo_barra)

    registrar_log_producto(
        request,
        accion="ESCANEO_PRODUCTO",
        detalle=f"Producto escaneado correctamente: {codigo_barra}",
    )

    return ok(data, "Producto encontrado")

@router.get("/productos/{codigo_barra}/stock")
def get_product_stock(codigo_barra: str):
    return ok(service.get_stock(codigo_barra), "Stock estimado obtenido exitosamente")


@router.get("/productos/{codigo_barra}/historial")
def get_product_history(codigo_barra: str, limit: int | None = Query(default=None, ge=1, le=500)):
    return ok(service.get_history(codigo_barra, limit=limit), "Historial obtenido exitosamente")

@router.get("/productos/{codigo_barra}/detalle-promocion")
def get_product_detail_with_promotion(codigo_barra: str, request: Request):
    data = service.get_detail_with_promotion(codigo_barra)

    registrar_log_producto(
        request,
        accion="CONSULTA_PRODUCTO_PROMOCION",
        detalle=f"Producto consultado con promoción: {codigo_barra}",
    )

    return ok(data, "Detalle con promoción obtenido exitosamente")

@router.get("/productos/{codigo_barra}/detalle")
def get_product_detail(codigo_barra: str):
    return ok(service.get_detail(codigo_barra), "Detalle del producto obtenido exitosamente")

@router.get("/productos/{codigo_barra}/ventas-resumen")
def get_product_sales_summary(
    codigo_barra: str,
    desde: str,
    hasta: str,
):
    return ok(
        service.get_sales_summary(codigo_barra, desde=desde, hasta=hasta),
        "Resumen de ventas obtenido exitosamente",
    )

@router.get("/productos/{codigo_barra}/kardex-tabla")
def get_product_kardex_table(
    codigo_barra: str,
    desde: str,
    hasta: str,
):
    return ok(
        service.get_kardex_table(codigo_barra, desde=desde, hasta=hasta),
        "Tabla Kardex obtenida exitosamente",
    )