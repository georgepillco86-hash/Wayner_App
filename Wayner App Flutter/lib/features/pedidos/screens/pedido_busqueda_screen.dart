import 'package:flutter/material.dart';

import '../models/pedido_item.dart';
import '../services/pedidos_service.dart';
import 'pedido_carrito_screen.dart';
import '../../../screens/scanner/scanner_screen.dart';
import '../../../core/storage/pedido_draft_storage.dart';
import '../../../core/storage/session_storage.dart';

// ---> NUEVAS IMPORTACIONES <---
import '../../saldos/data/services/saldos_api_service.dart';
import '../../cronograma/presentation/screens/cronograma_form_screen.dart';

class PedidoBusquedaScreen extends StatefulWidget {
  const PedidoBusquedaScreen({super.key});

  @override
  State<PedidoBusquedaScreen> createState() => _PedidoBusquedaScreenState();
}

class _PedidoBusquedaScreenState extends State<PedidoBusquedaScreen> {
  final PedidosService service = PedidosService();
  final SaldosApiService saldosService = SaldosApiService(); // Motor predictivo

  final TextEditingController searchController = TextEditingController();
  final TextEditingController secondSearchController = TextEditingController();

  List<String> proveedores = [];
  List<String> clasesDisponibles = [
    'Todas las clases',
    'BAZAR',
    'COMISARIATO',
    'FERRETERIA',
  ]; // Puedes cargar esto desde tu BD

  String? proveedorSeleccionado;
  String claseSeleccionada = 'Todas las clases';
  bool esAdmin = false;
  bool busquedaProfunda = false; // <-- Switch de Kardex

