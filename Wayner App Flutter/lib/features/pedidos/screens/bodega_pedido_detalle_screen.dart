import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/pedidos_service.dart';

class BodegaPedidoDetalleScreen extends StatefulWidget {
  final int pedidoId;
  final String proveedorFiltro;

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

  // Variables para WebSockets y control de la UI
  WebSocketChannel? _channel;
  bool _isRpaDialogVisible =
      false; // 🔥 NUEVO: Rastrea si el loading está abierto

  @override
  void initState() {
    super.initState();
    cargarDetalle();
    _conectarWebSocketRPA();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  // ==========================================
  // 🔥 LÓGICA DE WEBSOCKETS Y CONTROL RPA
  // ==========================================
  void _conectarWebSocketRPA() {
    final wsUrl = Uri.parse(
      'ws://TU_IP_AQUI/pedidos/rpa/ws/${widget.pedidoId}',
    );

    try {
      _channel = WebSocketChannel.connect(wsUrl);

      _channel?.stream.listen(
        (message) {
          // 1. Lo primero que hace al recibir mensaje es cerrar el Loading
          _cerrarCargaRPA();

          final data = jsonDecode(message);
          final estado = data['estado'];
          final mensaje = data['mensaje'] ?? 'Alerta del bot RPA';

          // 2. Evalúa la respuesta
          if (estado == 'EXITO') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
            );
            cargarDetalle();

            // Opcional: Aquí podrías forzar el regreso a la lista de pedidos
            // Navigator.pop(context, true);
          } else {
            // Si es DUPLICADO, ERROR_CLAVE o TIMEOUT, muestra el diálogo de decisión
            _mostrarAlertaRPA(estado, mensaje);
          }
        },
        onError: (error) {
          _cerrarCargaRPA();
          debugPrint("Error en WebSocket RPA: $error");
        },
        onDone: () {
          debugPrint("WebSocket RPA cerrado");
        },
      );
    } catch (e) {
      debugPrint("No se pudo iniciar WebSocket RPA: $e");
    }
  }

  // 🔥 NUEVO: Función para mostrar el escudo de carga
  void _mostrarCargaRPA() {
    _isRpaDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible:
          false, // El usuario no puede tocar fuera para cerrarlo
      builder: (context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  "Sincronizando con ERP BITS...\nEl RPA está procesando la orden.",
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      // Cuando el diálogo se cierra por cualquier motivo, actualizamos el estado
      _isRpaDialogVisible = false;
    });
  }

  // 🔥 NUEVO: Función para cerrar el escudo de carga de forma segura
  void _cerrarCargaRPA() {
    if (_isRpaDialogVisible) {
      // Usa rootNavigator para asegurar que cierra el diálogo y no la pantalla
      Navigator.of(context, rootNavigator: true).pop();
      _isRpaDialogVisible = false;
    }
  }

  void _mostrarAlertaRPA(String estado, String mensaje) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              Text(estado == 'DUPLICADO' ? "XML Existente" : "Atención RPA"),
            ],
          ),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Cierra este diálogo
                // TODO: Llamar a la API para notificar al RPA que ANULE
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Orden de anulación enviada")),
                );
              },
              child: const Text("Anular", style: TextStyle(color: Colors.red)),
            ),
            if (estado ==
                'DUPLICADO') // Solo mostrar "Sobrescribir" si es duplicado
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: Llamar a la API para notificar al RPA que SOBRESCRIBA
                  // _mostrarCargaRPA(); // Podrías volver a levantar el loading aquí
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Orden de sobrescribir enviada"),
                    ),
                  );
                },
                child: const Text("Sobrescribir"),
              ),
          ],
        );
      },
    );
  }
  // ==========================================

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
        const SnackBar(content: Text("Error al actualizar la recepción")),
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

        // 🔥 NUEVO: Botón para disparar el RPA
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            // 1. Levantas la barrera de carga
            _mostrarCargaRPA();

            // 2. TODO: Llama a tu API REST para indicar que este pedido
            // entra en estado 'PENDIENTE' para que el agente Python lo tome.
            // await service.enviarAlColaRPA(widget.pedidoId, claveDeAcceso);
          },
          icon: const Icon(Icons.sync),
          label: const Text("Procesar Factura"),
          backgroundColor: Colors.blueGrey,
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
