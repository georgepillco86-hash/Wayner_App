from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = Field(default="Ferrotienda API", alias="APP_NAME")
    app_env: str = Field(default="development", alias="APP_ENV")
    app_host: str = Field(default="0.0.0.0", alias="APP_HOST")
    app_port: int = Field(default=5000, alias="APP_PORT")
    app_debug: bool = Field(default=True, alias="APP_DEBUG")

    db_host: str = Field(alias="DB_HOST")
    db_port: int = Field(default=6033, alias="DB_PORT")
    db_name: str = Field(alias="DB_NAME")
    db_user: str = Field(alias="DB_USER")
    db_password: str = Field(alias="DB_PASSWORD")
    db_use_pure: bool = Field(default=True, alias="DB_USE_PURE")
    db_connect_timeout: int = Field(default=15, alias="DB_CONNECT_TIMEOUT")
    db_pool_name: str = Field(default="ferrotienda_pool", alias="DB_POOL_NAME")
    db_pool_size: int = Field(default=5, alias="DB_POOL_SIZE")

    api_prefix: str = Field(default="/api", alias="API_PREFIX")
    default_page_size: int = Field(default=25, alias="DEFAULT_PAGE_SIZE")
    max_page_size: int = Field(default=100, alias="MAX_PAGE_SIZE")
    product_search_limit: int = Field(default=50, alias="PRODUCT_SEARCH_LIMIT")
    history_limit: int = Field(default=100, alias="HISTORY_LIMIT")
    enable_cache: bool = Field(default=True, alias="ENABLE_CACHE")
    cache_ttl_seconds: int = Field(default=300, alias="CACHE_TTL_SECONDS")

    pedidos_db_host: str = Field(default="localhost", alias="PEDIDOS_DB_HOST")
    pedidos_db_port: int = Field(default=5432, alias="PEDIDOS_DB_PORT")
    pedidos_db_name: str = Field(default="ferrotienda_db", alias="PEDIDOS_DB_NAME")
    pedidos_db_user: str = Field(default="postgres", alias="PEDIDOS_DB_USER")
    pedidos_db_password: str = Field(alias="PEDIDOS_DB_PASSWORD")
    pedidos_db_schema: str = Field(default="ferrotienda", alias="PEDIDOS_DB_SCHEMA")
    pedidos_db_pool_size: int = Field(default=5, alias="PEDIDOS_DB_POOL_SIZE")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
