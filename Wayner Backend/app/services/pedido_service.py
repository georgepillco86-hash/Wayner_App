from __future__ import annotations

import logging
import math
from datetime import datetime, timedelta
from collections import defaultdict
from typing import Any

from app.core.exceptions import NotFoundError, ValidationError
from app.repositories.pedido_repository import PedidoRepository
# Importamos el ProductRepository para usar la consulta masiva del Kardex
from app.repositories.product_repository import ProductRepository
from app.schemas.pedido import (
    PedidoCreate,
    PedidoEstadoUpdate,
    PedidoItemAdd,
    PedidoItemCantidadUpdate,
    PedidoItemProveedorUpdate,
    PedidoItemNotaUpdate,
    PedidoItemUnidadUpdate,
    PedidoItemTipoDestinoUpdate,
    PedidoItemRecepcionUpdate,
)

# Inicializamos el logger
logger = logging.getLogger(__name__)


class PedidoService:
    def __init__(self, repository: PedidoRepository) -> None:
        self.repository = repository
        # Instanciamos el repo de productos para el cálculo de VDP
        self.product_repository = ProductRepository()

    @staticmethod
    def _validate_text(value: str, field_name: str) -> str:
        value = value.strip()
        if not value:
            raise ValidationError(f"{field_name} no puede estar vacío")
        return value

    @staticmethod
    def _normalizar_cantidad(cantidad: Any) -> Any:
        try:
            return int(float(cantidad))
        except Exception:
            return cantidad

    def _inyectar_vdp_dinamico(self, data: list[dict[str, Any]] | dict[str, Any] | None) -> list[dict[str, Any]] | dict[str, Any] | None:
        """
        Calcula el stock mínimo (VDP) dinámicamente para el listado de Pedidos.
        """
        if not data:
            return data

        is_dict = isinstance(data, dict)
        items = [data] if is_dict else data

        logger.info(f"[PEDIDO_SERVICE] Interceptando {len(items)} productos para inyectar VDP...")

        codigos_a_consultar = []
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo")
            if codigo and codigo not in codigos_a_consultar:
                codigos_a_consultar.append(codigo)

        hasta_date = datetime.now()
        desde_date = hasta_date - timedelta(days=30)
        desde_str = desde_date.strftime("%Y-%m-%d")
        hasta_str = hasta_date.strftime("%Y-%m-%d")

        ventas_bulk = {}
        if codigos_a_consultar:
            try:
                ventas_bulk = self.product_repository.get_ventas_en_bloque(
                    codigos=codigos_a_consultar,
                    desde=desde_str,
                    hasta=hasta_str
                )
            except Exception as e:
                logger.error(f"[PEDIDO_SERVICE] Error consultando bulk VDP: {e}")
                ventas_bulk = {}

        primer_log = False
        for item in items:
            codigo = item.get("codigo") or item.get("codigo_barra") or item.get("Codigo")
            ventas_totales = ventas_bulk.get(codigo, 0.0)

            dias_historial = 30
            pvd = ventas_totales / dias_historial if dias_historial > 0 else 0
            
            # Buscamos el lead time si viene de la DB, si no usamos 7 por defecto
            lead_time = int(item.get("lead_time_dias") or item.get("LeadTime") or 7)

            # Inyectamos en el JSON las variables que Flutter busca
            item["vdp"] = round(pvd, 4)
            item["lead_time_dias"] = lead_time

            stock_minimo_calc = math.ceil((pvd * 1.0 * lead_time) + (pvd * 3))
            item["stock_minimo"] = stock_minimo_calc
            if "min" in item: item["min"] = stock_minimo_calc
            if "Min" in item: item["Min"] = stock_minimo_calc

            if not primer_log:
                logger.info(f"[PEDIDO_SERVICE] OK! Ej: Codigo {codigo} | vdp={item.get('vdp', 0)} | min={item.get('Min', 0)}")
                primer_log = True

        return items[0] if is_dict else items

    def search_products(
        self,
        text: str,
        text2: str | None = None,
        proveedor: str | None = None,
        limit: int = 30,
    ) -> list[dict[str, Any]]:

        text = self._validate_text(text, "El texto de búsqueda")

        if len(text) < 2:
            raise ValidationError(
                "La búsqueda debe tener al menos 2 caracteres"
            )

        if text2:
            text2 = text2.strip()

        if proveedor:
            proveedor = proveedor.strip()

        # Obtenemos los productos crudos
        resultados = self.repository.search_products_for_order(
            text=text,
            text2=text2,
            proveedor=proveedor,
            limit=limit,
        )
        
        # INYECTAMOS EL CÁLCULO AQUÍ ANTES DE ENVIAR A FLUTTER
        return self._inyectar_vdp_dinamico(resultados)

    def get_product(self, codigo: str) -> dict[str, Any]:
        codigo = self._validate_text(codigo, "El código")
        product = self.repository.get_product_for_order(codigo)
        if not product:
            raise NotFoundError("Producto no encontrado para pedido")
            
        # INYECTAMOS TAMBIÉN EN EL PRODUCTO INDIVIDUAL
        return self._inyectar_vdp_dinamico(product)

    def create_order(self, payload: PedidoCreate) -> dict[str, Any]:
        pedido_id = self.repository.create_order(payload.usuario, payload.observacion)
        for input_item in payload.items:
            product = self.get_product(input_item.codigo)
            self.repository.add_order_item(
                pedido_id=pedido_id,
                item=product,
                cantidad=input_item.cantidad,
                unidad=input_item.unidad,
                nota_compra=input_item.nota_compra,
                tipo_destino=input_item.tipo_destino,
            )
        return self.get_order(pedido_id)

    def list_orders(self, limit: int = 50) -> list[dict[str, Any]]:
        return self.repository.list_orders(limit=limit)

    def get_order(self, pedido_id: int) -> dict[str, Any]:
        order = self.repository.get_order(pedido_id)
        if not order:
            raise NotFoundError("Pedido no encontrado")
        order["items"] = self.repository.get_order_items(pedido_id)
        return order

    def update_status(self, pedido_id: int, estado: str) -> dict[str, Any]:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        estado_actual = str(pedido.get("estado") or "").upper()
        nuevo_estado = str(estado or "").upper()

        estados_validos = {"BORRADOR", "ENVIADO", "RECIBIDO", "CANCELADO"}

        if nuevo_estado not in estados_validos:
            raise ValidationError("Estado no permitido")

        if estado_actual == nuevo_estado:
            return self.get_order(pedido_id)

        transiciones_validas = {
            "BORRADOR": {"ENVIADO", "CANCELADO"},
            "ENVIADO": {"RECIBIDO", "CANCELADO", "BORRADOR"},
            "RECIBIDO": {"BORRADOR"},
            "CANCELADO": {"BORRADOR"},
        }

        if nuevo_estado not in transiciones_validas.get(estado_actual, set()):
            raise ValidationError(
                f"No se puede cambiar el pedido de {estado_actual} a {nuevo_estado}"
            )

        self.repository.update_order_status(pedido_id, nuevo_estado)

        return self.get_order(pedido_id)

    def whatsapp_text(self, pedido_id: int) -> dict[str, Any]:
        order = self.get_order(pedido_id)
        grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)

        for item in order["items"]:
            proveedor = item.get("proveedor") or "SIN PROVEEDOR"
            grouped[proveedor].append(item)

        mensajes: list[dict[str, str]] = []

        for proveedor, items in grouped.items():
            lines = [
                "Hola, por favor ayudarme con el siguiente pedido:",
                "",
                f"Proveedor: {proveedor}",
                "",
            ]

            items_venta = [
                item for item in items
                if str(item.get("tipo_destino") or "VENTA").upper() == "VENTA"
            ]

            items_gasto = [
                item for item in items
                if str(item.get("tipo_destino") or "VENTA").upper() == "GASTO"
            ]

            def agregar_bloque(titulo: str, lista_items: list[dict[str, Any]]) -> None:
                if not lista_items:
                    return

                lines.append(titulo)
                lines.append("")

                current_marca = None

                for index, item in enumerate(lista_items, start=1):
                    marca = item.get("marca") or "SIN MARCA"

                    if marca != current_marca:
                        current_marca = marca
                        lines.append(f"Marca: {marca}")

                    cantidad = self._normalizar_cantidad(item.get("cantidad"))
                    unidad = item.get("unidad") or "UNIDADES"
                    nota_compra = item.get("nota_compra")

                    lines.extend(
                        [
                            f"{index}. {item.get('nombre')}",
                            f"   Código: {item.get('codigo')}",
                            f"   Cantidad: {cantidad} {unidad}",
                        ]
                    )

                    if nota_compra:
                        lines.append(f"   Nota de compra: {nota_compra}")

                    lines.append("")

            agregar_bloque("PRODUCTOS PARA VENTA:", items_venta)
            agregar_bloque("PRODUCTOS PARA GASTO / CONSUMO INTERNO:", items_gasto)

            lines.append("Gracias.")
            mensajes.append({"proveedor": proveedor, "mensaje": "\n".join(lines)})

        return {"pedido_id": pedido_id, "mensajes": mensajes}

    def get_product_providers(self, codigo: str) -> list[dict[str, Any]]:
        codigo = self._validate_text(codigo, "El código")

        product = self.repository.get_product_for_order(codigo)
        if not product:
            raise NotFoundError("Producto no encontrado para pedido")

        providers = self.repository.get_product_providers(codigo)

        if not providers:
            proveedor = product.get("proveedor") or "SIN PROVEEDOR"
            marca = product.get("marca") or "SIN MARCA"

            return [
                {
                    "proveedor": proveedor,
                    "marca": marca,
                }
            ]

        return providers

    def list_orders_by_user(self, usuario: str, limit: int = 50) -> list[dict[str, Any]]:
        usuario = self._validate_text(usuario, "El usuario")
        return self.repository.list_orders_by_user(usuario, limit=limit)

    def get_order_user_detail(self, pedido_id: int) -> dict:
        pedido = self.repository.get_order_user_detail(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        return pedido

    def list_orders_admin(self, limit: int = 100) -> list[dict]:
        return self.repository.list_orders_admin(limit=limit)

    def get_order_admin_detail(self, pedido_id: int) -> dict:
        pedido = self.repository.get_order_admin_detail(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        return pedido

    def get_order_grouped_by_provider(self, pedido_id: int) -> list[dict]:
        pedido = self.repository.get_order_admin_detail(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        return self.repository.get_order_grouped_by_provider(pedido_id)

    def get_order_provider_text(self, pedido_id: int) -> dict:
        pedido = self.repository.get_order_admin_detail(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        grupos = self.repository.get_order_grouped_by_provider(pedido_id)
        textos = []

        proveedor_excluido = "DUCHI SANCHEZ ROSA EMPERATRIZ"

        for grupo in grupos:
            proveedor_original = grupo["proveedor"].strip()
            proveedor = proveedor_original.upper()

            if proveedor == proveedor_excluido:
                continue

            items = grupo["items"]

            items_venta = [
                item for item in items
                if str(item.get("tipo_destino") or "VENTA").upper() == "VENTA"
            ]

            items_gasto = [
                item for item in items
                if str(item.get("tipo_destino") or "VENTA").upper() == "GASTO"
            ]

            lineas = []
            lineas.append("Hola, buen día.\n")
            lineas.append("Por favor ayudarme con el siguiente pedido:\n")

            def agregar_bloque_items(
                titulo: str,
                lista_items: list[dict[str, Any]],
            ) -> None:
                if not lista_items:
                    return

                lineas.append(titulo)
                lineas.append("")

                for item in lista_items:
                    lineas.append(f"- {item.get('nombre_producto')}")
                    lineas.append(f"  Código: {item.get('codigo_producto')}")

                    unidad = item.get("unidad") or "UNIDADES"
                    cantidad = self._normalizar_cantidad(
                        item.get("cantidad_pedida") or 0
                    )

                    lineas.append(f"  Cantidad: {cantidad} {unidad}")

                    nota_compra = item.get("nota_compra")
                    if nota_compra:
                        lineas.append(f"  Nota de compra: {nota_compra}")

                    lineas.append("")

            agregar_bloque_items("PRODUCTOS PARA VENTA:", items_venta)
            agregar_bloque_items(
                "PRODUCTOS PARA GASTO / CONSUMO INTERNO:",
                items_gasto,
            )

            lineas.append("Gracias.")

            texto = "\n".join(lineas)

            # 🔥 INYECCIÓN DE COSTOS PARA EL FRONTEND 🔥
            items_enriquecidos = []
            for item in items:
                costo_data = self.repository.get_lowest_cost_provider(
                    codigo=item.get('codigo_producto'), 
                    proveedor=proveedor_original, 
                    meses=3
                )
                
                item_dict = dict(item)
                if costo_data:
                    item_dict["costo_minimo"] = costo_data["costo_minimo"]
                    item_dict["tiene_iva"] = costo_data["tiene_iva"]
                else:
                    item_dict["costo_minimo"] = None
                    item_dict["tiene_iva"] = False
                    
                items_enriquecidos.append(item_dict)

            textos.append({
                "proveedor": proveedor_original,
                "texto": texto,
                "total_items": len(items),
                "total_venta": len(items_venta),
                "total_gasto": len(items_gasto),
                "items_detalle": items_enriquecidos
            })

        return {
            "pedido_id": pedido_id,
            "estado": pedido.get("estado"),
            "usuario": pedido.get("usuario"),
            "textos": textos,
        }

    def add_item_to_order(self, pedido_id: int, payload: PedidoItemAdd) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        product = self.repository.get_product_for_order(payload.codigo)

        if not product:
            raise NotFoundError("Producto no encontrado para pedido")

        item_id = self.repository.add_item_to_existing_order(
            pedido_id=pedido_id,
            item=product,
            cantidad=payload.cantidad,
            unidad=payload.unidad,
            nota_compra=payload.nota_compra,
            tipo_destino=payload.tipo_destino,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def update_item_quantity(
        self,
        pedido_id: int,
        item_id: int,
        payload: PedidoItemCantidadUpdate,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR   ":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        self.repository.update_order_item_quantity(
            pedido_id=pedido_id,
            item_id=item_id,
            cantidad=payload.cantidad,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def delete_item_from_order(
        self,
        pedido_id: int,
        item_id: int,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        self.repository.delete_order_item(
            pedido_id=pedido_id,
            item_id=item_id,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def get_best_provider_price_for_product(
        self,
        codigo: str,
        meses: int = 6,
    ) -> dict:
        codigo = self._validate_text(codigo, "El código")

        product = self.repository.get_product_for_order(codigo)

        if not product:
            raise NotFoundError("Producto no encontrado para pedido")

        return self.repository.get_best_provider_price_for_product(
            codigo=codigo,
            meses=meses,
        )

    def update_item_provider(
        self,
        pedido_id: int,
        item_id: int,
        payload: PedidoItemProveedorUpdate,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        self.repository.update_order_item_provider(
            pedido_id=pedido_id,
            item_id=item_id,
            proveedor_nombre=payload.proveedor,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def update_item_nota(
        self,
        pedido_id: int,
        item_id: int,
        payload: PedidoItemNotaUpdate,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        nota = payload.nota_compra.strip() if payload.nota_compra else None

        self.repository.update_order_item_nota(
            pedido_id=pedido_id,
            item_id=item_id,
            nota_compra=nota,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def update_item_unidad(
        self,
        pedido_id: int,
        item_id: int,
        payload: PedidoItemUnidadUpdate,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        self.repository.update_order_item_unidad(
            pedido_id=pedido_id,
            item_id=item_id,
            unidad=payload.unidad,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def update_item_tipo_destino(
        self,
        pedido_id: int,
        item_id: int,
        payload: PedidoItemTipoDestinoUpdate,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        if pedido.get("estado") != "BORRADOR":
            raise ValidationError("Solo se pueden modificar pedidos en estado BORRADOR")

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        self.repository.update_order_item_tipo_destino(
            pedido_id=pedido_id,
            item_id=item_id,
            tipo_destino=payload.tipo_destino,
        )

        pedido_actualizado = self.repository.get_order_admin_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def list_orders_bodega(self, limit: int = 100) -> list[dict]:
        return self.repository.list_orders_bodega(limit=limit)

    def get_order_bodega_detail(self, pedido_id: int) -> dict:
        pedido = self.repository.get_order_bodega_detail(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        items = pedido.get("items") or []

        grupos: dict[str, list[dict[str, Any]]] = defaultdict(list)

        for item in items:
            proveedor = item.get("proveedor") or "SIN PROVEEDOR"
            grupos[proveedor].append(item)

        pedido["proveedores"] = [
            {
                "proveedor": proveedor,
                "total_items": len(lista_items),
                "total_recibidos": len([
                    item for item in lista_items
                    if item.get("recibido") is True
                ]),
                "total_observaciones": len([
                    item for item in lista_items
                    if item.get("comentario_recepcion")
                ]),
                "items": lista_items,
            }
            for proveedor, lista_items in grupos.items()
        ]

        return pedido

    def update_item_recepcion(
        self,
        pedido_id: int,
        item_id: int,
        payload: PedidoItemRecepcionUpdate,
        usuario_recepcion: str | None = None,
    ) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        estado = str(pedido.get("estado") or "").upper()

        if estado != "ENVIADO":
            raise ValidationError(
                "Solo se puede modificar la recepción de pedidos en estado ENVIADO"
            )

        item = self.repository.get_order_item_by_id(pedido_id, item_id)

        if not item:
            raise NotFoundError("Item del pedido no encontrado")

        comentario = (
            payload.comentario_recepcion.strip()
            if payload.comentario_recepcion
            else None
        )

        self.repository.update_order_item_recepcion(
            pedido_id=pedido_id,
            item_id=item_id,
            recibido=payload.recibido,
            comentario_recepcion=comentario,
            usuario_recepcion=usuario_recepcion,
        )

        pedido_actualizado = self.get_order_bodega_detail(pedido_id)

        return {
            "item_id": item_id,
            "pedido": pedido_actualizado,
        }

    def generar_texto_novedades_recepcion(self, pedido_id: int, proveedor_filtro: str | None = None)  -> dict:
        pedido = self.get_order_bodega_detail(pedido_id)
        proveedores = pedido.get("proveedores") or []

        lineas: list[str] = [
            f"📦 *NOVEDADES DE RECEPCIÓN*",
            f"🧾 Pedido #{pedido_id}",
            "",
        ]

        tiene_novedades = False

        for grupo in proveedores:
            proveedor = grupo.get("proveedor") or "SIN PROVEEDOR"
            if proveedor_filtro and proveedor.strip().upper() != proveedor_filtro.strip().upper():
                continue
            items = grupo.get("items") or []

            no_recibidos = [
                item for item in items
                if item.get("recibido") is not True
            ]

            observados = [
                item for item in items
                if item.get("comentario_recepcion")
            ]

            if not no_recibidos and not observados:
                continue

            tiene_novedades = True

            lineas.append(f"🏢 *Proveedor:* {proveedor}")
            lineas.append("")

            # =========================
            # PRODUCTOS NO ENTREGADOS
            # =========================
            if no_recibidos:
                lineas.append("❌ *PRODUCTOS NO ENTREGADOS:*")
                lineas.append("")

                for item in no_recibidos:
                    cantidad = self._normalizar_cantidad(
                        item.get("cantidad_pedida") or 0
                    )

                    unidad = item.get("unidad") or "UNIDADES"

                    lineas.append(
                        f"• {item.get('nombre_producto')}"
                    )

                    lineas.append(
                        f"  Código: {item.get('codigo_producto')}"
                    )

                    lineas.append(
                        f"  Cantidad: {cantidad} {unidad}"
                    )

                    comentario = item.get("comentario_recepcion")

                    if comentario:
                        lineas.append(
                            f"  Observación: {comentario}"
                        )

                    lineas.append("")

            # =========================
            # PRODUCTOS OBSERVADOS
            # =========================
            productos_observados = [
                item for item in observados
                if item.get("recibido") is True
            ]

            if productos_observados:
                lineas.append("⚠️ *PRODUCTOS CON OBSERVACIÓN:*")
                lineas.append("")

                for item in productos_observados:
                    cantidad = self._normalizar_cantidad(
                        item.get("cantidad_pedida") or 0
                    )

                    unidad = item.get("unidad") or "UNIDADES"

                    lineas.append(
                        f"• {item.get('nombre_producto')}"
                    )

                    lineas.append(
                        f"  Código: {item.get('codigo_producto')}"
                    )

                    lineas.append(
                        f"  Cantidad: {cantidad} {unidad}"
                    )

                    lineas.append(
                        f"  Observación: {item.get('comentario_recepcion')}"
                    )

                    lineas.append("")

            lineas.append("────────────────────")
            lineas.append("")

        if not tiene_novedades:
            lineas.append(
                "✅ Todos los productos fueron recibidos correctamente."
            )

        else:
            lineas.extend([
                "Por favor revisar las novedades indicadas.",
                "",
                "Gracias."
            ])

        resumen = self.repository.get_order_recepcion_resumen(pedido_id)

        return {
            "pedido_id": pedido_id,
            "tiene_novedades": tiene_novedades,
            "resumen": resumen,
            "texto": "\n".join(lineas).strip(),
        }

    def marcar_pedido_recibido(self, pedido_id: int) -> dict:
        pedido = self.repository.get_order(pedido_id)

        if not pedido:
            raise NotFoundError("Pedido no encontrado")

        estado = str(pedido.get("estado") or "").upper()

        if estado != "ENVIADO":
            raise ValidationError(
                "Solo se pueden marcar como recibidos pedidos en estado ENVIADO"
            )

        resumen = self.repository.get_order_recepcion_resumen(pedido_id)

        if resumen["total_items"] <= 0:
            raise ValidationError("El pedido no tiene productos para recibir")

        if resumen["total_recibidos"] < resumen["total_items"]:
            raise ValidationError(
                "No se puede marcar como RECIBIDO. Existen productos pendientes de recepción"
            )

        self.repository.marcar_pedido_recibido(pedido_id)

        pedido_actualizado = self.get_order_bodega_detail(pedido_id)

        return {
            "pedido": pedido_actualizado,
            "resumen_recepcion": resumen,
        }

    def get_cantidad_recomendada_producto(
        self,
        codigo: str,
        dias_historial: int = 30,
        lead_time: int = 7,
        factor_estacionalidad: float = 1.0,
        dias_seguridad: int = 3
    ) -> dict:
        codigo = self._validate_text(codigo, "El código")

        product = self.repository.get_product_for_order(codigo)

        if not product:
            raise NotFoundError("Producto no encontrado para pedido")

        # 1. Obtener egresos históricos
        # Reemplazar la lectura estática anterior ('get_cantidad_recomendada_producto')
        # por una consulta de la suma de ventas en los últimos 'N' días.
        # NOTA: Debes asegurarte de implementar o ajustar este método en el PedidoRepository
        # para que retorne únicamente la suma total vendida en ese periodo (int o float).
        ventas_totales_periodo = self.repository.get_ventas_historicas_totales(
            codigo=codigo, 
            dias=dias_historial
        )

        # 2. Calcular PVD (Promedio de Ventas Diarias)
        pvd = ventas_totales_periodo / dias_historial if dias_historial > 0 else 0

        # 3. Calcular VDP Dinámico (Punto de Reorden)
        vdp_dinamico_float = ((pvd * factor_estacionalidad) * lead_time) + (pvd * dias_seguridad)
        vdp_dinamico = math.ceil(vdp_dinamico_float)

        # 4. Determinar la cantidad sugerida a pedir
        stock_actual = self._normalizar_cantidad(product.get("stock_actual") or 0)

        cantidad_a_pedir = 0
        if stock_actual <= vdp_dinamico:
            cantidad_a_pedir = vdp_dinamico - stock_actual

        return {
            "nombre": product.get("nombre"),
            "stock_actual": stock_actual,
            "stock_minimo_calculado": vdp_dinamico,
            "cantidad_recomendada": cantidad_a_pedir,
            "parametros_calculo": {
                "pvd": round(pvd, 2),
                "factor_estacionalidad": factor_estacionalidad,
                "lead_time": lead_time,
                "dias_seguridad": dias_seguridad
            }
        }
    
    def get_historial_costos(self, codigo: str, proveedor: str, meses: int = 5) -> list[dict]:
        codigo = self._validate_text(codigo, "El código")
        proveedor = self._validate_text(proveedor, "El proveedor")
        
        fecha_fin = datetime.now().date()
        fecha_inicio = self.repository._restar_meses(fecha_fin, meses)
        
        return self.repository.get_cost_history_provider(codigo, proveedor, fecha_inicio, fecha_fin)