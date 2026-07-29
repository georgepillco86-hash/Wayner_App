from __future__ import annotations
import xml.etree.ElementTree as ET
import re
import html  # 🔥 NUEVO IMPORT: Para traducir los &lt; a <
from datetime import datetime

from fastapi import APIRouter, Query, Request, Depends, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from typing import Dict

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
    DocumentoSRICreate,
)
from app.services.pedido_service import PedidoService
from app.repositories.audit_log_repository import AuditLogRepository
from app.services.audit_log_service import AuditLogService


class XMLPayload(BaseModel):
    xml_data: str
    proveedor_orden: str

class NotificarProveedorPayload(BaseModel):
    proveedor: str

# ==========================================
# 🔥 GESTOR DE WEBSOCKETS (FLUTTER <-> RPA)
# ==========================================
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[int, WebSocket] = {}

    async def connect(self, websocket: WebSocket, pedido_id: int):
        await websocket.accept()
        self.active_connections[pedido_id] = websocket

    def disconnect(self, pedido_id: int):
        if pedido_id in self.active_connections:
            del self.active_connections[pedido_id]

    async def send_json_to_client(self, pedido_id: int, message: dict):
        if pedido_id in self.active_connections:
            websocket = self.active_connections[pedido_id]
            await websocket.send_json(message)

manager = ConnectionManager()

class NotificacionRPA(BaseModel):
    estado: str
    mensaje: str
    documento_id: int | None = None

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


@router.patch("/{pedido_id}/notificar-proveedor")
def notificar_envio_proveedor(
    pedido_id: int,
    payload: NotificarProveedorPayload,
    request: Request,
):
    data = service.notificar_envio_proveedor(pedido_id, payload.proveedor)

    registrar_log_negocio(
        request,
        accion="PROVEEDOR_NOTIFICADO",
        modulo="PEDIDOS",
        detalle=f"Proveedor '{payload.proveedor}' notificado para pedido #{pedido_id}",
    )

    return ok(data, "Proveedor notificado exitosamente")


# ==========================================
# 🔥 NUEVOS ENDPOINTS: INTEGRACIÓN RPA (SRI) 🔥
# ==========================================

@router.post("/{pedido_id}/sri-clave")
def registrar_clave_sri(
    pedido_id: int,
    payload: DocumentoSRICreate,
    request: Request,
):
    data = service.registrar_documento_sri(pedido_id, payload)

    registrar_log_negocio(
        request,
        accion="CLAVE_SRI_REGISTRADA",
        modulo="RECEPCION",
        detalle=f"Clave de acceso enviada a RPA para pedido #{pedido_id}, proveedor: {payload.proveedor}",
    )
    return ok(data, "Clave SRI registrada para procesamiento")


@router.get("/rpa/tareas-pendientes")
def obtener_tareas_rpa():
    data = service.obtener_tareas_rpa_pendientes()
    return ok(data, "Tareas pendientes obtenidas")


@router.get("/rpa/estado-actual/{documento_id}")
async def obtener_estado_actual(documento_id: int):
    """Permite al bot RPA consultar qué botón presionó el bodeguero en Flutter."""
    try:
        estado = service.consultar_estado_rpa(documento_id)
        return {"estado": estado}
    except Exception as e:
        print(f"Error en router al consultar estado actual: {e}")
        return {"estado": "ERROR"}
    

@router.websocket("/rpa/ws/{pedido_id}")
async def websocket_rpa(websocket: WebSocket, pedido_id: int):
    await manager.connect(websocket, pedido_id)
    try:
        while True:
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(pedido_id)


@router.patch("/rpa/notificar-estado/{documento_id}")
async def notificar_estado_rpa(documento_id: int, payload: NotificacionRPA):
    pedido_id = service.actualizar_estado_rpa(documento_id, payload.estado, payload.mensaje)
    
    if pedido_id:
        datos_ws = payload.dict()
        datos_ws["documento_id"] = documento_id 
        await manager.send_json_to_client(pedido_id, datos_ws)
        
    return ok(None, "Estado actualizado en BD y notificación push enviada a Flutter")

