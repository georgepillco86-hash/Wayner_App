from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


class ProductSummary(BaseModel):
    codigo_barra: str = Field(alias="CodigoBarra")
    codigo: str = Field(alias="Codigo")
    nombre_producto: str = Field(alias="NombreProducto")
    precio: Decimal = Field(alias="Precio")
    iva: Decimal = Field(alias="IVA")
    precio_con_iva: Decimal = Field(alias="PrecioConIVA")


class ProductStock(BaseModel):
    codigo_barra: str = Field(alias="CodigoBarra")
    codigo: str = Field(alias="Codigo")
    nombre_producto: str = Field(alias="NombreProducto")
    total_ingreso: Decimal = Field(alias="TotalIngreso")
    total_egreso: Decimal = Field(alias="TotalEgreso")
    stock_estimado: Decimal = Field(alias="StockEstimado")
    precio_actual_ref: Decimal = Field(alias="PrecioActualRef")
    iva: Decimal = Field(alias="IVA")
    precio_con_iva: Decimal = Field(alias="PrecioConIVA")


class ProductHistoryItem(BaseModel):
    fecha: date = Field(alias="Fecha")
    documento: Optional[str] = Field(default=None, alias="Documento")
    nombre_documento: str = Field(alias="NombreDocumento")
    precio: Decimal = Field(alias="Precio")
    iva: Decimal = Field(alias="IVA")
    costo: Decimal = Field(alias="Costo")
    ingreso: Decimal = Field(alias="Ingreso")
    egreso: Decimal = Field(alias="Egreso")
    valor_ingreso: Decimal = Field(alias="ValorIngreso")
    valor_egreso: Decimal = Field(alias="ValorEgreso")
    factura: Optional[str] = Field(default=None, alias="Factura")
    nombre_proveedor: Optional[str] = Field(default=None, alias="NombreProveedor")


class ProductDetail(BaseModel):
    producto: ProductSummary
    stock: Optional[ProductStock] = None
    ultimo_movimiento: Optional[ProductHistoryItem] = None


class HealthResponse(BaseModel):
    app_name: str
    environment: str
    database: str
    server_time: datetime
    remote_source: str


class CatalogStats(BaseModel):
    total_registros: int
    total_productos: int
    total_codigos: int
