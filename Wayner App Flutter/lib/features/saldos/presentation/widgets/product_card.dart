import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'stock_health_bar.dart';

import '../../data/models/product_balance.dart';

class ProductCard extends StatelessWidget {
  final ProductBalance product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    // Si decides volver a usar el formatter en el futuro lo puedes dejar,
    // aunque el StockHealthBar ya maneja los números enteros internamente.
    // final formatter = NumberFormat('#,##0.###');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 4.0,
        ), // Un poco de respiro vertical
        child: ListTile(
          title: Text(
            product.nombre,
            style: const TextStyle(fontWeight: FontWeight.w700),
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
                // --- NUEVO: BARRA DE SALUD DEL INVENTARIO ---
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
              // Eliminamos el texto redundante de stock de aquí porque
              // la nueva barra de salud (StockHealthBar) ya lo indica gráficamente.
            ],
          ),
        ),
      ),
    );
  }
}
