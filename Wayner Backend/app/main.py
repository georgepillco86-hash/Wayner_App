from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

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

app = FastAPI(
    title=settings.app_name,
    version="1.1.0",
    debug=settings.app_debug,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(AuditLogMiddleware)


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
