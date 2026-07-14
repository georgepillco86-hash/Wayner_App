import asyncio
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# --- IMPORTACIONES DE RUTAS ---
from app.api.routes_products import router as products_router
from app.api.routes_saldos import router as saldos_router
from app.api.routes_pedidos import router as pedidos_router
from app.api.routes_auth import router as auth_router
from app.api.routes_usuarios import router as usuarios_router
from app.api.routes_unidades_medida import router as unidades_medida_router
from app.api.routes_audit_logs import router as audit_logs_router
from app.api.routes_promociones import router as promociones_router
from app.api.routes_mermas import router as mermas_router
from app.api.routes_proveedores import router as proveedores_router
from app.api.routes_cronogramas import router as cronogramas_router

# --- IMPORTACIONES DE CORE Y SERVICIOS ---
from app.core.config import settings
from app.core.exceptions import DatabaseConnectionError, NotFoundError, ValidationError
from app.services.audit_middleware import AuditLogMiddleware
from app.services.provider_mirror_service import ProviderMirrorService
from app.services.notification_service import NotificationService

app = FastAPI(
    title=settings.app_name,
    version="1.1.0",
    debug=settings.app_debug,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Permite peticiones de cualquier origen (ideal para desarrollo local)
    allow_credentials=True,
    allow_methods=["*"],  # Permite todos los métodos (GET, POST, PUT, DELETE, etc.)
    allow_headers=["*"],  # Permite todos los headers
)

app.add_middleware(AuditLogMiddleware)

@app.on_event("startup")
async def startup_event():
    await ProviderMirrorService.sincronizar_espejo()
    # 1. Inicia el bucle de sincronización de proveedores (Espejo)
    asyncio.create_task(ProviderMirrorService.iniciar_bucle_sincronizacion())
    
    # 2. Inicia el vigilante de notificaciones para los pedidos programados
    asyncio.create_task(NotificationService.iniciar_vigilante_alertas())


@app.exception_handler(DatabaseConnectionError)
async def database_error_handler(request: Request, exc: DatabaseConnectionError):
    return JSONResponse(
        status_code=503,
        content={
            "success": False,
            "message": "Error de conexión a la base de datos",
            "error": str(exc),
        },
    )

@app.exception_handler(NotFoundError)
async def not_found_handler(request: Request, exc: NotFoundError):
    return JSONResponse(
        status_code=404,
        content={
            "success": False,
            "message": str(exc),
            "error": str(exc),
        },
    )


@app.exception_handler(ValidationError)
async def validation_handler(request: Request, exc: ValidationError):
    return JSONResponse(
        status_code=400,
        content={
            "success": False,
            "message": str(exc),
            "error": str(exc),
        },
    )

# --- INCLUSIÓN DE RUTAS ---
app.include_router(products_router, prefix=settings.api_prefix)
app.include_router(saldos_router, prefix=settings.api_prefix)
app.include_router(pedidos_router, prefix=settings.api_prefix)
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(usuarios_router, prefix=settings.api_prefix)
app.include_router(unidades_medida_router, prefix=settings.api_prefix)
app.include_router(audit_logs_router, prefix=settings.api_prefix)
app.include_router(promociones_router, prefix=settings.api_prefix)
app.include_router(mermas_router, prefix=f"{settings.api_prefix}/mermas", tags=["Mermas"])

# Rutas Nuevas
app.include_router(proveedores_router, prefix="/api/proveedores", tags=["Proveedores"])
app.include_router(cronogramas_router, prefix="/api/cronograma", tags=["Cronograma"])

