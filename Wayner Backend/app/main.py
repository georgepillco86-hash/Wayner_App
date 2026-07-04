import asyncio
from app.services.provider_mirror_service import ProviderMirrorService
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes_products import router as products_router
from app.api.routes_saldos import router as saldos_router
from app.api.routes_pedidos import router as pedidos_router
from app.core.config import settings
from app.core.exceptions import DatabaseConnectionError, NotFoundError, ValidationError
from app.api.routes_auth import router as auth_router
from app.api.routes_usuarios import router as usuarios_router
from app.api.routes_unidades_medida import router as unidades_medida_router
from app.api.routes_audit_logs import router as audit_logs_router
from app.services.audit_middleware import AuditLogMiddleware
from app.api.routes_promociones import router as promociones_router
from app.api.routes_mermas import router as mermas_router


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
    # Inicia el bucle en segundo plano sin bloquear el hilo principal de la API
    asyncio.create_task(ProviderMirrorService.iniciar_bucle_cada_hora())


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


app.include_router(products_router, prefix=settings.api_prefix)
app.include_router(saldos_router, prefix=settings.api_prefix)
app.include_router(pedidos_router, prefix=settings.api_prefix)
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(usuarios_router, prefix=settings.api_prefix)
app.include_router(unidades_medida_router, prefix=settings.api_prefix)
app.include_router(audit_logs_router, prefix=settings.api_prefix)
app.include_router(promociones_router, prefix=settings.api_prefix)
app.include_router(mermas_router, prefix=f"{settings.api_prefix}/mermas", tags=["Mermas"])

