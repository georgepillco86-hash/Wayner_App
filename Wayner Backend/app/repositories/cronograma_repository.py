import json
import datetime
from typing import List, Optional
from app.core.pedidos_database import pedidos_db 

class CronogramaRepository:

    def eliminar_cronograma_proveedor(self, proveedor: str) -> None:
        """Elimina el cronograma anterior de un proveedor para permitir la edición limpia."""
        query = "DELETE FROM ferrotienda.cronograma_pedidos WHERE proveedor = %s"
        pedidos_db.execute(query, (proveedor,))

    def actualizar_whatsapp_proveedor(self, proveedor: str, celular: str) -> None:
        """(Opcional) Mantiene sincronizado el número en el maestro de proveedores."""
        if celular and celular.strip():
            query = """
                UPDATE ferrotienda.proveedores 
                SET whatsapp = %s 
                WHERE nombre = %s
            """
            pedidos_db.execute(query, (celular.strip(), proveedor))

    def crear_cronograma(self, data: dict) -> bool:
        proveedor = data["proveedor"]
        contacto_celular = data.get("contacto_celular", "")
        frecuencia_texto = data["frecuencia"]
        pares = data["pares"]
        repetir_meses = data["repetir_meses"]
        usuarios_list = data["usuarios_vinculados"]
        usuarios = json.dumps(usuarios_list)
        
        # 1. ACTUALIZAR WHATSAPP EN MAESTRO (Opcional, pero recomendado como respaldo)
        self.actualizar_whatsapp_proveedor(proveedor, contacto_celular)

        # 2. ELIMINACIÓN INTELIGENTE (Editar)
        self.eliminar_cronograma_proveedor(proveedor)
        
        # 3. TRADUCCIÓN DE TEXTO A ENTERO
        if frecuencia_texto == 'Semanal':
            frecuencia_db = 7
            semanas_salto = 1
        elif frecuencia_texto == 'Quincenal':
            frecuencia_db = 15
            semanas_salto = 2
        elif frecuencia_texto == 'Mensual':
            frecuencia_db = 30
            semanas_salto = 4
        else:
            frecuencia_db = 7
            semanas_salto = 1

        # 4. GUARDAR EL MAESTRO (cronograma_pedidos) - AHORA INCLUYE LA COLUMNA CONTACTO
        fecha_inicio_str = pares[0]['visita'].replace('Z', '') if isinstance(pares[0]['visita'], str) else pares[0]['visita']
        fecha_inicio_base = datetime.datetime.fromisoformat(str(fecha_inicio_str)) if isinstance(fecha_inicio_str, str) else fecha_inicio_str
        
        query_maestro = """
            INSERT INTO ferrotienda.cronograma_pedidos 
            (proveedor, frecuencia, fecha_inicio, usuarios_vinculados, activo, contacto)
            VALUES (%s, %s, %s, %s, %s, %s);
        """
        pedidos_db.execute(
            query_maestro, 
            (proveedor, frecuencia_db, fecha_inicio_base, usuarios, True, contacto_celular)
        )
        
        # 5. RECUPERAR EL ID RECIÉN CREADO
        query_id = "SELECT id FROM ferrotienda.cronograma_pedidos WHERE proveedor = %s ORDER BY id DESC LIMIT 1;"
        resultado_maestro = pedidos_db.fetch_one(query_id, (proveedor,))
        
        if not resultado_maestro:
            return False
            
        cronograma_id = resultado_maestro['id']
        total_semanas_duracion = repetir_meses * 4 
        
        # 6. CLONACIÓN DE LOS PARES
        fechas_a_insertar = []
        for par in pares:
            visita_str = par['visita'].replace('Z', '') if isinstance(par['visita'], str) else par['visita']
            entrega_str = par['entrega'].replace('Z', '') if isinstance(par['entrega'], str) else par['entrega']
            
            visita_base = datetime.datetime.fromisoformat(str(visita_str)) if isinstance(visita_str, str) else visita_str
            entrega_base = datetime.datetime.fromisoformat(str(entrega_str)) if isinstance(entrega_str, str) else entrega_str
            
            semanas_avanzadas = 0
            while semanas_avanzadas < total_semanas_duracion:
                visita_futura = visita_base + datetime.timedelta(weeks=semanas_avanzadas)
                entrega_futura = entrega_base + datetime.timedelta(weeks=semanas_avanzadas)
                fechas_a_insertar.append((visita_futura, entrega_futura))
                semanas_avanzadas += semanas_salto
                
        # 7. GUARDADO DE VISITAS (cronograma_visitas)
        for visita_dt, entrega_dt in fechas_a_insertar:
            query_visita = """
                INSERT INTO ferrotienda.cronograma_visitas 
                (cronograma_id, proveedor, fecha_programada, fecha_entrega, estado, usuarios_vinculados)
                VALUES (%s, %s, %s, %s, %s, %s);
            """
            pedidos_db.execute(query_visita, (cronograma_id, proveedor, visita_dt, entrega_dt, 'Pendiente', usuarios))
            
        return True

    def obtener_visitas_mes(self, mes: int, anio: int) -> List[dict]:
        query = """
            SELECT id, proveedor, fecha_programada, fecha_entrega, estado, usuarios_vinculados
            FROM ferrotienda.cronograma_visitas
            WHERE EXTRACT(MONTH FROM fecha_programada) = %s 
            AND EXTRACT(YEAR FROM fecha_programada) = %s
            ORDER BY fecha_programada ASC
        """
        return pedidos_db.fetch_all(query, (mes, anio))

    def obtener_notificaciones(self, usuario: str) -> List[dict]:
        query = "SELECT * FROM ferrotienda.notificaciones WHERE usuario = %s ORDER BY fecha_creacion DESC LIMIT 20"
        return pedidos_db.fetch_all(query, (usuario,))
        
    def marcar_notificacion_leida(self, notificacion_id: int) -> None:
        pedidos_db.execute("UPDATE ferrotienda.notificaciones SET leido = TRUE WHERE id = %s", (notificacion_id,))

    def obtener_lead_time_proveedor(self, nombre_proveedor: str) -> Optional[int]:
        query = """
            SELECT (fecha_entrega::date - fecha_programada::date) as lead_time
            FROM ferrotienda.cronograma_visitas
            WHERE proveedor = %s AND fecha_entrega IS NOT NULL
            ORDER BY fecha_programada DESC
            LIMIT 1;
        """
        resultados = pedidos_db.fetch_all(query, (nombre_proveedor,))
        if resultados and len(resultados) > 0:
            lead_time = resultados[0].get('lead_time')
            if lead_time is not None:
                return max(0, int(lead_time))
        return None
    
    def marcar_visita_realizada(self, usuario: str, proveedor: str) -> None:
        query = """
        UPDATE ferrotienda.cronograma_visitas
        SET estado = 'REALIZADO'
        WHERE LOWER(proveedor) = LOWER(%s)
          AND estado IN ('PENDIENTE', 'NOTIFICADO')
          AND fecha_programada >= CURRENT_DATE 
          AND fecha_programada <= CURRENT_DATE + INTERVAL '5 days'
        """
        pedidos_db.execute(query, (proveedor,))

    # =========================================================
    # 🔥 RUTAS DE ADMINISTRACIÓN 🔥
    # =========================================================
    def obtener_secuencias_programadas(self) -> List[dict]:
        # Ahora extraemos dinámicamente la "próxima" visita y entrega desde la tabla hija
        query = """
            SELECT 
                cp.id, 
                cp.proveedor, 
                cp.frecuencia, 
                cp.fecha_inicio, 
                cp.usuarios_vinculados, 
                cp.contacto as contacto_celular,
                (
                    SELECT cv.fecha_programada 
                    FROM ferrotienda.cronograma_visitas cv 
                    WHERE cv.cronograma_id = cp.id AND cv.fecha_programada >= CURRENT_DATE 
                    ORDER BY cv.fecha_programada ASC LIMIT 1
                ) as proxima_visita,
                (
                    SELECT cv.fecha_entrega 
                    FROM ferrotienda.cronograma_visitas cv 
                    WHERE cv.cronograma_id = cp.id AND cv.fecha_programada >= CURRENT_DATE 
                    ORDER BY cv.fecha_programada ASC LIMIT 1
                ) as proxima_entrega
            FROM ferrotienda.cronograma_pedidos cp
            WHERE cp.activo = true
            ORDER BY cp.id DESC
        """
        resultados = pedidos_db.fetch_all(query)
        return resultados if resultados else []

    def eliminar_secuencia(self, secuencia_id: int) -> bool:
        query = "DELETE FROM ferrotienda.cronograma_pedidos WHERE id = %s RETURNING id"
        resultado = pedidos_db.fetch_one(query, (secuencia_id,))
        return resultado is not None

    def auto_renovar_cronogramas(self) -> None:
        """Busca cronogramas que se quedarán sin visitas en menos de 30 días y los extiende 3 meses."""
        query_maestros = """
            SELECT cp.id, cp.proveedor, cp.frecuencia, cp.usuarios_vinculados,
                   MAX(cv.fecha_programada) as ultima_visita,
                   MAX(cv.fecha_entrega) as ultima_entrega
            FROM ferrotienda.cronograma_pedidos cp
            JOIN ferrotienda.cronograma_visitas cv ON cp.id = cv.cronograma_id
            WHERE cp.activo = true
            GROUP BY cp.id, cp.proveedor, cp.frecuencia, cp.usuarios_vinculados
            HAVING MAX(cv.fecha_programada) < CURRENT_DATE + INTERVAL '30 days'
        """
        cronogramas_a_renovar = pedidos_db.fetch_all(query_maestros)

        if not cronogramas_a_renovar:
            return

        for c in cronogramas_a_renovar:
            c_id = c['id']
            proveedor = c['proveedor']
            frecuencia_dias = c['frecuencia']
            usuarios = c['usuarios_vinculados']
            ultima_visita = c['ultima_visita']
            ultima_entrega = c['ultima_entrega']

            if ultima_entrega and ultima_visita:
                lead_time = (ultima_entrega.date() - ultima_visita.date()).days
            else:
                lead_time = 2 

            total_ciclos = 90 // frecuencia_dias if frecuencia_dias > 0 else 12

            fechas_a_insertar = []
            for i in range(1, total_ciclos + 1):
                nueva_visita = ultima_visita + datetime.timedelta(days=frecuencia_dias * i)
                nueva_entrega = nueva_visita + datetime.timedelta(days=lead_time)
                fechas_a_insertar.append((nueva_visita, nueva_entrega))

            for v_dt, e_dt in fechas_a_insertar:
                query_insert = """
                    INSERT INTO ferrotienda.cronograma_visitas 
                    (cronograma_id, proveedor, fecha_programada, fecha_entrega, estado, usuarios_vinculados)
                    VALUES (%s, %s, %s, %s, %s, %s);
                """
                pedidos_db.execute(query_insert, (c_id, proveedor, v_dt, e_dt, 'Pendiente', usuarios))