import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../data/services/saldos_api_service.dart';
import '../../data/models/product_balance.dart';
import '../../../products/data/models/product_price.dart';
import '../../../products/presentation/widgets/price_label_preview.dart';
import '../../../printer/services/bluetooth_printer_service.dart';
import '../../../printer/presentation/screens/printer_selection_screen.dart';

class CenefaFlotanteDialog extends StatefulWidget {
  final ProductBalance product;

  const CenefaFlotanteDialog({super.key, required this.product});

  @override
  State<CenefaFlotanteDialog> createState() => _CenefaFlotanteDialogState();
}

class _CenefaFlotanteDialogState extends State<CenefaFlotanteDialog> {
  final SaldosApiService _service = SaldosApiService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();

  bool _isLoading = true;
  ProductPrice? _productPrice;

  @override
  void initState() {
    super.initState();
    _loadProductPrice();
  }

  Future<void> _loadProductPrice() async {
    try {
      final price = await _service.getProductPrice(widget.product.codigo);
      if (mounted) {
        setState(() {
          _productPrice = price;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printLabel() async {
    if (_productPrice == null) return;

    try {
      final savedMac = await _printerService.getSavedPrinterMac();

      if (savedMac != null && savedMac.isNotEmpty) {
        final connected = await _printerService.connect(savedMac);
        if (!connected) {
          await _printerService.clearSavedPrinter();
          throw Exception(
            'No se pudo conectar a la impresora. Selecciónala nuevamente.',
          );
        }
      } else {
        final selectedPrinter = await Navigator.push<BluetoothInfo>(
          context,
          MaterialPageRoute(builder: (_) => const PrinterSelectionScreen()),
        );
        if (selectedPrinter == null) return;
      }

      final printed = await _printerService.printPriceLabel(
        productPrice: _productPrice!,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            printed ? 'Cenefa enviada a imprimir' : 'No se pudo imprimir',
          ),
          backgroundColor: printed ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: MediaQuery.of(context).size.width * 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Vista previa de cenefa",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : PriceLabelPreview(
                    productPrice: _productPrice,
                    fallbackName: widget.product.nombre,
                    fallbackCode: widget.product.codigo,
                  ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _productPrice == null ? null : _printLabel,
                icon: const Icon(Icons.print),
                label: const Text('Imprimir cenefa'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
