import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/storage/session_storage.dart';
import '../../../features/auth/screens/login_screen.dart';
import '../services/scanner_service.dart';

class ScannerPriceScreen extends StatefulWidget {
  const ScannerPriceScreen({super.key});

  @override
  State<ScannerPriceScreen> createState() => _ScannerPriceScreenState();
}

class _ScannerPriceScreenState extends State<ScannerPriceScreen> {
  final ScannerService _scannerService = ScannerService();
  final MobileScannerController _cameraController = MobileScannerController();

  bool _isProcessing = false;
  String? _codigo;
  String? _nombreProducto;
  double? _precioFinal;
  String? _errorMessage;

  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'es_EC',
    symbol: '\$',
    decimalDigits: 2,
  );

  Future<void> _logout() async {
    await SessionStorage.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    final code = barcode?.rawValue;

    if (code == null || code.trim().isEmpty) return;

    setState(() {
      _isProcessing = true;
      _codigo = code.trim();
      _errorMessage = null;
    });

    try {
      final producto = await _scannerService.buscarProductoPorCodigo(code.trim());

      if (!mounted) return;

      setState(() {
        _nombreProducto = producto.nombreProducto;
        _precioFinal = producto.precioConIva;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _nombreProducto = null;
        _precioFinal = null;
        _errorMessage = 'Producto no encontrado';
      });
    } finally {
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1F6F8B);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escáner de precios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: MobileScanner(
              controller: _cameraController,
              onDetect: _onDetect,
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              color: Colors.white,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_codigo == null) ...[
                    const Icon(
                      Icons.qr_code_scanner,
                      size: 52,
                      color: primaryColor,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Escanea un código de barras o QR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else if (_errorMessage != null) ...[
                    const Icon(
                      Icons.error_outline,
                      size: 52,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Código: $_codigo',
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Text(
                      _currencyFormatter.format(_precioFinal ?? 0),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _nombreProducto ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Código: $_codigo',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                  if (_isProcessing) ...[
                    const SizedBox(height: 18),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}