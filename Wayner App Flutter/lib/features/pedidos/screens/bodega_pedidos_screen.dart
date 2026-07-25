import 'package:flutter/material.dart';

import '../services/pedidos_service.dart';
import '../../saldos/presentation/screens/barcode_scanner_screen.dart'; // 🔥 Importación del escáner

class BodegaPedidosScreen extends StatefulWidget {
  const BodegaPedidosScreen({super.key});

  @override
  State<BodegaPedidosScreen> createState() => _BodegaPedidosScreenState();
}

class _BodegaPedidosScreenState extends State<BodegaPedidosScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  String? errorMessage;
  List<dynamic> pedidos = [];
  String filtroSeleccionado = "TODOS";
  final TextEditingController busquedaController = TextEditingController();

  DateTime? fechaDesde;
  DateTime? fechaHasta;

  final List<String> filtrosRecepcion = [
    "TODOS",
    "PENDIENTES",
    "INCOMPLETOS",
    "COMPLETOS",
  ];

  @override
  void initState() {
    super.initState();
    cargarPedidos();
  }

  Future<void> cargarPedidos() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await service.listarPedidosBodega();

      if (!mounted) return;

      setState(() {
        pedidos = data;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = "No se pudieron cargar los pedidos de bodega";
      });
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  String formatearFecha(dynamic fecha) {
    if (fecha == null) return "";
    return fecha.toString().replaceAll("T", " ").split(".").first;
  }

  DateTime? parseFecha(dynamic fecha) {
    if (fecha == null) return null;

    try {
      return DateTime.parse(fecha.toString());
    } catch (_) {
      return null;
    }
  }

  Future<void> seleccionarRangoFechas() async {
    final ahora = DateTime.now();

    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 3),
      lastDate: DateTime(ahora.year + 1),
      initialDateRange: fechaDesde != null && fechaHasta != null
          ? DateTimeRange(start: fechaDesde!, end: fechaHasta!)
          : null,
    );

    if (rango == null) return;

    setState(() {
      fechaDesde = rango.start;
      fechaHasta = rango.end;
    });
  }

  void limpiarFiltrosAvanzados() {
    setState(() {
      busquedaController.clear();
      fechaDesde = null;
      fechaHasta = null;
    });
  }

  double calcularProgreso(dynamic pedido) {
    final total = int.tryParse((pedido["total_items"] ?? 0).toString()) ?? 0;
    final recibidos =
        int.tryParse((pedido["total_recibidos"] ?? 0).toString()) ?? 0;

    if (total <= 0) return 0;

    return recibidos / total;
  }

  String obtenerEstadoVisual(dynamic pedido) {
    final total = int.tryParse((pedido["total_items"] ?? 0).toString()) ?? 0;
    final recibidos =
        int.tryParse((pedido["total_recibidos"] ?? 0).toString()) ?? 0;
    final observaciones =
        int.tryParse((pedido["total_observaciones"] ?? 0).toString()) ?? 0;

    if (total > 0 && recibidos == total) {
      return "COMPLETO";
    }

    if (recibidos > 0 || observaciones > 0) {
      return "INCOMPLETO";
    }

    return "PENDIENTE";
  }

  List<dynamic> get pedidosFiltrados {
    return pedidos.where((pedido) {
      final estado = obtenerEstadoVisual(pedido);

      if (filtroSeleccionado == "PENDIENTES" && estado != "PENDIENTE") {
        return false;
      }

      if (filtroSeleccionado == "INCOMPLETOS" && estado != "INCOMPLETO") {
        return false;
      }

      if (filtroSeleccionado == "COMPLETOS" && estado != "COMPLETO") {
        return false;
      }

      final busqueda = busquedaController.text.trim().toLowerCase();

      if (busqueda.isNotEmpty) {
        final id = pedido["id"]?.toString().toLowerCase() ?? "";
        final codigo = pedido["codigo_pedido"]?.toString().toLowerCase() ?? "";
        final usuario = pedido["usuario"]?.toString().toLowerCase() ?? "";

        final proveedor =
            pedido["proveedor"]?.toString().toLowerCase() ??
            pedido["proveedores"]?.toString().toLowerCase() ??
            "";

        final coincide =
            id.contains(busqueda) ||
            codigo.contains(busqueda) ||
            usuario.contains(busqueda) ||
            proveedor.contains(busqueda);

        if (!coincide) return false;
      }

      final fechaPedido = parseFecha(pedido["fecha_creacion"]);

      if (fechaDesde != null) {
        if (fechaPedido == null) return false;

        final desde = DateTime(
          fechaDesde!.year,
          fechaDesde!.month,
          fechaDesde!.day,
        );

        if (fechaPedido.isBefore(desde)) return false;
      }

      if (fechaHasta != null) {
        if (fechaPedido == null) return false;

        final hasta = DateTime(
          fechaHasta!.year,
          fechaHasta!.month,
          fechaHasta!.day,
          23,
          59,
          59,
        );

        if (fechaPedido.isAfter(hasta)) return false;
      }

      return true;
    }).toList();
  }

  Widget buildEstadoRecepcion(dynamic pedido) {
    final estado = obtenerEstadoVisual(pedido);

    MaterialColor color = Colors.orange;
    String texto = "Pendiente";

    if (estado == "COMPLETO") {
      color = Colors.green;
      texto = "Completo";
    } else if (estado == "INCOMPLETO") {
      color = Colors.blue;
      texto = "Incompleto";
    }

    return Chip(
      label: Text(
        texto,
        style: TextStyle(color: color.shade900, fontWeight: FontWeight.bold),
      ),
      backgroundColor: color.shade100,
      side: BorderSide(color: color.shade700),
    );
  }

  // 🔥 NUEVO FLUJO: Abrir modal RPA centrado
  Future<void> abrirDetalle(dynamic pedido) async {
    final pedidoId = int.tryParse(pedido["id"].toString());
    final proveedorSeleccionado =
        pedido["proveedor"]?.toString() ?? "SIN PROVEEDOR";

    if (pedidoId == null) return;

    mostrarDialogoRPA(pedidoId, proveedorSeleccionado);
  }

  // 🔥 INTERFAZ DEL DIÁLOGO CENTRAL PARA CARGAR FACTURA SRI 🔥
  void mostrarDialogoRPA(int pedidoId, String proveedor) {
    final TextEditingController claveController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Bloquea el cierre tocando fuera
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Cargar Factura (SRI)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (!isSubmitting)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Pedido #$pedidoId - $proveedor",
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 🔥 Mostrar Loader o el Input dependiendo del estado
                    if (isSubmitting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                "Procesando autorización...",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Por favor, no cierres la aplicación.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      TextFormField(
                        controller: claveController,
                        keyboardType: TextInputType.number,
                        maxLength: 49,
                        decoration: InputDecoration(
                          labelText: "Clave de Acceso (49 dígitos)",
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.blue,
                            ),
                            onPressed: () async {
                              // 🔥 Reutilizamos tu pantalla de escáner existente
                              final String? codigoEscaneado =
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const BarcodeScannerScreen(),
                                    ),
                                  );

                              if (codigoEscaneado != null &&
                                  codigoEscaneado.isNotEmpty) {
                                claveController.text = codigoEscaneado;
                                formKey.currentState?.validate();
                              }
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Por favor ingresa la clave.";
                          }
                          if (value.length != 49) {
                            return "Debe tener exactamente 49 dígitos (tiene ${value.length}).";
                          }
                          if (double.tryParse(value) == null) {
                            return "Solo se permiten números.";
                          }
                          return null;
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                if (!isSubmitting)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancelar",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                if (!isSubmitting)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() {
                          isSubmitting = true;
                        });

                        final exito = await service.enviarClaveSRI(
                          pedidoId: pedidoId,
                          proveedor: proveedor,
                          claveAcceso: claveController.text.trim(),
                        );

                        if (!context.mounted) return;

                        if (exito) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Factura procesada y validada correctamente",
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          cargarPedidos();
                        } else {
                          setDialogState(() {
                            isSubmitting = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Error: Autorización no válida"),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      "Continuar",
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: filtrosRecepcion.map((filtro) {
          final seleccionado = filtroSeleccionado == filtro;

          String texto = filtro;

          if (filtro == "TODOS") texto = "Todos";
          if (filtro == "PENDIENTES") texto = "Pendientes";
          if (filtro == "INCOMPLETOS") texto = "Incompletos";
          if (filtro == "COMPLETOS") texto = "Completos";

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(texto),
              selected: seleccionado,
              onSelected: (_) {
                setState(() {
                  filtroSeleccionado = filtro;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildFiltrosAvanzados() {
    final textoRango = fechaDesde == null || fechaHasta == null
        ? "Filtrar por fecha"
        : "${fechaDesde!.year}-${fechaDesde!.month.toString().padLeft(2, '0')}-${fechaDesde!.day.toString().padLeft(2, '0')} "
              "a ${fechaHasta!.year}-${fechaHasta!.month.toString().padLeft(2, '0')}-${fechaHasta!.day.toString().padLeft(2, '0')}";

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          TextField(
            controller: busquedaController,
            decoration: const InputDecoration(
              hintText: "Buscar por usuario, N° pedido o proveedor",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: seleccionarRangoFechas,
                  icon: const Icon(Icons.date_range),
                  label: Text(textoRango, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Limpiar filtros",
                onPressed: limpiarFiltrosAvanzados,
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Recepción de pedidos"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: cargarPedidos),
        ],
      ),
      body: Column(
        children: [
          buildFiltros(),
          buildFiltrosAvanzados(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: cargarPedidos,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    )
                  : pedidosFiltrados.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(
                          child: Text(
                            "No hay pedidos para el filtro seleccionado",
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: pedidosFiltrados.length,
                      itemBuilder: (context, index) {
                        final pedido = pedidosFiltrados[index];

                        final total =
                            int.tryParse(
                              (pedido["total_items"] ?? 0).toString(),
                            ) ??
                            0;

                        final recibidos =
                            int.tryParse(
                              (pedido["total_recibidos"] ?? 0).toString(),
                            ) ??
                            0;

                        final observaciones =
                            int.tryParse(
                              (pedido["total_observaciones"] ?? 0).toString(),
                            ) ??
                            0;

                        final proveedor =
                            pedido["proveedor"] ??
                            pedido["proveedores"] ??
                            'Sin proveedor asignado';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            onTap: () => abrirDetalle(
                              pedido,
                            ), // 🔥 Llama al Nuevo Diálogo
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        child: Text(
                                          pedido["id"]?.toString() ?? "-",
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Orden de pedido #${pedido["id"]}",
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Usuario: ${pedido["usuario"] ?? ""}",
                                            ),
                                            Text(
                                              "Fecha: ${formatearFecha(pedido["fecha_creacion"])}",
                                            ),
                                            Text(
                                              "Estado: ${pedido["estado"] ?? ""}",
                                            ),
                                            Text(
                                              "Proveedor: $proveedor",
                                              style: const TextStyle(
                                                fontStyle: FontStyle.italic,
                                                color: Colors.blueGrey,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      buildEstadoRecepcion(pedido),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(
                                    value: calcularProgreso(pedido),
                                    minHeight: 7,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Recibidos: $recibidos/$total",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (observaciones > 0)
                                    Text(
                                      "Observaciones: $observaciones",
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
