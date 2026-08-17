import 'package:flutter/material.dart';
// 🔥 CAMBIO: Quitamos el "show kIsWeb" para poder acceder a defaultTargetPlatform
import 'package:flutter/foundation.dart';

// --- IMPORTS PARA LA EPSON Y PROMOCIONES ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/services/saldos_api_service.dart';
import '../../data/models/product_balance.dart';
import '../../../products/data/models/product_price.dart';
import '../../../products/presentation/widgets/price_label_preview.dart';
import '../../../printer/services/bluetooth_printer_service.dart';
import '../../../printer/presentation/screens/printer_selection_screen.dart';

// 🔥 IMPORTAMOS SERVICIOS DE PROMOCIONES
import '../../../promociones/models/promocion.dart';
import '../../../promociones/services/promocion_service.dart';

class CenefaFlotanteDialog extends StatefulWidget {
  final ProductBalance product;

  const CenefaFlotanteDialog({super.key, required this.product});

  @override
  State<CenefaFlotanteDialog> createState() => _CenefaFlotanteDialogState();
}

class _CenefaFlotanteDialogState extends State<CenefaFlotanteDialog> {
  final SaldosApiService _service = SaldosApiService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final PromocionService _promocionService = PromocionService();

  bool _isLoading = true;
  ProductPrice? _productPrice;
  Promocion? _promocionActiva;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final price = await _service.getProductPrice(widget.product.codigo);

      Promocion? promo;
      try {
        final listaPromos = await _promocionService.listar(
          codigoBarra: widget.product.codigo,
        );
        promo = listaPromos.firstWhere(
          (p) => p.activa == true,
          orElse: () => throw Exception('No promo'),
        );
      } catch (_) {
        promo = null;
      }

      if (mounted) {
        setState(() {
          _productPrice = price;
          _promocionActiva = promo;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printCenefaBluetooth() async {
    if (_productPrice == null && _promocionActiva == null) return;

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

  String _formatPdfDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _imprimirCartelaEpson(PdfPageFormat format) async {
    final bool isPromo = _promocionActiva != null;

    final name = isPromo
        ? (_promocionActiva!.nombreProducto ?? widget.product.nombre)
        : (_productPrice?.nombreProducto ?? widget.product.nombre);
    final code = isPromo
        ? (_promocionActiva!.codigoBarra ?? widget.product.codigo)
        : (_productPrice?.codigoBarra ?? widget.product.codigo);
    final price = isPromo
        ? (_promocionActiva!.precioActualProm ?? 0.0)
        : (_productPrice?.precioConIva ?? 0.0);

    // VARIABLES EXCLUSIVAS DE PROMOCIÓN
    final oldPrice = isPromo ? (_promocionActiva!.precioAnterior ?? 0.0) : 0.0;
    final encabezado = isPromo
        ? (_promocionActiva!.encabezado ?? 'OFERTA')
        : '';
    final ahorro = isPromo ? (_promocionActiva!.ahorro ?? 0.0) : 0.0;
    final mecanica = isPromo ? (_promocionActiva!.mecanica ?? '') : '';
    final fInicio = isPromo
        ? _formatPdfDate(_promocionActiva!.fechaInicio)
        : '';
    final fFin = isPromo ? _formatPdfDate(_promocionActiva!.fechaFin) : '';

    final qrData =
        '''Producto: $name\nCódigo: $code\nPrecio venta: \$${price.toStringAsFixed(2)}\n${isPromo ? 'Mecánica: $mecanica\nVálido: $fInicio al $fFin' : ''}''';

    final doc = pw.Document();
    final bool isA4 = format == PdfPageFormat.a4;
    final pageFormat = isA4 ? PdfPageFormat.a4.landscape : PdfPageFormat.a5;

    // --- BLOQUE DINÁMICO DE TÍTULO ---
    pw.Widget buildHeaderBlock(bool isA4Size) {
      if (isPromo) {
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                encabezado.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.red,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 60 : 50,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                name.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColors.blue900,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 45 : 35,
                ),
              ),
            ),
          ],
        );
      } else {
        return pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(
            name.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: PdfColors.blue900,
              fontWeight: pw.FontWeight.bold,
              fontSize: isA4Size ? 65 : 60,
            ),
          ),
        );
      }
    }

    // --- BLOQUE DINÁMICO DE PRECIOS ---
    pw.Widget buildPriceBlock(bool isA4Size) {
      if (isPromo) {
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                'PRECIO ANTERIOR: \$${oldPrice.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  color: PdfColors.grey700,
                  decoration: pw.TextDecoration.lineThrough,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 25 : 20,
                ),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                child: pw.Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                'AHORRO: \$${ahorro.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  color: PdfColors.green800,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 25 : 20,
                ),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                'MECÁNICA: ${mecanica.toUpperCase()}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 20 : 16,
                ),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                'VÁLIDO DEL $fInicio AL $fFin',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 18 : 14,
                ),
              ),
            ),
          ],
        );
      } else {
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                'PRECIO ESPECIAL',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: isA4Size ? 45 : 40,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                child: pw.Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          if (isA4) {
            // ================== DISEÑO A4 ==================
            return pw.Container(
              padding: const pw.EdgeInsets.all(30),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    flex: isPromo
                        ? 35
                        : 30, // Damos un poco más de espacio arriba si es promo
                    child: pw.Align(
                      alignment: pw.Alignment.topCenter,
                      child: buildHeaderBlock(true),
                    ),
                  ),
                  pw.Expanded(
                    flex: isPromo ? 65 : 70,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Expanded(flex: 65, child: buildPriceBlock(true)),
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
            // ================== DISEÑO A5 ==================
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              child: pw.Column(
                children: [
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(15),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Expanded(
                            flex: isPromo ? 40 : 35,
                            child: pw.Align(
                              alignment: pw.Alignment.center,
                              child: buildHeaderBlock(false),
                            ),
                          ),
                          pw.Expanded(
                            flex: isPromo ? 60 : 65,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Expanded(
                                  flex: 65,
                                  child: buildPriceBlock(false),
                                ),
                                pw.SizedBox(width: 25),
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
                  pw.Expanded(flex: 1, child: pw.SizedBox()),
                ],
              ),
            );
          }
        },
      ),
    );

    try {
      // 🚀 SOLUCIÓN APLICADA AQUÍ: Control de plataformas
      if (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat f) async => doc.save(),
          name: 'Cartela_Ferrotienda',
        );
      } else {
        // En Escritorio (Windows) busca la impresora AnyDesk
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
                // 🔥 SOLUCIÓN: Flexible + SingleChildScrollView permite hacer scroll
                : Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: PriceLabelPreview(
                        productPrice: _productPrice,
                        promocion: _promocionActiva,
                        fallbackName: widget.product.nombre,
                        fallbackCode: widget.product.codigo,
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        (_productPrice == null && _promocionActiva == null)
                        ? null
                        : _printCenefaBluetooth,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Cenefa', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (_productPrice == null && _promocionActiva == null)
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
