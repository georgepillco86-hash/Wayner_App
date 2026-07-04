import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/product_balance.dart';

class ProductCard extends StatelessWidget {
  final ProductBalance product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.###');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(
          product.nombre,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Código: ${product.codigo}\nMarca: ${product.marca ?? '-'}\nClase: ${product.clase ?? '-'}',
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize
              .min, // Evita que la columna desborde los límites del ListTile
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // --- SECCIÓN DEL PRECIO ---
            Text(
              '\$${product.precio.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Theme.of(
                  context,
                ).colorScheme.primary, // Usa el color principal del tema
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6), // Espaciador
            // --- SECCIÓN DEL STOCK ---
            const Text(
              'Stock',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.0),
            ),
            Text(
              formatter.format(product.stock),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
