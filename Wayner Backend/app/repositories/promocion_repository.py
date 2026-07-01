from __future__ import annotations

from typing import Any

from app.core.pedidos_database import pedidos_db


class PromocionRepository:
    def listar(
        self,
        texto: str | None = None,
        codigo_barra: str | None = None,
        estado: str | None = None,
        fecha_desde=None,
        fecha_hasta=None,
    ) -> list[dict[str, Any]]:
        filtros = []
        params: list[Any] = []

        if texto:
            filtros.append("""
            (
                codigo_barra ILIKE %s
                OR nombre_producto ILIKE %s
                OR encabezado ILIKE %s
                OR mecanica ILIKE %s
            )
            """)
            like = f"%{texto}%"
            params.extend([like, like, like, like])

        if codigo_barra:
            filtros.append("codigo_barra = %s")
            params.append(codigo_barra)

        if fecha_desde and fecha_hasta:
            filtros.append("""
            (
                fecha_inicio <= %s
                AND fecha_fin >= %s
            )
            """)
            params.extend([fecha_hasta, fecha_desde])

        if estado == "ACTIVA":
            filtros.append("activa = TRUE")
            filtros.append("fecha_inicio <= CURRENT_DATE")
            filtros.append("fecha_fin >= CURRENT_DATE")

        elif estado == "VENCIDA":
            filtros.append("fecha_fin < CURRENT_DATE")

        elif estado == "DESACTIVADA":
            filtros.append("activa = FALSE")

        where = f"WHERE {' AND '.join(filtros)}" if filtros else ""

        query = f"""
        SELECT *
        FROM promociones
        {where}
        ORDER BY fecha_inicio DESC, id DESC
        """

        return pedidos_db.fetch_all(query, tuple(params))

    def obtener_por_id(self, promocion_id: int) -> dict[str, Any] | None:
        query = """
        SELECT *
        FROM promociones
        WHERE id = %s
        LIMIT 1
        """
        return pedidos_db.fetch_one(query, (promocion_id,))

    def obtener_activa_por_codigo(self, codigo_barra: str) -> dict[str, Any] | None:
        query = """
        SELECT *
        FROM promociones
        WHERE codigo_barra = %s
          AND activa = TRUE
          AND fecha_inicio <= CURRENT_DATE
          AND fecha_fin >= CURRENT_DATE
        ORDER BY fecha_fin ASC, id DESC
        LIMIT 1
        """
        return pedidos_db.fetch_one(query, (codigo_barra,))

    def existe_solapamiento(
        self,
        codigo_barra: str,
        fecha_inicio,
        fecha_fin,
        excluir_id: int | None = None,
    ) -> dict[str, Any] | None:
        params: list[Any] = [codigo_barra, fecha_inicio, fecha_fin]

        extra = ""
        if excluir_id is not None:
            extra = "AND id <> %s"
            params.append(excluir_id)

        query = f"""
        SELECT id
        FROM promociones
        WHERE codigo_barra = %s
          AND activa = TRUE
          AND fecha_fin >= %s
          AND fecha_inicio <= %s
          {extra}
        LIMIT 1
        """

        return pedidos_db.fetch_one(query, tuple(params))

    def crear(self, data: dict[str, Any]) -> int:
        query = """
        INSERT INTO promociones (
            codigo_barra,
            nombre_producto,
            precio_base,
            precio_anterior,
            precio_actual_prom,
            ahorro,
            encabezado,
            mecanica,
            fecha_inicio,
            fecha_fin,
            activa
        )
        VALUES (
            %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s
        )
        RETURNING id
        """

        return pedidos_db.execute(
            query,
            (
                data["codigo_barra"],
                data["nombre_producto"],
                data["precio_base"],
                data["precio_anterior"],
                data["precio_actual_prom"],
                data["ahorro"],
                data.get("encabezado"),
                data.get("mecanica"),
                data["fecha_inicio"],
                data["fecha_fin"],
                data["activa"],
            ),
        )

    def actualizar(self, promocion_id: int, data: dict[str, Any]) -> None:
        campos = []
        params: list[Any] = []

        for key, value in data.items():
            campos.append(f"{key} = %s")
            params.append(value)

        if not campos:
            return

        params.append(promocion_id)

        query = f"""
        UPDATE promociones
        SET {', '.join(campos)}
        WHERE id = %s
        """

        pedidos_db.execute(query, tuple(params))

    def desactivar(self, promocion_id: int) -> None:
        query = """
        UPDATE promociones
        SET activa = FALSE
        WHERE id = %s
        """
        pedidos_db.execute(query, (promocion_id,))