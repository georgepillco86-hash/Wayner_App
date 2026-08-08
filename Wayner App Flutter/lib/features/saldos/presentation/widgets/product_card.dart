import 'package:flutter/material.dart';
import 'stock_health_bar.dart';
import '../../data/models/product_balance.dart';

import '../../../cronograma/presentation/screens/cronograma_form_screen.dart';

// 🔥 Importamos las ventanas flotantes
import 'kardex_flotante_dialog.dart';
import 'ventas_flotante_dialog.dart';
import 'cenefa_flotante_dialog.dart';
// 🔥 NUEVA: Importamos la ventana del historial de costos
import 'historial_costos_flotante_dialog.dart';

class ProductCard extends StatelessWidget {
  final ProductBalance product;
  final bool esAdmin; // 🔥 NUEVO: Recibimos si es Admin

  const ProductCard({
    super.key,
    required this.product,
    this.esAdmin = false, // Por defecto es falso por seguridad
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 Lógica matemática adaptada a las variables de tu ProductBalance
    final double costoBase = product.costo ?? 0.0;
    final double ivaPorcentaje = product.iva ?? 0.0;

    // Si el porcentaje de IVA es mayor a 0, significa que tiene IVA.
    final bool tieneIva = ivaPorcentaje > 0;

    final double costoCalculado = tieneIva
        ? costoBase * (1 + (ivaPorcentaje / 100.0))
        : costoBase;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          children: [
            ListTile(
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (product.alertaLeadTime == true)
                    Tooltip(
                      message:
                          product.mensajeAlerta ??
                          'Falta cronograma. Toque para crear.',
                      child: GestureDetector(
                        onTap: () {
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
                            color: Colors.red,
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
                    const SizedBox(height: 12),
                    StockHealthBar(product: product, diasCobertura: 7),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // --- PRECIO (+20% GRANDE) ---
                  Text(
                    '\$${product.precio.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20.4, // 🔥 Aumentado en un 20%
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      height: 1.0,
                    ),
                  ),

                  // --- ÚLTIMO COSTO CON IVA (SOLO ADMIN) ---
                  if (esAdmin) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Costo: \$${costoCalculado.toStringAsFixed(4)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      tieneIva ? 'Inc. IVA ($ivaPorcentaje%)' : 'Sin IVA',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1),

            // --- BOTONERA DE ACCIONES RÁPIDAS ---
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

                  // 🔥 Botón: Historial de Costos (SOLO ADMIN)
                  if (esAdmin)
                    TextButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => HistorialCostosFlotanteDialog(
                            codigoProducto: product.codigo,
                            nombreProducto: product.nombre,
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.history,
                        size: 18,
                        color: Colors.orange.shade800,
                      ),
                      label: const Text(
                        'Historial',
                        style: TextStyle(fontSize: 12),
                      ),
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
