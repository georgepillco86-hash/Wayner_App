import 'package:ferrotienda_flutter_proyecto/features/saldos/data/services/saldos_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../services/pedidos_service.dart';
import 'package:ferrotienda_flutter_proyecto/features/mermas/data/services/merma_service.dart';
import 'package:ferrotienda_flutter_proyecto/features/mermas/presentation/screens/merma_screen.dart';
import '../../../core/storage/session_storage.dart';

class GenerarPedidoProveedorDialog extends StatefulWidget {
  final int pedidoId;

  const GenerarPedidoProveedorDialog({super.key, required this.pedidoId});

  @override
  State<GenerarPedidoProveedorDialog> createState() =>
      _GenerarPedidoProveedorDialogState();
}

class _GenerarPedidoProveedorDialogState
    extends State<GenerarPedidoProveedorDialog> {
  final PedidosService service = PedidosService();
  late final SaldosApiService saldosService;

  final MermaService _mermaService = MermaService();
  Set<String> proveedoresConMermas = {};

  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? pedido;
  Map<String, dynamic>? textosGenerados;

  String filtroSeleccionado = "TODOS";

  Map<String, Map<String, dynamic>?> costosGlobalesCache = {};
  Map<String, List<dynamic>> historialCache = {};
  Map<String, Map<String, dynamic>> stockYMinimoCache = {};
  List<String> unidadesGlobales = ["UNIDAD/ES"];

  Set<String> proveedoresEnviados = {};
  SharedPreferences? _prefs;

  final Map<String, TextEditingController> _descProvControllers = {};
  final Map<String, TextEditingController> _descItemControllers = {};
  final Map<String, TextEditingController> _cantControllers = {};
  final Map<String, TextEditingController> _costoControllers = {};

  @override
  void initState() {
    super.initState();
    saldosService = SaldosApiService();
    _cargarTodo();
  }

  @override
  void dispose() {
    for (var c in _descProvControllers.values) {
      c.dispose();
    }
    for (var c in _descItemControllers.values) {
      c.dispose();
    }
    for (var c in _cantControllers.values) {
      c.dispose();
    }
    for (var c in _costoControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getDescProvController(String prov) {
    if (!_descProvControllers.containsKey(prov)) {
      _descProvControllers[prov] = TextEditingController(text: "0");
    }
    return _descProvControllers[prov]!;
  }

  TextEditingController _getDescItemController(String uniqueKey) {
    if (!_descItemControllers.containsKey(uniqueKey)) {
      _descItemControllers[uniqueKey] = TextEditingController(text: "0");
    }
    return _descItemControllers[uniqueKey]!;
  }

  TextEditingController _getCantController(
    String uniqueKey,
    String valorInicial,
  ) {
    if (!_cantControllers.containsKey(uniqueKey)) {
      _cantControllers[uniqueKey] = TextEditingController(text: valorInicial);
    }
    return _cantControllers[uniqueKey]!;
  }

  TextEditingController _getCostoController(
    String uniqueKey,
    String valorInicial,
  ) {
    if (!_costoControllers.containsKey(uniqueKey)) {
      _costoControllers[uniqueKey] = TextEditingController(text: valorInicial);
    }
    return _costoControllers[uniqueKey]!;
  }

  double _getDescuentoProv(String prov) {
    return double.tryParse(_descProvControllers[prov]?.text ?? "0") ?? 0.0;
  }

  double _getDescuentoItem(String uniqueKey) {
    return double.tryParse(_descItemControllers[uniqueKey]?.text ?? "0") ?? 0.0;
  }

  double _obtenerCostoActualParaCalculos(
    String uniqueKey,
    String codigo,
    String proveedor,
    double costoBaseFallback,
  ) {
    if (_costoControllers.containsKey(uniqueKey)) {
      return double.tryParse(_costoControllers[uniqueKey]!.text) ??
          costoBaseFallback;
    }
    return _obtenerUltimoCostoParaProveedor(
      codigo,
      proveedor,
      costoBaseFallback,
    );
  }

  String _formatearSecuencial(int id) {
    int bloque2 = (id / 1000000).ceil();
    if (bloque2 == 0) bloque2 = 1;
    int correlativo = id % 1000000;
    if (correlativo == 0) correlativo = 1000000;

    String b2Str = bloque2.toString().padLeft(3, '0');
    String corrStr = correlativo.toString().padLeft(6, '0');
    return "001-$b2Str-$corrStr";
  }

  Future<void> _cargarProveedoresConMermas() async {
    try {
      final provs = await _mermaService.obtenerProveedoresConMermasPendientes();
      proveedoresConMermas = provs.toSet();
    } catch (e) {
      debugPrint("Error cargando mermas: $e");
    }
  }

  Future<void> _cargarTodo() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      _prefs = await SharedPreferences.getInstance();
      final guardados =
          _prefs?.getStringList('pedido_${widget.pedidoId}_sent') ?? [];
      proveedoresEnviados = guardados.toSet();

      try {
        final uni = await service.obtenerUnidadesMedida();
        if (uni.isNotEmpty) unidadesGlobales = uni;
      } catch (e) {
        debugPrint("Error cargando unidades: $e");
      }

      final dataPedido = await service.obtenerDetallePedidoAdmin(
        widget.pedidoId,
      );
      final dataTextos = await service.obtenerTextosProveedor(widget.pedidoId);

      pedido = dataPedido;
      textosGenerados = dataTextos;

      await Future.wait([
        _cargarCostosGlobales(),
        _cargarHistorialCostos(),
        _cargarStockYMinimoEnVivo(),
        _cargarProveedoresConMermas(),
      ]);
    } catch (e) {
      errorMessage = "Error al cargar la información del pedido.";
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _cargarStockYMinimoEnVivo() async {
    final items = pedido?["items"] as List<dynamic>? ?? [];
    List<Future> peticiones = [];

    for (var item in items) {
      final codigo = item["codigo_producto"]?.toString();
      if (codigo != null &&
          codigo.isNotEmpty &&
          !stockYMinimoCache.containsKey(codigo)) {
        peticiones.add(
          saldosService
              .buscarRapido(termino: codigo)
              .then((resultados) {
                if (resultados.isNotEmpty) {
                  final dataInfo = resultados.first;
                  stockYMinimoCache[codigo] = {
                    "stock":
                        dataInfo["Stock"] ??
                        dataInfo["stock"] ??
                        dataInfo["stock_actual"] ??
                        0,
                    "minimo":
                        dataInfo["Minimo"] ??
                        dataInfo["minimo"] ??
                        dataInfo["stock_minimo"] ??
                        0,
                  };
                }
              })
              .catchError((_) {}),
        );
      }
    }
    await Future.wait(peticiones);
  }

  Future<void> _cargarCostosGlobales() async {
    final items = pedido?["items"] as List<dynamic>? ?? [];
    List<Future> peticiones = [];

    for (var item in items) {
      final codigo = item["codigo_producto"]?.toString();
      if (codigo != null &&
          codigo.isNotEmpty &&
          !costosGlobalesCache.containsKey(codigo)) {
        peticiones.add(
          service
              .obtenerMejorCostoGlobal(codigo, meses: 3)
              .then((costoData) {
                costosGlobalesCache[codigo] = costoData;
              })
              .catchError((_) {}),
        );
      }
    }
    await Future.wait(peticiones);
  }

  Future<void> _cargarHistorialCostos() async {
    final items = pedido?["items"] as List<dynamic>? ?? [];
    List<Future> peticiones = [];

    for (var item in items) {
      final codigo = item["codigo_producto"]?.toString();
      if (codigo != null &&
          codigo.isNotEmpty &&
          !historialCache.containsKey(codigo)) {
        peticiones.add(
          service
              .obtenerHistorialCostos(codigo, 20)
              .then((historial) {
                historialCache[codigo] = historial;
              })
              .catchError((_) {}),
        );
      }
    }
    await Future.wait(peticiones);
  }

  double _obtenerUltimoCostoParaProveedor(
    String codigo,
    String proveedor,
    double costoBaseFallback,
  ) {
    final historial = historialCache[codigo];
    if (historial == null || historial.isEmpty) return costoBaseFallback;

    for (var h in historial) {
      final provHistorial =
          h["proveedor"]?.toString().trim().toUpperCase() ?? "";
      if (provHistorial == proveedor.trim().toUpperCase()) {
        return double.tryParse(h["costo_final"]?.toString() ?? "0") ??
            costoBaseFallback;
      }
    }
    return costoBaseFallback;
  }

  String _formatearFechaCorta(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Future<void> _autoMarcarComoEnviado() async {
    final estadoActual = pedido?["estado"]?.toString().toUpperCase();
    if (estadoActual != "ENVIADO" && estadoActual != "RECIBIDO") {
      try {
        await service.actualizarEstadoPedido(
          pedidoId: widget.pedidoId,
          estado: "ENVIADO",
        );
        if (mounted) {
          setState(() => pedido?["estado"] = "ENVIADO");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "✅ Todos los pedidos enviados. Orden marcada como ENVIADA.",
              ),
            ),
          );
        }
      } catch (e) {}
    }
  }

  Color _getColorPorEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'BORRADOR':
        return Colors.orange;
      case 'ENVIADO':
        return Colors.blue;
      case 'RECIBIDO':
        return Colors.green;
      case 'CANCELADO':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _cambiarProveedor(dynamic itemInfo) async {
    final codigo = itemInfo["codigo_producto"]?.toString() ?? "";
    final itemsPedidoOriginal = pedido?["items"] as List<dynamic>? ?? [];
    final itemReal = itemsPedidoOriginal.firstWhere(
      (i) => i["codigo_producto"]?.toString() == codigo,
      orElse: () => {},
    );
    final itemIdStr = itemReal["id"]?.toString() ?? "0";
    final itemId = int.tryParse(itemIdStr) ?? 0;

    if (codigo.isEmpty || itemId == 0) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final proveedores = await service.obtenerProveedoresProducto(codigo);
      if (!mounted) return;
      Navigator.pop(context);

      if (proveedores.isEmpty) return;

      showModalBottomSheet(
        context: context,
        builder: (_) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Seleccionar Nuevo Destino",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: proveedores.length,
                  itemBuilder: (context, index) {
                    final p = proveedores[index];
                    final nombreProv =
                        p["proveedor"]?.toString() ?? "Sin nombre";

                    return ListTile(
                      leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                      title: Text(nombreProv),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await service.actualizarProveedorItemPedido(
                            pedidoId: widget.pedidoId,
                            itemId: itemId,
                            proveedor: nombreProv,
                          );
                          proveedoresEnviados.clear();
                          if (_prefs != null)
                            await _prefs!.remove(
                              'pedido_${widget.pedidoId}_sent',
                            );
                          _cargarTodo();
                        } catch (e) {}
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  void _verHistorial(String codigo, String nombreProducto) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final historial = await service.obtenerHistorialCostos(codigo, 5);
      if (!mounted) return;
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Historial de Costos",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  nombreProducto,
                  style: const TextStyle(color: Colors.grey),
                ),
                const Divider(),
                Expanded(
                  child: historial.isEmpty
                      ? const Center(
                          child: Text("No hay historial de compras disponible"),
                        )
                      : ListView.builder(
                          itemCount: historial.length,
                          itemBuilder: (context, index) {
                            final h = historial[index];
                            final costoFinal =
                                double.tryParse(
                                  h["costo_final"]?.toString() ?? "0",
                                ) ??
                                0.0;
                            final ivaPct =
                                h["iva_porcentaje"]?.toString() ?? "0";
                            final tieneIva = h["tiene_iva"] == true;
                            final etiquetaIva = tieneIva
                                ? "(Con IVA)"
                                : "(Sin IVA)";

                            return Card(
                              child: ListTile(
                                title: Text(
                                  "\$${costoFinal.toStringAsFixed(3)} $etiquetaIva",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Proveedor: ${h["proveedor"] ?? 'Desconocido'}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      "Fecha: ${h["fecha"]?.toString().split('T').first ?? ''} | Impuesto: $ivaPct% IVA",
                                    ),
                                    Text(
                                      "Doc: ${h["documento"] ?? ''}",
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  Future<void> _guardarCantidadEscrita(
    Map<String, dynamic> item,
    String uniqueKey,
    String valorTipeado,
  ) async {
    double nuevaCant = double.tryParse(valorTipeado) ?? 1.0;
    if (nuevaCant <= 0) nuevaCant = 1.0;

    final itemsPedidoOriginal = pedido?["items"] as List<dynamic>? ?? [];
    final itemReal = itemsPedidoOriginal.firstWhere(
      (i) =>
          i["codigo_producto"]?.toString() ==
          item["codigo_producto"]?.toString(),
      orElse: () => {},
    );
    final itemId = itemReal["id"];

    if (itemId != null) {
      try {
        await service.actualizarCantidadItemPedido(
          pedidoId: widget.pedidoId,
          itemId: itemId,
          cantidad: nuevaCant,
        );
        setState(() {
          item["cantidad_pedida"] = nuevaCant;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Cantidad actualizada",
              style: TextStyle(fontSize: 12),
            ),
            duration: Duration(seconds: 1),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar cantidad: $e")),
        );
      }
    }
  }

  Future<void> _modificarCantidadBoton(
    Map<String, dynamic> item,
    String uniqueKey,
    double delta,
  ) async {
    double cantActual =
        double.tryParse(_getCantController(uniqueKey, "").text) ?? 1.0;
    double nuevaCant = cantActual + delta;
    if (nuevaCant <= 0) return;

    _getCantController(uniqueKey, "").text = nuevaCant.toStringAsFixed(
      nuevaCant.truncateToDouble() == nuevaCant ? 0 : 2,
    );
    await _guardarCantidadEscrita(
      item,
      uniqueKey,
      _getCantController(uniqueKey, "").text,
    );
  }

  Future<void> _cambiarUnidadMedidaItem(
    Map<String, dynamic> item,
    String nuevaUnidad,
  ) async {
    final itemsPedidoOriginal = pedido?["items"] as List<dynamic>? ?? [];
    final itemReal = itemsPedidoOriginal.firstWhere(
      (i) =>
          i["codigo_producto"]?.toString() ==
          item["codigo_producto"]?.toString(),
      orElse: () => {},
    );
    final itemId = itemReal["id"];

    if (itemId != null) {
      try {
        await service.actualizarUnidadItemPedido(
          pedidoId: widget.pedidoId,
          itemId: itemId,
          unidad: nuevaUnidad,
        );
        setState(() => item["unidad"] = nuevaUnidad);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error al cambiar unidad: $e")));
      }
    }
  }

  Future<void> _eliminarProducto(Map<String, dynamic> item) async {
    bool confirmar =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Eliminar producto"),
            content: const Text(
              "¿Estás seguro de quitar este producto del pedido?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Eliminar"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmar) {
      try {
        final itemsPedidoOriginal = pedido?["items"] as List<dynamic>? ?? [];
        final itemReal = itemsPedidoOriginal.firstWhere(
          (i) =>
              i["codigo_producto"]?.toString() ==
              item["codigo_producto"]?.toString(),
          orElse: () => {},
        );
        final itemId = itemReal["id"];
        if (itemId != null) {
          await service.eliminarItemPedido(
            pedidoId: widget.pedidoId,
            itemId: itemId,
          );
        }
        _cargarTodo();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _agregarPromocion(Map<String, dynamic> item) async {
    final TextEditingController cantPromoController = TextEditingController(
      text: "1",
    );
    final nombreProd = item["nombre_producto"]?.toString() ?? "Producto";
    final codigoProd = item["codigo_producto"]?.toString() ?? "";
    final unidadStr = item["unidad"]?.toString() ?? "UNIDAD/ES";

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Añadir Bonificación / Promo"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombreProd,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Se agregará una copia de este producto que será detectada automáticamente como PROMO (Costo \$0) en el PDF.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cantPromoController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Cantidad gratis (Ej: 3)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.card_giftcard),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Agregar Bonificación"),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      final cantPromo = double.tryParse(cantPromoController.text) ?? 1;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await service.agregarItemPedido(
          pedidoId: widget.pedidoId,
          codigoProducto: codigoProd,
          cantidad: cantPromo,
          unidad: unidadStr,
          notaCompra: "PROMO",
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Promoción agregada exitosamente")),
          );
          _cargarTodo();
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _agregarProducto() async {
    final productoSeleccionado =
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) =>
              _BuscadorProductosSheet(saldosService: saldosService),
        );

    if (productoSeleccionado != null) {
      _solicitarCantidadYAgregar(productoSeleccionado);
    }
  }

  Future<void> _solicitarCantidadYAgregar(Map<String, dynamic> producto) async {
    final TextEditingController cantController = TextEditingController(
      text: "1",
    );
    final nombreProd =
        producto["Nombre"] ?? producto["nombre_producto"] ?? "Producto";
    final codigoProd = producto["Codigo"] ?? producto["codigo"] ?? "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    if (unidadesGlobales.isEmpty) unidadesGlobales = ["UNIDAD/ES"];
    if (mounted) Navigator.pop(context);

    String unidadSeleccionada = unidadesGlobales.first;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                "Añadir al Pedido",
                style: TextStyle(fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombreProd,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Código: $codigoProd",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: cantController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Cantidad a pedir",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.shopping_cart_checkout),
                    ),
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: unidadesGlobales.contains(unidadSeleccionada)
                        ? unidadSeleccionada
                        : unidadesGlobales.first,
                    decoration: const InputDecoration(
                      labelText: "Unidad de medida",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.square_foot),
                    ),
                    isExpanded: true,
                    items: unidadesGlobales.map((u) {
                      return DropdownMenuItem(
                        value: u,
                        child: Text(
                          u,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null)
                        setDialogState(() => unidadSeleccionada = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancelar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Agregar a Pedido"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmar == true) {
      final cantidad = double.tryParse(cantController.text) ?? 1;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await service.agregarItemPedido(
          pedidoId: widget.pedidoId,
          codigoProducto: codigoProd,
          cantidad: cantidad,
          unidad: unidadSeleccionada,
          tipoDestino: "VENTA",
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "✅ Producto agregado correctamente: $cantidad $unidadSeleccionada",
              ),
            ),
          );
          _cargarTodo();
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error al agregar producto: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<dynamic> _obtenerItemsParaTexto(String proveedor) {
    final textos = textosGenerados?["textos"] as List<dynamic>? ?? [];
    final provData = textos.firstWhere(
      (t) => t["proveedor"] == proveedor,
      orElse: () => {},
    );
    final items = provData["items_detalle"] as List<dynamic>? ?? [];

    return items.where((item) {
      final tipo = item["tipo_destino"]?.toString().toUpperCase() ?? "VENTA";
      return filtroSeleccionado == "TODOS" || tipo == filtroSeleccionado;
    }).toList();
  }

  String _construirTextoComoPDF(String proveedor, List<dynamic> items) {
    double totalConIvaAcumulado = 0.0;
    double subtotal0 = 0.0;
    double totalDescuentos = 0.0;
    Set<String> codigosVistos = {};

    final idSecuencial = _formatearSecuencial(widget.pedidoId);
    final descGlobalProv = _getDescuentoProv(proveedor);

    String txt = "*Duchi Sanchez Rosa Emperatriz*\n";
    txt += "RUC: 0102249976001\n";
    txt += "*FERROTIENDA*\n";
    txt += "Dirección Matriz: 1ro de Septiembre y Cantón Sígsig\n\n";
    txt += "Orden de pedido #$idSecuencial\n";
    txt += "Proveedor: $proveedor\n";
    txt += "Fecha de emisión: ${_formatearFechaCorta(DateTime.now())}\n";
    txt += "Vigencia del pedido: 1 semana\n\n";
    txt += "📦 *DETALLE DEL PEDIDO:*\n";
    txt += "----------------------------------------\n";

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final cant = double.tryParse(item["cantidad_pedida"].toString()) ?? 0;
      final tieneIva = item["tiene_iva"] == true;
      final codigo = item["codigo_producto"]?.toString() ?? "";

      final costoBaseData =
          double.tryParse(item["costo_base"]?.toString() ?? "0") ?? 0.0;
      final uniqueKey = "${proveedor}_${codigo}_$i";

      final costoUnit = _obtenerCostoActualParaCalculos(
        uniqueKey,
        codigo,
        proveedor,
        costoBaseData,
      );
      final descItem = _getDescuentoItem(uniqueKey);

      double descPorcentajeTotal = descGlobalProv + descItem;
      if (descPorcentajeTotal > 100) descPorcentajeTotal = 100;

      bool esPromo = false;
      if (codigosVistos.contains(codigo)) {
        esPromo = true;
      } else {
        codigosVistos.add(codigo);
      }

      double descUnitario = esPromo
          ? costoUnit
          : (costoUnit * (descPorcentajeTotal / 100));
      double costoFinalUnit = costoUnit - descUnitario;
      double subtotalItem = costoFinalUnit * cant;

      totalDescuentos += (descUnitario * cant);

      if (tieneIva) {
        totalConIvaAcumulado += subtotalItem;
      } else {
        subtotal0 += subtotalItem;
      }

      final unidadTxt = item["unidad"] ?? "UNIDAD/ES";

      txt += "▪️ ${item["nombre_producto"]} ${esPromo ? '🎁 (PROMO)' : ''}\n";
      txt += "   Código: $codigo | Cant: $cant $unidadTxt\n";
      txt +=
          "   Costo U: \$${costoUnit.toStringAsFixed(4)} | Dscto/U: \$${descUnitario.toStringAsFixed(4)}\n";
      txt += "   Total: \$${subtotalItem.toStringAsFixed(2)}\n\n";
    }

    final base15 = totalConIvaAcumulado / 1.15;
    final totalIva = totalConIvaAcumulado - base15;
    final totalNeto = totalConIvaAcumulado + subtotal0;

    txt += "----------------------------------------\n";
    if (descGlobalProv > 0)
      txt += "Descuento del Proveedor Aplicado: $descGlobalProv%\n";
    txt += "Subtotal 15% (Base sin IVA): \$${base15.toStringAsFixed(2)}\n";
    txt += "Subtotal 0% (Base sin IVA): \$${subtotal0.toStringAsFixed(2)}\n";
    txt += "Total Ahorro/Dsctos: \$${totalDescuentos.toStringAsFixed(2)}\n";
    txt += "Valor Total de IVA (15%): \$${totalIva.toStringAsFixed(2)}\n";
    txt += "💰 *TOTAL NETO A PAGAR: \$${totalNeto.toStringAsFixed(2)}*\n";

    return txt;
  }

  Future<void> _compartirUnificado(
    String proveedor,
    List<dynamic> items,
    String textoPlano,
    int totalProveedores,
  ) async {
    final pdf = pw.Document();

    double totalConIvaAcumulado = 0.0;
    double subtotal0 = 0.0;
    double totalDescuentos = 0.0;
    Set<String> codigosVistos = {};

    final idSecuencial = _formatearSecuencial(widget.pedidoId);
    final descGlobalProv = _getDescuentoProv(proveedor);

    final tableData = items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;

      final cant = double.tryParse(item["cantidad_pedida"].toString()) ?? 0;
      final tieneIva = item["tiene_iva"] == true;
      final codigo = item["codigo_producto"]?.toString() ?? "";

      final costoBaseData =
          double.tryParse(item["costo_base"]?.toString() ?? "0") ?? 0.0;
      final uniqueKey = "${proveedor}_${codigo}_$i";

      final costoUnit = _obtenerCostoActualParaCalculos(
        uniqueKey,
        codigo,
        proveedor,
        costoBaseData,
      );
      final descItem = _getDescuentoItem(uniqueKey);

      double descPorcentajeTotal = descGlobalProv + descItem;
      if (descPorcentajeTotal > 100) descPorcentajeTotal = 100;

      bool esPromo = false;
      if (codigosVistos.contains(codigo)) {
        esPromo = true;
      } else {
        codigosVistos.add(codigo);
      }

      double descUnitario = esPromo
          ? costoUnit
          : (costoUnit * (descPorcentajeTotal / 100));
      double costoFinalUnit = costoUnit - descUnitario;
      double subtotalItem = costoFinalUnit * cant;

      totalDescuentos += (descUnitario * cant);

      if (tieneIva) {
        totalConIvaAcumulado += subtotalItem;
      } else {
        subtotal0 += subtotalItem;
      }

      return [
        codigo,
        "${item["nombre_producto"]} ${esPromo ? '(PROMO)' : ''}",
        cant.toString(),
        "\$${costoUnit.toStringAsFixed(4)}",
        "\$${descUnitario.toStringAsFixed(4)}",
        tieneIva ? "15%" : "0%",
        "\$${subtotalItem.toStringAsFixed(2)}",
      ];
    }).toList();

    final base15 = totalConIvaAcumulado / 1.15;
    final totalIva = totalConIvaAcumulado - base15;
    final totalNeto = totalConIvaAcumulado + subtotal0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Text(
              "Duchi Sanchez Rosa Emperatriz",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
            ),
            pw.Text("RUC: 0102249976001"),
            pw.Text(
              "FERROTIENDA",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.Text("Dirección Matriz: 1ro de Septiembre y Cantón Sígsig"),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Orden de pedido #$idSecuencial",
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.Text("Proveedor: $proveedor"),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Fecha de emisión: ${_formatearFechaCorta(DateTime.now())}",
                    ),
                    pw.Text("Vigencia del pedido: 1 semana"),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'Código',
                'Descripción',
                'Cant.',
                'Costo U.',
                'Dscto.',
                'IVA',
                'Total',
              ],
              data: tableData,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
              },
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (descGlobalProv > 0)
                    pw.Text(
                      "Descuento del Proveedor Aplicado: $descGlobalProv%",
                    ),
                  pw.Text(
                    "Subtotal 15% (Base sin IVA): \$${base15.toStringAsFixed(2)}",
                  ),
                  pw.Text(
                    "Subtotal 0% (Base sin IVA): \$${subtotal0.toStringAsFixed(2)}",
                  ),
                  pw.Text(
                    "Total Ahorro/Dsctos: \$${totalDescuentos.toStringAsFixed(2)}",
                  ),
                  pw.Text(
                    "Valor Total de Impuestos (IVA 15%): \$${totalIva.toStringAsFixed(2)}",
                  ),
                  pw.Container(width: 180, child: pw.Divider()),
                  pw.Text(
                    "Total Neto a Pagar: \$${totalNeto.toStringAsFixed(2)}",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final xFile = XFile.fromData(
      bytes,
      name: 'Orden_${idSecuencial}_$proveedor.pdf',
      mimeType: 'application/pdf',
    );

    await Share.shareXFiles([xFile], text: textoPlano);

    try {
      await service.notificarEnvioProveedor(
        pedidoId: widget.pedidoId,
        proveedor: proveedor,
      );
      setState(() => proveedoresEnviados.add(proveedor));
      if (_prefs != null)
        await _prefs!.setStringList(
          'pedido_${widget.pedidoId}_sent',
          proveedoresEnviados.toList(),
        );
      if (proveedoresEnviados.length == totalProveedores)
        await _autoMarcarComoEnviado();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textos = textosGenerados?["textos"] as List<dynamic>? ?? [];
    final proveedoresDisponibles = textos
        .map((t) => t["proveedor"]?.toString() ?? "SIN PROVEEDOR")
        .toList();
    final totalProv = proveedoresDisponibles.length;
    final sentProv = proveedoresEnviados.length;
    final progress = totalProv == 0 ? 0.0 : sentProv / totalProv;

    if (_prefs != null && totalProv > 0) {
      _prefs!.setInt('pedido_${widget.pedidoId}_total', totalProv);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.95,
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Cargando historiales de costos...",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : errorMessage != null
            ? Center(child: Text(errorMessage!))
            : Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Gestión de Pedidos",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.green,
                          size: 28,
                        ),
                        tooltip: "Agregar Producto",
                        onPressed: _agregarProducto,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getColorPorEstado(
                            pedido?["estado"]?.toString(),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "Estado: ${pedido?["estado"] ?? 'CARGANDO...'}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (totalProv > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Progreso de envíos:",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                "$sentProv/$totalProv",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade200,
                            color: Colors.green,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                    ),

                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text(
                          "Todos",
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: filtroSeleccionado == "TODOS",
                        onSelected: (_) =>
                            setState(() => filtroSeleccionado = "TODOS"),
                      ),
                      ChoiceChip(
                        label: const Text(
                          "Venta",
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: filtroSeleccionado == "VENTA",
                        onSelected: (_) =>
                            setState(() => filtroSeleccionado = "VENTA"),
                      ),
                      ChoiceChip(
                        label: const Text(
                          "Gasto",
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: filtroSeleccionado == "GASTO",
                        onSelected: (_) =>
                            setState(() => filtroSeleccionado = "GASTO"),
                      ),
                    ],
                  ),
                  const Divider(),

                  Expanded(
                    child: _buildListaUnificada(
                      proveedoresDisponibles,
                      totalProv,
                    ),
                  ),

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cerrar",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildListaUnificada(
    List<String> proveedoresDisponibles,
    int totalProveedores,
  ) {
    if (proveedoresDisponibles.isEmpty) {
      return const Center(
        child: Text("No hay productos asignados a proveedores."),
      );
    }

    final nombreColaborador = pedido?["usuario"]?.toString() ?? "Colaborador";
    final celularColaborador = pedido?["celular_usuario"]?.toString() ?? "";

    return ListView.builder(
      itemCount: proveedoresDisponibles.length,
      itemBuilder: (context, index) {
        final prov = proveedoresDisponibles[index];
        final items = _obtenerItemsParaTexto(prov);

        if (items.isEmpty) return const SizedBox.shrink();

        final textoPlanoFinal = _construirTextoComoPDF(prov, items);
        final bool enviado = proveedoresEnviados.contains(prov);

        return Card(
          color: enviado ? Colors.green.shade50 : Colors.grey.shade50,
          margin: const EdgeInsets.only(bottom: 24),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: enviado
                ? BorderSide(color: Colors.green.shade300, width: 1.5)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        prov,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: enviado
                              ? Colors.green.shade800
                              : Colors.blueGrey,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          "Desc Prov (%): ",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          width: 45,
                          height: 25,
                          child: TextField(
                            controller: _getDescProvController(prov),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                if (proveedoresConMermas.contains(
                  prov.toUpperCase().trim(),
                )) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final user = await SessionStorage.getUser();
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MermaScreen(
                            usuarioActual: user?.nombreUsuario ?? '',
                            rolUsuario: user?.rol ?? '',
                            esModoReporte: true,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "⚠️ Este proveedor tiene productos en merma pendientes por gestionar",
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.amber.shade800,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (enviado)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Text(
                          "Enviado",
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: enviado
                              ? Colors.grey.shade300
                              : Colors.blue.shade700,
                          foregroundColor: enviado
                              ? Colors.black87
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        icon: Icon(enviado ? Icons.replay : Icons.share),
                        label: Text(
                          enviado
                              ? "Reenviar PDF + Texto"
                              : "Compartir PDF y Texto",
                        ),
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          _compartirUnificado(
                            prov,
                            items,
                            textoPlanoFinal,
                            totalProveedores,
                          );
                        },
                      ),
                    ),

                    if (celularColaborador.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                            side: BorderSide(color: Colors.green.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.chat),
                          label: Text("Notificar texto a $nombreColaborador"),
                          onPressed: () async {
                            FocusScope.of(context).unfocus();

                            String numero = celularColaborador.replaceAll(
                              " ",
                              "",
                            );
                            if (numero.startsWith('0')) {
                              numero = numero.substring(1);
                            }

                            final idSecuencial = _formatearSecuencial(
                              widget.pedidoId,
                            );
                            final textoWhats =
                                "Hola *$nombreColaborador*, te notifico que tu pedido de la orden #$idSecuencial para el proveedor *$prov* ya fue procesado y enviado.\n\nAquí tienes el detalle:\n$textoPlanoFinal";

                            final url = Uri.parse(
                              "https://wa.me/593$numero?text=${Uri.encodeComponent(textoWhats)}",
                            );

                            try {
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "No se pudo abrir WhatsApp. Verifica que la app esté instalada.",
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),

                const Divider(height: 32, thickness: 1.5),

                const Text(
                  "Análisis de Costos y Cantidades:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                ...items.asMap().entries.map((entry) {
                  final int idx = entry.key;
                  final item = entry.value;

                  final codigo = item["codigo_producto"]?.toString() ?? "";
                  final uniqueKey = "${prov}_${codigo}_$idx";

                  final stock =
                      stockYMinimoCache[codigo]?['stock'] ??
                      item["stock_actual"] ??
                      "0";
                  final minimo =
                      stockYMinimoCache[codigo]?['minimo'] ??
                      item["minimo"] ??
                      "0";
                  final cantController = _getCantController(
                    uniqueKey,
                    item["cantidad_pedida"]?.toString() ?? "1",
                  );

                  final costoGlobalData = costosGlobalesCache[codigo];
                  String txtMejorCosto = "Mejor costo (3m): Sin registro";
                  String txtMejorProv = "";

                  if (costoGlobalData != null) {
                    final cGlobal =
                        double.tryParse(
                          costoGlobalData["costo_final"]?.toString() ?? "0",
                        ) ??
                        0.0;
                    if (cGlobal > 0) {
                      txtMejorCosto =
                          "Mejor costo (3m): \$${cGlobal.toStringAsFixed(4)}";
                      txtMejorProv =
                          "Prov: ${costoGlobalData["proveedor"] ?? 'Desconocido'}";
                    }
                  }

                  final costoBase =
                      double.tryParse(item["costo_base"]?.toString() ?? "0") ??
                      0.0;
                  final ultimoCostoProv = _obtenerUltimoCostoParaProveedor(
                    codigo,
                    prov,
                    costoBase,
                  );
                  final costoController = _getCostoController(
                    uniqueKey,
                    ultimoCostoProv.toStringAsFixed(4),
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item["nombre_producto"]?.toString() ?? "",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {},
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      Icons.inventory,
                                      color: Colors.purple,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _agregarPromocion(item),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      Icons.card_giftcard,
                                      color: Colors.orange,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _eliminarProducto(item),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        Row(
                          children: [
                            const Text(
                              "Cant: ",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  _modificarCantidadBoton(item, uniqueKey, -1),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.blueGrey,
                                  size: 22,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 25,
                              child: TextField(
                                controller: cantController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (val) {
                                  _guardarCantidadEscrita(item, uniqueKey, val);
                                },
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  _modificarCantidadBoton(item, uniqueKey, 1),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.blueGrey,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            Expanded(
                              child: Container(
                                height: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value:
                                        unidadesGlobales.contains(
                                          item["unidad"],
                                        )
                                        ? item["unidad"]
                                        : unidadesGlobales.first,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    iconSize: 16,
                                    items: unidadesGlobales.map((u) {
                                      return DropdownMenuItem(
                                        value: u,
                                        child: Text(
                                          u,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (newVal) {
                                      if (newVal != null) {
                                        _cambiarUnidadMedidaItem(item, newVal);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  "Stock: $stock (Mín: $minimo)",
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      "Desc(%): ",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 45,
                                      height: 25,
                                      child: TextField(
                                        controller: _getDescItemController(
                                          uniqueKey,
                                        ),
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      "Costo (\$): ",
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 60,
                                      height: 25,
                                      child: TextField(
                                        controller: costoController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),

                        const Divider(height: 12),

                        // 🔥 AQUI ESTÁ EL CAMBIO: Iconos "Cambiar Proveedor" e "Historial" pegados
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    txtMejorCosto,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (txtMejorProv.isNotEmpty)
                                    Text(
                                      txtMejorProv,
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Último con $prov: \$${ultimoCostoProv.toStringAsFixed(4)}",
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => _cambiarProveedor(item),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Icon(
                                      Icons.swap_horiz,
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _verHistorial(
                                    codigo,
                                    item["nombre_producto"]?.toString() ?? "",
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Icon(
                                      Icons.history,
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),

                const Divider(height: 32, thickness: 1.5),

                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    "Vista previa del texto para WhatsApp:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        textoPlanoFinal,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: textoPlanoFinal),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Texto copiado al portapapeles"),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text("Copiar Texto"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 🔥 WIDGET: BUSCADOR DE PRODUCTOS CON CÁMARA 🔥
// ============================================================================
class _BuscadorProductosSheet extends StatefulWidget {
  final dynamic saldosService;
  const _BuscadorProductosSheet({required this.saldosService});

  @override
  State<_BuscadorProductosSheet> createState() =>
      _BuscadorProductosSheetState();
}

class _BuscadorProductosSheetState extends State<_BuscadorProductosSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _resultados = [];
  bool _isLoading = false;
  String? _error;

  Future<void> _escanearCodigo() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "La cámara no está soportada en el navegador Web. Usa un dispositivo físico o emulador.",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      String barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
        "#ff6666",
        "Cancelar",
        true,
        ScanMode.BARCODE,
      );

      if (barcodeScanRes != '-1') {
        _searchController.text = barcodeScanRes;
        _buscar();
      }
    } on PlatformException {
      setState(() => _error = "Error al abrir la cámara.");
    }
  }

  Future<void> _buscar() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _resultados = [];
    });

    try {
      final data = await widget.saldosService.buscarRapido(termino: query);

      final Map<String, dynamic> productosUnicos = {};
      for (var item in data) {
        final codigo =
            item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
        if (codigo.isNotEmpty && !productosUnicos.containsKey(codigo)) {
          productosUnicos[codigo] = item;
        }
      }

      setState(() {
        _resultados = productosUnicos.values.toList();
      });
    } catch (e) {
      setState(() => _error = "Error al buscar: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        bottom: bottomInset,
        left: 16,
        right: 16,
        top: 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "Buscar por nombre, código...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.blue),
                      onPressed: _escanearCodigo,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onSubmitted: (_) => _buscar(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _buscar, child: const Text("Buscar")),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_resultados.isEmpty && _searchController.text.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("No se encontraron resultados"),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _resultados.length,
                itemBuilder: (context, index) {
                  final prod = _resultados[index];
                  final nombre =
                      prod["Nombre"] ??
                      prod["nombre_producto"] ??
                      "Desconocido";
                  final codigo = prod["Codigo"] ?? prod["codigo"] ?? "";
                  final stock = prod["Stock"] ?? prod["stock_actual"] ?? 0;

                  return ListTile(
                    leading: const Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.blueGrey,
                    ),
                    title: Text(
                      nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text("Cód: $codigo | Stock: $stock"),
                    trailing: const Icon(Icons.add_circle, color: Colors.green),
                    onTap: () {
                      Navigator.pop(context, prod);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
