import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb; // Importante para detectar la Web
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../logs/services/audit_log_service.dart';
import '../../products/data/models/product_price.dart';
import '../../promociones/models/promocion.dart';

class BluetoothPrinterService {
  static const String _printerMacKey = 'selected_printer_mac';
  static const String _printerNameKey = 'selected_printer_name';

  final AuditLogService _auditLogService = AuditLogService();
  final ApiClient _apiClient = ApiClient();

  Future<List<BluetoothInfo>> getPairedDevices() async {
    // Protección Web: Retorna lista vacía en lugar de buscar Bluetooth nativo
    if (kIsWeb) {
      debugPrint(
        "Web detectada: Retornando lista vacía de dispositivos Bluetooth.",
      );
      return [];
    }

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      await _registrarLogImpresion(
        accion: 'BLUETOOTH_DESCONECTADO',
        detalle: 'Bluetooth apagado al consultar impresoras vinculadas',
      );
      throw Exception('Bluetooth está apagado');
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> saveSelectedPrinter({
    required String macAddress,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerMacKey, macAddress);
    await prefs.setString(_printerNameKey, name);
  }

  Future<String?> getSavedPrinterMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_printerMacKey);
  }

  Future<String?> getSavedPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_printerNameKey);
  }

  Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_printerMacKey);
    await prefs.remove(_printerNameKey);
  }

  Future<bool> connect(String macAddress) async {
    // Protección Web: Simulamos conexión exitosa
    if (kIsWeb) {
      debugPrint(
        "Web detectada: Simulando conexión a impresora Bluetooth ($macAddress).",
      );
      return true;
    }

    final isConnected = await PrintBluetoothThermal.connectionStatus;
    if (isConnected) return true;

    await PrintBluetoothThermal.disconnect;
    await Future.delayed(const Duration(milliseconds: 800));

    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<void> disconnect() async {
    // Protección Web: Evita ejecutar código nativo
    if (kIsWeb) return;

    await PrintBluetoothThermal.disconnect;
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<bool> printPriceLabel({required ProductPrice productPrice}) async {
    // Protección Web: Simulamos impresión exitosa para no bloquear la interfaz
    if (kIsWeb) {
      debugPrint(
        "Web detectada: Simulando impresión exitosa de ${productPrice.nombreProducto}",
      );
      return true;
    }

    final printerName = await getSavedPrinterName();
    final printerMac = await getSavedPrinterMac();

    try {
      final connected = await PrintBluetoothThermal.connectionStatus;

      if (!connected) {
        await _registrarLogImpresion(
          accion: 'BLUETOOTH_DESCONECTADO',
          detalle:
              'Intento de impresión sin conexión. Producto: ${productPrice.nombreProducto}, Código: ${productPrice.codigoBarra}, Impresora: ${printerName ?? '-'}',
        );

        throw Exception('La impresora no está conectada');
      }

      final promocion = await _obtenerPromocionActiva(productPrice.codigoBarra);

      final bytes = await _buildPriceLabel(
        productPrice: productPrice,
        promocion: promocion,
      );

      final result = await PrintBluetoothThermal.writeBytes(bytes);

      await Future.delayed(const Duration(milliseconds: 1200));
      await PrintBluetoothThermal.disconnect;
      await Future.delayed(const Duration(milliseconds: 800));

      await _registrarLogImpresion(
        accion: result ? 'IMPRESION_EXITOSA' : 'ERROR_IMPRESION',
        detalle:
            'Cenefa ${result ? 'impresa correctamente' : 'rechazada por impresora'}. '
            'Tipo: ${promocion == null ? 'NORMAL' : 'PROMOCION'}, '
            'Producto: ${productPrice.nombreProducto}, '
            'Código: ${productPrice.codigoBarra}, '
            'Precio: \$${_precioFinal(productPrice, promocion).toStringAsFixed(2)}, '
            'Impresora: ${printerName ?? '-'}, MAC: ${printerMac ?? '-'}',
      );

      return result;
    } catch (e) {
      await _registrarLogImpresion(
        accion: 'ERROR_IMPRESION',
        detalle:
            'Error imprimiendo cenefa. Producto: ${productPrice.nombreProducto}, Código: ${productPrice.codigoBarra}, Error: $e',
      );

      rethrow;
    }
  }

  Future<Promocion?> _obtenerPromocionActiva(String codigoBarra) async {
    try {
      final response = await _apiClient.get(
        '/api/promociones/activa/$codigoBarra',
      );

      final data = response['data'];

      if (data is Map<String, dynamic>) {
        return Promocion.fromJson(data);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _buildPriceLabel({
    required ProductPrice productPrice,
    required Promocion? promocion,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    final bytes = <int>[];
    bytes.addAll(generator.reset());

    if (promocion == null) {
      bytes.addAll(generator.feed(3));

      final labelImage = await _buildNormalLabelImage(productPrice);

      bytes.addAll(
        generator.imageRaster(
          labelImage,
          align: PosAlign.center,
          highDensityHorizontal: true,
          highDensityVertical: true,
        ),
      );

      bytes.addAll(generator.feed(4));
      return bytes;
    }

    bytes.addAll(generator.feed(12));

    bytes.addAll(
      await _buildPromotionEscPosLabel(
        generator: generator,
        productPrice: productPrice,
        promocion: promocion,
      ),
    );

    bytes.addAll(generator.feed(4));
    return bytes;
  }

  Future<List<int>> _buildPromotionEscPosLabel({
    required Generator generator,
    required ProductPrice productPrice,
    required Promocion promocion,
  }) async {
    final bytes = <int>[];

    final codigo = productPrice.codigoBarra.trim();

    final encabezado = _cleanText(
      promocion.encabezado?.isNotEmpty == true
          ? promocion.encabezado!
          : 'PROMOCION',
    );

    final nombre = _cleanText(
      promocion.nombreProducto.isNotEmpty
          ? promocion.nombreProducto
          : productPrice.nombreProducto,
    );

    final antes = promocion.precioAnterior.toStringAsFixed(2);
    final ahora = promocion.precioActualProm.toStringAsFixed(2);
    final ahorro = promocion.ahorro.toStringAsFixed(2);
    final descuento = _calcularDescuento(promocion);

    final vigencia =
        '${_formatDate(promocion.fechaInicio)} hasta ${_formatDate(promocion.fechaFin)}';

    bytes.addAll(
      generator.text(
        'PROMOCION',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size2,
        ),
      ),
    );

    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        encabezado.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size2,
        ),
      ),
    );

    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        'NOMBRE:',
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size1,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        nombre,
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
          width: PosTextSize.size1,
          height: PosTextSize.size1,
        ),
      ),
    );

    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        'ANTES:',
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size1,
        ),
      ),
    );

    final oldPriceImage = await _buildStrikethroughPriceImage('\$$antes');

    bytes.addAll(
      generator.imageRaster(
        oldPriceImage,
        align: PosAlign.center,
        highDensityHorizontal: true,
        highDensityVertical: true,
      ),
    );

    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        'AHORA',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size1,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        '\$$ahora',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size2,
        ),
      ),
    );

    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        'AHORRO:',
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size1,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        '\$$ahorro',
        styles: const PosStyles(align: PosAlign.left, bold: true),
      ),
    );

    bytes.addAll(
      generator.text(
        'DESCUENTO:',
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size1,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        descuento,
        styles: const PosStyles(align: PosAlign.left, bold: true),
      ),
    );

    bytes.addAll(
      generator.text(
        'VIGENCIA:',
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size1,
        ),
      ),
    );

    bytes.addAll(
      generator.text(
        vigencia,
        styles: const PosStyles(align: PosAlign.left, bold: true),
      ),
    );

    if (promocion.mecanica?.isNotEmpty == true) {
      bytes.addAll(generator.feed(1));

      bytes.addAll(
        generator.text(
          'MECANICA:',
          styles: const PosStyles(
            align: PosAlign.left,
            bold: true,
            width: PosTextSize.size2,
            height: PosTextSize.size1,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          _cleanText(promocion.mecanica!),
          styles: const PosStyles(align: PosAlign.left, bold: true),
        ),
      );
    }

    bytes.addAll(generator.feed(1));

    final smallQrImage = await _buildSmallQrImage(codigo);

    bytes.addAll(
      generator.imageRaster(
        smallQrImage,
        align: PosAlign.center,
        highDensityHorizontal: true,
        highDensityVertical: true,
      ),
    );

    bytes.addAll(
      generator.text(
        codigo,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );

    return bytes;
  }

  Future<img.Image> _buildNormalLabelImage(ProductPrice productPrice) async {
    const width = 384;
    const height = 213;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    _drawWhiteBackground(canvas, width, height);

    final nombre = _cleanText(productPrice.nombreProducto);
    final codigo = productPrice.codigoBarra.trim();
    final precio = '\$${productPrice.precioConIva.toStringAsFixed(2)}';

    _drawText(
      canvas,
      nombre,
      x: 12,
      y: 10,
      width: 360,
      fontSize: 25,
      fontWeight: FontWeight.w900,
      maxLines: 2,
      height: 1.05,
    );

    _drawText(
      canvas,
      'Precio de especial',
      x: 14,
      y: 88,
      width: 220,
      fontSize: 21,
      fontWeight: FontWeight.w800,
      maxLines: 1,
    );

    _drawText(
      canvas,
      precio,
      x: 14,
      y: 118,
      width: 225,
      fontSize: 44,
      fontWeight: FontWeight.w900,
      maxLines: 1,
    );

    _drawQr(canvas, data: codigo, x: 255, y: 68, size: 112);

    _drawText(
      canvas,
      codigo,
      x: 235,
      y: 194,
      width: 140,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      maxLines: 1,
      textAlign: TextAlign.center,
    );

    return _canvasToImage(recorder, width, height);
  }

  Future<img.Image> _buildSmallQrImage(String codigo) async {
    const width = 112;
    const height = 112;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    _drawWhiteBackground(canvas, width, height);

    final qrPainter = QrPainter(
      data: codigo,
      version: QrVersions.auto,
      gapless: false,
      color: Colors.black,
      emptyColor: Colors.white,
    );

    qrPainter.paint(canvas, const Size(112, 112));

    return _canvasToImage(recorder, width, height);
  }

  Future<img.Image> _buildStrikethroughPriceImage(String price) async {
    const width = 384;
    const height = 68;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    _drawWhiteBackground(canvas, width, height);

    _drawText(
      canvas,
      price,
      x: 0,
      y: 0,
      width: width.toDouble(),
      fontSize: 42,
      fontWeight: FontWeight.w900,
      maxLines: 1,
      textAlign: TextAlign.center,
    );

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(const Offset(5, 20), const Offset(100, 20), paint);

    return _canvasToImage(recorder, width, height);
  }

  void _drawWhiteBackground(Canvas canvas, int width, int height) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );
  }

  void _drawQr(
    Canvas canvas, {
    required String data,
    required double x,
    required double y,
    required double size,
  }) {
    canvas.save();
    canvas.translate(x, y);

    final qrPainter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: false,
      color: Colors.black,
      emptyColor: Colors.white,
    );

    qrPainter.paint(canvas, Size(size, size));
    canvas.restore();
  }

  void _drawText(
    Canvas canvas,
    String text, {
    required double x,
    required double y,
    required double width,
    required double fontSize,
    required FontWeight fontWeight,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.left,
    double height = 1.0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: height,
        ),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '...',
    );

    painter.layout(maxWidth: width);
    painter.paint(canvas, Offset(x, y));
  }

  Future<img.Image> _canvasToImage(
    ui.PictureRecorder recorder,
    int width,
    int height,
  ) async {
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(width, height);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _calcularDescuento(Promocion promocion) {
    if (promocion.precioAnterior <= 0) {
      return promocion.mecanica ?? 'PROMOCION';
    }

    final porcentaje = (promocion.ahorro / promocion.precioAnterior) * 100;
    return '${porcentaje.round()}%';
  }

  double _precioFinal(ProductPrice productPrice, Promocion? promocion) {
    return promocion?.precioActualProm ?? productPrice.precioConIva;
  }

  Future<void> _registrarLogImpresion({
    required String accion,
    required String detalle,
  }) async {
    try {
      await _auditLogService.registrarEvento(
        accion: accion,
        modulo: 'IMPRESION',
        detalle: detalle,
      );
    } catch (_) {}
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
