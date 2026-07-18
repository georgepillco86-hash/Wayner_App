import 'package:flutter/material.dart';

import '../services/pedidos_service.dart';
import 'admin_pedido_detalle_screen.dart';

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

      setState(() {
        pedidos = data;
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

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorEstado(estado),
                      child: const Icon(Icons.assignment, color: Colors.white),
                    ),
                    title: Text("Orden de pedido #${pedido["id"]}"),
                    subtitle: Text(
                      "Usuario: ${pedido["usuario"] ?? ""}\n"
                      "Estado: $estado\n"
                      "Items: ${pedido["total_items"] ?? 0}\n"
                      "Fecha: ${formatearFecha(pedido["fecha_creacion"])}",
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminPedidoDetalleScreen(
                            pedidoId:
                                int.tryParse(pedido["id"].toString()) ?? 0,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
