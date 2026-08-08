import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/models/product_price.dart';

class PriceLabelPreview extends StatelessWidget {
  final ProductPrice? productPrice;
  final String fallbackName;
  final String fallbackCode;

  const PriceLabelPreview({
    super.key,
    required this.productPrice,
    required this.fallbackName,
    required this.fallbackCode,
  });

  @override
  Widget build(BuildContext context) {
    final name = productPrice?.nombreProducto ?? fallbackName;
    final code = productPrice?.codigoBarra ?? fallbackCode;
    final price = productPrice?.precioConIva ?? 0;

    final qrData =
        '''
Producto: $name
Código: $code
Precio venta: \$${price.toStringAsFixed(2)}
''';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 4),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- 1. DESCRIPCIÓN ---
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: -0.8,
                  height: 1.0,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6), // Leve separación para respirar
          // --- 2. SECCIÓN DE PRECIO Y QR ---
          Row(
            // 🔥 Cambiado a center para "levantar" los elementos y ocupar el espacio superior
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- COLUMNA IZQUIERDA: PRECIO ---
              Expanded(
                flex: 55,
                child: Column(
                  // 🔥 Centrado para aprovechar la altura disponible
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'PRECIO ESPECIAL',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 26, // 🔥 Más grande
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 90, // 🔥 Aún más gigante
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2.0,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8), // 🔥 Barrera para evitar que choquen
              // --- COLUMNA DERECHA: QR + CÓDIGO NUMÉRICO ---
              Expanded(
                flex: 45,
                child: Column(
                  // 🔥 Centrado para alinearse perfectamente con el precio
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 140,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        code,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 26, // 🔥 Código también más grande
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
