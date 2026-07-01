import 'package:flutter/material.dart';

import '../services/pedidos_service.dart';
import 'bodega_pedido_detalle_screen.dart';

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

        final coincide = id.contains(busqueda) ||
            codigo.contains(busqueda) ||
            usuario.contains(busqueda);

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
        style: TextStyle(
          color: color.shade900,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color.shade100,
      side: BorderSide(color: color.shade700),
    );
  }

  Future<void> abrirDetalle(dynamic pedido) async {
    final pedidoId = int.tryParse(pedido["id"].toString());

    if (pedidoId == null) return;

    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BodegaPedidoDetalleScreen(
          pedidoId: pedidoId,
        ),
      ),
    );

    if (actualizado == true) {
      await cargarPedidos();
    }
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
              hintText: "Buscar por usuario o número de pedido",
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
                  label: Text(
                    textoRango,
                    overflow: TextOverflow.ellipsis,
                  ),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarPedidos,
          ),
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

                                final total = int.tryParse(
                                      (pedido["total_items"] ?? 0).toString(),
                                    ) ??
                                    0;

                                final recibidos = int.tryParse(
                                      (pedido["total_recibidos"] ?? 0).toString(),
                                    ) ??
                                    0;

                                final observaciones = int.tryParse(
                                      (pedido["total_observaciones"] ?? 0).toString(),
                                    ) ??
                                    0;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: InkWell(
                                    onTap: () => abrirDetalle(pedido),
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
                                                      "Pedido #${pedido["id"]}",
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