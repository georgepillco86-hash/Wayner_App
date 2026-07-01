from __future__ import annotations

import time
from typing import Any

from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.product_repository import ProductRepository
from app.repositories.promocion_repository import PromocionRepository


class TTLCache:
    def __init__(self, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self._store: dict[str, tuple[float, Any]] = {}

    def get(self, key: str) -> Any | None:
        item = self._store.get(key)
        if not item:
            return None
        created_at, value = item
        if time.time() - created_at > self.ttl_seconds:
            self._store.pop(key, None)
            return None
        return value

    def set(self, key: str, value: Any) -> None:
        self._store[key] = (time.time(), value)


class ProductService:
    def __init__(self, repository: ProductRepository) -> None:
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
    def validate_barcode(barcode: str) -> str:
        barcode = barcode.strip()
        if len(barcode) < 1:
            raise ValidationError("El código de barras no puede estar vacío")
        return barcode

    def health(self) -> dict[str, Any]:
        return self.repository.health()

    def catalog_stats(self) -> dict[str, Any]:
        cache_key = "catalog_stats"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
        return self._cache_set(cache_key, self.repository.catalog_stats())

    def dataset_scanner(self, limit: int | None = None) -> list[dict[str, Any]]:
        cache_key = f"dataset_scanner:{limit or 0}"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
        return self._cache_set(cache_key, self.repository.dataset_scanner(limit))

    def search_products(self, text: str, limit: int | None = None) -> list[dict[str, Any]]:
        text = text.strip()
        if len(text) < 2:
            raise ValidationError("La búsqueda debe tener al menos 2 caracteres")
        return self.repository.search_products(text=text, limit=limit)

    def get_by_barcode(self, barcode: str) -> dict[str, Any]:
        barcode = self.validate_barcode(barcode)
        cache_key = f"product:{barcode}"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
        product = self.repository.get_product_summary(barcode)
        if not product:
            raise NotFoundError("Producto no encontrado")
        return self._cache_set(cache_key, product)

    def get_stock(self, barcode: str) -> dict[str, Any]:
        barcode = self.validate_barcode(barcode)
        cache_key = f"stock:{barcode}"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
        stock = self.repository.get_stock(barcode)
        if not stock:
            raise NotFoundError("No se encontró stock para el producto")
        return self._cache_set(cache_key, stock)

    def get_history(self, barcode: str, limit: int | None = None) -> list[dict[str, Any]]:
        barcode = self.validate_barcode(barcode)
        history = self.repository.get_history(barcode, limit=limit)
        if not history:
            raise NotFoundError("No se encontró historial para el producto")
        return history

    def get_detail(self, barcode: str) -> dict[str, Any]:
        product = self.get_by_barcode(barcode)
        stock = self.repository.get_stock(barcode)
        last_movement = self.repository.get_last_movement(barcode)
        return {
            "producto": product,
            "stock": stock,
            "ultimo_movimiento": last_movement,
        }
    
    def get_sales_summary(
        self,
        barcode: str,
        desde: str,
        hasta: str,
    ) -> list[dict[str, Any]]:
        barcode = self.validate_barcode(barcode)

        data = self.repository.get_sales_summary(
            barcode,
            desde=desde,
            hasta=hasta,
        )

        if not data:
            raise NotFoundError("No se encontró resumen de ventas para el producto")

        return data
    
    def get_kardex_table(
        self,
        barcode: str,
        desde: str,
        hasta: str,
    ) -> list[dict[str, Any]]:
        barcode = self.validate_barcode(barcode)

        if not desde or not hasta:
            raise ValidationError("Debe enviar fecha desde y fecha hasta")

        data = self.repository.get_kardex_table(
            barcode,
            desde=desde,
            hasta=hasta,
        )

        if not data:
            raise NotFoundError("No se encontró información Kardex para el rango seleccionado")

        return data
    
    def get_detail_with_promotion(self, barcode: str) -> dict[str, Any]:
        barcode = self.validate_barcode(barcode)

        product = self.get_by_barcode(barcode)
        stock = self.repository.get_stock(barcode)
        last_movement = self.repository.get_last_movement(barcode)

        promocion_repository = PromocionRepository()
        promocion = promocion_repository.obtener_activa_por_codigo(barcode)

        return {
            "producto": product,
            "stock": stock,
            "ultimo_movimiento": last_movement,
            "promocion_activa": promocion is not None,
            "promocion": promocion,
        }