@router.patch("/rpa/completar/{documento_id}")
async def completar_tarea_rpa(documento_id: int):
    pedido_id = service.actualizar_estado_rpa(documento_id, "EXITO", "Factura guardada correctamente en BITS.")
    if pedido_id:
        await manager.send_json_to_client(pedido_id, {"estado": "EXITO", "mensaje": "Factura guardada correctamente en BITS."})
    return ok(None, "Tarea RPA completada exitosamente en BD")


@router.patch("/rpa/error/{documento_id}")
async def error_tarea_rpa(documento_id: int, payload: NotificacionRPA):
    pedido_id = service.actualizar_estado_rpa(documento_id, payload.estado, payload.mensaje)
    
    if pedido_id:
        datos_ws = payload.dict()
        datos_ws["documento_id"] = documento_id
        await manager.send_json_to_client(pedido_id, datos_ws)
        
    return ok(None, "Error registrado en base de datos")

@router.post("/rpa/subir-xml/{documento_id}")
async def procesar_y_validar_xml(documento_id: int, payload: XMLPayload):
    xml_string = payload.xml_data
    validaciones = []
    con_errores = False

    # 1. EJECUTAR EL GUARDADO EN POSTGRESQL
    service.guardar_xml_rpa(documento_id, xml_string)
    
    try:
        # Extraer la <fechaAutorizacion> del sobre principal
        match_fecha = re.search(r'<fechaAutorizacion[^>]*>(.*?)</fechaAutorizacion>', xml_string, re.DOTALL)
        fecha_xml_raw = match_fecha.group(1).strip() if match_fecha else ""

        # 🔥 LA SOLUCIÓN: Si la factura viene dentro de <comprobante>, traducimos los caracteres "escapados" (&lt;) a reales (<)
        match_comprobante = re.search(r'<comprobante>(.*?)</comprobante>', xml_string, re.DOTALL)
        if match_comprobante:
            xml_string = html.unescape(match_comprobante.group(1))
        elif "<![CDATA[" in xml_string:
            match_cdata = re.search(r'<!\[CDATA\[(.*?)\]\]>', xml_string, re.DOTALL)
            if match_cdata:
                xml_string = match_cdata.group(1)
        else:
            xml_string = html.unescape(xml_string)
                
        # Ahora que el XML es XML real, las expresiones regulares encontrarán la información de inmediato
        match_emisor = re.search(r'<(?:[^>:]+:)?razonSocial[^>]*>(.*?)</(?:[^>:]+:)?razonSocial>', xml_string, re.DOTALL)
        emisor_xml = match_emisor.group(1).strip() if match_emisor else "(No encontrado)"
        
        match_cliente = re.search(r'<(?:[^>:]+:)?razonSocialComprador[^>]*>(.*?)</(?:[^>:]+:)?razonSocialComprador>', xml_string, re.DOTALL)
        cliente_xml = match_cliente.group(1).strip() if match_cliente else "(No encontrado)"
        
        match_ruc = re.search(r'<(?:[^>:]+:)?identificacionComprador[^>]*>(.*?)</(?:[^>:]+:)?identificacionComprador>', xml_string, re.DOTALL)
        ruc_xml = match_ruc.group(1).strip() if match_ruc else "(No encontrado)"
        
        # ==========================================
        # REGLA 1: Proveedor (<razonSocial>)
        # ==========================================
        proveedor_orden = payload.proveedor_orden.upper().strip()
        if emisor_xml == "(No encontrado)":
            validaciones.append({"paso": "Validar Proveedor", "estado": "ERROR", "detalle": f"Esperado: {proveedor_orden}\nXML: (No encontrado)"})
            con_errores = True
        elif proveedor_orden not in emisor_xml.upper() and emisor_xml.upper() not in proveedor_orden:
            validaciones.append({"paso": "Validar Proveedor", "estado": "ERROR", "detalle": f"Esperado: {proveedor_orden}\nXML: {emisor_xml}"})
            con_errores = True
        else:
            validaciones.append({"paso": "Validar Proveedor", "estado": "OK", "detalle": f"Esperado: {proveedor_orden}\nXML: {emisor_xml}"})
            
        # ==========================================
        # REGLA 2: Cliente (<razonSocialComprador>)
        # ==========================================
        nombres_permitidos = ["DUCHI SANCHEZ ROSA EMPERATRIZ", "ROSA DUCHI SANCHEZ", "ROSA DUCHI"]
        if cliente_xml.upper() not in nombres_permitidos:
            validaciones.append({"paso": "Validar Cliente", "estado": "ERROR", "detalle": f"Esperado: ROSA DUCHI...\nXML: {cliente_xml}"})
            con_errores = True
        else:
            validaciones.append({"paso": "Validar Cliente", "estado": "OK", "detalle": f"Esperado: ROSA DUCHI...\nXML: {cliente_xml}"})
            
        # ==========================================
        # REGLA 3: RUC (<identificacionComprador>)
        # ==========================================
        if ruc_xml != "0102249976001":
            validaciones.append({"paso": "Validar RUC", "estado": "ERROR", "detalle": f"Esperado: 0102249976001\nXML: {ruc_xml}"})
            con_errores = True
        else:
            validaciones.append({"paso": "Validar RUC", "estado": "OK", "detalle": f"Esperado: 0102249976001\nXML: {ruc_xml}"})
            
        # ==========================================
        # REGLA 4: Fecha (<fechaAutorizacion> del mes actual)
        # ==========================================
        hoy = datetime.now()
        if not fecha_xml_raw:
            validaciones.append({"paso": "Validar Fecha", "estado": "ERROR", "detalle": f"Esperado: Mes {hoy.month}/{hoy.year}\nXML: (Sin <fechaAutorizacion>)"})
            con_errores = True
        else:
            try:
                es_valida = False
                m1 = re.search(r'(20\d{2})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])', fecha_xml_raw)
                m2 = re.search(r'(0[1-9]|[12]\d|3[01])/(0[1-9]|1[0-2])/(20\d{2})', fecha_xml_raw)
                
                anio_xml = mes_xml = None
                if m1:
                    anio_xml, mes_xml = int(m1.group(1)), int(m1.group(2))
                elif m2:
                    anio_xml, mes_xml = int(m2.group(3)), int(m2.group(2))
                
                if anio_xml == hoy.year and mes_xml == hoy.month:
                    es_valida = True
                    
                fecha_mostrar = fecha_xml_raw[:10]
                if not es_valida:
                    validaciones.append({"paso": "Validar Fecha", "estado": "ERROR", "detalle": f"Esperado: Mes {hoy.month}/{hoy.year}\nXML: {fecha_mostrar}"})
                    con_errores = True
                else:
                    validaciones.append({"paso": "Validar Fecha", "estado": "OK", "detalle": f"Esperado: Mes {hoy.month}/{hoy.year}\nXML: {fecha_mostrar}"})
            except Exception:
                validaciones.append({"paso": "Validar Fecha", "estado": "ERROR", "detalle": f"Esperado: Fecha Válida\nXML: {fecha_xml_raw[:10]}"})
                con_errores = True

    except Exception as e:
        validaciones.append({"paso": "Lectura Estructural", "estado": "ERROR", "detalle": f"XML dañado o irreconocible.\nError: {str(e)[:50]}"})
        con_errores = True

    pedido_id = service.actualizar_estado_rpa(documento_id, "VALIDANDO", "Mostrando reporte de validación...")

    if pedido_id:
        await manager.send_json_to_client(pedido_id, {
            "estado": "REPORTE_VALIDACION",
            "mensaje": "Revisión completada",
            "validaciones": validaciones,
            "con_errores": con_errores,
            "documento_id": documento_id
        })
            
    return ok(None, "Validación completada")


