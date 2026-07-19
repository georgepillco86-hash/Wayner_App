from __future__ import annotations

from fastapi import APIRouter, Query, Request, Depends

from app.repositories.pedido_repository import PedidoRepository
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
from app.services.pedido_service import PedidoService
from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService


router = APIRouter(prefix="/pedidos", tags=["pedidos"])
service = PedidoService(PedidoRepository())
audit_service = AuditLogService(AuditLogRepository())


def registrar_log_negocio(
    request: Request,
    *,
    accion: str,
    modulo: str,
    detalle: str,
):
    usuario_id_raw = request.headers.get("x-user-id")
    usuario_id = int(usuario_id_raw) if usuario_id_raw and usuario_id_raw.isdigit() else None

    audit_service.create_log(
        usuario_id=usuario_id,
        nombre_usuario=request.headers.get("x-user-name"),
        rol=request.headers.get("x-user-role"),
        accion=accion,
        modulo=modulo,
        metodo=request.method,
        ruta=request.url.path,
        estado_http=200,
        detalle=detalle,
        ip=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )


def ok(data, message: str = "Operación exitosa"):
    return {"success": True, "message": message, "data": data}


@router.get("/productos/buscar")
def search_products_for_order(
    texto: str = Query(..., min_length=2, alias="q"),
    texto2: str | None = Query(default=None, alias="q2"),
    proveedor: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
):
    return ok(
        service.search_products(
            texto,
            text2=texto2,
            proveedor=proveedor,
            limit=limit,
        ),
        "Productos obtenidos para pedido",
    )


@router.get("/productos/{codigo}/proveedores")
def get_product_providers_for_order(codigo: str):
    return ok(
        service.get_product_providers(codigo),
        "Proveedores obtenidos para producto"
    )


@router.get("/productos/{codigo}/mejor-proveedor-precio")
def get_best_provider_price_for_product(
    codigo: str,
    meses: int = Query(default=6, ge=1, le=24),
):
    return ok(
        service.get_best_provider_price_for_product(codigo, meses=meses),
        "Mejor proveedor por precio obtenido exitosamente"
    )

@router.get("/productos/{codigo}/cantidad-recomendada")
def get_cantidad_recomendada_producto(codigo: str):
    return ok(
        service.get_cantidad_recomendada_producto(codigo),
        "Cantidad recomendada obtenida exitosamente",
    )

# 🔥 NUEVO ENDPOINT: Historial de Costos 🔥
@router.get("/producto/{codigo}/historial-costos")
def obtener_historial_costos(
    codigo: str, 
    meses: int = Query(default=5, ge=1, le=24),
):
    return ok(
        service.get_historial_costos(codigo, meses),
        "Historial de costos obtenido exitosamente"
    )

@router.get("/productos/{codigo}")
def get_product_for_order(codigo: str):
    return ok(service.get_product(codigo), "Producto obtenido para pedido")


@router.post("")
def create_order(payload: PedidoCreate, request: Request):
    data = service.create_order(payload)

    registrar_log_negocio(
        request,
        accion="PEDIDO_CREADO",
        modulo="PEDIDOS",
        detalle="Pedido creado como borrador",
    )

    return ok(data, "Pedido creado como borrador")


@router.get("")
def list_orders(limit: int = Query(default=50, ge=1, le=200)):
    return ok(service.list_orders(limit=limit), "Pedidos obtenidos exitosamente")


@router.get("/mis-pedidos")
def list_my_orders(
    usuario: str = Query(..., min_length=1),
    limit: int = Query(default=50, ge=1, le=200),
):
    return ok(
        service.list_orders_by_user(usuario, limit=limit),
        "Pedidos del usuario obtenidos exitosamente"
    )


@router.get("/admin")
def list_orders_admin(limit: int = Query(default=100, ge=1, le=300)):
    return ok(
        service.list_orders_admin(limit=limit),
        "Pedidos admin obtenidos exitosamente"
    )


