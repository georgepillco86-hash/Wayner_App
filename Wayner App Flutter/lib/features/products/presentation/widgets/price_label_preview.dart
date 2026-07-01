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

    final qrData = '''
Producto: $name
Código: $code
Precio venta: \$${price.toStringAsFixed(2)}
''';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 55,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Precio de venta',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '\$${price.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 26),
              Expanded(
                flex: 45,
                child: Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(4),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 105,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}