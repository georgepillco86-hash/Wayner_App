import 'package:flutter/material.dart';

import '../models/pedido_item.dart';
import '../services/pedidos_service.dart';
import 'pedido_carrito_screen.dart';
import '../../../screens/scanner/scanner_screen.dart';
import '../../../core/storage/pedido_draft_storage.dart';
import '../../../core/storage/session_storage.dart';

import '../../saldos/data/services/saldos_api_service.dart';
import '../../cronograma/presentation/screens/cronograma_form_screen.dart';

class PedidoBusquedaScreen extends StatefulWidget {
  const PedidoBusquedaScreen({super.key});

  @override
  State<PedidoBusquedaScreen> createState() => _PedidoBusquedaScreenState();
}

class _PedidoBusquedaScreenState extends State<PedidoBusquedaScreen> {
  final PedidosService service = PedidosService();
  final SaldosApiService saldosService = SaldosApiService();

  final TextEditingController searchController = TextEditingController();
  final TextEditingController marcaController = TextEditingController();

  List<String> proveedores = [];
  List<String> marcasGlobales = [];
  List<String> clasesDisponibles = [
    'Todas las clases',
    'BAZAR',
    'COMISARIATO',
    'FERRETERIA',
  ];

  String? proveedorSeleccionado;
  String claseSeleccionada = 'Todas las clases';

