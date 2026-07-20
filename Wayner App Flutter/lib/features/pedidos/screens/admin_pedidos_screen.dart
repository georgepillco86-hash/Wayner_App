import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 NUEVO IMPORT

import '../services/pedidos_service.dart';
import 'admin_pedido_detalle_screen.dart';
import '../widgets/generar_pedido_proveedor_dialog.dart';

class AdminPedidosScreen extends StatefulWidget {
  const AdminPedidosScreen({super.key});

  @override
  State<AdminPedidosScreen> createState() => _AdminPedidosScreenState();
}

class _AdminPedidosScreenState extends State<AdminPedidosScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  String? errorMessage;
  List<dynamic> pedidos = [];

  // 🔥 NUEVO: Mapa para almacenar el progreso cargado desde la caché
  Map<int, Map<String, int>> progresos = {};

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
      final data = await service.listarPedidosAdmin();

      // 🔥 Cargamos los progresos desde SharedPreferences para toda la lista
      final prefs = await SharedPreferences.getInstance();
      Map<int, Map<String, int>> nuevosProgresos = {};

      for (var p in data) {
        int id = int.tryParse(p["id"].toString()) ?? 0;
        int total = prefs.getInt('pedido_${id}_total') ?? 0;
        List<String> sent = prefs.getStringList('pedido_${id}_sent') ?? [];
        nuevosProgresos[id] = {'total': total, 'sent': sent.length};
      }

      setState(() {
        pedidos = data;
        progresos = nuevosProgresos;
      });
    } catch (e) {
      setState(() {
        errorMessage = "No se pudieron cargar los pedidos";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatearFecha(dynamic fecha) {
    if (fecha == null) return "";
    return fecha.toString().replaceAll("T", " ").split(".").first;
  }

  Color colorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case "ENVIADO":
        return Colors.blue;
      case "RECIBIDO":
        return Colors.green;
      case "CANCELADO":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Administrar pedidos"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: cargarPedidos),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(child: Text(errorMessage!))
          : pedidos.isEmpty
          ? const Center(child: Text("No hay pedidos registrados"))
          : ListView.builder(
              itemCount: pedidos.length,
              itemBuilder: (context, index) {
                final pedido = pedidos[index];
                final estado = pedido["estado"]?.toString() ?? "SIN ESTADO";
                final pedidoId = int.tryParse(pedido["id"].toString()) ?? 0;

                // 🔥 Lógica de lectura de progreso
                final prog = progresos[pedidoId];
                final totalProv = prog != null ? prog['total'] ?? 0 : 0;
                final sentProv = prog != null ? prog['sent'] ?? 0 : 0;
                final double progressValue = totalProv == 0
                    ? 0.0
                    : sentProv / totalProv;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            GenerarPedidoProveedorDialog(pedidoId: pedidoId),
                      ).then((_) {
                        cargarPedidos();
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: colorEstado(estado),
                            child: const Icon(
                              Icons.assignment,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Orden de pedido #$pedidoId",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text("Usuario: ${pedido["usuario"] ?? ""}"),
                                Text("Estado: $estado"),
                                Text("Items: ${pedido["total_items"] ?? 0}"),
                                Text(
                                  "Fecha: ${formatearFecha(pedido["fecha_creacion"])}",
                                ),

                                // 🔥 BARRA DE PROGRESO INYECTADA EN LA TARJETA
                                if (estado == "BORRADOR" && totalProv > 0) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Progreso envíos:",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        "$sentProv/$totalProv provs.",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: progressValue,
                                    backgroundColor: Colors.grey.shade300,
                                    color: Colors.green,
                                    minHeight: 6,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blueGrey,
                                ),
                                tooltip: "Editar Pedido",
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdminPedidoDetalleScreen(
                                        pedidoId: pedidoId,
                                      ),
                                    ),
                                  ).then((_) => cargarPedidos());
                                },
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
