from __future__ import annotations

from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.unidad_medida_repository import UnidadMedidaRepository
from app.schemas.unidad_medida import UnidadMedidaCreate, UnidadMedidaUpdate


class UnidadMedidaService:
    def __init__(self, repository: UnidadMedidaRepository) -> None:
        self.repository = repository

    def list_active(self) -> list[dict]:
        return self.repository.list_active()

    def list_all(self) -> list[dict]:
        return self.repository.list_all()

    def create(self, payload: UnidadMedidaCreate) -> dict:
        nombre = payload.nombre.strip().upper()

        existing = self.repository.get_by_name(nombre)
        if existing:
            raise ValidationError("Ya existe una unidad de medida con ese nombre")

        unidad_id = self.repository.create(nombre)
        return self.repository.get_by_id(unidad_id)

    def update(self, unidad_id: int, payload: UnidadMedidaUpdate) -> dict:
        unidad = self.repository.get_by_id(unidad_id)

        if not unidad:
            raise NotFoundError("Unidad de medida no encontrada")

        nuevo_nombre = (
            payload.nombre.strip().upper()
            if payload.nombre is not None
            else unidad["nombre"]
        )

        if nuevo_nombre.lower() != unidad["nombre"].lower():
            existing = self.repository.get_by_name(nuevo_nombre)
            if existing:
                raise ValidationError("Ya existe una unidad de medida con ese nombre")

        nuevo_activo = (
            payload.activo
            if payload.activo is not None
            else unidad["activo"]
        )

        self.repository.update(
            unidad_id=unidad_id,
            nombre=nuevo_nombre,
            activo=nuevo_activo,
        )

        return self.repository.get_by_id(unidad_id)

    def deactivate(self, unidad_id: int) -> dict:
        unidad = self.repository.get_by_id(unidad_id)

        if not unidad:
            raise NotFoundError("Unidad de medida no encontrada")

        self.repository.deactivate(unidad_id)

        return self.repository.get_by_id(unidad_id)