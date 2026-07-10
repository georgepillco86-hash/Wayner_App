from fastapi import APIRouter
from app.repositories.proveedor_repository import ProveedorRepository
from typing import Optional

# Aquí es donde se define el "router" que estaba dando error
router = APIRouter()
proveedor_repo = ProveedorRepository()

@router.get("/")
async def listar_proveedores():
    return proveedor_repo.get_proveedores_list()

@router.get("/clases")
async def listar_clases():
    return proveedor_repo.get_clases_list()

@router.get("/{nombre_proveedor}/productos")
async def listar_productos_proveedor(nombre_proveedor: str):
    productos = proveedor_repo.get_productos_por_proveedor(nombre_proveedor)
    return productos

# --- RUTAS NUEVAS PARA BÚSQUEDA HÍBRIDA ---

@router.get("/producto/{codigo}/precio-vivo")
async def obtener_precio_real(codigo: str):
    """Devuelve los valores financieros actuales de un producto"""
    valores = proveedor_repo.obtener_precio_en_vivo(codigo)
    return valores

@router.get("/busqueda-profunda")
async def buscar_en_kardex(q: str):
    """Busca directamente en la base de datos principal agrupando por código"""
    if len(q) < 3:
        return [] # Evitar búsquedas masivas con solo 1 o 2 letras
    productos = proveedor_repo.busqueda_profunda_kardex(q)
    return productos

@router.get("/buscar-rapido")
def buscar_rapido(
    q: str = "", 
    proveedor: Optional[str] = None,
    clase: Optional[str] = None  # ---> NUEVO: Recibimos la clase
):
    """Busca instantáneamente en las tablas espejo y cruza con datos vivos"""
    
    # 🚨 CAMBIO AQUÍ: Bloqueamos la búsqueda solo si NO hay texto, NO hay proveedor y NO hay clase
    if len(q) < 2 and not proveedor and not clase:
        return []
        
    # Pasamos los 3 parámetros (nombrados para evitar confusiones de posición)
    return proveedor_repo.buscar_rapido_proveedores(
        termino=q, 
        proveedor_especifico=proveedor, 
        clase_especifica=clase
    )