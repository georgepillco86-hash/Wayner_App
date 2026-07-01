from __future__ import annotations

from fastapi import APIRouter, Query

from app.repositories.saldo_repository import SaldoProductRepository
from app.services.saldo_service import SaldoProductService

router = APIRouter(prefix="/saldos", tags=["saldos productos"])
service = SaldoProductService(SaldoProductRepository())


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.get("/health")
def health():
    return ok(service.health(), "API de saldos funcionando correctamente")


@router.get("/columnas")
def columns():
    return ok(service.columns(), "Columnas de v_saldosproductos obtenidas exitosamente")


@router.get("/resumen")
def summary():
    return ok(service.summary(), "Resumen de saldos obtenido exitosamente")


@router.get("/dataset")
def dataset(
    limit: int | None = Query(default=None, ge=1, le=5000),
    proveedor: str | None = Query(default=None),
):
    return ok(
        service.dataset(limit=limit, proveedor=proveedor),
        "Dataset de saldos obtenido exitosamente",
    )


@router.get("/buscar")
def search_products(
    texto: str = Query(..., min_length=2),
    clase: str | None = Query(default=None),
    categoria: str | None = Query(default=None),
    proveedor: str | None = Query(default=None),
    limit: int | None = Query(default=None, ge=1, le=500),
):
    return ok(
        service.search_products(
            texto,
            clase=clase,
            categoria=categoria,
            proveedor=proveedor,
            limit=limit,
        ),
        "Búsqueda de saldos completada",
    )


@router.get("/clases")
def classes():
    return ok(service.list_classes(), "Clases obtenidas exitosamente")

@router.get("/proveedores")
def providers():
    return ok(
        service.list_providers(),
        "Proveedores obtenidos exitosamente",
    )

@router.get("/clase/{clase}")
def products_by_class(
    clase: str,
    limit: int | None = Query(default=None, ge=1, le=500),
    proveedor: str | None = Query(default=None),
):
    return ok(
        service.get_by_class(clase, limit=limit, proveedor=proveedor),
        "Productos por clase obtenidos exitosamente",
    )


@router.get("/producto/{codigo}")
def product_by_code(codigo: str):
    return ok(service.get_by_code(codigo), "Producto encontrado en saldos")
