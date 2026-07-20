import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 NUEVO IMPORT
import '../services/pedidos_service.dart';

class GenerarPedidoProveedorDialog extends StatefulWidget {
  final int pedidoId;

  const GenerarPedidoProveedorDialog({super.key, required this.pedidoId});

  @override
  State<GenerarPedidoProveedorDialog> createState() =>
      _GenerarPedidoProveedorDialogState();
}

class _GenerarPedidoProveedorDialogState
    extends State<GenerarPedidoProveedorDialog> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic>? pedido;
  Map<String, dynamic>? textosGenerados;

  String filtroSeleccionado = "TODOS";
  Map<String, Map<String, dynamic>?> costosCache = {};

  Set<String> proveedoresEnviados = {};
  SharedPreferences? _prefs; // 🔥 Referencia a la caché

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // 🔥 Cargamos la caché local
      _prefs = await SharedPreferences.getInstance();
      final guardados =
          _prefs?.getStringList('pedido_${widget.pedidoId}_sent') ?? [];
      proveedoresEnviados = guardados.toSet();

      final dataPedido = await service.obtenerDetallePedidoAdmin(
        widget.pedidoId,
      );
      final dataTextos = await service.obtenerTextosProveedor(widget.pedidoId);

      setState(() {
        pedido = dataPedido;
        textosGenerados = dataTextos;
      });

      _cargarCostosGlobales();
    } catch (e) {
      setState(() {
        errorMessage = "Error al cargar la información del pedido.";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _cargarCostosGlobales() async {
    final items = pedido?["items"] as List<dynamic>? ?? [];
    for (var item in items) {
      final codigo = item["codigo_producto"]?.toString();
      if (codigo != null &&
          codigo.isNotEmpty &&
          !costosCache.containsKey(codigo)) {
        try {
          final costoData = await service.obtenerMejorCostoGlobal(
            codigo,
            meses: 3,
          );
          if (mounted) {
            setState(() {
              costosCache[codigo] = costoData;
            });
          }
        } catch (_) {}
      }
    }
  }

  String _formatearFechaCorta(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Future<void> _autoMarcarComoEnviado() async {
    final estadoActual = pedido?["estado"]?.toString().toUpperCase();
    if (estadoActual != "ENVIADO" && estadoActual != "RECIBIDO") {
      try {
        await service.actualizarEstadoPedido(
          pedidoId: widget.pedidoId,
          estado: "ENVIADO",
        );

        if (mounted) {
          setState(() {
            pedido?["estado"] = "ENVIADO";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "✅ Todos los pedidos enviados. Orden marcada como ENVIADA.",
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint("Error al auto-actualizar estado: $e");
      }
    }
  }

  Color _getColorPorEstado(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'BORRADOR':
        return Colors.orange;
      case 'ENVIADO':
        return Colors.blue;
      case 'RECIBIDO':
        return Colors.green;
      case 'CANCELADO':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _cambiarProveedor(dynamic itemInfo) async {
    final codigo = itemInfo["codigo_producto"]?.toString() ?? "";

    final itemsPedidoOriginal = pedido?["items"] as List<dynamic>? ?? [];
    final itemReal = itemsPedidoOriginal.firstWhere(
      (i) => i["codigo_producto"]?.toString() == codigo,
      orElse: () => {},
    );

    final itemIdStr = itemReal["id"]?.toString() ?? "0";
    final itemId = int.tryParse(itemIdStr) ?? 0;

    if (codigo.isEmpty || itemId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Error: No se pudo identificar el ID del producto en el pedido.",
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final proveedores = await service.obtenerProveedoresProducto(codigo);
      if (!mounted) return;
      Navigator.pop(context);

      if (proveedores.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No se encontraron otros proveedores para este producto.",
            ),
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        builder: (_) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Seleccionar Nuevo Destino",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: proveedores.length,
                  itemBuilder: (context, index) {
                    final p = proveedores[index];
                    final nombreProv =
                        p["proveedor"]?.toString() ?? "Sin nombre";

                    return ListTile(
                      leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                      title: Text(nombreProv),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await service.actualizarProveedorItemPedido(
                            pedidoId: widget.pedidoId,
                            itemId: itemId,
                            proveedor: nombreProv,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Proveedor actualizado exitosamente.",
                              ),
                            ),
                          );
                          // Si cambiamos un proveedor, reiniciamos el tracking local para evitar bugs
                          proveedoresEnviados.clear();
                          if (_prefs != null) {
                            await _prefs!.remove(
                              'pedido_${widget.pedidoId}_sent',
                            );
                          }
                          _cargarTodo();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Error al actualizar proveedor."),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al obtener proveedores.")),
      );
    }
  }

  void _verHistorial(String codigo, String nombreProducto) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final historial = await service.obtenerHistorialCostos(codigo, 5);
      if (!mounted) return;
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Historial de Costos",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  nombreProducto,
                  style: const TextStyle(color: Colors.grey),
                ),
                const Divider(),
                Expanded(
                  child: historial.isEmpty
                      ? const Center(
                          child: Text("No hay historial de compras disponible"),
                        )
                      : ListView.builder(
                          itemCount: historial.length,
                          itemBuilder: (context, index) {
                            final h = historial[index];

                            final costoFinal =
                                double.tryParse(
                                  h["costo_final"]?.toString() ?? "0",
                                ) ??
                                0.0;
                            final ivaPct =
                                h["iva_porcentaje"]?.toString() ?? "0";
                            final tieneIva = h["tiene_iva"] == true;
                            final etiquetaIva = tieneIva
                                ? "(Con IVA)"
                                : "(Sin IVA)";

                            return Card(
                              child: ListTile(
                                title: Text(
                                  "\$${costoFinal.toStringAsFixed(3)} $etiquetaIva",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Proveedor: ${h["proveedor"] ?? 'Desconocido'}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      "Fecha: ${h["fecha"]?.toString().split('T').first ?? ''} | Impuesto: $ivaPct% IVA",
                                    ),
                                    Text(
                                      "Doc: ${h["documento"] ?? ''}",
                                      style: const TextStyle(fontSize: 12),
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
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al cargar el historial")),
      );
    }
  }

  List<dynamic> _obtenerItemsParaTexto(String proveedor) {
    final textos = textosGenerados?["textos"] as List<dynamic>? ?? [];
    final provData = textos.firstWhere(
      (t) => t["proveedor"] == proveedor,
      orElse: () => {},
    );
    final items = provData["items_detalle"] as List<dynamic>? ?? [];

    return items.where((item) {
      final tipo = item["tipo_destino"]?.toString().toUpperCase() ?? "VENTA";
      return filtroSeleccionado == "TODOS" || tipo == filtroSeleccionado;
    }).toList();
  }

  String _construirTextoComoPDF(String proveedor, List<dynamic> items) {
    double subtotal15 = 0.0;
    double subtotal0 = 0.0;
    const double totalDescuentos = 0.0;

    String txt = "*Duchi Sanchez Rosa Emperatriz*\n";
    txt += "RUC: 0102249976001\n";
    txt += "*FERROTIENDA*\n";
    txt += "Dirección Matriz: 1ro de Septiembre y Cantón Sígsig\n\n";

    txt += "Orden de pedido #${widget.pedidoId}\n";
    txt += "Proveedor: $proveedor\n";
    txt += "Fecha de emisión: ${_formatearFechaCorta(DateTime.now())}\n";
    txt +=
        "Fecha tentativa entrega: ${_formatearFechaCorta(DateTime.now().add(const Duration(days: 7)))}\n";
    txt += "Vigencia del pedido: 1 semana\n\n";

    txt += "📦 *DETALLE DEL PEDIDO:*\n";
    txt += "----------------------------------------\n";

    for (var item in items) {
      final cant = double.tryParse(item["cantidad_pedida"].toString()) ?? 0;
      final costoUnit =
          double.tryParse(item["costo_base"]?.toString() ?? "0") ?? 0.0;
      final tieneIva = item["tiene_iva"] == true;
      const desc = 0.0;

      final subtotalItem = (costoUnit - desc) * cant;

      if (tieneIva) {
        subtotal15 += subtotalItem;
      } else {
        subtotal0 += subtotalItem;
      }

      txt += "▪️ ${item["nombre_producto"]}\n";
      txt += "   Código: ${item["codigo_producto"]} | Cant: $cant\n";
      txt +=
          "   Costo U: \$${costoUnit.toStringAsFixed(4)} | IVA: ${tieneIva ? '15%' : '0%'}\n";
      txt += "   Total: \$${subtotalItem.toStringAsFixed(2)}\n\n";
    }

    final totalIva = subtotal15 * 0.15;
    final totalNeto = subtotal15 + subtotal0 + totalIva - totalDescuentos;

    txt += "----------------------------------------\n";
    txt += "Subtotal 15% (con IVA): \$${subtotal15.toStringAsFixed(2)}\n";
    txt += "Subtotal 0% (sin IVA): \$${subtotal0.toStringAsFixed(2)}\n";
    txt += "Total Descuentos: \$${totalDescuentos.toStringAsFixed(2)}\n";
    txt += "Valor Total de IVA: \$${totalIva.toStringAsFixed(2)}\n";
    txt += "💰 *TOTAL NETO A PAGAR: \$${totalNeto.toStringAsFixed(2)}*\n";

    return txt;
  }

  Future<void> _compartirUnificado(
    String proveedor,
    List<dynamic> items,
    String textoPlano,
    int totalProveedores,
  ) async {
    final pdf = pw.Document();

    double subtotal15 = 0.0;
    double subtotal0 = 0.0;
    const double totalDescuentos = 0.0;

    final tableData = items.map((item) {
      final cant = double.tryParse(item["cantidad_pedida"].toString()) ?? 0;
      final costoUnit =
          double.tryParse(item["costo_base"]?.toString() ?? "0") ?? 0.0;
      final tieneIva = item["tiene_iva"] == true;
      const desc = 0.0;

      final subtotalItem = (costoUnit - desc) * cant;

      if (tieneIva) {
        subtotal15 += subtotalItem;
      } else {
        subtotal0 += subtotalItem;
      }

      return [
        item["codigo_producto"]?.toString() ?? "",
        item["nombre_producto"]?.toString() ?? "",
        cant.toString(),
        "\$${costoUnit.toStringAsFixed(4)}",
        "\$${desc.toStringAsFixed(2)}",
        tieneIva ? "15%" : "0%",
        "\$${subtotalItem.toStringAsFixed(2)}",
      ];
    }).toList();

    final totalIva = subtotal15 * 0.15;
    final totalNeto = subtotal15 + subtotal0 + totalIva - totalDescuentos;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Text(
              "Duchi Sanchez Rosa Emperatriz",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
            ),
            pw.Text("RUC: 0102249976001"),
            pw.Text(
              "FERROTIENDA",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.Text("Dirección Matriz: 1ro de Septiembre y Cantón Sígsig"),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Orden de pedido #${widget.pedidoId}",
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.Text("Proveedor: $proveedor"),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Fecha de emisión: ${_formatearFechaCorta(DateTime.now())}",
                    ),
                    pw.Text(
                      "Fecha tentativa entrega: ${_formatearFechaCorta(DateTime.now().add(const Duration(days: 7)))}",
                    ),
                    pw.Text("Vigencia del pedido: 1 semana"),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'Código',
                'Descripción',
                'Cant.',
                'Costo Unit.',
                'Dscto',
                'IVA',
                'Total',
              ],
              data: tableData,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellAlignment: pw.Alignment.centerRight,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
              },
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    "Subtotal 15% (con IVA): \$${subtotal15.toStringAsFixed(2)}",
                  ),
                  pw.Text(
                    "Subtotal 0% (sin IVA): \$${subtotal0.toStringAsFixed(2)}",
                  ),
                  pw.Text(
                    "Total Descuentos Comerciales: \$${totalDescuentos.toStringAsFixed(2)}",
                  ),
                  pw.Text(
                    "Valor Total de Impuestos (IVA): \$${totalIva.toStringAsFixed(2)}",
                  ),
                  pw.Container(width: 180, child: pw.Divider()),
                  pw.Text(
                    "Total Neto a Pagar: \$${totalNeto.toStringAsFixed(2)}",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final xFile = XFile.fromData(
      bytes,
      name: 'Orden_Pedido_${widget.pedidoId}_$proveedor.pdf',
      mimeType: 'application/pdf',
    );

    await Share.shareXFiles([xFile], text: textoPlano);

    // 🔥 GUARDAMOS EL PROGRESO EN CACHÉ 🔥
    setState(() {
      proveedoresEnviados.add(proveedor);
    });
    if (_prefs != null) {
      await _prefs!.setStringList(
        'pedido_${widget.pedidoId}_sent',
        proveedoresEnviados.toList(),
      );
    }

    if (proveedoresEnviados.length == totalProveedores) {
      await _autoMarcarComoEnviado();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textos = textosGenerados?["textos"] as List<dynamic>? ?? [];
    final proveedoresDisponibles = textos
        .map((t) => t["proveedor"]?.toString() ?? "SIN PROVEEDOR")
        .toList();
    final totalProv = proveedoresDisponibles.length;
    final sentProv = proveedoresEnviados.length;
    final progress = totalProv == 0 ? 0.0 : sentProv / totalProv;

    // 🔥 Actualizamos el total general en caché para que la lista principal lo lea
    if (_prefs != null && totalProv > 0) {
      _prefs!.setInt('pedido_${widget.pedidoId}_total', totalProv);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? Center(child: Text(errorMessage!))
            : Column(
                children: [
                  const Text(
                    "Gestión de Pedidos a Proveedores",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getColorPorEstado(pedido?["estado"]?.toString()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "Estado General: ${pedido?["estado"] ?? 'CARGANDO...'}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  if (totalProv > 0)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 16.0,
                        bottom: 8.0,
                        left: 16,
                        right: 16,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Progreso de envíos:",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                "$sentProv/$totalProv",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade200,
                            color: Colors.green,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text("Todos"),
                        selected: filtroSeleccionado == "TODOS",
                        onSelected: (_) =>
                            setState(() => filtroSeleccionado = "TODOS"),
                      ),
                      ChoiceChip(
                        label: const Text("Venta"),
                        selected: filtroSeleccionado == "VENTA",
                        onSelected: (_) =>
                            setState(() => filtroSeleccionado = "VENTA"),
                      ),
                      ChoiceChip(
                        label: const Text("Gasto"),
                        selected: filtroSeleccionado == "GASTO",
                        onSelected: (_) =>
                            setState(() => filtroSeleccionado = "GASTO"),
                      ),
                    ],
                  ),
                  const Divider(),

                  Expanded(
                    child: _buildListaUnificada(
                      proveedoresDisponibles,
                      totalProv,
                    ),
                  ),

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cerrar",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildListaUnificada(
    List<String> proveedoresDisponibles,
    int totalProveedores,
  ) {
    if (proveedoresDisponibles.isEmpty) {
      return const Center(
        child: Text("No hay productos asignados a proveedores en este pedido."),
      );
    }

    return ListView.builder(
      itemCount: proveedoresDisponibles.length,
      itemBuilder: (context, index) {
        final prov = proveedoresDisponibles[index];
        final items = _obtenerItemsParaTexto(prov);

        if (items.isEmpty) return const SizedBox.shrink();

        final textoPlanoFinal = _construirTextoComoPDF(prov, items);
        final bool enviado = proveedoresEnviados.contains(prov);

        return Card(
          color: enviado ? Colors.green.shade50 : Colors.grey.shade50,
          margin: const EdgeInsets.only(bottom: 24),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: enviado
                ? BorderSide(color: Colors.green.shade300, width: 1.5)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        prov,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: enviado
                              ? Colors.green.shade800
                              : Colors.blueGrey,
                        ),
                      ),
                    ),
                    if (enviado)
                      const Row(
                        children: [
                          Text(
                            "Enviado",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: enviado
                          ? Colors.grey.shade300
                          : Colors.blue.shade700,
                      foregroundColor: enviado ? Colors.black87 : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    icon: Icon(enviado ? Icons.replay : Icons.share),
                    label: Text(
                      enviado
                          ? "Reenviar PDF + Texto"
                          : "Compartir PDF y Texto",
                    ),
                    onPressed: () => _compartirUnificado(
                      prov,
                      items,
                      textoPlanoFinal,
                      totalProveedores,
                    ),
                  ),
                ),
                const Divider(height: 32, thickness: 1.5),

                const Text(
                  "Análisis de Costos de los Productos:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),

                ...items.map((item) {
                  final codigo = item["codigo_producto"]?.toString() ?? "";
                  final costoData = costosCache[codigo];

                  String textoCosto = "Buscando...";
                  String provMasBarato = "";

                  if (costosCache.containsKey(codigo)) {
                    if (costoData == null) {
                      textoCosto = "Sin historial en 3 meses";
                    } else {
                      final tieneIva = costoData["tiene_iva"] == true;
                      final etiquetaIva = tieneIva ? "(Con IVA)" : "(Sin IVA)";
                      final costoFinal =
                          double.tryParse(
                            costoData["costo_final"]?.toString() ?? "0",
                          ) ??
                          0.0;

                      textoCosto =
                          "\$${costoFinal.toStringAsFixed(3)} $etiquetaIva";
                      provMasBarato = costoData["proveedor"] ?? "Desconocido";
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item["nombre_producto"]?.toString() ?? "",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Cant a pedir: ${item["cantidad_pedida"]} ${item["unidad"] ?? 'U'}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (costoData != null) ...[
                                Text(
                                  "Mejor costo: $textoCosto",
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  "Prov. barato: $provMasBarato",
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  textoCosto,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              tooltip: "Cambiar Proveedor Destino",
                              icon: const Icon(
                                Icons.swap_horiz,
                                color: Colors.blue,
                              ),
                              onPressed: () => _cambiarProveedor(item),
                            ),
                            IconButton(
                              tooltip: "Historial de Costos",
                              icon: const Icon(
                                Icons.history,
                                color: Colors.blue,
                              ),
                              onPressed: () => _verHistorial(
                                codigo,
                                item["nombre_producto"]?.toString() ?? "",
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),

                const Divider(height: 32, thickness: 1.5),

                const Text(
                  "Vista previa del texto para WhatsApp:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    textoPlanoFinal,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: textoPlanoFinal));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Texto copiado al portapapeles"),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text("Copiar Texto"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
