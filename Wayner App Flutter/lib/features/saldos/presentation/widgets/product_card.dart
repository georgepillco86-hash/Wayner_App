import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'stock_health_bar.dart';
import '../../data/models/product_balance.dart';

import '../../../cronograma/presentation/screens/cronograma_form_screen.dart';

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
        child: ListTile(
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
              // --- NUEVO: ALERTA DE LEAD TIME (CRONOGRAMA FALTANTE) ---
              // Asumimos que product.alertaLeadTime es true cuando falta configurar
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
      ),
    );
  }
}