@router.patch("/rpa/forzar-exito/{documento_id}")
async def forzar_exito_rpa(documento_id: int):
    pedido_id = service.actualizar_estado_rpa(documento_id, "EXITO", "Guardado forzado por el usuario.")
    if pedido_id:
        await manager.send_json_to_client(pedido_id, {
            "estado": "EXITO",
            "mensaje": "Guardado forzado aceptado."
        })
    return ok(None)

@router.get("/rpa/comparar-xml-orden/{documento_id}")
async def comparar_xml_vs_orden(documento_id: int):
    doc = service.repository.get_documento_sri(documento_id)
    if not doc or not doc.get("xml_data"):
        return ok({"error": "No se encontró el documento o el XML no está guardado"}, "Error")

    pedido_id = doc["pedido_id"]
    items_orden = service.repository.get_order_items(pedido_id)
    
    xml_string = doc["xml_data"]
    
    # 🔥 Mantenemos la lógica de decodificación aquí para que la pantalla del escáner no falle
    match_comprobante = re.search(r'<comprobante>(.*?)</comprobante>', xml_string, re.DOTALL)
    if match_comprobante:
        xml_string = html.unescape(match_comprobante.group(1))
    elif "<![CDATA[" in xml_string:
        match_cdata = re.search(r'<!\[CDATA\[(.*?)\]\]>', xml_string, re.DOTALL)
        if match_cdata:
            xml_string = match_cdata.group(1)
    else:
        xml_string = html.unescape(xml_string)
            
    # Limpiar namespaces que rompen ElementTree
    xml_string = re.sub(r'\sxmlns="[^"]+"', '', xml_string)
            
    try:
        root = ET.fromstring(xml_string)
    except Exception as e:
        return ok({"error": f"Error al leer la estructura del XML: {e}"}, "Error")

    detalles = root.find('detalles')
    items_xml = []
    
    if detalles is not None:
        for detalle in detalles.findall('detalle'):
            codigo = detalle.find('codigoPrincipal')
            descripcion = detalle.find('descripcion')
            cantidad = detalle.find('cantidad')
            
            items_xml.append({
                "codigo_xml": codigo.text if codigo is not None else "SIN_CODIGO",
                "descripcion_xml": descripcion.text if descripcion is not None else "SIN DESCRIPCION",
                "cantidad_xml": float(cantidad.text) if cantidad is not None else 0.0,
            })

    resultado_orden = []
    
    for item in items_orden:
        resultado_orden.append({
            "item_id": item["id"],
            "codigo_producto": item["codigo"],
            "nombre_producto": item["nombre"],
            "cantidad_pedida": float(item["cantidad"] or 0.0),
            "cantidad_xml": 0.0,
            "cantidad_escaneada": 0,
            "coincidencia_xml": False,
            "descripcion_facturada": None
        })
        
    items_extra_facturados = []

    for facturado in items_xml:
        match_encontrado = False
        
        for esperado in resultado_orden:
            if not esperado["coincidencia_xml"]:
                if (facturado["codigo_xml"] == esperado["codigo_producto"]) or \
                   (esperado["nombre_producto"].upper()[:8] in facturado["descripcion_xml"].upper()):
                    
                    esperado["cantidad_xml"] = facturado["cantidad_xml"]
                    esperado["coincidencia_xml"] = True
                    esperado["descripcion_facturada"] = facturado["descripcion_xml"]
                    match_encontrado = True
                    break
                    
        if not match_encontrado:
            items_extra_facturados.append(facturado)

    return ok({
        "pedido_id": pedido_id,
        "documento_id": documento_id,
        "proveedor": doc["proveedor"],
        "items_esperados": resultado_orden,
        "items_no_solicitados": items_extra_facturados
    }, "Comparación exitosa")