  bool esAdmin = false;
  bool busquedaProfunda = false;

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
    cargarSesionYFiltros();
  }

  @override
  void dispose() {
    searchController.dispose();
    marcaController.dispose();
    super.dispose();
  }

  Future<void> cargarSesionYFiltros() async {
    final user = await SessionStorage.getUser();
    final rol = user?.rol.trim().toUpperCase() ?? "";

    if (!mounted) return;
    setState(() => esAdmin = rol == "ADMIN" || rol == "SUPERADMIN");

    try {
      final marcasBD = await saldosService.obtenerMarcasGlobales();
      if (mounted) setState(() => marcasGlobales = marcasBD);
    } catch (_) {}

    if (!esAdmin) return;
    try {
      final provBD = await service.obtenerProveedores();
      if (mounted) setState(() => proveedores = provBD);
    } catch (_) {}
  }

  Future<void> cargarUnidadesMedida() async {
    try {
      final unidades = await service.obtenerUnidadesMedida();
      if (mounted)
        setState(
          () => unidadesMedida = unidades.isEmpty ? ['UNIDADES'] : unidades,
        );
    } catch (_) {
      if (mounted) setState(() => unidadesMedida = ['UNIDADES']);
    }
  }

  List<dynamic> get resultadosFiltrados {
    final filtroMarca = marcaController.text.trim().toLowerCase();
    if (filtroMarca.isEmpty) return resultados;

    return resultados.where((item) {
      final m = (item["Marca"] ?? item["marca"] ?? "").toString().toLowerCase();
      return m.contains(filtroMarca);
    }).toList();
  }

  Future<void> buscar(String query) async {
    // Para que no se bloquee si el cuadro está vacío pero hay filtros
    if (query.trim().isEmpty &&
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
        errorMessage = "No se pudieron cargar productos.";
        resultados = [];
      });
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  void abrirScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          onDetect: (codigo) async {
            searchController.text = codigo;
            await buscar(codigo);
          },
        ),
      ),
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
        marcaController.clear();
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

  void _actualizarCantidad(dynamic item, int delta) {
    final codigo =
        item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
    if (codigo.isEmpty) return;

    setState(() {
      final index = carrito.indexWhere((c) => c.codigo == codigo);
      if (index >= 0) {
        int nueva = carrito[index].cantidad + delta;
        if (nueva <= 0) {
          carrito.removeAt(index);
        } else {
          carrito[index].cantidad = nueva;
        }
      } else if (delta > 0) {
        final nombreCorregido =
            item["Nombre"]?.toString() ??
            item["NombreProducto"]?.toString() ??
            item["nombre"]?.toString() ??
            "Sin nombre";
        final stockActual =
            double.tryParse(
              (item["Stock"] ?? item["stock_actual"] ?? 0).toString(),
            ) ??
            0;

        carrito.add(
          PedidoItem(
            codigo: codigo,
            nombre: nombreCorregido,
            marca: item["Marca"]?.toString() ?? item["marca"]?.toString() ?? "",
            clase: item["Clase"]?.toString() ?? item["clase"]?.toString(),
            stockActual: stockActual,
            cantidad: delta,
            proveedor:
                item["Proveedor"]?.toString() ?? item["proveedor"]?.toString(),
            unidad: unidadesMedida.isNotEmpty
                ? unidadesMedida.first
                : 'UNIDADES',
            tipoDestino: "VENTA",
          ),
        );
      }
    });
    PedidoDraftStorage.save(carrito);
  }

  void _cambiarDestino(dynamic item, String destino) {
    final codigo =
        item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
    setState(() {
      final index = carrito.indexWhere((c) => c.codigo == codigo);
      if (index >= 0) {
        carrito[index].tipoDestino = destino;
      } else {
        _actualizarCantidad(item, 1);
        final newIndex = carrito.indexWhere((c) => c.codigo == codigo);
        if (newIndex >= 0) carrito[newIndex].tipoDestino = destino;
      }
    });
    PedidoDraftStorage.save(carrito);
  }

  Future<void> _agregarNota(dynamic item) async {
    final codigo =
        item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
    int index = carrito.indexWhere((c) => c.codigo == codigo);

    if (index < 0) {
      _actualizarCantidad(item, 1);
      index = carrito.indexWhere((c) => c.codigo == codigo);
    }

    final currentItem = carrito[index];
    final notaController = TextEditingController(
      text: currentItem.notaCompra ?? "",
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          "Nota para ${currentItem.nombre}",
          style: const TextStyle(fontSize: 16),
        ),
        content: TextField(
          controller: notaController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "Escriba una observación...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Guardar Nota"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        final nuevaNota = notaController.text.trim().isEmpty
            ? null
            : notaController.text.trim();
        carrito[index] = PedidoItem(
          codigo: currentItem.codigo,
          nombre: currentItem.nombre,
          marca: currentItem.marca,
          clase: currentItem.clase,
          stockActual: currentItem.stockActual,
          cantidad: currentItem.cantidad,
          proveedor: currentItem.proveedor,
          unidad: currentItem.unidad,
          tipoDestino: currentItem.tipoDestino,
          notaCompra: nuevaNota,
        );
      });
      PedidoDraftStorage.save(carrito);
    }
  }

  Future<void> autoSugerirCompras() async {
    if (resultadosFiltrados.isEmpty) return;
    int agregados = 0;

    setState(() {
      for (var item in resultadosFiltrados) {
        final double stockActual =
            double.tryParse(
              (item["Stock"] ?? item["stock_actual"] ?? 0).toString(),
            ) ??
            0;
        final double stockMinimo =
            double.tryParse((item["stock_minimo"] ?? 0).toString()) ?? 0;

        if (stockMinimo > 0 && stockActual <= stockMinimo) {
          final codigo =
              item["Codigo"]?.toString() ?? item["codigo"]?.toString() ?? "";
          if (carrito.indexWhere((c) => c.codigo == codigo) == -1 &&
              codigo.isNotEmpty) {
            int sugerencia =
                (stockMinimo - stockActual).ceil() + (stockMinimo * 0.2).ceil();
            _actualizarCantidad(item, sugerencia < 1 ? 1 : sugerencia);
            agregados++;
          }
        }
      }
    });

    if (agregados > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🤖 Se auto-agregaron $agregados productos críticos.'),
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

  @override
  Widget build(BuildContext context) {
    final currentList = resultadosFiltrados;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
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

                // 🔥 COLADOR EN VIVO PARA MARCA 🔥
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textValue) {
                    final q = textValue.text.trim().toLowerCase();
                    if (q.isEmpty) return marcasGlobales.take(20);
                    return marcasGlobales.where(
                      (m) => m.toLowerCase().contains(q),
                    );
                  },
                  onSelected: (val) {
                    marcaController.text = val;
                    setState(
                      () {},
                    ); // Fuerza actualización de la lista de abajo
                  },
                  fieldViewBuilder: (context, controller, focus, onSubmitted) {
                    // Sincronizamos el controlador interno del Autocomplete con el nuestro
                    if (controller.text != marcaController.text &&
                        !focus.hasFocus) {
                      controller.text = marcaController.text;
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focus,
                      decoration: InputDecoration(
                        labelText: 'Refinar por Marca',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.filter_alt_outlined),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  controller.clear();
                                  marcaController.clear();
                                  setState(() {}); // Limpia la lista inferior
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        marcaController.text = val;
                        setState(() {}); // Actualiza en vivo mientras tipeo
                      },
                    );
                  },
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
                  ],
                ),
                const SizedBox(height: 8),

                // 🔥 AUTOCOMPLETE PARA PROVEEDOR 🔥
                if (esAdmin)
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textValue) {
                      final q = textValue.text.trim().toLowerCase();
                      if (q.isEmpty) return proveedores.take(20);
                      return proveedores.where(
                        (p) => p.toLowerCase().contains(q),
                      );
                    },
                    onSelected: (val) {
                      setState(() => proveedorSeleccionado = val);
                      buscar(
                        searchController.text,
                      ); // Lanza la búsqueda al dar clic en la lista
                    },
                    fieldViewBuilder: (context, controller, focus, onSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focus,
                        decoration: InputDecoration(
                          labelText: 'Filtrar por Proveedor',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.local_shipping_outlined),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    controller.clear();
                                    setState(
                                      () => proveedorSeleccionado = null,
                                    );
                                    buscar(
                                      searchController.text,
                                    ); // Busca todo de nuevo sin proveedor
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) {
                          // Guardamos lo que va escribiendo para que busque con ILIKE en Python
                          proveedorSeleccionado = val.trim();
                        },
                        onSubmitted: (val) {
                          setState(() => proveedorSeleccionado = val.trim());
                          buscar(searchController.text);
                        },
                      );
                    },
                  ),

                if (currentList.isNotEmpty)
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
                    child: Text("Busca o selecciona un proveedor para empezar"),
                  )
                : currentList.isEmpty && !isLoading
                ? const Center(
                    child: Text(
                      "Ninguna marca coincide en estos resultados",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: currentList.length,
                    itemBuilder: (_, i) {
                      final item = currentList[i];

                      final codigo =
                          item["Codigo"]?.toString() ??
                          item["codigo"]?.toString() ??
                          "";
                      final proveedor =
                          item["Proveedor"]?.toString().trim() ??
                          item["proveedor"]?.toString().trim() ??
                          "";
                      final marca = item["Marca"]?.toString().trim() ?? "-";
                      final nombreCorregido =
                          item["Nombre"]?.toString() ??
                          item["NombreProducto"]?.toString() ??
                          item["nombre"]?.toString() ??
                          "Sin nombre";

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

                      final indexCarrito = carrito.indexWhere(
                        (c) => c.codigo == codigo,
                      );
                      final PedidoItem? pedidoActual = indexCarrito >= 0
                          ? carrito[indexCarrito]
                          : null;
                      final int cantidadPedida = pedidoActual?.cantidad ?? 0;
                      final String destino =
                          pedidoActual?.tipoDestino ?? "VENTA";
                      final bool tieneNota =
                          pedidoActual?.notaCompra != null &&
                          pedidoActual!.notaCompra!.isNotEmpty;

                      return Card(
                        elevation: estaEnPeligro ? 3 : 1,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: estaEnPeligro
                                ? Colors.red.shade300
                                : Colors.grey.shade300,
                            width: estaEnPeligro ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      nombreCorregido,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (alertaActiva)
                                    InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                CronogramaFormScreen(
                                                  proveedorInicial:
                                                      item["proveedor_objetivo"] ??
                                                      proveedor,
                                                  onSaved: () => buscar(
                                                    searchController.text,
                                                  ),
                                                ),
                                          ),
                                        );
                                      },
                                      child: const Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.red,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              Text(
                                "Código: $codigo",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                "Stock: $stockActual (Mínimo: $stockMinimo)",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: estaEnPeligro
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                "Marca: $marca",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              if (item["vdp"] != null && item["vdp"] > 0)
                                Text(
                                  "Venta Diaria (VDP): ${item["vdp"]} unid.  |  Llega en: ${item["lead_time_dias"] ?? 2} días",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.deepPurple,
                                  ),
                                ),

                              const Divider(height: 16),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: cantidadPedida > 0
                                          ? Colors.blue.shade50
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: cantidadPedida > 0
                                            ? Colors.blue.shade200
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.remove,
                                            color: cantidadPedida > 0
                                                ? Colors.red
                                                : Colors.grey,
                                            size: 20,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          padding: EdgeInsets.zero,
                                          onPressed: cantidadPedida > 0
                                              ? () => _actualizarCantidad(
                                                  item,
                                                  -1,
                                                )
                                              : null,
                                        ),
                                        Text(
                                          '$cantidadPedida',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: cantidadPedida > 0
                                                ? Colors.blue.shade900
                                                : Colors.grey,
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.add,
                                            color: Colors.blue.shade700,
                                            size: 20,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          padding: EdgeInsets.zero,
                                          onPressed: () =>
                                              _actualizarCantidad(item, 1),
                                        ),
                                      ],
                                    ),
                                  ),

                                  Row(
                                    children: [
                                      ChoiceChip(
                                        label: const Text(
                                          'VENTA',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        selected: destino == 'VENTA',
                                        padding: const EdgeInsets.all(2),
                                        selectedColor: Colors.green.shade100,
                                        onSelected: (_) =>
                                            _cambiarDestino(item, 'VENTA'),
                                      ),
                                      const SizedBox(width: 4),
                                      ChoiceChip(
                                        label: const Text(
                                          'GASTO',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        selected: destino == 'GASTO',
                                        padding: const EdgeInsets.all(2),
                                        selectedColor: Colors.orange.shade100,
                                        onSelected: (_) =>
                                            _cambiarDestino(item, 'GASTO'),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => _agregarNota(item),
                                        child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: tieneNota
                                              ? Colors.blue.shade100
                                              : Colors.grey.shade200,
                                          child: Icon(
                                            tieneNota
                                                ? Icons.comment
                                                : Icons.comment_outlined,
                                            size: 16,
                                            color: tieneNota
                                                ? Colors.blue.shade800
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
  }
}
