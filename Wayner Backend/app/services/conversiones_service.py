from __future__ import annotations
import json  # 🔥 IMPORTANTE: Agregamos json para convertir la lista
from typing import Any
from app.repositories.conversiones_repository import ConversionesRepository
from app.core.exceptions import NotFoundError, ValidationError

class ConversionesService:
    def __init__(self) -> None:
        self.repository = ConversionesRepository()

    def listar_requerimientos(self) -> list[dict[str, Any]]:
        return self.repository.listar_requerimientos()

    def crear_orden_trabajo(self, items: list[dict], usuario: str) -> dict[str, Any]:
        if not items: raise ValidationError("Debe enviar al menos un producto")
        orden_trabajo = self.repository.get_next_orden_trabajo()
        for item in items:
            req_id = self.repository.crear_requerimiento_item(
                orden=orden_trabajo,
                cod_destino=item["codigo_destino"],
                nom_destino=item["nombre_destino"],
                cant_destino=item["cantidad_destino"]
            )
            self.repository.registrar_historial(req_id, usuario, f"Creado en Orden {orden_trabajo}")
        return {"orden_trabajo": orden_trabajo, "total_items": len(items)}

    def ejecutar_conversion(self, req_id: int, payload: dict, usuario: str) -> dict[str, Any]:
        actividad_completa = payload.get("actividad_completa", False)
        estado = "PESADO" if actividad_completa else "PENDIENTE"
        porcentaje = 100 if actividad_completa else payload.get("porcentaje", 0)
        
        # 🔥 Cambiamos a la nueva estructura: origenes en JSON y usuario de ejecución
        datos_update = {
            "origenes_json": json.dumps(payload.get("origenes", [])),
            "cantidad_destino": payload.get("cantidad_destino"),
            "porcentaje_avance": porcentaje,
            "fecha_estimada_fin": payload.get("fecha_estimada"),
            "estado": estado,
            "usuario_ejecucion": payload.get("usuario_ejecucion", usuario)
        }

        self.repository.ejecutar_conversion(req_id, datos_update)
        accion_str = f"Actualizó avance al {porcentaje}% con múltiples orígenes"
        self.repository.registrar_historial(req_id, usuario, accion_str)
        return self.repository.get_requerimiento(req_id)