from __future__ import annotations

import logging
import math
from datetime import datetime, timedelta
from typing import Any

from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.saldo_repository import SaldoProductRepository
# Importamos el ProductRepository para reutilizar la consulta masiva de Kardex
from app.repositories.product_repository import ProductRepository
from app.services.product_service import TTLCache

logger = logging.getLogger(__name__)

class SaldoProductService:
    def __init__(self, repository: SaldoProductRepository) -> None:
        self.repository = repository
        self.cache = TTLCache(settings.cache_ttl_seconds)
        # Instanciamos el product_repository para acceder a ventas_en_bloque
        self.product_repository = ProductRepository()

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
        Calcula e inyecta el PVD (vdp) y el lead time mediante una consulta masiva
        para que Flutter procese dinámicamente la barra de salud del inventario.
        """
        if not data:
            logger.warning("[SALDOS_SERVICE] _inyectar_vdp_dinamico recibió data vacía.")
            return data

        is_dict = isinstance(data, dict)
        items = [data] if is_dict else data

        logger.info(f"[SALDOS_SERVICE] Iniciando inyección para {len(items)} productos.")

        # 1. Extraer los códigos de la página actual
        codigos_a_consultar = []
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo")
            if codigo and codigo not in codigos_a_consultar:
                codigos_a_consultar.append(codigo)

        logger.info(f"[SALDOS_SERVICE] Se extrajeron {len(codigos_a_consultar)} códigos únicos para consultar al Kardex.")
        # 2. Definir rango de 30 días
        hasta_date = datetime.now()
        desde_date = hasta_date - timedelta(days=30)
        desde_str = desde_date.strftime("%Y-%m-%d")
        hasta_str = hasta_date.strftime("%Y-%m-%d")

        # 3. Consulta masiva a la vista v_kardexproductos reusando el repositorio
        ventas_bulk = {}
        if codigos_a_consultar:
            try:
                logger.info("[SALDOS_SERVICE] Llamando a get_ventas_en_bloque...")
                ventas_bulk = self.product_repository.get_ventas_en_bloque(
                    codigos=codigos_a_consultar,
                    desde=desde_str,
                    hasta=hasta_str
                )
            except Exception:
                logger.error(f"[SALDOS_SERVICE] Falló la llamada a bulk query: {str(e)}")
                ventas_bulk = {}

        primer_item_logueado = False

        # 4. Inyectar las métricas de predicción para Flutter
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo")
            ventas_totales = ventas_bulk.get(codigo, 0.0)
            
            dias_historial = 30
            pvd = ventas_totales / dias_historial if dias_historial > 0 else 0

            # Si el proveedor tiene un lead time en la BD, lo usamos, si no por defecto 3 (o el que definas)
            lead_time = int(item.get("lead_time_dias") or item.get("LeadTime") or 3)

            # ==========================================
            # LAS DOS LLAVES QUE FLUTTER NECESITA PARA CALCULAR LA BARRA
            # ==========================================
            item["vdp"] = round(pvd, 4)
            item["lead_time_dias"] = lead_time

            # Mantenemos stock_minimo pre-calculado para compatibilidad con otras áreas
            stock_minimo_calc = math.ceil((pvd * 1.0 * lead_time) + (pvd * 3))
            item["stock_minimo"] = stock_minimo_calc
            if "min" in item: item["min"] = stock_minimo_calc
            if "Min" in item: item["Min"] = stock_minimo_calc

            if not primer_item_logueado:
                logger.info(f"[SALDOS_SERVICE] EJEMPLO INYECCIÓN -> Codigo: {codigo} | Ventas Hist.: {ventas_totales} | vdp Inyectado: {item['vdp']} | lead_time Inyectado: {item['lead_time_dias']}")
                primer_item_logueado = True

        logger.info("[SALDOS_SERVICE] Inyección completada con éxito.")
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