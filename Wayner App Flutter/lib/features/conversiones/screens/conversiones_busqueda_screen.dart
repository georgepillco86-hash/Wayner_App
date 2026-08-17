import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../saldos/data/services/saldos_api_service.dart';
import '../services/conversiones_service.dart';
import '../../pedidos/services/pedidos_service.dart';
import '../../../core/storage/session_storage.dart';

// 🔥 IMPORTAMOS TU PROPIO ESCÁNER PARA EVITAR ERRORES DE CÁMARA 🔥
import '../../saldos/presentation/screens/barcode_scanner_screen.dart';

class ConversionesBusquedaScreen extends StatefulWidget {
  const ConversionesBusquedaScreen({super.key});

  @override
  State<ConversionesBusquedaScreen> createState() =>
      _ConversionesBusquedaScreenState();
}

class _ConversionesBusquedaScreenState
    extends State<ConversionesBusquedaScreen> {
  final SaldosApiService _saldosService = SaldosApiService();
  final ConversionesService _conversionesService = ConversionesService();
  final PedidosService _pedidosService = PedidosService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _resultados = [];
  bool _isLoading = false;

  List<String> _unidadesGlobales = ["UNIDADES"];
  String _nombreUsuario = "Desconocido";

  // Carrito de productos a convertir (AQUÍ GUARDAMOS EL DESTINO)
  List<Map<String, dynamic>> _carrito = [];

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    final user = await SessionStorage.getUser();
    if (mounted && user != null) {
      setState(() => _nombreUsuario = user.nombreUsuario);
    }

    try {
      final uni = await _pedidosService.obtenerUnidadesMedida();
      if (uni.isNotEmpty && mounted) {
        setState(() => _unidadesGlobales = uni);
      }
    } catch (e) {
      // Mantiene "UNIDADES" por defecto
    }
  }

  Future<void> _buscar() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isLoading = true;
      _resultados = [];
    });
    try {
      final data = await _saldosService.buscarRapido(termino: query);
      final Map<String, dynamic> productosUnicos = {};
      for (var item in data) {
        final codigo =
            item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
        if (codigo.isNotEmpty && !productosUnicos.containsKey(codigo)) {
          productosUnicos[codigo] = item;
        }
      }
      setState(() => _resultados = productosUnicos.values.toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _escanearCodigo() async {
    if (kIsWeb) return;

    try {
      final code = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      );
      if (code != null && code.isNotEmpty) {
        _searchController.text = code;
        _buscar();
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo abrir la cámara")),
        );
      }
    }
  }

  void _seleccionarProducto(Map<String, dynamic> producto) {
    final TextEditingController cantController = TextEditingController(
      text: "1",
    );
    String unidadSeleccionada = _unidadesGlobales.first;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Añadir a la Orden (Destino)"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto["Nombre"] ?? "",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cantController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ], // 🔥 SEGURIDAD: Solo enteros
                    decoration: const InputDecoration(
                      labelText: "Cantidad a obtener",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _unidadesGlobales.contains(unidadSeleccionada)
                        ? unidadSeleccionada
                        : _unidadesGlobales.first,
                    decoration: const InputDecoration(
                      labelText: "Unidad de medida",
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: _unidadesGlobales.map((u) {
                      return DropdownMenuItem(
                        value: u,
                        child: Text(u, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => unidadSeleccionada = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                FilledButton(
                  onPressed: () {
                    final cant = int.tryParse(cantController.text) ?? 0;
                    if (cant > 0) {
                      setState(() {
                        // 🔥 GUARDAMOS COMO DESTINO 🔥
                        _carrito.add({
                          "codigo_destino":
                              producto["Codigo"] ?? producto["codigo"],
                          "nombre_destino":
                              producto["Nombre"] ?? producto["nombre_producto"],
                          "cantidad_destino": cant,
                          "unidad_destino": unidadSeleccionada,
                        });
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Agregado a la orden"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: const Text("Añadir"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _verCarrito() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Orden de Trabajo",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _carrito.length,
                itemBuilder: (_, i) {
                  final item = _carrito[i];
                  return ListTile(
                    leading: const Icon(
                      Icons.move_to_inbox,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      item["nombre_destino"],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Cant: ${item["cantidad_destino"]} ${item["unidad_destino"] ?? ''} | Cód: ${item["codigo_destino"]}",
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() => _carrito.removeAt(i));
                        Navigator.pop(context);
                        _verCarrito(); // Refrescar modal
                      },
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _carrito.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(context); // Cerrar modal
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          await _conversionesService.crearOrdenTrabajo(
                            _carrito,
                            _nombreUsuario,
                          );
                          if (mounted) {
                            Navigator.pop(context); // Cerrar loading
                            Navigator.pop(
                              context,
                              true,
                            ); // Volver a la pantalla principal
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Error: $e"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.save),
                label: const Text("Guardar Orden de Trabajo"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Buscar producto (Destino)"),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: _verCarrito,
              ),
              if (_carrito.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      '${_carrito.length}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "Código o Nombre...",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 0),
                    ),
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _escanearCodigo,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _resultados.isEmpty && !_isLoading
                ? const Center(child: Text("Busca un producto para empezar"))
                : ListView.builder(
                    itemCount: _resultados.length,
                    itemBuilder: (_, index) {
                      final prod = _resultados[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.blueGrey,
                        ),
                        title: Text(
                          prod["Nombre"] ?? "",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          "Cód: ${prod["Codigo"]} | Stock: ${prod["Stock"] ?? 0}",
                        ),
                        trailing: const Icon(
                          Icons.add_circle,
                          color: Colors.green,
                        ),
                        onTap: () => _seleccionarProducto(prod),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
