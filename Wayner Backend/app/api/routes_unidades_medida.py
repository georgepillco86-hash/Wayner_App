from __future__ import annotations

from fastapi import APIRouter

from app.repositories.unidad_medida_repository import UnidadMedidaRepository
from app.schemas.unidad_medida import UnidadMedidaCreate, UnidadMedidaUpdate
from app.services.unidad_medida_service import UnidadMedidaService

router = APIRouter(prefix="/unidades-medida", tags=["unidades-medida"])
service = UnidadMedidaService(UnidadMedidaRepository())


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.get("")
def list_active_units():
    return ok(
        service.list_active(),
        "Unidades de medida activas obtenidas exitosamente",
    )


@router.get("/admin")
def list_all_units():
    return ok(
        service.list_all(),
        "Unidades de medida obtenidas exitosamente",
    )


@router.post("")
def create_unit(payload: UnidadMedidaCreate):
    return ok(
        service.create(payload),
        "Unidad de medida creada exitosamente",
    )


@router.patch("/{unidad_id}")
def update_unit(unidad_id: int, payload: UnidadMedidaUpdate):
    return ok(
        service.update(unidad_id, payload),
        "Unidad de medida actualizada exitosamente",
    )


@router.delete("/{unidad_id}")
def deactivate_unit(unidad_id: int):
    return ok(
        service.deactivate(unidad_id),
        "Unidad de medida desactivada exitosamente",
    )