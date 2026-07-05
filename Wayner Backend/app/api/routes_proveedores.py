from fastapi import APIRouter
from app.repositories.proveedor_repository import ProveedorRepository

router = APIRouter()
proveedor_repo = ProveedorRepository()

@router.get("/")
async def listar_proveedores():
    proveedores = proveedor_repo.get_proveedores_list()
    return proveedores

@router.get("/{nombre_proveedor}/productos")
async def listar_productos_proveedor(nombre_proveedor: str):
    productos = proveedor_repo.get_productos_por_proveedor(nombre_proveedor)
    return productos