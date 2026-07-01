from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, field_validator

PedidoEstado = Literal["BORRADOR", "ENVIADO", "RECIBIDO", "CANCELADO"]
TipoDestino = Literal["VENTA", "GASTO"]


def normalizar_tipo_destino(value: str | None) -> str:
    value = (value or "VENTA").strip().upper()
    if value not in {"VENTA", "GASTO"}:
        raise ValueError("tipo_destino debe ser VENTA o GASTO")
    return value


class PedidoItemCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    codigo: str = Field(
        ...,
        min_length=1,
        max_length=80,
        validation_alias=AliasChoices("codigo", "codigo_producto"),
    )
    cantidad: Decimal = Field(
        ...,
        gt=0,
        validation_alias=AliasChoices("cantidad", "cantidad_pedida"),
    )
    unidad: str | None = Field(default=None, max_length=50)
    nota_compra: str | None = Field(default=None, max_length=500)
    tipo_destino: TipoDestino = Field(default="VENTA")

    @field_validator("codigo")
    @classmethod
    def clean_codigo(cls, value: str) -> str:
        return value.strip()

    @field_validator("unidad")
    @classmethod
    def clean_unidad(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip().upper()
        return value or None

    @field_validator("tipo_destino", mode="before")
    @classmethod
    def clean_tipo_destino(cls, value: str | None) -> str:
        return normalizar_tipo_destino(value)


class PedidoCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    usuario: str | None = Field(
        default=None,
        max_length=120,
        validation_alias=AliasChoices("usuario", "usuario_creacion"),
    )
    observacion: str | None = Field(default=None, max_length=500)
    items: list[PedidoItemCreate] = Field(..., min_length=1)


class PedidoEstadoUpdate(BaseModel):
    estado: PedidoEstado


class PedidoItemResponse(BaseModel):
    id: int
    codigo: str
    nombre: str
    marca: str | None = None
    clase: str | None = None
    proveedor: str | None = None
    stock_actual: Decimal | None = None
    cantidad: Decimal
    unidad: str | None = None
    nota_compra: str | None = None
    tipo_destino: TipoDestino = "VENTA"

    recibido: bool = False
    comentario_recepcion: str | None = None
    fecha_recepcion_item: datetime | None = None
    usuario_recepcion: str | None = None


class PedidoResponse(BaseModel):
    id: int
    estado: PedidoEstado
    usuario: str | None = None
    observacion: str | None = None
    fecha_creacion: datetime
    fecha_actualizacion: datetime | None = None
    items: list[PedidoItemResponse] = []


class PedidoItemAdd(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    codigo: str = Field(
        ...,
        min_length=1,
        max_length=80,
        validation_alias=AliasChoices("codigo", "codigo_producto"),
    )
    cantidad: Decimal = Field(
        ...,
        gt=0,
        validation_alias=AliasChoices("cantidad", "cantidad_pedida"),
    )
    unidad: str | None = Field(default=None, max_length=50)
    nota_compra: str | None = Field(default=None, max_length=500)
    tipo_destino: TipoDestino = Field(default="VENTA")

    @field_validator("codigo")
    @classmethod
    def clean_codigo(cls, value: str) -> str:
        return value.strip()

    @field_validator("unidad")
    @classmethod
    def clean_unidad(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip().upper()
        return value or None

    @field_validator("tipo_destino", mode="before")
    @classmethod
    def clean_tipo_destino(cls, value: str | None) -> str:
        return normalizar_tipo_destino(value)


class PedidoItemCantidadUpdate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    cantidad: Decimal = Field(
        ...,
        gt=0,
        validation_alias=AliasChoices("cantidad", "cantidad_pedida"),
    )


class PedidoItemProveedorUpdate(BaseModel):
    proveedor: str = Field(..., min_length=1, max_length=200)

    @field_validator("proveedor")
    @classmethod
    def clean_proveedor(cls, value: str) -> str:
        return value.strip()


class PedidoItemNotaUpdate(BaseModel):
    nota_compra: str | None = Field(default=None, max_length=500)


class PedidoItemUnidadUpdate(BaseModel):
    unidad: str | None = Field(default=None, max_length=50)

    @field_validator("unidad")
    @classmethod
    def clean_unidad(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip().upper()
        return value or None


class PedidoItemTipoDestinoUpdate(BaseModel):
    tipo_destino: TipoDestino = Field(default="VENTA")

    @field_validator("tipo_destino", mode="before")
    @classmethod
    def clean_tipo_destino(cls, value: str | None) -> str:
        return normalizar_tipo_destino(value)


class PedidoItemRecepcionUpdate(BaseModel):
    recibido: bool = Field(default=False)
    comentario_recepcion: str | None = Field(default=None, max_length=1000)

    @field_validator("comentario_recepcion")
    @classmethod
    def clean_comentario_recepcion(cls, value: str | None) -> str | None:
        if value is None:
            return None

        value = value.strip()
        return value or None