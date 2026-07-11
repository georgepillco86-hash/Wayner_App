from __future__ import annotations

import math
import time
from datetime import datetime, timedelta
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

    def _inyectar_vdp_dinamico(self, data: list[dict[str, Any]] | dict[str, Any] | None) -> list[dict[str, Any]] | dict[str, Any] | None:
        """
        Calcula el stock mínimo (VDP) dinámicamente mediante Bulk Query
        para evitar sobrecargar la base de datos espejo.
        """
        if not data:
            return data

        is_dict = isinstance(data, dict)
        items = [data] if is_dict else data

        # 1. Extraer los códigos de la página/lista actual (Ej: los 30 productos que devolvió la búsqueda)
        codigos_a_consultar = []
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo")
            if codigo and codigo not in codigos_a_consultar:
                codigos_a_consultar.append(codigo)

        # 2. Definir fechas (últimos 30 días)
        hasta_date = datetime.now()
        desde_date = hasta_date - timedelta(days=30)
        desde_str = desde_date.strftime("%Y-%m-%d")
        hasta_str = hasta_date.strftime("%Y-%m-%d")

        # 3. Hacer UNA SOLA consulta a la base de datos para obtener los egresos de todos esos códigos
        ventas_bulk = {}
        if codigos_a_consultar:
            try:
                # Este método devolverá un diccionario: {"1001": 25.0, "1002": 10.0}
                ventas_bulk = self.repository.get_ventas_en_bloque(
                    codigos=codigos_a_consultar,
                    desde=desde_str,
                    hasta=hasta_str
                )
            except Exception as e:
                # Log del error en caso de fallo en la conexión
                ventas_bulk = {}

        # 4. Inyectar el cálculo iterando rápidamente en memoria
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo")
            
            # Leemos del diccionario en memoria (0.0 si no hubo ventas)
            ventas_totales = ventas_bulk.get(codigo, 0.0)

            # Variables Logísticas
            dias_historial = 30
            pvd = ventas_totales / dias_historial if dias_historial > 0 else 0
            factor_estacionalidad = 1.0
            lead_time = 7       # Días de entrega del proveedor
            dias_seguridad = 3  # Colchón de seguridad

            # Fórmula VDP
            vdp_dinamico_float = ((pvd * factor_estacionalidad) * lead_time) + (pvd * dias_seguridad)
            vdp_calculado = math.ceil(vdp_dinamico_float)

            # Inyectar el cálculo final para la vista en Flutter
            item["stock_minimo"] = vdp_calculado
            if "min" in item: item["min"] = vdp_calculado
            if "Min" in item: item["Min"] = vdp_calculado
            if "stock_estimado_minimo" in item: item["stock_estimado_minimo"] = vdp_calculado

        return items[0] if is_dict else items

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
            
        resultados = self.repository.dataset_scanner(limit)
        resultados_dinamicos = self._inyectar_vdp_dinamico(resultados)
        return self._cache_set(cache_key, resultados_dinamicos)

    def search_products(self, text: str, limit: int | None = None) -> list[dict[str, Any]]:
        text = text.strip()
        if len(text) < 2:
            raise ValidationError("La búsqueda debe tener al menos 2 caracteres")
            
        resultados = self.repository.search_products(text=text, limit=limit)
        return self._inyectar_vdp_dinamico(resultados)

    def get_by_barcode(self, barcode: str) -> dict[str, Any]:
        barcode = self.validate_barcode(barcode)
        cache_key = f"product:{barcode}"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
            
        product = self.repository.get_product_summary(barcode)
        if not product:
            raise NotFoundError("Producto no encontrado")
            
        product_dinamico = self._inyectar_vdp_dinamico(product)
        return self._cache_set(cache_key, product_dinamico)

    def get_stock(self, barcode: str) -> dict[str, Any]:
        barcode = self.validate_barcode(barcode)
        cache_key = f"stock:{barcode}"
        cached = self._cache_get(cache_key)
        if cached is not None:
            return cached
            
        stock = self.repository.get_stock(barcode)
        if not stock:
            raise NotFoundError("No se encontró stock para el producto")
            
        stock_dinamico = self._inyectar_vdp_dinamico(stock)
        return self._cache_set(cache_key, stock_dinamico)

    def get_history(self, barcode: str, limit: int | None = None) -> list[dict[str, Any]]:
        barcode = self.validate_barcode(barcode)
        history = self.repository.get_history(barcode, limit=limit)
        if not history:
            raise NotFoundError("No se encontró historial para el producto")
        return history

    def get_detail(self, barcode: str) -> dict[str, Any]:
        product = self.get_by_barcode(barcode)
        stock = self.repository.get_stock(barcode)
        stock_dinamico = self._inyectar_vdp_dinamico(stock)
        last_movement = self.repository.get_last_movement(barcode)
        
        return {
            "producto": product,
            "stock": stock_dinamico,
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
        stock_dinamico = self._inyectar_vdp_dinamico(stock)
        last_movement = self.repository.get_last_movement(barcode)

        promocion_repository = PromocionRepository()
        promocion = promocion_repository.obtener_activa_por_codigo(barcode)

        return {
            "producto": product,
            "stock": stock_dinamico,
            "ultimo_movimiento": last_movement,
            "promocion_activa": promocion is not None,
            "promocion": promocion,
        }