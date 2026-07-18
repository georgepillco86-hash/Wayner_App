from __future__ import annotations

from typing import Any

from app.core.database import db
from app.core.pedidos_database import pedidos_db

from datetime import date
import calendar


class PedidoRepository:
    PROVEEDOR_EXCLUIDO = "DUCHI SANCHEZ ROSA EMPERATRIZ"

    def _es_proveedor_excluido(self, nombre: str | None) -> bool:
        if not nombre:
            return False
        return nombre.strip().upper() == self.PROVEEDOR_EXCLUIDO

    def search_products_for_order(
        self,
        text: str,
        text2: str | None = None,
        proveedor: str | None = None,
        limit: int = 30,
    ) -> list[dict[str, Any]]:

        pattern1 = f"%{text}%"

        filtros = [
            """
            (
                s.Codigo LIKE %s
                OR s.Nombre LIKE %s
                OR s.Marca LIKE %s
                OR s.Clase LIKE %s
            )
            """
        ]

        params: list[Any] = [
            pattern1,
            pattern1,
            pattern1,
            pattern1,
        ]

        if text2 and text2.strip():
            pattern2 = f"%{text2.strip()}%"

            filtros.append(
                """
                (
                    s.Codigo LIKE %s
                    OR s.Nombre LIKE %s
                    OR s.Marca LIKE %s
                    OR s.Clase LIKE %s
                )
                """
            )

            params.extend([
                pattern2,
                pattern2,
                pattern2,
                pattern2,
            ])

        if proveedor and proveedor.strip():
            filtros.append(
                """
                EXISTS (
                    SELECT 1
                    FROM v_kardexproductos kp
                    WHERE kp.Codigo = s.Codigo
                    AND kp.NombreProveedor IS NOT NULL
                    AND TRIM(kp.NombreProveedor) <> ''
                    AND UPPER(TRIM(kp.NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
                    AND kp.NombreProveedor LIKE %s
                )
                """
            )
            params.append(f"%{proveedor.strip()}%")

        query = f"""
        SELECT
            s.Codigo AS codigo,
            s.Nombre AS nombre,
            s.Stock AS stock_actual,
            s.Marca AS marca,
            s.Clase AS clase,
            (
                SELECT k.NombreProveedor
                FROM v_kardexproductos k
                WHERE k.Codigo = s.Codigo
                AND k.NombreProveedor IS NOT NULL
                AND TRIM(k.NombreProveedor) <> ''
                AND UPPER(TRIM(k.NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
                ORDER BY k.Fecha DESC
                LIMIT 1
            ) AS proveedor
        FROM v_saldosproductos s
        WHERE {" AND ".join(filtros)}
        ORDER BY s.Nombre
        LIMIT %s
        """

        params.append(limit)

        return db.fetch_all(query, tuple(params))

    def get_product_for_order(self, codigo: str) -> dict[str, Any] | None:
        query = """
        SELECT
            s.Codigo AS codigo,
            s.Nombre AS nombre,
            s.Stock AS stock_actual,
            s.Marca AS marca,
            s.Clase AS clase,
            (
                SELECT k.NombreProveedor
                FROM v_kardexproductos k
                WHERE k.Codigo = s.Codigo
                  AND k.NombreProveedor IS NOT NULL
                  AND TRIM(k.NombreProveedor) <> ''
                  AND UPPER(TRIM(k.NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
                ORDER BY k.Fecha DESC
                LIMIT 1
            ) AS proveedor
        FROM v_saldosproductos s
        WHERE s.Codigo = %s
        LIMIT 1
        """

        return db.fetch_one(query, (codigo,))

    def create_order(self, usuario: str | None, observacion: str | None) -> int:
        query = """
        INSERT INTO pedidos (
            estado,
            usuario_creacion,
            observacion,
            fecha_envio
        )
        VALUES (
            'BORRADOR',
            %s,
            %s,
            NULL
        )
        RETURNING id
        """

        return pedidos_db.execute(query, (usuario, observacion))

    def add_order_item(
        self,
        pedido_id: int,
        item: dict[str, Any],
        cantidad: Any,
        unidad: str | None = None,
        nota_compra: str | None = None,
        tipo_destino: str = "VENTA",
    ) -> int:
        proveedor_nombre = item.get("proveedor")

        if proveedor_nombre is None or str(proveedor_nombre).strip() == "":
            proveedor_id = None
        elif self._es_proveedor_excluido(str(proveedor_nombre)):
            proveedor_id = None
        else:
            proveedor_id = self.get_or_create_provider(
                nombre=str(proveedor_nombre).strip(),
                marca_principal=item.get("marca"),
            )

        query = """
        INSERT INTO pedido_items (
            pedido_id,
            proveedor_id,
            codigo_producto,
            nombre_producto,
            marca,
            stock_actual,
            cantidad_pedida,
            unidad,
            observacion,
            nota_compra,
            tipo_destino
        )
        VALUES (
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s,
            %s
        )
        RETURNING id
        """

        return pedidos_db.execute(
            query,
            (
                pedido_id,
                proveedor_id,
                item.get("codigo"),
                item.get("nombre"),
                item.get("marca"),
                item.get("stock_actual"),
                cantidad,
                unidad,
                item.get("clase"),
                nota_compra,
                tipo_destino,
            ),
        )

    def get_or_create_provider(
        self,
        nombre: str,
        marca_principal: str | None = None,
    ) -> int:
        if self._es_proveedor_excluido(nombre):
            raise ValueError("Proveedor excluido no debe registrarse como proveedor oficial")

        query_select = """
        SELECT id
        FROM proveedores
        WHERE LOWER(nombre) = LOWER(%s)
        LIMIT 1
        """

        proveedor = pedidos_db.fetch_one(query_select, (nombre,))

        if proveedor:
            return int(proveedor["id"])

        query_insert = """
        INSERT INTO proveedores (
            nombre,
            marca_principal
        )
        VALUES (
            %s,
            %s
        )
        RETURNING id
        """

        return pedidos_db.execute(query_insert, (nombre, marca_principal))

    def list_orders(self, limit: int = 50) -> list[dict[str, Any]]:
        query = """
        SELECT
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion AS usuario,
            p.usuario_creacion AS usuario_nombre,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion,
            NULL AS fecha_actualizacion,
            COUNT(pi.id) AS total_items,
            STRING_AGG(DISTINCT pr.nombre, ', ') AS proveedores
        FROM pedidos p
        LEFT JOIN pedido_items pi
            ON pi.pedido_id = p.id
        LEFT JOIN proveedores pr 
            ON pr.id = pi.proveedor_id
        GROUP BY
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion
        ORDER BY p.fecha_creacion DESC
        LIMIT %s
        """

        return pedidos_db.fetch_all(query, (limit,))

    def get_order(self, pedido_id: int) -> dict[str, Any] | None:
        query = """
        SELECT
            id,
            codigo_pedido,
            estado,
            usuario_creacion AS usuario,
            observacion,
            fecha_creacion,
            fecha_envio,
            fecha_recepcion,
            NULL AS fecha_actualizacion
        FROM pedidos
        WHERE id = %s
        LIMIT 1
        """

        return pedidos_db.fetch_one(query, (pedido_id,))

    def get_order_items(self, pedido_id: int) -> list[dict[str, Any]]:
        query = """
        SELECT
            pi.id,
            pi.codigo_producto AS codigo,
            pi.nombre_producto AS nombre,
            pi.marca,
            pi.observacion AS clase,
            pi.nota_compra,
            COALESCE(p.nombre, 'SIN PROVEEDOR') AS proveedor,
            pi.stock_actual,
            pi.cantidad_pedida AS cantidad,
            pi.unidad,
            pi.tipo_destino,
            pi.recibido,
            pi.comentario_recepcion,
            pi.fecha_recepcion_item,
            pi.usuario_recepcion
        FROM pedido_items pi
        LEFT JOIN proveedores p
            ON p.id = pi.proveedor_id
        WHERE pi.pedido_id = %s
        ORDER BY proveedor, pi.marca, pi.nombre_producto
        """

        return pedidos_db.fetch_all(query, (pedido_id,))

    def update_order_status(self, pedido_id: int, estado: str) -> None:
        if estado == "ENVIADO":
            query = """
            UPDATE pedidos
            SET estado = %s,
                fecha_envio = CURRENT_TIMESTAMP
            WHERE id = %s
            """
        elif estado == "RECIBIDO":
            query = """
            UPDATE pedidos
            SET estado = %s,
                fecha_recepcion = CURRENT_TIMESTAMP
            WHERE id = %s
            """
        else:
            query = """
            UPDATE pedidos
            SET estado = %s
            WHERE id = %s
            """

        pedidos_db.execute(query, (estado, pedido_id))

    def get_product_providers(self, codigo: str) -> list[dict[str, Any]]:
        query = """
        SELECT DISTINCT
            k.NombreProveedor AS proveedor,
            s.Marca AS marca
        FROM v_kardexproductos k
        INNER JOIN v_saldosproductos s
            ON s.Codigo = k.Codigo
        WHERE k.Codigo = %s
          AND k.NombreProveedor IS NOT NULL
          AND TRIM(k.NombreProveedor) <> ''
          AND UPPER(TRIM(k.NombreProveedor)) <> 'DUCHI SANCHEZ ROSA EMPERATRIZ'
        ORDER BY k.NombreProveedor
        """

        return db.fetch_all(query, (codigo,))

    def list_orders_by_user(self, usuario: str, limit: int = 50) -> list[dict[str, Any]]:
        query = """
        SELECT
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion AS usuario,
            p.usuario_creacion AS usuario_nombre,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion,
            NULL AS fecha_actualizacion,
            COUNT(pi.id) AS total_items,
            STRING_AGG(DISTINCT pr.nombre, ', ') AS proveedores
        FROM pedidos p
        LEFT JOIN pedido_items pi
            ON pi.pedido_id = p.id
        LEFT JOIN proveedores pr 
            ON pr.id = pi.proveedor_id
        WHERE LOWER(p.usuario_creacion) = LOWER(%s)
        GROUP BY
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion
        ORDER BY p.fecha_creacion DESC
        LIMIT %s
        """

        return pedidos_db.fetch_all(query, (usuario, limit))

    def get_order_user_detail(self, pedido_id: int) -> dict[str, Any] | None:
        query_pedido = """
        SELECT
            id,
            codigo_pedido,
            estado,
            usuario_creacion AS usuario,
            observacion,
            fecha_creacion,
            fecha_envio,
            fecha_recepcion
        FROM pedidos
        WHERE id = %s
        LIMIT 1
        """

        pedido = pedidos_db.fetch_one(query_pedido, (pedido_id,))

        if not pedido:
            return None

        query_items = """
        SELECT
            id,
            pedido_id,
            codigo_producto,
            nombre_producto,
            marca,
            stock_actual,
            cantidad_pedida,
            unidad,
            observacion,
            nota_compra,
            tipo_destino,
            recibido,
            comentario_recepcion,
            fecha_recepcion_item,
            usuario_recepcion,
            fecha_creacion
        FROM pedido_items
        WHERE pedido_id = %s
        ORDER BY id ASC
        """

        items = pedidos_db.fetch_all(query_items, (pedido_id,))

        pedido["items"] = items
        return pedido

    def list_orders_admin(self, limit: int = 100) -> list[dict[str, Any]]:
        query = """
        SELECT
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion AS usuario,
            p.usuario_creacion AS usuario_nombre,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion,
            COUNT(pi.id) AS total_items,
            STRING_AGG(DISTINCT pr.nombre, ', ') AS proveedores
        FROM pedidos p
        LEFT JOIN pedido_items pi
            ON pi.pedido_id = p.id
        LEFT JOIN proveedores pr 
            ON pr.id = pi.proveedor_id
        GROUP BY
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion
        ORDER BY p.fecha_creacion DESC
        LIMIT %s
        """

        return pedidos_db.fetch_all(query, (limit,))

    def get_order_admin_detail(self, pedido_id: int) -> dict[str, Any] | None:
        query_pedido = """
        SELECT
            id,
            codigo_pedido,
            estado,
            usuario_creacion AS usuario,
            observacion,
            fecha_creacion,
            fecha_envio,
            fecha_recepcion
        FROM pedidos
        WHERE id = %s
        LIMIT 1
        """

        pedido = pedidos_db.fetch_one(query_pedido, (pedido_id,))

        if not pedido:
            return None

        query_items = """
        SELECT
            pi.id,
            pi.pedido_id,
            pi.proveedor_id,
            COALESCE(pr.nombre, 'SIN PROVEEDOR') AS proveedor,
            pi.codigo_producto,
            pi.nombre_producto,
            pi.marca,
            pi.stock_actual,
            pi.cantidad_pedida,
            pi.unidad,
            pi.observacion,
            pi.nota_compra,
            pi.tipo_destino,
            pi.recibido,
            pi.comentario_recepcion,
            pi.fecha_recepcion_item,
            pi.usuario_recepcion,
            pi.fecha_creacion
        FROM pedido_items pi
        LEFT JOIN proveedores pr
            ON pr.id = pi.proveedor_id
        WHERE pi.pedido_id = %s
        ORDER BY proveedor ASC, pi.nombre_producto ASC
        """

        items = pedidos_db.fetch_all(query_items, (pedido_id,))

        pedido["items"] = items
        return pedido

    def get_order_grouped_by_provider(self, pedido_id: int) -> list[dict[str, Any]]:
        query = """
        SELECT
            COALESCE(pr.nombre, 'SIN PROVEEDOR') AS proveedor,
            pi.codigo_producto,
            pi.nombre_producto,
            pi.marca,
            pi.cantidad_pedida,
            pi.unidad,
            pi.nota_compra,
            pi.tipo_destino,
            pi.recibido,
            pi.comentario_recepcion,
            pi.fecha_recepcion_item,
            pi.usuario_recepcion
        FROM pedido_items pi
        LEFT JOIN proveedores pr
            ON pr.id = pi.proveedor_id
        WHERE pi.pedido_id = %s
        ORDER BY proveedor ASC, pi.nombre_producto ASC
        """

        rows = pedidos_db.fetch_all(query, (pedido_id,))

        grouped: dict[str, list[dict[str, Any]]] = {}

        for row in rows:
            proveedor = row.get("proveedor") or "SIN PROVEEDOR"

            if self._es_proveedor_excluido(proveedor):
                proveedor = "SIN PROVEEDOR"

            if proveedor not in grouped:
                grouped[proveedor] = []

            grouped[proveedor].append({
                "codigo_producto": row.get("codigo_producto"),
                "nombre_producto": row.get("nombre_producto"),
                "marca": row.get("marca"),
                "cantidad_pedida": row.get("cantidad_pedida"),
                "unidad": row.get("unidad"),
                "nota_compra": row.get("nota_compra"),
                "tipo_destino": row.get("tipo_destino") or "VENTA",
                "recibido": row.get("recibido"),
                "comentario_recepcion": row.get("comentario_recepcion"),
                "fecha_recepcion_item": row.get("fecha_recepcion_item"),
                "usuario_recepcion": row.get("usuario_recepcion"),
            })

        return [
            {
                "proveedor": proveedor,
                "items": items,
            }
            for proveedor, items in grouped.items()
        ]

    def add_item_to_existing_order(
        self,
        pedido_id: int,
        item: dict[str, Any],
        cantidad: Any,
        unidad: str | None = None,
        nota_compra: str | None = None,
        tipo_destino: str = "VENTA",
    ) -> int:
        return self.add_order_item(
            pedido_id=pedido_id,
            item=item,
            cantidad=cantidad,
            unidad=unidad,
            nota_compra=nota_compra,
            tipo_destino=tipo_destino,
        )

    def get_order_item_by_id(self, pedido_id: int, item_id: int) -> dict[str, Any] | None:
        query = """
        SELECT
            id,
            pedido_id,
            codigo_producto,
            nombre_producto,
            cantidad_pedida,
            unidad,
            nota_compra,
            tipo_destino,
            recibido,
            comentario_recepcion,
            fecha_recepcion_item,
            usuario_recepcion
        FROM pedido_items
        WHERE id = %s
          AND pedido_id = %s
        LIMIT 1
        """

        return pedidos_db.fetch_one(query, (item_id, pedido_id))

    def update_order_item_quantity(
        self,
        pedido_id: int,
        item_id: int,
        cantidad: Any,
    ) -> None:
        query = """
        UPDATE pedido_items
        SET cantidad_pedida = %s
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(query, (cantidad, item_id, pedido_id))

    def delete_order_item(
        self,
        pedido_id: int,
        item_id: int,
    ) -> None:
        query = """
        DELETE FROM pedido_items
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(query, (item_id, pedido_id))

    def _restar_meses(self, fecha: date, meses: int) -> date:
        mes = fecha.month - meses
        anio = fecha.year

        while mes <= 0:
            mes += 12
            anio -= 1

        dia = min(fecha.day, calendar.monthrange(anio, mes)[1])
        return date(anio, mes, dia)

    def _get_kardex_columns(self) -> set[str]:
        rows = db.fetch_all("DESCRIBE v_kardexproductos")
        return {row["Field"] for row in rows}

    def _get_kardex_price_column(self) -> str:
        columnas = self._get_kardex_columns()

        posibles_columnas = [
            "Precio",
            "PrecioUnitario",
            "Costo",
            "CostoUnitario",
            "ValorUnitario",
            "PrecioCompra",
            "CostoCompra",
        ]

        for columna in posibles_columnas:
            if columna in columnas:
                return columna

        raise ValueError(
            "No se encontró una columna de precio compatible en v_kardexproductos"
        )

    def get_best_provider_price_for_product(
        self,
        codigo: str,
        meses: int = 6,
    ) -> dict[str, Any]:
        precio_columna = self._get_kardex_price_column()
        fecha_desde = self._restar_meses(date.today(), meses)

        query = f"""
        SELECT
            k.NombreProveedor AS proveedor,
            k.{precio_columna} AS precio,
            k.Fecha AS fecha
        FROM v_kardexproductos k
        WHERE k.Codigo = %s
          AND k.NombreProveedor IS NOT NULL
          AND TRIM(k.NombreProveedor) <> ''
          AND UPPER(TRIM(k.NombreProveedor)) <> %s
          AND k.{precio_columna} IS NOT NULL
          AND k.{precio_columna} > 0
          AND k.Fecha >= %s
        ORDER BY k.{precio_columna} ASC, k.Fecha DESC
        """

        rows = db.fetch_all(
            query,
            (
                codigo,
                self.PROVEEDOR_EXCLUIDO,
                fecha_desde,
            ),
        )

        proveedores: dict[str, dict[str, Any]] = {}

        for row in rows:
            proveedor = row.get("proveedor")

            if not proveedor:
                continue

            proveedor_key = proveedor.strip().upper()

            precio = row.get("precio")
            fecha = row.get("fecha")

            if proveedor_key not in proveedores:
                proveedores[proveedor_key] = {
                    "proveedor": proveedor.strip(),
                    "mejor_precio": precio,
                    "fecha": fecha,
                    "es_mejor": False,
                    "es_unico": False,
                }

        lista = list(proveedores.values())

        lista.sort(
            key=lambda x: float(x["mejor_precio"] or 0)
        )

        if lista:
            lista[0]["es_mejor"] = True

        if len(lista) == 1:
            lista[0]["es_unico"] = True

        return {
            "codigo_producto": codigo,
            "periodo_meses": meses,
            "columna_precio_usada": precio_columna,
            "proveedores": lista,
        }

    def update_order_item_provider(
        self,
        pedido_id: int,
        item_id: int,
        proveedor_nombre: str,
    ) -> None:
        if self._es_proveedor_excluido(proveedor_nombre):
            proveedor_id = None
        else:
            proveedor_id = self.get_or_create_provider(
                nombre=proveedor_nombre.strip(),
                marca_principal=None,
            )

        query = """
        UPDATE pedido_items
        SET proveedor_id = %s
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(query, (proveedor_id, item_id, pedido_id))

    def update_order_item_nota(
        self,
        pedido_id: int,
        item_id: int,
        nota_compra: str | None,
    ) -> None:
        query = """
        UPDATE pedido_items
        SET nota_compra = %s
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(query, (nota_compra, item_id, pedido_id))

    def update_order_item_unidad(
        self,
        pedido_id: int,
        item_id: int,
        unidad: str | None,
    ) -> None:
        query = """
        UPDATE pedido_items
        SET unidad = %s
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(query, (unidad, item_id, pedido_id))

    def update_order_item_tipo_destino(
        self,
        pedido_id: int,
        item_id: int,
        tipo_destino: str,
    ) -> None:
        query = """
        UPDATE pedido_items
        SET tipo_destino = %s
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(query, (tipo_destino, item_id, pedido_id))

    def list_orders_bodega(self, limit: int = 100) -> list[dict[str, Any]]:
        query = """
        SELECT
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion AS usuario,
            p.usuario_creacion AS usuario_nombre,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion,
            COUNT(pi.id) AS total_items,
            STRING_AGG(DISTINCT pr.nombre, ', ') AS proveedores,
            SUM(
                CASE
                    WHEN pi.recibido = true THEN 1
                    ELSE 0
                END
            ) AS total_recibidos,
            SUM(
                CASE
                    WHEN pi.comentario_recepcion IS NOT NULL
                     AND TRIM(pi.comentario_recepcion) <> '' THEN 1
                    ELSE 0
                END
            ) AS total_observaciones
        FROM pedidos p
        LEFT JOIN pedido_items pi
            ON pi.pedido_id = p.id
        LEFT JOIN proveedores pr 
            ON pr.id = pi.proveedor_id
        WHERE p.estado IN ('ENVIADO', 'RECIBIDO')
        GROUP BY
            p.id,
            p.codigo_pedido,
            p.estado,
            p.usuario_creacion,
            p.observacion,
            p.fecha_creacion,
            p.fecha_envio,
            p.fecha_recepcion
        ORDER BY p.fecha_creacion DESC
        LIMIT %s
        """

        return pedidos_db.fetch_all(query, (limit,))

    def get_order_bodega_detail(self, pedido_id: int) -> dict[str, Any] | None:
        query_pedido = """
        SELECT
            id,
            codigo_pedido,
            estado,
            usuario_creacion AS usuario,
            observacion,
            fecha_creacion,
            fecha_envio,
            fecha_recepcion
        FROM pedidos
        WHERE id = %s
        LIMIT 1
        """

        pedido = pedidos_db.fetch_one(query_pedido, (pedido_id,))

        if not pedido:
            return None

        query_items = """
        SELECT
            pi.id,
            pi.pedido_id,
            pi.proveedor_id,
            COALESCE(pr.nombre, 'SIN PROVEEDOR') AS proveedor,
            pi.codigo_producto,
            pi.nombre_producto,
            pi.marca,
            pi.stock_actual,
            pi.cantidad_pedida,
            pi.unidad,
            pi.observacion,
            pi.nota_compra,
            pi.tipo_destino,
            pi.recibido,
            pi.comentario_recepcion,
            pi.fecha_recepcion_item,
            pi.usuario_recepcion,
            pi.fecha_creacion
        FROM pedido_items pi
        LEFT JOIN proveedores pr
            ON pr.id = pi.proveedor_id
        WHERE pi.pedido_id = %s
        ORDER BY proveedor ASC, pi.nombre_producto ASC
        """

        items = pedidos_db.fetch_all(query_items, (pedido_id,))

        pedido["items"] = items
        return pedido

    def update_order_item_recepcion(
        self,
        pedido_id: int,
        item_id: int,
        recibido: bool,
        comentario_recepcion: str | None,
        usuario_recepcion: str | None,
    ) -> None:
        query = """
        UPDATE pedido_items
        SET recibido = %s,
            comentario_recepcion = %s,
            fecha_recepcion_item = CURRENT_TIMESTAMP,
            usuario_recepcion = %s
        WHERE id = %s
          AND pedido_id = %s
        """

        pedidos_db.execute(
            query,
            (
                recibido,
                comentario_recepcion,
                usuario_recepcion,
                item_id,
                pedido_id,
            ),
        )

    def marcar_pedido_recibido(self, pedido_id: int) -> None:
        query = """
        UPDATE pedidos
        SET estado = 'RECIBIDO',
            fecha_recepcion = CURRENT_TIMESTAMP
        WHERE id = %s
        """

        pedidos_db.execute(query, (pedido_id,))

    def get_order_recepcion_resumen(self, pedido_id: int) -> dict[str, Any]:
        query = """
        SELECT
            COUNT(*) AS total_items,
            SUM(
                CASE
                    WHEN recibido = true THEN 1
                    ELSE 0
                END
            ) AS total_recibidos,
            SUM(
                CASE
                    WHEN recibido = false THEN 1
                    ELSE 0
                END
            ) AS total_no_recibidos,
            SUM(
                CASE
                    WHEN comentario_recepcion IS NOT NULL
                     AND TRIM(comentario_recepcion) <> '' THEN 1
                    ELSE 0
                END
            ) AS total_observaciones
        FROM pedido_items
        WHERE pedido_id = %s
        """

        data = pedidos_db.fetch_one(query, (pedido_id,)) or {}

        return {
            "total_items": int(data.get("total_items") or 0),
            "total_recibidos": int(data.get("total_recibidos") or 0),
            "total_no_recibidos": int(data.get("total_no_recibidos") or 0),
            "total_observaciones": int(data.get("total_observaciones") or 0),
        }
    
    def get_cantidad_recomendada_producto(self, codigo: str) -> dict[str, Any]:
        query = """
        SELECT
            CAST(SUM(
                CASE
                    WHEN Fecha BETWEEN DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND CURDATE()
                    THEN IFNULL(Egreso, 0)
                    ELSE 0
                END
            ) AS DECIMAL(18,3)) AS ventas_7_dias,

            CAST(SUM(
                CASE
                    WHEN Fecha BETWEEN DATE_SUB(CURDATE(), INTERVAL 30 DAY) AND CURDATE()
                    THEN IFNULL(Egreso, 0)
                    ELSE 0
                END
            ) AS DECIMAL(18,3)) AS ventas_30_dias
        FROM v_kardexproductos
        WHERE (Codigo = %s OR CodigoBarra = %s)
        AND IFNULL(Egreso, 0) > 0
        """

        data = db.fetch_one(query, (codigo, codigo)) or {}

        ventas_7 = float(data.get("ventas_7_dias") or 0)
        ventas_30 = float(data.get("ventas_30_dias") or 0)

        recomendacion_semanal = round(ventas_7)
        recomendacion_mensual = round(ventas_30 / 4) if ventas_30 > 0 else 0

        return {
            "codigo": codigo,
            "ventas_7_dias": ventas_7,
            "ventas_30_dias": ventas_30,
            "recomendacion_semanal": recomendacion_semanal,
            "recomendacion_mensual": recomendacion_mensual,
        }

    # 🔥 NUEVO: Función para histórico de ventas de N días
    def get_ventas_historicas_totales(self, codigo: str, dias: int) -> float:
        query = """
        SELECT CAST(SUM(IFNULL(Egreso, 0)) AS DECIMAL(18,3)) AS total_ventas
        FROM v_kardexproductos
        WHERE (Codigo = %s OR CodigoBarra = %s)
          AND Fecha BETWEEN DATE_SUB(CURDATE(), INTERVAL %s DAY) AND CURDATE()
        """
        data = db.fetch_one(query, (codigo, codigo, dias))
        return float(data.get("total_ventas") or 0) if data else 0.0

    # 🔥 NUEVO: Función para obtener el costo más bajo 
    def get_lowest_cost_provider(self, codigo: str, proveedor: str, meses: int = 3) -> dict[str, Any] | None:
        fecha_desde = self._restar_meses(date.today(), meses)
        
        query = """
        SELECT Costo, IVA
        FROM v_kardexproductos
        WHERE (Codigo = %s OR CodigoBarra = %s)
          AND LOWER(TRIM(NombreProveedor)) = LOWER(TRIM(%s))
          AND Fecha >= %s
          AND Costo IS NOT NULL AND Costo > 0
        ORDER BY Costo ASC
        LIMIT 1
        """
        
        row = db.fetch_one(query, (codigo, codigo, proveedor, fecha_desde))
        if row:
            return {
                "costo_minimo": float(row["Costo"]),
                "tiene_iva": str(row["IVA"]).strip().upper() in ["S", "SI", "1", "TRUE", "Y", "YES"]
            }
        return None

    # 🔥 NUEVO: Función para historial de costos en N meses
    def get_cost_history_provider(self, codigo: str, proveedor: str, fecha_inicio: date, fecha_fin: date) -> list[dict[str, Any]]:
        query = """
        SELECT Fecha, Costo, IVA, NombreDocumento
        FROM v_kardexproductos
        WHERE (Codigo = %s OR CodigoBarra = %s)
          AND LOWER(TRIM(NombreProveedor)) = LOWER(TRIM(%s))
          AND Fecha BETWEEN %s AND %s
          AND Costo IS NOT NULL AND Costo > 0
        ORDER BY Fecha DESC
        """
        
        rows = db.fetch_all(query, (codigo, codigo, proveedor, fecha_inicio, fecha_fin))
        
        resultado = []
        ultimo_costo = None
        
        for row in rows:
            costo_actual = float(row["Costo"])
            
            # Filtrar repetidos o variaciones menores a 2 centavos
            if ultimo_costo is None or abs(costo_actual - ultimo_costo) >= 0.02:
                # Aseguramos que la fecha sea serializable para JSON
                fecha_str = row["Fecha"].isoformat() if isinstance(row["Fecha"], date) else row["Fecha"]
                
                resultado.append({
                    "fecha": fecha_str,
                    "costo": costo_actual,
                    "tiene_iva": str(row["IVA"]).strip().upper() in ["S", "SI", "1", "TRUE", "Y", "YES"],
                    "documento": row["NombreDocumento"]
                })
                ultimo_costo = costo_actual
                
        return resultado