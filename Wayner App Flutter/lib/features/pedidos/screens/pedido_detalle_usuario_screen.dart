import 'package:flutter/material.dart';

import '../services/pedidos_service.dart';
import 'pedido_agregar_item_screen.dart';

class PedidoDetalleUsuarioScreen extends StatefulWidget {
  final int pedidoId;

  const PedidoDetalleUsuarioScreen({
    super.key,
    required this.pedidoId,
  });

  @override
  State<PedidoDetalleUsuarioScreen> createState() =>
      _PedidoDetalleUsuarioScreenState();
}

class _PedidoDetalleUsuarioScreenState
    extends State<PedidoDetalleUsuarioScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? pedido;

  List<String> unidadesMedida = ['UNIDADES'];

  @override
  void initState() {
    super.initState();
    cargarDetalle();
    cargarUnidadesMedida();
  }

  Future<void> cargarUnidadesMedida() async {
    try {
      final unidades = await service.obtenerUnidadesMedida();

      if (!mounted) return;

      setState(() {
        unidadesMedida = unidades.isEmpty ? ['UNIDADES'] : unidades;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        unidadesMedida = ['UNIDADES'];
      });
    }
  }

  Future<void> cargarDetalle() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await service.obtenerDetallePedidoUsuario(widget.pedidoId);

      setState(() {
        pedido = data;
      });
    } catch (e) {
      setState(() {
        errorMessage = "No se pudo cargar el detalle del pedido";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  bool get pedidoEditable {
    final estado = pedido?["estado"]?.toString().toUpperCase() ?? "";
    return estado == "BORRADOR";
  }

  int? obtenerItemId(dynamic item) {
    final rawId = item["id"];
    if (rawId == null) return null;

    final id = int.tryParse(rawId.toString());
    if (id == null || id <= 0) return null;

    return id;
  }

  String obtenerTipoDestino(dynamic item) {
    final tipo = item["tipo_destino"]?.toString().trim().toUpperCase();

    if (tipo == "GASTO") {
      return "GASTO";
    }

    return "VENTA";
  }

  String formatearFecha(dynamic fecha) {
    if (fecha == null) return "";
    return fecha.toString().replaceAll("T", " ").split(".").first;
  }

  Future<void> abrirAgregarProducto() async {
    final agregado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoAgregarItemScreen(
          pedidoId: widget.pedidoId,
        ),
      ),
    );

    if (agregado == true) {
      await cargarDetalle();
    }
  }

  Future<void> editarCantidad(dynamic item) async {
    final itemId = obtenerItemId(item);

    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No se puede editar: el backend no devolvió el ID del item",
          ),
        ),
      );
      return;
    }

    final cantidadActual =
        int.tryParse(item["cantidad_pedida"].toString()) ?? 1;

    final controller = TextEditingController(
      text: cantidadActual.toString(),
    );

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Modificar cantidad"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Cantidad",
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
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );

    if (confirmado != true) return;

    final nuevaCantidad = int.tryParse(controller.text.trim()) ?? cantidadActual;

    try {
      await service.actualizarCantidadItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
        cantidad: nuevaCantidad <= 0 ? 1 : nuevaCantidad,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cantidad actualizada")),
      );

      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo actualizar la cantidad")),
      );
    }
  }

  Future<void> editarUnidad(dynamic item) async {
    final itemId = obtenerItemId(item);

    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No se puede editar: el backend no devolvió el ID del item",
          ),
        ),
      );
      return;
    }

    String unidadSeleccionada =
        item["unidad"]?.toString().trim().toUpperCase() ?? "UNIDADES";

    if (!unidadesMedida.contains(unidadSeleccionada)) {
      unidadSeleccionada =
          unidadesMedida.isNotEmpty ? unidadesMedida.first : "UNIDADES";
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Editar unidad de medida"),
              content: DropdownButtonFormField<String>(
                value: unidadSeleccionada,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Unidad de medida",
                  border: OutlineInputBorder(),
                ),
                items: unidadesMedida.map((unidad) {
                  return DropdownMenuItem<String>(
                    value: unidad,
                    child: Text(unidad),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    unidadSeleccionada = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Guardar"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmado != true) return;

    try {
      await service.actualizarUnidadItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
        unidad: unidadSeleccionada,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unidad de medida actualizada")),
      );

      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo actualizar la unidad")),
      );
    }
  }

  Future<void> editarTipoDestino(dynamic item) async {
    final itemId = obtenerItemId(item);

    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No se puede editar: el backend no devolvió el ID del item",
          ),
        ),
      );
      return;
    }

    String tipoDestinoSeleccionado = obtenerTipoDestino(item);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Editar destino"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Selecciona el destino del producto:"),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text("VENTA"),
                        avatar: Icon(
                          Icons.shopping_cart,
                          size: 18,
                          color: tipoDestinoSeleccionado == "VENTA"
                              ? Colors.blue.shade900
                              : null,
                        ),
                        selected: tipoDestinoSeleccionado == "VENTA",
                        selectedColor: Colors.blue.shade100,
                        onSelected: (_) {
                          setDialogState(() {
                            tipoDestinoSeleccionado = "VENTA";
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text("GASTO"),
                        avatar: Icon(
                          Icons.local_fire_department,
                          size: 18,
                          color: tipoDestinoSeleccionado == "GASTO"
                              ? Colors.orange.shade900
                              : null,
                        ),
                        selected: tipoDestinoSeleccionado == "GASTO",
                        selectedColor: Colors.orange.shade100,
                        onSelected: (_) {
                          setDialogState(() {
                            tipoDestinoSeleccionado = "GASTO";
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Guardar"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmado != true) return;

    try {
      await service.actualizarTipoDestinoItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
        tipoDestino: tipoDestinoSeleccionado,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Destino actualizado")),
      );

      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo actualizar el destino")),
      );
    }
  }

  Future<void> eliminarProducto(dynamic item) async {
    final itemId = obtenerItemId(item);

    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No se puede eliminar: el backend no devolvió el ID del item",
          ),
        ),
      );
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Eliminar producto"),
          content: Text(
            "¿Seguro que deseas eliminar este producto del pedido?\n\n"
            "${item["nombre_producto"] ?? ""}",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Eliminar"),
            ),
          ],
        );
      },
    );

    if (confirmado != true) return;

    try {
      await service.eliminarItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Producto eliminado")),
      );

      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo eliminar el producto")),
      );
    }
  }

  Future<void> editarNotaCompra(dynamic item) async {
    final itemId = obtenerItemId(item);

    if (itemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No se puede editar: el backend no devolvió el ID del item",
          ),
        ),
      );
      return;
    }

    final notaActual = item["nota_compra"]?.toString() ?? "";

    final controller = TextEditingController(text: notaActual);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Editar nota de compra"),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: "Nota de compra",
              hintText: "Nota opcional para este producto",
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );

    if (confirmado != true) {
      return;
    }

    final nuevaNota = controller.text.trim();

    try {
      await service.actualizarNotaItemPedido(
        pedidoId: widget.pedidoId,
        itemId: itemId,
        notaCompra: nuevaNota.isEmpty ? null : nuevaNota,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nota de compra actualizada")),
      );

      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo actualizar la nota")),
      );
    }
  }

  Widget buildTipoDestinoBadge(dynamic item) {
    final tipoDestino = obtenerTipoDestino(item);
    final esGasto = tipoDestino == "GASTO";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: esGasto ? Colors.orange.shade100 : Colors.blue.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: esGasto ? Colors.orange.shade700 : Colors.blue.shade700,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            esGasto ? Icons.local_fire_department : Icons.shopping_cart,
            size: 14,
            color: esGasto ? Colors.orange.shade900 : Colors.blue.shade900,
          ),
          const SizedBox(width: 4),
          Text(
            tipoDestino,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: esGasto ? Colors.orange.shade900 : Colors.blue.shade900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = pedido?["items"] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text("Pedido #${widget.pedidoId}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarDetalle,
          ),
          if (pedidoEditable)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: "Agregar producto",
              onPressed: abrirAgregarProducto,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : pedido == null
                  ? const Center(child: Text("Pedido no encontrado"))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Pedido #${pedido!["id"]}",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text("Estado: ${pedido!["estado"] ?? ""}"),
                                Text(
                                  "Fecha: ${formatearFecha(pedido!["fecha_creacion"])}",
                                ),
                                if (pedido!["observacion"] != null)
                                  Text("Observación: ${pedido!["observacion"]}"),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Productos enviados",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Text("Este pedido no tiene productos"),
                            ),
                          )
                        else
                          ...items.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text("${index + 1}"),
                                ),
                                title: Text(
                                  item["nombre_producto"]?.toString() ??
                                      "Producto sin nombre",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      buildTipoDestinoBadge(item),
                                      const SizedBox(height: 6),
                                      Text(
                                        "Código: ${item["codigo_producto"] ?? ""}",
                                      ),
                                      Text("Marca: ${item["marca"] ?? ""}"),
                                      Text(
                                        "Cantidad: ${item["cantidad_pedida"] ?? 0} ${item["unidad"] ?? "UNIDADES"}",
                                      ),
                                      if (item["nota_compra"] != null &&
                                          item["nota_compra"]
                                              .toString()
                                              .trim()
                                              .isNotEmpty)
                                        Text(
                                          "Nota de compra: ${item["nota_compra"]}",
                                        ),
                                    ],
                                  ),
                                ),
                                trailing: pedidoEditable
                                    ? PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == "editar") {
                                            editarCantidad(item);
                                          } else if (value == "unidad") {
                                            editarUnidad(item);
                                          } else if (value == "destino") {
                                            editarTipoDestino(item);
                                          } else if (value == "nota") {
                                            editarNotaCompra(item);
                                          } else if (value == "eliminar") {
                                            eliminarProducto(item);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: "editar",
                                            child: Text("Editar cantidad"),
                                          ),
                                          PopupMenuItem(
                                            value: "unidad",
                                            child: Text("Editar unidad"),
                                          ),
                                          PopupMenuItem(
                                            value: "destino",
                                            child: Text("Editar destino"),
                                          ),
                                          PopupMenuItem(
                                            value: "nota",
                                            child: Text("Editar nota de compra"),
                                          ),
                                          PopupMenuItem(
                                            value: "eliminar",
                                            child: Text("Eliminar producto"),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                      ],
                    ),
    );
  }
}