@router.get("/bodega")
def list_orders_bodega(
    request: Request,
    limit: int = Query(default=100, ge=1, le=300),
):
    data = service.list_orders_bodega(limit=limit)

    registrar_log_negocio(
        request,
        accion="CONSULTA_PEDIDOS_BODEGA",
        modulo="BODEGA",
        detalle="Consulta de pedidos pendientes de recepción",
    )

    return ok(
        data,
        "Pedidos de bodega obtenidos exitosamente"
    )


@router.get("/{pedido_id}/admin-detalle")
def get_order_admin_detail(pedido_id: int):
    return ok(
        service.get_order_admin_detail(pedido_id),
        "Detalle admin del pedido obtenido exitosamente"
    )


@router.get("/{pedido_id}/bodega-detalle")
def get_order_bodega_detail(
    pedido_id: int,
    request: Request,
):
    data = service.get_order_bodega_detail(pedido_id)

    registrar_log_negocio(
        request,
        accion="CONSULTA_DETALLE_BODEGA",
        modulo="BODEGA",
        detalle=f"Consulta detalle recepción pedido #{pedido_id}",
    )

    return ok(
        data,
        "Detalle de recepción obtenido exitosamente"
    )


@router.get("/{pedido_id}/proveedores-grupo")
def get_order_grouped_by_provider(pedido_id: int):
    return ok(
        service.get_order_grouped_by_provider(pedido_id),
        "Pedido agrupado por proveedor obtenido exitosamente"
    )


@router.get("/{pedido_id}/proveedores-texto")
def get_order_provider_text(pedido_id: int):
    return ok(
        service.get_order_provider_text(pedido_id),
        "Texto por proveedor generado exitosamente"
    )


@router.get("/{pedido_id}/detalle-usuario")
def get_order_user_detail(pedido_id: int):
    return ok(
        service.get_order_user_detail(pedido_id),
        "Detalle del pedido obtenido exitosamente"
    )


@router.post("/{pedido_id}/items")
def add_item_to_order(pedido_id: int, payload: PedidoItemAdd, request: Request):
    data = service.add_item_to_order(pedido_id, payload)

    registrar_log_negocio(
        request,
        accion="ITEM_AGREGADO",
        modulo="CARRITO",
        detalle=f"Producto agregado al pedido #{pedido_id}",
    )

    return ok(data, "Producto agregado al pedido exitosamente")


@router.patch("/{pedido_id}/items/{item_id}/proveedor")
def update_order_item_provider(
    pedido_id: int,
    item_id: int,
    payload: PedidoItemProveedorUpdate,
    request: Request,
):
    data = service.update_item_provider(pedido_id, item_id, payload)

    registrar_log_negocio(
        request,
        accion="PROVEEDOR_CAMBIADO",
        modulo="CARRITO",
        detalle=f"Proveedor actualizado en pedido #{pedido_id}, item #{item_id}",
    )

    return ok(data, "Proveedor del producto actualizado exitosamente")


@router.patch("/{pedido_id}/items/{item_id}/nota")
def update_order_item_nota(
    pedido_id: int,
    item_id: int,
    payload: PedidoItemNotaUpdate,
):
    return ok(
        service.update_item_nota(pedido_id, item_id, payload),
        "Nota de compra actualizada exitosamente"
    )


@router.patch("/{pedido_id}/items/{item_id}")
def update_order_item_quantity(
    pedido_id: int,
    item_id: int,
    payload: PedidoItemCantidadUpdate,
):
    return ok(
        service.update_item_quantity(pedido_id, item_id, payload),
        "Cantidad del producto actualizada exitosamente"
    )


@router.delete("/{pedido_id}/items/{item_id}")
def delete_order_item(
    pedido_id: int,
    item_id: int,
    request: Request,
):
    data = service.delete_item_from_order(pedido_id, item_id)

    registrar_log_negocio(
        request,
        accion="ITEM_ELIMINADO",
        modulo="CARRITO",
        detalle=f"Item #{item_id} eliminado del pedido #{pedido_id}",
    )

    return ok(data, "Producto eliminado del pedido exitosamente")


@router.get("/{pedido_id}")
def get_order(pedido_id: int):
    return ok(service.get_order(pedido_id), "Pedido obtenido exitosamente")


