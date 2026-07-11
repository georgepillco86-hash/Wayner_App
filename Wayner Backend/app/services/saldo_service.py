from __future__ import annotations

import math
from typing import Any

from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.saldo_repository import SaldoProductRepository
from app.services.product_service import TTLCache


class SaldoProductService:
    def __init__(self, repository: SaldoProductRepository) -> None:
        self.repository = repository
        self.cache = TTLCache(settings.cache_ttl_seconds)

    def _cache_get(self, key: str) -> Any | None:
        if not settings.enable_cache:
            return None
        return self.cache.get(key)

    def _cache_set(self, key: str, value: Any) -> Any:
        if settings.enable_cache:
            self.cache.set(key, value)
        return value

    @staticmethod
    def _validate_text(value: str, field_name: str) -> str:
        value = value.strip()
        if not value:
            raise ValidationError(f"{field_name} no puede estar vacío")
        return value

    def _inyectar_vdp_dinamico(self, data: list[dict[str, Any]] | dict[str, Any] | None) -> list[dict[str, Any]] | dict[str, Any] | None:
        """
        Intercepta los resultados de la base de datos y calcula el stock mínimo (VDP) dinámicamente.
        """
        if not data:
            return data

        is_dict = isinstance(data, dict)
        items = [data] if is_dict else data

        for item in items:
            # IMPORTANTE: Para que esto sea exacto en listados, tu vista SQL 'v_saldosproductos' 
            # debería traer un campo como 'ventas_ultimos_30_dias'. 
            # Si no existe, usamos 0 por defecto temporalmente.
            ventas_historicas = float(item.get("ventas_ultimos_30_dias") or 0)
            
            dias_historial = 30
            pvd = ventas_historicas / dias_historial if dias_historial > 0 else 0

            # Parámetros logísticos (puedes ajustarlos o leerlos de la BD por proveedor)
            factor_estacionalidad = 1.0
            lead_time = 7       # 7 días en que tarda en llegar el pedido
            dias_seguridad = 3  # 3 días de colchón

            # Cálculo de la fórmula VDP
            vdp_dinamico_float = ((pvd * factor_estacionalidad) * lead_time) + (pvd * dias_seguridad)
            vdp_calculado = math.ceil(vdp_dinamico_float)

            # Sobrescribimos el campo que el frontend lee para mostrar la barra de estado
            # Asumo que el frontend busca 'stock_minimo' o 'Min', inyectamos ambos por seguridad
            item["stock_minimo"] = vdp_calculado
            if "min" in item or "Min" in item:
                item["Min"] = vdp_calculado # O usa la clave exacta que espere Flutter

        return items[0] if is_dict else items

    def health(self) -> dict[str, Any]:
        return self.repository.health()

    def columns(self) -> list[dict[str, Any]]:
        return self.repository.columns()

    def summary(self) -> dict[str, Any]:
        cached = self._cache_get("saldos:summary")
        if cached is not None:
            return cached
        return self._cache_set("saldos:summary", self.repository.summary())

    def dataset(
        self,
        limit: int | None = None,
        proveedor: str | None = None,
    ):
        resultados = self.repository.dataset(
            limit=limit,
            proveedor=proveedor,
        )
        return self._inyectar_vdp_dinamico(resultados)

    def search_products(
        self,
        texto: str,
        clase: str | None = None,
        categoria: str | None = None,
        proveedor: str | None = None,
        limit: int | None = None,
    ):
        resultados = self.repository.search_products(
            texto,
            clase=clase,
            categoria=categoria,
            proveedor=proveedor,
            limit=limit,
        )
        return self._inyectar_vdp_dinamico(resultados)

    def get_by_code(self, codigo: str) -> dict[str, Any]:
        codigo = self._validate_text(codigo, "El código")
        cache_key = f"saldos:producto:{codigo}"
        cached = self._cache_get(cache_key)
        
        if cached is not None:
            return cached
            
        product = self.repository.get_by_code(codigo)
        if not product:
            raise NotFoundError("Producto no encontrado en v_saldosproductos")
            
        # Inyectar el cálculo dinámico antes de guardar en caché y retornar
        product_dinamico = self._inyectar_vdp_dinamico(product)
        return self._cache_set(cache_key, product_dinamico)

    def list_classes(self) -> list[dict[str, Any]]:
        cached = self._cache_get("saldos:clases")
        if cached is not None:
            return cached
        return self._cache_set("saldos:clases", self.repository.list_classes())

    def list_providers(self):
        return self.repository.list_providers()

    def get_by_class(
        self,
        clase: str,
        limit: int | None = None,
        proveedor: str | None = None,
    ):
        resultados = self.repository.get_by_class(
            clase,
            limit=limit,
            proveedor=proveedor,
        )
        return self._inyectar_vdp_dinamico(resultados)