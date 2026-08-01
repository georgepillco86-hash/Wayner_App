import 'package:flutter/material.dart';
import 'stock_health_bar.dart';
import '../../data/models/product_balance.dart';

import '../../../cronograma/presentation/screens/cronograma_form_screen.dart';

// 🔥 Importamos las 3 ventanas flotantes
import 'kardex_flotante_dialog.dart';
import 'ventas_flotante_dialog.dart';
import 'cenefa_flotante_dialog.dart';

class ProductCard extends StatelessWidget {
  final ProductBalance product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 4.0,
        ), // Un poco de respiro vertical
        child: Column(
          children: [
            ListTile(
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Usamos Expanded para que el nombre ocupe el espacio disponible
                  // sin empujar al ícono de advertencia fuera de la pantalla.
                  Expanded(
                    child: Text(
                      product.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  // --- ALERTA DE LEAD TIME (CRONOGRAMA FALTANTE) ---
                  if (product.alertaLeadTime == true)
                    Tooltip(
                      message:
                          product.mensajeAlerta ??
                          'Falta cronograma. Toque para crear.',
                      child: GestureDetector(
                        onTap: () {
                          // Redirige directamente al formulario
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  CronogramaFormScreen(onSaved: () {}),
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: Icon(
                            Icons.warning_rounded,
                            color: Colors.red, // Advertencia visual urgente
                            size: 26.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Código: ${product.codigo}\nMarca: ${product.marca ?? '-'}\nClase: ${product.clase ?? '-'}',
                    ),
                    const SizedBox(height: 12), // Espaciador antes de la barra
                    // --- BARRA DE SALUD DEL INVENTARIO ---
                    StockHealthBar(
                      product: product,
                      diasCobertura:
                          7, // Evaluamos el nivel de stock para la próxima semana
                    ),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // --- SECCIÓN DEL PRECIO ---
                  Text(
                    '\$${product.precio.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // --- NUEVO: BOTONERA DE ACCIONES RÁPIDAS (Modales) ---
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botón: Ventas
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => VentasFlotanteDialog(
                          codigoProducto: product.codigo,
                          nombreProducto: product.nombre,
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.bar_chart,
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    label: const Text('Ventas', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),

                  // Botón: Kardex
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => KardexFlotanteDialog(
                          codigoProducto: product.codigo,
                          nombreProducto: product.nombre,
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.table_chart,
                      size: 18,
                      color: Colors.teal.shade700,
                    ),
                    label: const Text('Kardex', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),

                  // Botón: Cenefa
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) =>
                            CenefaFlotanteDialog(product: product),
                      );
                    },
                    icon: Icon(
                      Icons.print,
                      size: 18,
                      color: Colors.deepPurple.shade700,
                    ),
                    label: const Text('Cenefa', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
