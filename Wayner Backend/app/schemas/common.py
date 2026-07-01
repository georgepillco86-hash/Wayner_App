from datetime import datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


class ApiResponse(BaseModel, Generic[T]):
    success: bool = True
    message: str = "Operación exitosa"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    data: T


class Pagination(BaseModel):
    page: int
    page_size: int
    total: int
    returned: int
