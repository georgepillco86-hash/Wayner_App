import 'package:flutter/material.dart';
import '../services/pedidos_service.dart';

class BodegaPedidoDetalleScreen extends StatefulWidget {
  final int pedidoId;
  final String proveedorFiltro; // 🔥 Parámetro para saber qué proveedor mostrar

  const BodegaPedidoDetalleScreen({
    super.key,
    required this.pedidoId,
    required this.proveedorFiltro,
  });

  @override
  State<BodegaPedidoDetalleScreen> createState() =>
      _BodegaPedidoDetalleScreenState();
}

class _BodegaPedidoDetalleScreenState extends State<BodegaPedidoDetalleScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? detallePedido;

  @override
  void initState() {
    super.initState();
    cargarDetalle();
  }

  Future<void> cargarDetalle() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await service.obtenerDetallePedidoBodega(widget.pedidoId);

      if (!mounted) return;

      setState(() {
        detallePedido = data;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = "No se pudo cargar el detalle del pedido";
      });
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> actualizarRecepcion(
    int itemId,
    bool recibido,
    String? comentario,
  ) async {
    try {
      await service.actualizarRecepcionItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
        recibido: recibido,
        comentarioRecepcion: comentario,
      );
      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error al actualizar la recepción del item"),
        ),
      );
    }
  }

  void mostrarDialogoComentario(
    int itemId,
    bool recibidoActual,
    String? comentarioActual,
  ) {
    final TextEditingController controller = TextEditingController(
      text: comentarioActual ?? "",
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Comentario / Observación"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Escribe alguna novedad (opcional)...",
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                actualizarRecepcion(
                  itemId,
                  recibidoActual,
                  controller.text.trim(),
                );
              },
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = detallePedido?["usuario"] ?? "";
    final estado = detallePedido?["estado"] ?? "";
    final observacionGeneral = detallePedido?["observacion"] ?? "";

    // 🔥 FILTRAMOS LOS PROVEEDORES PARA MOSTRAR ÚNICAMENTE EL QUE CORRESPONDE 🔥
    final todosLosProveedores =
        detallePedido?["proveedores"] as List<dynamic>? ?? [];
    final proveedoresFiltrados = todosLosProveedores.where((grupo) {
      final provNombre =
          grupo["proveedor"]?.toString().trim().toUpperCase() ?? "";
      return provNombre == widget.proveedorFiltro.trim().toUpperCase();
    }).toList();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Recepción Pedido #${widget.pedidoId}"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? Center(
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabecera informativa
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Usuario: $usuario",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text("Estado: $estado"),
                            if (observacionGeneral.isNotEmpty)
                              Text(
                                "Obs: $observacionGeneral",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            const Divider(),
                            Text(
                              "Proveedor en revisión: ${widget.proveedorFiltro}",
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Lista de productos del proveedor seleccionado
                    Expanded(
                      child: proveedoresFiltrados.isEmpty
                          ? const Center(
                              child: Text(
                                "No hay productos asignados para este proveedor.",
                              ),
                            )
                          : ListView.builder(
                              itemCount: proveedoresFiltrados.length,
                              itemBuilder: (context, pIndex) {
                                final grupo = proveedoresFiltrados[pIndex];
                                final items =
                                    grupo["items"] as List<dynamic>? ?? [];

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...items.map((item) {
                                      final itemId =
                                          int.tryParse(item["id"].toString()) ??
                                          0;
                                      final nombre =
                                          item["nombre_producto"] ?? "";
                                      final codigo =
                                          item["codigo_producto"] ?? "";
                                      final cantidad =
                                          item["cantidad_pedida"] ?? 0;
                                      final unidad = item["unidad"] ?? "U";
                                      final tipoDestino =
                                          item["tipo_destino"] ?? "VENTA";
                                      final recibido = item["recibido"] == true;
                                      final comentario =
                                          item["comentario_recepcion"];

                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: ListTile(
                                          leading: Checkbox(
                                            value: recibido,
                                            onChanged: (val) {
                                              actualizarRecepcion(
                                                itemId,
                                                val ?? false,
                                                comentario,
                                              );
                                            },
                                          ),
                                          title: Text(
                                            nombre,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              decoration: recibido
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Código: $codigo | Cantidad: $cantidad $unidad",
                                              ),
                                              Row(
                                                children: [
                                                  Chip(
                                                    label: Text(tipoDestino),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    backgroundColor:
                                                        Colors.blue.shade50,
                                                  ),
                                                ],
                                              ),
                                              if (comentario != null &&
                                                  comentario
                                                      .toString()
                                                      .isNotEmpty)
                                                Text(
                                                  "Obs: $comentario",
                                                  style: const TextStyle(
                                                    color: Colors.orange,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          trailing: IconButton(
                                            icon: Icon(
                                              Icons.comment,
                                              color:
                                                  (comentario != null &&
                                                      comentario
                                                          .toString()
                                                          .isNotEmpty)
                                                  ? Colors.orange
                                                  : Colors.grey,
                                            ),
                                            tooltip: "Agregar observación",
                                            onPressed: () =>
                                                mostrarDialogoComentario(
                                                  itemId,
                                                  recibido,
                                                  comentario,
                                                ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
