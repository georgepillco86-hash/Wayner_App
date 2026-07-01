import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pedidos_service.dart';

class BodegaPedidoDetalleScreen extends StatefulWidget {
  final int pedidoId;

  const BodegaPedidoDetalleScreen({
    super.key,
    required this.pedidoId,
  });

  @override
  State<BodegaPedidoDetalleScreen> createState() =>
      _BodegaPedidoDetalleScreenState();
}

class _BodegaPedidoDetalleScreenState
    extends State<BodegaPedidoDetalleScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  bool procesandoRecepcion = false;

  Map<String, dynamic>? pedido;

  @override
  void initState() {
    super.initState();
    cargarDetalle();
  }

  bool get puedeEditarRecepcion {
    final estado = pedido?["estado"]?.toString().toUpperCase() ?? "";
    return estado == "ENVIADO";
  }

  Future<void> cargarDetalle() async {
    setState(() {
      isLoading = true;
    });

    try {
      final data = await service.obtenerDetallePedidoBodega(widget.pedidoId);

      if (!mounted) return;

      setState(() {
        pedido = data;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error cargando detalle: $e")),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> actualizarRecepcionItem({
    required int itemId,
    required bool recibido,
    required String? comentario,
  }) async {
    if (!puedeEditarRecepcion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este pedido ya no permite modificar recepción"),
        ),
      );
      return;
    }

    setState(() {
      procesandoRecepcion = true;
    });

    try {
      await service.actualizarRecepcionItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
        recibido: recibido,
        comentarioRecepcion: comentario,
      );

      await cargarDetalle();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Recepción actualizada")),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error actualizando recepción: $e")),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        procesandoRecepcion = false;
      });
    }
  }

  Future<void> editarComentario(dynamic item) async {
    if (!puedeEditarRecepcion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este pedido ya no permite modificar comentarios"),
        ),
      );
      return;
    }

    final controller = TextEditingController(
      text: item["comentario_recepcion"] ?? "",
    );

    final result = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Comentario de recepción"),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "Ej: llegó incompleto",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    await actualizarRecepcionItem(
      itemId: item["id"],
      recibido: item["recibido"] == true,
      comentario: result,
    );
  }

  Future<void> toggleRecibido(dynamic item, bool value) async {
    await actualizarRecepcionItem(
      itemId: item["id"],
      recibido: value,
      comentario: item["comentario_recepcion"],
    );
  }

  Future<void> marcarPedidoRecibido() async {
    if (!puedeEditarRecepcion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Solo se puede finalizar un pedido ENVIADO"),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Finalizar recepción"),
          content: const Text(
            "¿Deseas finalizar la recepción y marcar este pedido como RECIBIDO?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Confirmar"),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    setState(() {
      procesandoRecepcion = true;
    });

    try {
      await service.marcarPedidoRecibido(widget.pedidoId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pedido marcado como recibido")),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error marcando pedido recibido: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          procesandoRecepcion = false;
        });
      }
    }
  }

  Future<void> seleccionarTodoPedido() async {
    if (!puedeEditarRecepcion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este pedido ya no permite modificar recepción"),
        ),
      );
      return;
    }

    final proveedores = pedido?["proveedores"] as List<dynamic>? ?? [];

    final items = proveedores
        .expand((proveedor) => proveedor["items"] as List<dynamic>? ?? [])
        .where((item) => item["recibido"] != true)
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Todos los productos ya están recibidos")),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Seleccionar todo"),
        content: Text(
          "¿Deseas marcar como recibidos los ${items.length} productos pendientes?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      procesandoRecepcion = true;
    });

    try {
      for (final item in items) {
        await service.actualizarRecepcionItemPedido(
          pedidoId: widget.pedidoId,
          itemId: item["id"],
          recibido: true,
          comentarioRecepcion: item["comentario_recepcion"],
        );
      }

      await cargarDetalle();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Todos los productos fueron marcados como recibidos"),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error seleccionando todo: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          procesandoRecepcion = false;
        });
      }
    }
  }

  Future<void> marcarProveedorCompleto(dynamic proveedorData) async {
    if (!puedeEditarRecepcion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este pedido ya no permite modificar recepción"),
        ),
      );
      return;
    }

    final proveedor = proveedorData["proveedor"] ?? "SIN PROVEEDOR";
    final items = proveedorData["items"] as List<dynamic>? ?? [];

    final pendientes = items.where((item) => item["recibido"] != true).toList();

    if (pendientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$proveedor ya está completo")),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Marcar proveedor completo"),
        content: Text(
          "¿Deseas marcar como recibidos los ${pendientes.length} productos de $proveedor?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      procesandoRecepcion = true;
    });

    try {
      for (final item in pendientes) {
        await service.actualizarRecepcionItemPedido(
          pedidoId: widget.pedidoId,
          itemId: item["id"],
          recibido: true,
          comentarioRecepcion: item["comentario_recepcion"],
        );
      }

      await cargarDetalle();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Proveedor $proveedor marcado como completo")),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error actualizando proveedor: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          procesandoRecepcion = false;
        });
      }
    }
  }

  Future<void> vistaPreviaNovedades({String? proveedor}) async {
    try {
      final data = await service.obtenerTextoNovedadesRecepcion(
        widget.pedidoId,
        proveedor: proveedor,
      );

      final texto = data["texto"]?.toString() ?? "";

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            proveedor == null
                ? "Vista previa de novedades"
                : "Novedades - $proveedor",
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(texto),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cerrar"),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: texto));

                if (!mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Texto copiado")),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text("Copiar"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generando vista previa: $e")),
      );
    }
  }

  Widget buildBadgeDestino(String tipo) {
    final isVenta = tipo.toUpperCase() == "VENTA";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isVenta ? Colors.blue.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isVenta ? Colors.blue.shade700 : Colors.orange.shade700,
        ),
      ),
      child: Text(
        isVenta ? "🛒 VENTA" : "🔥 GASTO",
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isVenta ? Colors.blue.shade900 : Colors.orange.shade900,
        ),
      ),
    );
  }

  Widget buildProveedorCard(dynamic proveedorData) {
    final proveedor = proveedorData["proveedor"] ?? "SIN PROVEEDOR";
    final items = proveedorData["items"] as List<dynamic>? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              proveedor,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !puedeEditarRecepcion || procesandoRecepcion
                      ? null
                      : () => marcarProveedorCompleto(proveedorData),
                  icon: const Icon(Icons.done_all),
                  label: const Text("Proveedor completo"),
                ),
                OutlinedButton.icon(
                  onPressed: () => vistaPreviaNovedades(proveedor: proveedor),
                  icon: const Icon(Icons.preview),
                  label: const Text("Vista previa"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final recibido = item["recibido"] == true;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        recibido ? Colors.green.shade300 : Colors.grey.shade300,
                  ),
                  color: recibido ? Colors.green.shade50 : Colors.white,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: recibido,
                      onChanged: !puedeEditarRecepcion || procesandoRecepcion
                          ? null
                          : (value) {
                              toggleRecibido(item, value ?? false);
                            },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item["nombre_producto"] ?? "",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          buildBadgeDestino(item["tipo_destino"] ?? "VENTA"),
                          const SizedBox(height: 8),
                          Text("Código: ${item["codigo_producto"] ?? ""}"),
                          Text(
                            "Cantidad: ${item["cantidad_pedida"]} "
                            "${item["unidad"] ?? "UNIDADES"}",
                          ),
                          if ((item["nota_compra"] ?? "")
                              .toString()
                              .trim()
                              .isNotEmpty)
                            Text(
                              "Nota: ${item["nota_compra"]}",
                              style: TextStyle(color: Colors.orange.shade900),
                            ),
                          const SizedBox(height: 10),
                          if ((item["comentario_recepcion"] ?? "")
                              .toString()
                              .trim()
                              .isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.orange.shade300,
                                ),
                              ),
                              child: Text(
                                item["comentario_recepcion"],
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    !puedeEditarRecepcion || procesandoRecepcion
                                        ? null
                                        : () {
                                            editarComentario(item);
                                          },
                                icon: const Icon(Icons.edit_note),
                                label: const Text("Comentario"),
                              ),
                              const SizedBox(width: 10),
                              if (recibido)
                                Chip(
                                  label: const Text("RECIBIDO"),
                                  backgroundColor: Colors.green.shade100,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final proveedores = pedido?["proveedores"] as List<dynamic>? ?? [];
    final estadoPedido = pedido?["estado"]?.toString().toUpperCase() ?? "";
    final puedeFinalizarRecepcion = estadoPedido == "ENVIADO";

    return Scaffold(
      appBar: AppBar(
        title: Text("Recepción Pedido #${widget.pedidoId}"),
        actions: [
          IconButton(
            tooltip: "Seleccionar todo",
            icon: const Icon(Icons.done_all),
            onPressed: !puedeEditarRecepcion || procesandoRecepcion
                ? null
                : seleccionarTodoPedido,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarDetalle,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Usuario: ${pedido?["usuario"] ?? ""}"),
                              Text("Estado: ${pedido?["estado"] ?? ""}"),
                              if ((pedido?["observacion"] ?? "")
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(pedido?["observacion"] ?? ""),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...proveedores.map(buildProveedorCard),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 6,
                        color: Colors.black.withOpacity(0.08),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => vistaPreviaNovedades(),
                              icon: const Icon(Icons.copy),
                              label: const Text("Vista previa"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context, true);
                              },
                              icon: const Icon(Icons.save),
                              label: const Text("Actualizar pedido"),
                            ),
                          ),
                        ],
                      ),
                      if (puedeFinalizarRecepcion) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: procesandoRecepcion
                                ? null
                                : marcarPedidoRecibido,
                            icon: const Icon(Icons.check_circle),
                            label: const Text("Finalizar recepción"),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}