  List<String> unidadesMedida = ['UNIDADES'];
  List<dynamic> resultados = [];
  List<PedidoItem> carrito = [];

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    cargarUnidadesMedida();
    cargarBorradorCarrito();
    cargarSesionYProveedores();
  }

  Future<void> cargarSesionYProveedores() async {
    final user = await SessionStorage.getUser();
    final rol = user?.rol.trim().toUpperCase() ?? "";

    if (!mounted) return;

    setState(() {
      esAdmin = rol == "ADMIN" || rol == "SUPERADMIN";
    });

    if (!esAdmin) return;

    try {
      final data = await service.obtenerProveedores();
      if (!mounted) return;
      setState(() => proveedores = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => proveedores = []);
    }
  }

  Future<void> cargarUnidadesMedida() async {
    try {
      final unidades = await service.obtenerUnidadesMedida();
      if (!mounted) return;
      setState(
        () => unidadesMedida = unidades.isEmpty ? ['UNIDADES'] : unidades,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => unidadesMedida = ['UNIDADES']);
    }
  }

  // 🔥 EL NUEVO MOTOR DE BÚSQUEDA HÍBRIDA 🔥
  Future<void> buscar(String query) async {
    if (query.trim().length < 2 &&
        proveedorSeleccionado == null &&
        claseSeleccionada == 'Todas las clases') {
      if (!mounted) return;
      setState(() {
        resultados = [];
        errorMessage = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final prov =
          (esAdmin &&
              proveedorSeleccionado != null &&
              proveedorSeleccionado!.isNotEmpty)
          ? proveedorSeleccionado
          : null;
      final clase = claseSeleccionada == 'Todas las clases'
          ? null
          : claseSeleccionada;

      List<dynamic> data = [];

      // Decidimos si usamos el Kardex General o la Búsqueda Rápida Predictiva
      if (busquedaProfunda) {
        data = await saldosService.buscarEnKardex(query.trim());
      } else {
        data = await saldosService.buscarRapido(
          termino: query.trim(),
          proveedor: prov,
          clase: clase,
        );
      }

      if (!mounted) return;
      setState(() => resultados = data);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorMessage =
            "No se pudieron cargar productos con el motor predictivo.";
        resultados = [];
      });
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> buscarPorCodigo(String codigo) async {
    if (codigo.trim().isEmpty) return;
    searchController.text = codigo;
    await buscar(codigo);
  }

  void abrirScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          onDetect: (codigo) async {
            await buscarPorCodigo(codigo);
          },
        ),
      ),
    );
  }

  // 🔥 LA MAGIA: AUTO-SUGERIR COMPRAS 🔥
  Future<void> autoSugerirCompras() async {
    if (resultados.isEmpty) return;

    int agregados = 0;
    String unidadSeleccionada = unidadesMedida.isNotEmpty
        ? unidadesMedida.first
        : 'UNIDADES';

    setState(() {
      for (var item in resultados) {
        final double stockActual =
            double.tryParse(
              (item["Stock"] ?? item["stock_actual"] ?? 0).toString(),
            ) ??
            0;
        final double stockMinimo =
            double.tryParse((item["stock_minimo"] ?? 0).toString()) ?? 0;

        // Validamos si está en peligro
        if (stockMinimo > 0 && stockActual <= stockMinimo) {
          // Ya está en el carrito?
          final codigo =
              item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
          final indexExistente = carrito.indexWhere((c) => c.codigo == codigo);

          if (indexExistente == -1 && codigo.isNotEmpty) {
            // Sugerimos pedir lo que falta para llegar al mínimo + 20%
            int cantidadSugerida =
                (stockMinimo - stockActual).ceil() + (stockMinimo * 0.2).ceil();
            if (cantidadSugerida < 1) cantidadSugerida = 1;

            final nuevo = PedidoItem(
              codigo: codigo,
              nombre:
                  item["NombreProducto"]?.toString() ??
                  item["nombre"]?.toString() ??
                  "",
              marca: item["marca"]?.toString() ?? "",
              clase: item["Clase"]?.toString() ?? item["clase"]?.toString(),
              stockActual: stockActual,
              cantidad: cantidadSugerida,
              proveedor:
                  item["Proveedor"]?.toString() ??
                  item["proveedor"]?.toString(),
              unidad: unidadSeleccionada,
              tipoDestino: "VENTA", // Por defecto auto-sugiere para venta
            );

            carrito.add(nuevo);
            agregados++;
          }
        }
      }
    });

    if (agregados > 0) {
      await PedidoDraftStorage.save(carrito);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🤖 Se auto-agregaron $agregados productos en estado crítico al carrito.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay nuevos productos críticos para sugerir.'),
        ),
      );
    }
  }

  // --- SE MANTIENE TU MODAL ORIGINAL INTÁCTO PARA LA LOGÍSTICA DE VENTA/GASTO ---
  Future<void> agregarProducto(dynamic item) async {
    // Calculamos si hay sugerencia basada en el VDP
    final double stockActual =
        double.tryParse(
          (item["Stock"] ?? item["stock_actual"] ?? 0).toString(),
        ) ??
        0;
    final double stockMinimo =
        double.tryParse((item["stock_minimo"] ?? 0).toString()) ?? 0;
    int recomendacion = 1;

    if (stockMinimo > 0 && stockActual < stockMinimo) {
      recomendacion = (stockMinimo - stockActual).ceil();
      if (recomendacion < 1) recomendacion = 1;
    }

    final TextEditingController cantidadController = TextEditingController(
      text: recomendacion.toString(),
    );
    final TextEditingController notaCompraController = TextEditingController();

    String unidadSeleccionada = unidadesMedida.isNotEmpty
        ? unidadesMedida.first
        : 'UNIDADES';
    String tipoDestinoSeleccionado = "VENTA";

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Agregar al pedido"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item["NombreProducto"]?.toString() ??
                            item["nombre"]?.toString() ??
                            "Producto sin nombre",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Stock Actual: $stockActual"),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Mínimo Estadístico: $stockMinimo"),
                    ),
                    if (item["vdp"] != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Ventas Diarias (VDP): ${item["vdp"]}"),
                      ),

                    const SizedBox(height: 12),
                    TextField(
                      controller: cantidadController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Cantidad a pedir",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unidadSeleccionada,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Unidad de medida",
                        border: OutlineInputBorder(),
                      ),
                      items: unidadesMedida
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null)
                          setDialogState(() => unidadSeleccionada = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text("VENTA"),
                          selected: tipoDestinoSeleccionado == "VENTA",
                          onSelected: (_) => setDialogState(
                            () => tipoDestinoSeleccionado = "VENTA",
                          ),
                        ),
                        ChoiceChip(
                          label: const Text("GASTO"),
                          selected: tipoDestinoSeleccionado == "GASTO",
                          onSelected: (_) => setDialogState(
                            () => tipoDestinoSeleccionado = "GASTO",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notaCompraController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Nota de compra",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Agregar"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmado != true) return;

    final cantidad = int.tryParse(cantidadController.text.trim()) ?? 1;
    final notaCompra = notaCompraController.text.trim();

    final nuevo = PedidoItem(
      codigo: item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "",
      nombre:
          item["NombreProducto"]?.toString() ??
          item["nombre"]?.toString() ??
          "",
      marca: item["marca"]?.toString() ?? "",
      clase: item["Clase"]?.toString() ?? item["clase"]?.toString(),
      stockActual: stockActual,
      cantidad: cantidad <= 0 ? 1 : cantidad,
      proveedor: item["Proveedor"]?.toString() ?? item["proveedor"]?.toString(),
      unidad: unidadSeleccionada,
      notaCompra: notaCompra.isEmpty ? null : notaCompra,
      tipoDestino: tipoDestinoSeleccionado,
    );

    setState(() => carrito.add(nuevo));
    await PedidoDraftStorage.save(carrito);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Producto agregado (${tipoDestinoSeleccionado})")),
    );
  }

  Future<void> abrirCarrito() async {
    final enviado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PedidoCarritoScreen(carrito: carrito)),
    );

    if (enviado == true) {
      await PedidoDraftStorage.clear();
      setState(() {
        carrito.clear();
        resultados.clear();
        searchController.clear();
        proveedorSeleccionado = null;
      });
    } else {
      await PedidoDraftStorage.save(carrito);
      setState(() {});
    }
  }

  Future<void> cargarBorradorCarrito() async {
    final borrador = await PedidoDraftStorage.load();
    if (!mounted || borrador.isEmpty) return;
    setState(() => carrito = borrador);
  }

  @override
  void dispose() {
    searchController.dispose();
    secondSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Realizar Pedido Inteligente"),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: abrirScanner,
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: abrirCarrito,
              ),
              if (carrito.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${carrito.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // --- CABECERA DE FILTROS ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar producto...",
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () => buscar(searchController.text),
                    ),
                  ),
                  onSubmitted: buscar,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Búsqueda Profunda (Kardex):'),
                    Switch(
                      value: busquedaProfunda,
                      onChanged: (val) {
                        setState(() => busquedaProfunda = val);
                        if (searchController.text.length >= 2)
                          buscar(searchController.text);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Clase',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        value: claseSeleccionada,
                        items: clasesDisponibles
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() => claseSeleccionada = val!);
                          buscar(searchController.text);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (esAdmin)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Proveedor',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          value: proveedorSeleccionado,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Todos'),
                            ),
                            ...proveedores.map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() => proveedorSeleccionado = val);
                            buscar(searchController.text);
                          },
                        ),
                      ),
                  ],
                ),
                if (resultados.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade700),
                      ),
                      onPressed: autoSugerirCompras,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text(
                        'Auto-sugerir pedido (Cruzar con Mínimo)',
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- LISTA DE PRODUCTOS ---
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          Expanded(
            child: resultados.isEmpty && !isLoading
                ? const Center(
                    child: Text(
                      "Busca o escanea un producto para agregar al pedido",
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: resultados.length,
                    itemBuilder: (_, i) {
                      final item = resultados[i];
                      final proveedor =
                          item["Proveedor"]?.toString().trim() ??
                          item["proveedor"]?.toString().trim() ??
                          "";
                      final stockActual =
                          double.tryParse(
                            (item["Stock"] ?? item["stock_actual"] ?? 0)
                                .toString(),
                          ) ??
                          0;
                      final stockMinimo =
                          double.tryParse(
                            (item["stock_minimo"] ?? 0).toString(),
                          ) ??
                          0;
                      final alertaActiva = item["alerta_lead_time"] == true;

                      final bool estaEnPeligro =
                          stockMinimo > 0 && stockActual <= stockMinimo;

                      return Card(
                        elevation: estaEnPeligro ? 3 : 1,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: estaEnPeligro
                                ? Colors.red.shade300
                                : Colors.grey.shade300,
                            width: estaEnPeligro ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item["NombreProducto"]?.toString() ??
                                      item["nombre"]?.toString() ??
                                      "Sin nombre",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (alertaActiva)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Falta Cronograma de Entregas',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            CronogramaFormScreen(
                                              proveedorInicial:
                                                  item["proveedor_objetivo"] ??
                                                  proveedor,
                                              onSaved: () =>
                                                  buscar(searchController.text),
                                            ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Código: ${item["Codigo"] ?? item["codigo"] ?? ""}",
                              ),
                              Text(
                                "Stock: $stockActual (Mín: $stockMinimo)",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: estaEnPeligro
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                ),
                              ),
                              if (item["vdp"] != null && item["vdp"] > 0)
                                Text(
                                  "VDP: ${item["vdp"]} | Lead Time: ${item["lead_time_dias"] ?? 2} días",
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (proveedor.isNotEmpty)
                                Text(
                                  "Prov: $proveedor",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.add_shopping_cart,
                              color: Colors.blue,
                            ),
                            onPressed: () => agregarProducto(item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