@router.patch("/{pedido_id}/estado")
def update_order_status(pedido_id: int, payload: PedidoEstadoUpdate, request: Request):
    data = service.update_status(pedido_id, payload.estado)

    estado = str(payload.estado).upper()

    if estado == "ENVIADO":
        accion = "PEDIDO_ENVIADO"
    elif estado == "RECIBIDO":
        accion = "PEDIDO_RECIBIDO"
    elif estado == "CANCELADO":
        accion = "PEDIDO_CANCELADO"
    else:
        accion = "PEDIDO_ESTADO_ACTUALIZADO"

    registrar_log_negocio(
        request,
        accion=accion,
        modulo="PEDIDOS",
        detalle=f"Pedido #{pedido_id} cambiado a estado {estado}",
    )

    return ok(data, "Estado del pedido actualizado")


@router.get("/{pedido_id}/whatsapp-text")
def get_whatsapp_text(pedido_id: int):
    return ok(service.whatsapp_text(pedido_id), "Texto para WhatsApp generado exitosamente")


@router.patch("/{pedido_id}/items/{item_id}/unidad")
def update_order_item_unidad(
    pedido_id: int,
    item_id: int,
    payload: PedidoItemUnidadUpdate,
):
    return ok(
        service.update_item_unidad(pedido_id, item_id, payload),
        "Unidad del producto actualizada exitosamente"
    )


@router.patch("/{pedido_id}/items/{item_id}/tipo-destino")
def update_order_item_tipo_destino(
    pedido_id: int,
    item_id: int,
    payload: PedidoItemTipoDestinoUpdate,
    request: Request,
):
    data = service.update_item_tipo_destino(pedido_id, item_id, payload)

    registrar_log_negocio(
        request,
        accion="TIPO_DESTINO_CAMBIADO",
        modulo="CARRITO",
        detalle=f"Destino actualizado en pedido #{pedido_id}, item #{item_id}: {payload.tipo_destino}",
    )

    return ok(data, "Destino del producto actualizado exitosamente")


@router.patch("/{pedido_id}/items/{item_id}/recepcion")
def update_order_item_recepcion(
    pedido_id: int,
    item_id: int,
    payload: PedidoItemRecepcionUpdate,
    request: Request,
):
    data = service.update_item_recepcion(
        pedido_id=pedido_id,
        item_id=item_id,
        payload=payload,
        usuario_recepcion=request.headers.get("x-user-name"),
    )

    registrar_log_negocio(
        request,
        accion="ITEM_RECEPCION_ACTUALIZADA",
        modulo="BODEGA",
        detalle=(
            f"Recepción actualizada pedido #{pedido_id}, "
            f"item #{item_id}, recibido={payload.recibido}"
        ),
    )

    return ok(
        data,
        "Recepción del item actualizada exitosamente"
    )


@router.get("/{pedido_id}/novedades-recepcion-texto")
def generar_texto_novedades_recepcion(
    pedido_id: int,
    request: Request,
    proveedor: str | None = Query(default=None),
):
    data = service.generar_texto_novedades_recepcion(
        pedido_id=pedido_id,
        proveedor_filtro=proveedor,
    )

    registrar_log_negocio(
        request,
        accion="NOVEDADES_RECEPCION_GENERADAS",
        modulo="BODEGA",
        detalle=f"Texto de novedades generado para pedido #{pedido_id}",
    )

    return ok(
        data,
        "Texto de novedades generado exitosamente"
    )


@router.patch("/{pedido_id}/recibir")
def marcar_pedido_recibido(
    pedido_id: int,
    request: Request,
):
    data = service.marcar_pedido_recibido(pedido_id)

    registrar_log_negocio(
        request,
        accion="PEDIDO_RECIBIDO_BODEGA",
        modulo="BODEGA",
        detalle=f"Pedido #{pedido_id} marcado como recibido",
    )

    return ok(
        data,
        "Pedido marcado como recibido exitosamente"
    )

@router.get("/producto/{codigo}/mejor-costo")
def obtener_mejor_costo(codigo: str, meses: int = Query(default=3, ge=1, le=12)):
     return ok(service.repository.get_lowest_cost_provider(codigo, meses=meses), "Mejor costo")
