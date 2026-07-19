import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // Controladores para los números de WhatsApp por proveedor
  final Map<String, TextEditingController> _celularControllers = {};

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

  // 🔥 Lógica de Generación de PDF 🔥
  Future<void> _generarYCompartirPDF(
    String proveedor,
    List<dynamic> items,
  ) async {
    final pdf = pw.Document();

    double subtotal15 = 0.0;
    double subtotal0 = 0.0;
    const double totalDescuentos =
        0.0; // Espacio para futura lógica de descuentos

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
            // Encabezado
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
                    // Sumamos 7 días como fecha tentativa por defecto
                    pw.Text(
                      "Fecha tentativa entrega: ${_formatearFechaCorta(DateTime.now().add(const Duration(days: 7)))}",
                    ),
                    pw.Text("Vigencia del pedido: 1 semana"),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Tabla de productos
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

            // Totales (Footer)
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

    // Guardar y compartir
    // Guardar y compartir (CÓDIGO ANTERIOR QUE FALLA EN WEB)
    // Guardar y compartir (CÓDIGO NUEVO - COMPATIBLE CON WEB Y MÓVIL)
    final bytes = await pdf.save();

    final xFile = XFile.fromData(
      bytes,
      name: 'Orden_Pedido_${widget.pedidoId}_$proveedor.pdf',
      mimeType: 'application/pdf',
    );

    await Share.shareXFiles([
      xFile,
    ], text: 'Adjunto la Orden de Pedido #${widget.pedidoId} para $proveedor');
  }

  void _enviarWhatsAppTexto(String numero, String texto) async {
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingresa un número de celular")),
      );
      return;
    }
    final url = Uri.parse(
      "https://wa.me/593${numero.replaceFirst(RegExp(r'^0'), '')}?text=${Uri.encodeComponent(texto)}",
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo abrir WhatsApp")),
      );
    }
  }

  // --- Mismos métodos _cambiarProveedor y _verHistorial que antes ---
  Future<void> _cambiarProveedor(dynamic item) async {
    /* Mismo código anterior */
  }
  void _verHistorial(String codigo, String nombreProducto) async {
    /* Mismo código anterior */
  }

  List<dynamic> _obtenerItemsParaTexto(String proveedor) {
    final items =
        textosGenerados?["textos"]?.firstWhere(
              (t) => t["proveedor"] == proveedor,
              orElse: () => {},
            )["items_detalle"]
            as List<dynamic>? ??
        [];
    return items.where((item) {
      final tipo = item["tipo_destino"]?.toString().toUpperCase() ?? "VENTA";
      return filtroSeleccionado == "TODOS" || tipo == filtroSeleccionado;
    }).toList();
  }

  String _construirTexto(String proveedor) {
    final items = _obtenerItemsParaTexto(proveedor);
    final ventas = items.where(
      (i) =>
          (i["tipo_destino"]?.toString().toUpperCase() ?? "VENTA") == "VENTA",
    );
    final gastos = items.where(
      (i) => (i["tipo_destino"]?.toString().toUpperCase() ?? "") == "GASTO",
    );

    String texto =
        "Hola, buen día.\n\nPor favor ayudarme con la Orden de Pedido #${widget.pedidoId}:\n\n";

    if (ventas.isNotEmpty) {
      texto += "🛒 PRODUCTOS PARA VENTA:\n\n";
      for (var i in ventas) {
        texto +=
            "- ${i["nombre_producto"]}\n  Código: ${i["codigo_producto"]}\n  Cantidad: ${i["cantidad_pedida"]} ${i["unidad"] ?? 'UNIDADES'}\n\n";
      }
    }

    if (gastos.isNotEmpty) {
      texto += "🔥 PRODUCTOS PARA GASTO:\n\n";
      for (var i in gastos) {
        texto +=
            "- ${i["nombre_producto"]}\n  Código: ${i["codigo_producto"]}\n  Cantidad: ${i["cantidad_pedida"]} ${i["unidad"] ?? 'UNIDADES'}\n\n";
      }
    }
    texto += "Gracias.";
    return texto;
  }

  @override
  Widget build(BuildContext context) {
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
                    "Generar pedido y Análisis Global",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            labelColor: Colors.blue,
                            unselectedLabelColor: Colors.grey,
                            indicatorColor: Colors.blue,
                            tabs: [
                              Tab(text: "Textos Proveedores (PDF)"),
                              Tab(text: "Análisis Global"),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildPestanaTextos(),
                                _buildPestanaAnalisisGlobal(),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildPestanaTextos() {
    final textos = textosGenerados?["textos"] as List<dynamic>? ?? [];
    final proveedoresDisponibles = textos
        .map((t) => t["proveedor"]?.toString() ?? "SIN PROVEEDOR")
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text("Todos"),
              selected: filtroSeleccionado == "TODOS",
              onSelected: (_) => setState(() => filtroSeleccionado = "TODOS"),
            ),
            ChoiceChip(
              label: const Text("Venta"),
              selected: filtroSeleccionado == "VENTA",
              onSelected: (_) => setState(() => filtroSeleccionado = "VENTA"),
            ),
            ChoiceChip(
              label: const Text("Gasto"),
              selected: filtroSeleccionado == "GASTO",
              onSelected: (_) => setState(() => filtroSeleccionado = "GASTO"),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: proveedoresDisponibles.length,
            itemBuilder: (context, index) {
              final prov = proveedoresDisponibles[index];
              final items = _obtenerItemsParaTexto(prov);
              if (items.isEmpty) return const SizedBox.shrink();

              final textoFinal = _construirTexto(prov);
              _celularControllers.putIfAbsent(
                prov,
                () => TextEditingController(),
              );

              return Card(
                color: Colors.grey.shade50,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prov,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Items a pedir: ${items.length}",
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),

                      // Celdas de Acción PDF y WhatsApp
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _celularControllers[prov],
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: "WhatsApp Prov.",
                                prefixIcon: Icon(Icons.phone_android, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.picture_as_pdf,
                              color: Colors.red,
                            ),
                            tooltip: "Generar y Compartir PDF",
                            onPressed: () => _generarYCompartirPDF(prov, items),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send, color: Colors.green),
                            tooltip: "Enviar Resumen por WhatsApp",
                            onPressed: () => _enviarWhatsAppTexto(
                              _celularControllers[prov]!.text,
                              textoFinal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Caja de texto copiable
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: SelectableText(
                          textoFinal,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: textoFinal));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Copiado al portapapeles"),
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
          ),
        ),
      ],
    );
  }

  Widget _buildPestanaAnalisisGlobal() {
    final items = pedido?["items"] as List<dynamic>? ?? [];

    if (items.isEmpty)
      return const Center(child: Text("El pedido no tiene productos."));

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final codigo = item["codigo_producto"]?.toString() ?? "";
        final costoData = costosCache[codigo];

        String textoCosto = "Buscando...";
        String provMasBarato = "";

        if (costosCache.containsKey(codigo)) {
          if (costoData == null) {
            textoCosto = "Sin historial en 3 meses";
          } else {
            // Evaluamos si es Con IVA o Sin IVA en el UI
            final tieneIva = costoData["tiene_iva"] == true;
            final etiquetaIva = tieneIva ? "(Con IVA)" : "(Sin IVA)";
            final costoFinal =
                double.tryParse(costoData["costo_final"]?.toString() ?? "0") ??
                0.0;

            textoCosto = "\$${costoFinal.toStringAsFixed(3)} $etiquetaIva";
            provMasBarato = costoData["proveedor"] ?? "Desconocido";
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item["nombre_producto"]?.toString() ?? "",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Actual: ${item["proveedor"] ?? 'Sin Asignar'} | Cant: ${item["cantidad_pedida"]}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
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
                      icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                      onPressed: () => _cambiarProveedor(item),
                    ),
                    IconButton(
                      tooltip: "Historial de Costos",
                      icon: const Icon(Icons.history, color: Colors.blue),
                      onPressed: () => _verHistorial(
                        codigo,
                        item["nombre_producto"]?.toString() ?? "",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
