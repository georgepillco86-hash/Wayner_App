from __future__ import annotations

import logging
import math
import time
from datetime import datetime, timedelta
from typing import Any

from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.product_repository import ProductRepository
from app.repositories.promocion_repository import PromocionRepository
from app.repositories.cronograma_repository import CronogramaRepository

# Inicializar logger
logger = logging.getLogger(__name__)

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
        self.cronograma_repo = CronogramaRepository() 

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

    @staticmethod
    def _calcular_estadistica_producto(ventas_diarias: list[dict[str, Any]], lead_time: int, dias_analisis: int) -> dict:
        """
        Motor matemático para VDP, Desviación Estándar y Punto de Reorden.
        ventas_diarias: [{'fecha': 'YYYY-MM-DD', 'cantidad': 2.0}, ...]
        """
        if not ventas_diarias:
            return {"vdp": 0.0, "desviacion": 0.0, "stock_seguridad": 0, "minimo": 0}

        # 1. Agrupar las ventas exactas por día (para identificar los ceros)
        mapa_ventas = {v["fecha"]: v["cantidad"] for v in ventas_diarias}
        
        serie_diaria = []
        fecha_fin = datetime.now()
        fecha_inicio = fecha_fin - timedelta(days=dias_analisis)

        # 2. Construir la serie de tiempo rellenando los días sin venta con 0
        for i in range(dias_analisis):
            dia_actual = (fecha_inicio + timedelta(days=i)).strftime("%Y-%m-%d")
            serie_diaria.append(mapa_ventas.get(dia_actual, 0.0))

        # 3. VDP Matemático
        vdp = sum(serie_diaria) / dias_analisis

        # 4. Volatilidad (Desviación Estándar)
        varianza = sum((x - vdp) ** 2 for x in serie_diaria) / dias_analisis
        desviacion_estandar = math.sqrt(varianza)

        # 5. Stock de Seguridad (Z = 1.65 para 95% de nivel de servicio)
        stock_seguridad = 1.65 * desviacion_estandar * math.sqrt(lead_time)

        # 6. Punto de Reorden Real
        minimo_sugerido = (vdp * lead_time) + stock_seguridad

        return {
            "vdp": round(vdp, 4),
            "desviacion": round(desviacion_estandar, 4),
            "stock_seguridad": math.ceil(stock_seguridad),
            "minimo": math.ceil(minimo_sugerido)
        }

    def _inyectar_vdp_dinamico(self, data: list[dict[str, Any]] | dict[str, Any] | None) -> list[dict[str, Any]] | dict[str, Any] | None:
        """
        Calcula el stock mínimo estadístico cruzando la volatilidad de ventas 
        con los tiempos de entrega del cronograma de proveedores.
        """
        if not data:
            logger.warning("[PRODUCT_SERVICE] _inyectar_vdp_dinamico recibió data vacía.")
            return data

        is_dict = isinstance(data, dict)
        items = [data] if is_dict else data

        logger.info(f"[PRODUCT_SERVICE] Iniciando cálculo estadístico para {len(items)} productos.")

        # 1. Extraer códigos y proveedores únicos
        codigos_a_consultar = []
        proveedores_a_consultar = set()
        
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo") or item.get("CodigoBarra")
            
            # ---> CORRECCIÓN CLAVE: Capturar todas las formas posibles de 'Proveedor' <---
            proveedor = item.get("proveedor") or item.get("Proveedor") or item.get("NombreProveedor") or item.get("proveedor_nombre")
            
            if codigo and codigo not in codigos_a_consultar:
                codigos_a_consultar.append(codigo)
            if proveedor:
                proveedores_a_consultar.add(proveedor)

        # 2. Definir ventana de análisis (ej: 45 días para capturar estacionalidad mensual)
        dias_analisis = 45
        hasta_date = datetime.now()
        desde_date = hasta_date - timedelta(days=dias_analisis)
        desde_str = desde_date.strftime("%Y-%m-%d")
        hasta_str = hasta_date.strftime("%Y-%m-%d")

        # 3. Consultas en bloque (Base de datos)
        ventas_bulk = {}
        lead_times_bulk = {}

        try:
            ventas_bulk = self.repository.get_ventas_diarias_en_bloque(
                codigos=codigos_a_consultar,
                desde=desde_str,
                hasta=hasta_str
            )
            
            for prov in proveedores_a_consultar:
                lead_times_bulk[prov] = self.cronograma_repo.obtener_lead_time_proveedor(prov)

        except Exception as e:
            logger.error(f"[PRODUCT_SERVICE] Falló la extracción bulk de datos: {str(e)}")

        primer_item_logueado = False

        # 4. Motor de Inyección
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo") or item.get("CodigoBarra") or ""
            
            # ---> CORRECCIÓN CLAVE: Re-aplicar la extracción exhaustiva en el mapeo <---
            proveedor = item.get("proveedor") or item.get("Proveedor") or item.get("NombreProveedor") or item.get("proveedor_nombre")
            
            ventas_diarias_producto = ventas_bulk.get(codigo, [])
            
            if not proveedor:
                lead_time_real = 2  
                item["alerta_lead_time"] = True
                item["mensaje_alerta"] = "No hay proveedor asignado. Cálculo estimado a 2 días."
                item["proveedor_objetivo"] = None
            else:
                lead_time_db = lead_times_bulk.get(proveedor)
                if lead_time_db is None:
                    lead_time_real = 2  
                    item["alerta_lead_time"] = True
                    item["mensaje_alerta"] = f"No hay cronograma para {proveedor}. Cálculo estimado a 2 días."
                    item["proveedor_objetivo"] = proveedor
                else:
                    lead_time_real = lead_time_db
                    item["alerta_lead_time"] = False
                    item["mensaje_alerta"] = ""
                    item["proveedor_objetivo"] = None

            # Ejecutar Matemática
            estadistica = self._calcular_estadistica_producto(
                ventas_diarias=ventas_diarias_producto,
                lead_time=lead_time_real,
                dias_analisis=dias_analisis
            )

            # ==========================================
            # INYECCIÓN PARA FLUTTER
            # ==========================================
            item["vdp"] = estadistica["vdp"]
            item["lead_time_dias"] = lead_time_real
            item["volatilidad"] = estadistica["desviacion"]
            item["stock_seguridad"] = estadistica["stock_seguridad"]
            
            # El Mínimo unificado
            item["stock_minimo"] = estadistica["minimo"]
            if "min" in item: item["min"] = estadistica["minimo"]
            if "Min" in item: item["Min"] = estadistica["minimo"]
            if "stock_estimado_minimo" in item: item["stock_estimado_minimo"] = estadistica["minimo"]

            if not primer_item_logueado:
                logger.info(f"📊 [ESTADÍSTICA] {codigo} -> VDP: {estadistica['vdp']} | SS: {estadistica['stock_seguridad']} | LTime: {lead_time_real} | MÍN: {estadistica['minimo']}")
                primer_item_logueado = True

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