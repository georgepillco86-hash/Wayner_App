import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// --- NUEVOS IMPORTS PARA LA EPSON ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  // ==========================================
  // LÓGICA 1: IMPRESIÓN TÉRMICA BLUETOOTH
  // ==========================================
  Future<void> _printCenefaBluetooth() async {
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
        final selectedPrinter = await Navigator.push(
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
            printed ? 'Cenefa enviada a térmica' : 'No se pudo imprimir',
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

  // ==========================================
  // LÓGICA 2: IMPRESIÓN EPSON (CARTELA A4/A5)
  // ==========================================
  void _mostrarOpcionesCartela() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Tamaño de Cartela',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '¿En qué tamaño de hoja deseas imprimir esta cartela?',
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _imprimirCartelaEpson(PdfPageFormat.a5);
            },
            icon: const Icon(Icons.note_outlined),
            label: const Text('A5 (Mitad)'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _imprimirCartelaEpson(PdfPageFormat.a4);
            },
            icon: const Icon(Icons.insert_page_break_outlined),
            label: const Text('A4 (Completa)'),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimirCartelaEpson(PdfPageFormat format) async {
    final name = _productPrice?.nombreProducto ?? widget.product.nombre;
    final code = _productPrice?.codigoBarra ?? widget.product.codigo;
    final price = _productPrice?.precioConIva ?? 0.0;

    final qrData =
        'Producto: $name\nCódigo: $code\nPrecio venta: \$${price.toStringAsFixed(2)}';

    final doc = pw.Document();
    final bool isA4 = format == PdfPageFormat.a4;
    final pageFormat = isA4 ? PdfPageFormat.a4.landscape : PdfPageFormat.a5;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          if (isA4) {
            // ==========================================
            // DISEÑO A4 (HORIZONTAL - HOJA COMPLETA)
            // ==========================================
            return pw.Container(
              padding: const pw.EdgeInsets.all(30),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    flex: 30,
                    child: pw.Align(
                      alignment: pw.Alignment.topCenter,
                      child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        child: pw.Text(
                          name.toUpperCase(),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            color: PdfColors.blue900,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 65,
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 70,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Expanded(
                          flex: 65,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.FittedBox(
                                fit: pw.BoxFit.scaleDown,
                                child: pw.Text(
                                  'PRECIO ESPECIAL',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 45,
                                  ),
                                ),
                              ),
                              pw.SizedBox(height: 10),
                              pw.Expanded(
                                child: pw.FittedBox(
                                  fit: pw.BoxFit.contain,
                                  child: pw.Text(
                                    '\$${price.toStringAsFixed(2)}',
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 40),
                        pw.Expanded(
                          flex: 35,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.Expanded(
                                child: pw.Center(
                                  child: pw.AspectRatio(
                                    aspectRatio: 1,
                                    child: pw.BarcodeWidget(
                                      barcode: pw.Barcode.qrCode(),
                                      data: qrData,
                                      drawText: false,
                                    ),
                                  ),
                                ),
                              ),
                              pw.SizedBox(height: 15),
                              pw.FittedBox(
                                fit: pw.BoxFit.scaleDown,
                                child: pw.Text(
                                  code,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } else {
            // ==========================================
            // DISEÑO A5 (VERTICAL - MAXIMIZADO EN MITAD SUPERIOR)
            // ==========================================
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              child: pw.Column(
                children: [
                  // --- MITAD SUPERIOR (ÁREA ACTIVA) ---
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(
                        15,
                      ), // 🔥 Redujimos márgenes para ganar área
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // TÍTULO MASIVO
                          pw.Expanded(
                            flex:
                                35, // Damos más peso al título para que crezca
                            child: pw.Align(
                              alignment: pw.Alignment.center,
                              child: pw.FittedBox(
                                fit: pw.BoxFit.scaleDown,
                                child: pw.Text(
                                  name.toUpperCase(),
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(
                                    color: PdfColors.blue900,
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize:
                                        60, // 🔥 Base enorme, se achicará solo lo necesario
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // CUERPO (PRECIO + QR)
                          pw.Expanded(
                            flex: 65,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                // IZQUIERDA: PRECIO
                                pw.Expanded(
                                  flex: 65,
                                  child: pw.Column(
                                    mainAxisAlignment: pw.MainAxisAlignment.end,
                                    children: [
                                      pw.FittedBox(
                                        fit: pw.BoxFit.scaleDown,
                                        child: pw.Text(
                                          'PRECIO ESPECIAL',
                                          style: pw.TextStyle(
                                            fontWeight: pw.FontWeight.bold,
                                            fontSize: 40,
                                          ),
                                        ), // 🔥 Base gigante
                                      ),
                                      pw.SizedBox(height: 5),
                                      pw.Expanded(
                                        child: pw.FittedBox(
                                          fit: pw
                                              .BoxFit
                                              .contain, // Crece como un globo hasta llenar el área
                                          child: pw.Text(
                                            '\$${price.toStringAsFixed(2)}',
                                            style: pw.TextStyle(
                                              fontWeight: pw.FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                pw.SizedBox(width: 25),
                                // DERECHA: QR + CÓDIGO
                                pw.Expanded(
                                  flex: 35,
                                  child: pw.Column(
                                    mainAxisAlignment: pw.MainAxisAlignment.end,
                                    children: [
                                      pw.Expanded(
                                        // 🔥 Hace que el QR crezca dinámicamente en vez de estar fijo
                                        child: pw.Center(
                                          child: pw.AspectRatio(
                                            aspectRatio: 1,
                                            child: pw.BarcodeWidget(
                                              barcode: pw.Barcode.qrCode(),
                                              data: qrData,
                                              drawText: false,
                                            ),
                                          ),
                                        ),
                                      ),
                                      pw.SizedBox(height: 10),
                                      pw.FittedBox(
                                        fit: pw.BoxFit.scaleDown,
                                        child: pw.Text(
                                          code,
                                          style: pw.TextStyle(
                                            fontWeight: pw.FontWeight.bold,
                                            fontSize: 35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- MITAD INFERIOR (ESPACIO EN BLANCO) ---
                  pw.Expanded(flex: 1, child: pw.SizedBox()),
                ],
              ),
            );
          }
        },
      ),
    );

    // ==========================================
    // LÓGICA DE IMPRESIÓN
    // ==========================================
    try {
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat f) async => doc.save(),
        );
      } else {
        final printers = await Printing.listPrinters();
        Printer? targetPrinter;

        try {
          targetPrinter = printers.firstWhere(
            (p) => p.name.contains("AnyDesk v4 Printer Driver"),
          );
        } catch (e) {
          targetPrinter = null;
        }

        if (targetPrinter != null) {
          await Printing.directPrintPdf(
            printer: targetPrinter,
            onLayout: (PdfPageFormat f) async => doc.save(),
            usePrinterSettings: true,
          );
        } else {
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat f) async => doc.save(),
            usePrinterSettings: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al procesar cartela: $e')));
    }
  }

  // ==========================================
  // INTERFAZ DE USUARIO
  // ==========================================
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
                  "Vista previa de etiqueta",
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _productPrice == null
                        ? null
                        : _printCenefaBluetooth,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Cenefa', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _productPrice == null
                        ? null
                        : _mostrarOpcionesCartela,
                    icon: const Icon(Icons.print),
                    label: const Text(
                      'Cartela',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
