from __future__ import annotations

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
        return self.repository.dataset(
            limit=limit,
            proveedor=proveedor,
        )

    def search_products(
        self,
        texto: str,
        clase: str | None = None,
        categoria: str | None = None,
        proveedor: str | None = None,
        limit: int | None = None,
    ):
        return self.repository.search_products(
            texto,
            clase=clase,
            categoria=categoria,
            proveedor=proveedor,
            limit=limit,
        )

    def get_by_code(self, codigo: str) -> dict[str, Any]:
        codigo = self._validate_text(codigo, "El código")
        cache_key = f"saldos:producto:{codigo}"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
        product = self.repository.get_by_code(codigo)
        if not product:
            raise NotFoundError("Producto no encontrado en v_saldosproductos")
        return self._cache_set(cache_key, product)

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
        return self.repository.get_by_class(
            clase,
            limit=limit,
            proveedor=proveedor,
        )
