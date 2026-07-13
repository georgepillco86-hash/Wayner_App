from fastapi import APIRouter
from typing import Optional

from app.repositories.proveedor_repository import ProveedorRepository

# 🔥 IMPORTAMOS EL NUEVO CEREBRO ESTADÍSTICO Y DE CRONOGRAMAS 🔥
from app.services.product_service import ProductService
from app.repositories.product_repository import ProductRepository

# Inicializamos las rutas y los repositorios
router = APIRouter()
proveedor_repo = ProveedorRepository()

# Instanciamos el servicio de productos para usar su matemática predictiva
product_service = ProductService(ProductRepository())

@router.get("/")
async def listar_proveedores():
    return proveedor_repo.get_proveedores_list()

@router.get("/clases")
async def listar_clases():
    return proveedor_repo.get_clases_list()

@router.get("/{nombre_proveedor}/productos")
async def listar_productos_proveedor(nombre_proveedor: str):
    productos = proveedor_repo.get_productos_por_proveedor(nombre_proveedor)
    # También inyectamos las alertas si revisan por proveedor
    return product_service._inyectar_vdp_dinamico(productos)

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
    # Inyectamos estadística
    return product_service._inyectar_vdp_dinamico(productos)

@router.get("/buscar-rapido")
def buscar_rapido(
    q: str = "", 
    proveedor: Optional[str] = None,
    clase: Optional[str] = None
):
    """Busca instantáneamente en las tablas espejo y cruza con datos vivos"""
    
    # 📍 RASTREADOR DE ENTRADA
    print(f"📥 [ROUTER] Petición recibida -> q='{q}', proveedor='{proveedor}', clase='{clase}'")
    
    # Bloqueamos la búsqueda solo si NO hay texto, NO hay proveedor y NO hay clase
    if len(q) < 2 and not proveedor and not clase:
        print("🛑 [ROUTER] Bloqueado por seguridad: Búsqueda demasiado corta o vacía.")
        return []
        
    print("✅ [ROUTER] Permiso concedido. Extrayendo base de datos espejo...")
    
    # 1. Obtenemos los productos con la consulta original (rápida)
    productos_base = proveedor_repo.buscar_rapido_proveedores(
        termino=q, 
        proveedor_especifico=proveedor, 
        clase_especifica=clase
    )
    
    # 2. 🔥 LA MAGIA: Pasamos los resultados por el nuevo filtro predictivo 🔥
    print("🧠 [ROUTER] Inyectando motor predictivo (VDP) y validando Cronogramas...")
    productos_inteligentes = product_service._inyectar_vdp_dinamico(productos_base)
    
    # Retornamos los productos ya sobreescritos con las Alertas y Estadísticas Reales
    return productos_inteligentes