from __future__ import annotations

from decimal import Decimal, ROUND_CEILING
from typing import Any

from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.promocion_repository import PromocionRepository
from app.schemas.promocion import PromocionCreate, PromocionUpdate


class PromocionService:
    def __init__(self, repository: PromocionRepository) -> None:
        self.repository = repository

    @staticmethod
    def _calcular_ahorro(precio_anterior: Decimal, precio_actual_prom: Decimal) -> Decimal:
        ahorro = precio_anterior - precio_actual_prom
        if ahorro < 0:
            raise ValidationError("El precio promocional no puede ser mayor al precio anterior")
        return ahorro.quantize(Decimal("0.01"))

    @staticmethod
    def _calcular_mecanica(
        precio_anterior: Decimal,
        precio_actual_prom: Decimal,
        mecanica_manual: str | None = None,
    ) -> str:
        if mecanica_manual and mecanica_manual.strip():
            return mecanica_manual.strip().upper()

        ahorro = precio_anterior - precio_actual_prom

        if precio_anterior <= 0:
            return "PROMOCIÓN"

        porcentaje = ((ahorro / precio_anterior) * Decimal("100")).to_integral_value(
            rounding=ROUND_CEILING
        )

        return f"DESCUENTO {porcentaje}%"

    def listar(
        self,
        texto: str | None = None,
        codigo_barra: str | None = None,
        estado: str | None = None,
        fecha_desde=None,
        fecha_hasta=None,
    ) -> list[dict[str, Any]]:
        return self.repository.listar(
            texto=texto,
            codigo_barra=codigo_barra,
            estado=estado,
            fecha_desde=fecha_desde,
            fecha_hasta=fecha_hasta,
        )

    def obtener(self, promocion_id: int) -> dict[str, Any]:
        promocion = self.repository.obtener_por_id(promocion_id)

        if not promocion:
            raise NotFoundError("Promoción no encontrada")

        return promocion

    def obtener_activa_por_codigo(self, codigo_barra: str) -> dict[str, Any]:
        promocion = self.repository.obtener_activa_por_codigo(codigo_barra)

        if not promocion:
            raise NotFoundError("No existe promoción activa para este producto")

        return promocion

    def crear(self, payload: PromocionCreate) -> dict[str, Any]:
        data = payload.model_dump()

        solapada = self.repository.existe_solapamiento(
            codigo_barra=data["codigo_barra"],
            fecha_inicio=data["fecha_inicio"],
            fecha_fin=data["fecha_fin"],
        )

        if solapada:
            raise ValidationError("Ya existe una promoción activa para este producto en ese rango de fechas")

        ahorro = self._calcular_ahorro(
            data["precio_anterior"],
            data["precio_actual_prom"],
        )

        data["ahorro"] = ahorro
        data["mecanica"] = self._calcular_mecanica(
            data["precio_anterior"],
            data["precio_actual_prom"],
            data.get("mecanica"),
        )

        if not data.get("encabezado"):
            data["encabezado"] = "PROMOCIÓN ESPECIAL"

        promocion_id = self.repository.crear(data)

        return self.obtener(promocion_id)

    def actualizar(self, promocion_id: int, payload: PromocionUpdate) -> dict[str, Any]:
        actual = self.obtener(promocion_id)
        cambios = payload.model_dump(exclude_unset=True)

        if not cambios:
            return actual

        combinado = {**actual, **cambios}

        if combinado["fecha_fin"] < combinado["fecha_inicio"]:
            raise ValidationError("La fecha fin no puede ser menor que la fecha inicio")

        solapada = self.repository.existe_solapamiento(
            codigo_barra=combinado["codigo_barra"],
            fecha_inicio=combinado["fecha_inicio"],
            fecha_fin=combinado["fecha_fin"],
            excluir_id=promocion_id,
        )

        if solapada:
            raise ValidationError("Ya existe otra promoción activa para este producto en ese rango de fechas")

        if "precio_anterior" in cambios or "precio_actual_prom" in cambios:
            cambios["ahorro"] = self._calcular_ahorro(
                combinado["precio_anterior"],
                combinado["precio_actual_prom"],
            )

            cambios["mecanica"] = self._calcular_mecanica(
                combinado["precio_anterior"],
                combinado["precio_actual_prom"],
                combinado.get("mecanica"),
            )

        self.repository.actualizar(promocion_id, cambios)

        return self.obtener(promocion_id)

    def desactivar(self, promocion_id: int) -> dict[str, Any]:
        self.obtener(promocion_id)
        self.repository.desactivar(promocion_id)
        return self.obtener(promocion_id)