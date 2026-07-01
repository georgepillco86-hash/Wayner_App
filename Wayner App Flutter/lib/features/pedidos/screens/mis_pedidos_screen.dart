import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../services/pedidos_service.dart';

import 'pedido_detalle_usuario_screen.dart';

class MisPedidosScreen extends StatefulWidget {
  const MisPedidosScreen({super.key});

  @override
  State<MisPedidosScreen> createState() => _MisPedidosScreenState();
}

class _MisPedidosScreenState extends State<MisPedidosScreen> {
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
      final user = await SessionStorage.getUser();

      if (user == null) {
        throw Exception("No hay usuario en sesión");
      }

      final data = await service.listarMisPedidos(user.nombreUsuario);

      setState(() {
        pedidos = data;
      });
    } catch (e) {
      setState(() {
        errorMessage = "No se pudieron cargar tus pedidos";
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
        title: const Text("Mis pedidos enviados"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarPedidos,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : pedidos.isEmpty
                  ? const Center(child: Text("Todavía no tienes pedidos enviados"))
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
                              child: const Icon(
                                Icons.receipt_long,
                                color: Colors.white,
                              ),
                            ),
                            title: Text("Pedido #${pedido["id"]}"),
                            subtitle: Text(
                              "Estado: $estado\n"
                              "Items: ${pedido["total_items"] ?? 0}\n"
                              "Fecha: ${formatearFecha(pedido["fecha_creacion"])}",
                            ),
                            isThreeLine: true,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PedidoDetalleUsuarioScreen(
                                    pedidoId: int.tryParse(pedido["id"].toString()) ?? 0,
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