import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pedidos_service.dart';
import 'pedido_agregar_item_screen.dart';

class AdminPedidoDetalleScreen extends StatefulWidget {
  final int pedidoId;

  const AdminPedidoDetalleScreen({
    super.key,
    required this.pedidoId,
  });

  @override
  State<AdminPedidoDetalleScreen> createState() =>
      _AdminPedidoDetalleScreenState();
}

class _AdminPedidoDetalleScreenState extends State<AdminPedidoDetalleScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  bool isLoadingTexto = false;
  String? errorMessage;

  Map<String, dynamic>? pedido;
  Map<String, dynamic>? textosProveedor;

  List<String> unidadesMedida = ['UNIDADES'];

  bool get pedidoEditable {
    final estado = pedido?["estado"]?.toString().toUpperCase() ?? "";
    return estado == "BORRADOR";
  }

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
      final data = await service.obtenerDetallePedidoAdmin(widget.pedidoId);

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

  int obtenerItemId(dynamic item) {
    return int.tryParse(item["id"].toString()) ?? 0;
  }

  String obtenerTipoDestino(dynamic item) {
    final tipo = item["tipo_destino"]?.toString().trim().toUpperCase();

    if (tipo == "GASTO") {
      return "GASTO";
    }

    return "VENTA";
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

    final nuevaCantidad =
        int.tryParse(controller.text.trim()) ?? cantidadActual;

    try {
      await service.actualizarCantidadItemPedido(
        pedidoId: widget.pedidoId,
        itemId: obtenerItemId(item),
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
        itemId: obtenerItemId(item),
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
        itemId: obtenerItemId(item),
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

  Future<void> editarNotaCompra(dynamic item) async {
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
        itemId: obtenerItemId(item),
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

  Future<void> eliminarProducto(dynamic item) async {
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
        itemId: obtenerItemId(item),
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

  Future<void> cargarTextosProveedor() async {
    setState(() {
      isLoadingTexto = true;
    });

    try {
      final data = await service.obtenerTextoPorProveedor(widget.pedidoId);

      setState(() {
        textosProveedor = data;
      });

      if (!mounted) return;

      mostrarTextosProveedor();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo generar el texto")),
      );
    } finally {
      setState(() {
        isLoadingTexto = false;
      });
    }
  }

  Future<void> cambiarEstadoPedido() async {
    final estadoActual = pedido?["estado"]?.toString().toUpperCase() ?? "";

    final opciones = ["BORRADOR", "ENVIADO", "RECIBIDO", "CANCELADO"];

    final nuevoEstado = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Cambiar estado del pedido"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: opciones.map((estado) {
              final esActual = estado == estadoActual;

              return ListTile(
                title: Text(estado),
                trailing: esActual
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, estado),
              );
            }).toList(),
          ),
        );
      },
    );

    if (nuevoEstado == null || nuevoEstado == estadoActual) return;

    try {
      await service.actualizarEstadoPedido(
        pedidoId: widget.pedidoId,
        estado: nuevoEstado,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Estado cambiado a $nuevoEstado")),
      );

      await cargarDetalle();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo cambiar el estado")),
      );
    }
  }

  Future<void> mostrarMejorProveedorPrecio(dynamic item) async {
    final codigo = item["codigo_producto"]?.toString() ?? "";
    final itemId = obtenerItemId(item);
    final proveedorActual = item["proveedor"]?.toString() ?? "SIN PROVEEDOR";

    if (codigo.isEmpty || itemId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Producto sin código o ID")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await service.obtenerMejorProveedorPrecio(
        codigoProducto: codigo,
        meses: 6,
      );

      if (!mounted) return;

      Navigator.pop(context);

      final proveedores = data["proveedores"] ?? [];

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.78,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: proveedores.isEmpty
                    ? const Center(
                        child: Text(
                          "No hay proveedores con precio registrado en los últimos 6 meses",
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item["nombre_producto"]?.toString() ??
                                "Producto sin nombre",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text("Código: $codigo"),
                          Text("Proveedor actual: $proveedorActual"),
                          Text("Periodo: ${data["periodo_meses"] ?? 6} meses"),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              itemCount: proveedores.length,
                              itemBuilder: (context, index) {
                                final p = proveedores[index];

                                final proveedor =
                                    p["proveedor"]?.toString() ?? "Proveedor";
                                final precio =
                                    p["mejor_precio"]?.toString() ?? "";
                                final fecha = p["fecha"]?.toString() ?? "";
                                final esMejor = p["es_mejor"] == true;
                                final esUnico = p["es_unico"] == true;

                                final yaSeleccionado =
                                    proveedor.trim().toUpperCase() ==
                                        proveedorActual.trim().toUpperCase();

                                String etiqueta = "";

                                if (yaSeleccionado) {
                                  etiqueta =
                                      "Proveedor seleccionado actualmente";
                                } else if (esUnico) {
                                  etiqueta =
                                      "Proveedor único registrado en los últimos 6 meses";
                                } else if (esMejor) {
                                  etiqueta =
                                      "Proveedor recomendado por mejor precio";
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              child: Text("${index + 1}"),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    proveedor,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text("Precio: \$$precio"),
                                                  Text("Fecha: $fecha"),
                                                  if (etiqueta.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        top: 6,
                                                      ),
                                                      child: Text(
                                                        etiqueta,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: yaSeleccionado
                                                              ? Colors.green
                                                              : Colors.blue,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: yaSeleccionado
                                                ? null
                                                : () async {
                                                    try {
                                                      await service
                                                          .actualizarProveedorItemPedido(
                                                        pedidoId:
                                                            widget.pedidoId,
                                                        itemId: itemId,
                                                        proveedor: proveedor,
                                                      );

                                                      if (!mounted) return;

                                                      Navigator.pop(context);

                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            "Proveedor actualizado",
                                                          ),
                                                        ),
                                                      );

                                                      await cargarDetalle();
                                                    } catch (e) {
                                                      if (!mounted) return;

                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            "No se pudo actualizar el proveedor",
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                            icon: Icon(
                                              yaSeleccionado
                                                  ? Icons.check_circle
                                                  : Icons.check,
                                            ),
                                            label: Text(
                                              yaSeleccionado
                                                  ? "Seleccionado"
                                                  : "Seleccionar proveedor",
                                            ),
                                          ),
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
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No se pudo obtener el mejor proveedor"),
        ),
      );
    }
  }

  List<dynamic> obtenerItemsProveedorFiltrados({
    required String proveedor,
    required String filtro,
  }) {
    final items = pedido?["items"] ?? [];

    return items.where((item) {
      final proveedorItem = item["proveedor"] == null ||
              item["proveedor"].toString().trim().isEmpty
          ? "SIN PROVEEDOR"
          : item["proveedor"].toString().trim();

      final tipoDestino = obtenerTipoDestino(item);

      final coincideProveedor = proveedorItem == proveedor;
      final coincideFiltro = filtro == "TODOS" || tipoDestino == filtro;

      return coincideProveedor && coincideFiltro;
    }).toList();
  }

  String construirTextoProveedorFiltrado({
    required String proveedor,
    required String filtro,
  }) {
    final itemsProveedor = obtenerItemsProveedorFiltrados(
      proveedor: proveedor,
      filtro: filtro,
    );

    final productosVenta = itemsProveedor
        .where((item) => obtenerTipoDestino(item) == "VENTA")
        .toList();

    final productosGasto = itemsProveedor
        .where((item) => obtenerTipoDestino(item) == "GASTO")
        .toList();

    String texto = "Hola, buen día.\n\n";
    texto += "Por favor ayudarme con el siguiente pedido:\n\n";

    if (productosVenta.isNotEmpty) {
      texto += "🛒 PRODUCTOS PARA VENTA:\n\n";

      for (final item in productosVenta) {
        texto += "- ${item["nombre_producto"] ?? "Producto sin nombre"}\n";
        texto += "  Código: ${item["codigo_producto"] ?? ""}\n";
        texto +=
            "  Cantidad: ${item["cantidad_pedida"] ?? 0} ${item["unidad"] ?? "UNIDADES"}\n";

        if (item["nota_compra"] != null &&
            item["nota_compra"].toString().trim().isNotEmpty) {
          texto += "  Nota de compra: ${item["nota_compra"]}\n";
        }

        texto += "\n";
      }
    }

    if (productosGasto.isNotEmpty) {
      texto += "🔥 PRODUCTOS PARA GASTO / CONSUMO INTERNO:\n\n";

      for (final item in productosGasto) {
        texto += "- ${item["nombre_producto"] ?? "Producto sin nombre"}\n";
        texto += "  Código: ${item["codigo_producto"] ?? ""}\n";
        texto +=
            "  Cantidad: ${item["cantidad_pedida"] ?? 0} ${item["unidad"] ?? "UNIDADES"}\n";

        if (item["nota_compra"] != null &&
            item["nota_compra"].toString().trim().isNotEmpty) {
          texto += "  Nota de compra: ${item["nota_compra"]}\n";
        }

        texto += "\n";
      }
    }

    texto += "Gracias.";

    return texto;
  }

  void mostrarTextosProveedor() {
    final textos = textosProveedor?["textos"] ?? [];
    String filtroSeleccionado = "TODOS";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final textosFiltrados = textos.where((item) {
              final proveedor =
                  item["proveedor"]?.toString() ?? "SIN PROVEEDOR";

              final itemsFiltrados = obtenerItemsProveedorFiltrados(
                proveedor: proveedor,
                filtro: filtroSeleccionado,
              );

              return itemsFiltrados.isNotEmpty;
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Generar pedido por proveedor",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text("Todos"),
                                selected: filtroSeleccionado == "TODOS",
                                onSelected: (_) {
                                  setModalState(() {
                                    filtroSeleccionado = "TODOS";
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: const Text("Venta"),
                                avatar: const Icon(
                                  Icons.shopping_cart,
                                  size: 18,
                                ),
                                selected: filtroSeleccionado == "VENTA",
                                selectedColor: Colors.blue.shade100,
                                onSelected: (_) {
                                  setModalState(() {
                                    filtroSeleccionado = "VENTA";
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: const Text("Gasto"),
                                avatar: const Icon(
                                  Icons.local_fire_department,
                                  size: 18,
                                ),
                                selected: filtroSeleccionado == "GASTO",
                                selectedColor: Colors.orange.shade100,
                                onSelected: (_) {
                                  setModalState(() {
                                    filtroSeleccionado = "GASTO";
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: textosFiltrados.isEmpty
                          ? const Center(
                              child: Text(
                                "No hay productos para el filtro seleccionado",
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: textosFiltrados.length,
                              itemBuilder: (context, index) {
                                final item = textosFiltrados[index];
                                final proveedor =
                                    item["proveedor"]?.toString() ??
                                        "SIN PROVEEDOR";

                                final itemsFiltrados =
                                    obtenerItemsProveedorFiltrados(
                                  proveedor: proveedor,
                                  filtro: filtroSeleccionado,
                                );

                                final texto = construirTextoProveedorFiltrado(
                                  proveedor: proveedor,
                                  filtro: filtroSeleccionado,
                                );

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          proveedor,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "Items: ${itemsFiltrados.length}",
                                        ),
                                        Text(
                                          "Filtro: ${filtroSeleccionado == "TODOS" ? "Todos" : filtroSeleccionado}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Divider(),
                                        SelectableText(texto),
                                        const SizedBox(height: 10),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              Clipboard.setData(
                                                ClipboardData(text: texto),
                                              );

                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text("Texto copiado"),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.copy),
                                            label: const Text("Copiar"),
                                          ),
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
              ),
            );
          },
        );
      },
    );
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

  String formatearFecha(dynamic fecha) {
    if (fecha == null) return "";
    return fecha.toString().replaceAll("T", " ").split(".").first;
  }

  @override
  Widget build(BuildContext context) {
    final items = pedido?["items"] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text("Admin Pedido #${widget.pedidoId}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: cargarDetalle,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Cambiar estado del pedido",
            onPressed: cambiarEstadoPedido,
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
                                Text("Usuario: ${pedido!["usuario"] ?? ""}"),
                                Text("Estado: ${pedido!["estado"] ?? ""}"),
                                Text(
                                  "Fecha: ${formatearFecha(pedido!["fecha_creacion"])}",
                                ),
                                if (pedido!["observacion"] != null)
                                  Text("Observación: ${pedido!["observacion"]}"),
                                if (pedidoEditable) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    "Este pedido puede ser editado porque está en estado ENVIADO.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                isLoadingTexto ? null : cargarTextosProveedor,
                            icon: isLoadingTexto
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.business),
                            label: Text(
                              isLoadingTexto
                                  ? "Generando..."
                                  : "Generar pedido por proveedor",
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          "Productos del pedido",
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
                                        "Proveedor: ${item["proveedor"] ?? "SIN PROVEEDOR"}",
                                      ),
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
                                          if (value == "mejor_precio") {
                                            mostrarMejorProveedorPrecio(item);
                                          } else if (value == "editar") {
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
                                            value: "mejor_precio",
                                            child: Text("Ver mejor proveedor"),
                                          ),
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