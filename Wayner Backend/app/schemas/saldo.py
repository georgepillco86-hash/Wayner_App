from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


class SaldoProduct(BaseModel):
    codigo: str = Field(alias="Codigo")
    nombre: str = Field(alias="Nombre")
    stock: Decimal = Field(alias="Stock")
    marca: Optional[str] = Field(default=None, alias="Marca")
    categoria: Optional[str] = Field(default=None, alias="Categoria")
    clase: Optional[str] = Field(default=None, alias="Clase")


class SaldoSummary(BaseModel):
    total_registros: int
    total_productos: int
    total_categorias: int
    total_clases: int
    stock_total: Decimal
