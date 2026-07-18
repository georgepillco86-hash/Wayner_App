import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<dynamic> proveedoresTextos = [];
  String filtroSeleccionado = 'Todos';

  @override
  void initState() {
    super.initState();
    cargarTextos();
  }

  Future<void> cargarTextos() async {
    try {
      final res = await service.obtenerTextosProveedor(widget.pedidoId);
      if (mounted) {
        setState(() {
          proveedoresTextos = res['textos'] ?? [];
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _mostrarHistorialCostos(
    BuildContext context,
    String codigo,
    String nombre,
    String proveedor,
  ) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _HistorialCostosSheet(
        codigo: codigo,
        nombre: nombre,
        proveedor: proveedor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.85,
        color: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  const Text(
                    "Generar pedido por proveedor",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFilterChip('Todos', Icons.check),
                      const SizedBox(width: 8),
                      _buildFilterChip('Venta', Icons.shopping_cart),
                      const SizedBox(width: 8),
                      _buildFilterChip('Gasto', Icons.home),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: proveedoresTextos.length,
                itemBuilder: (context, index) {
                  final prov = proveedoresTextos[index];
                  final itemsDetalle =
                      prov['items_detalle'] as List<dynamic>? ?? [];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prov['proveedor'] ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Items: ${prov['total_items']} | Filtro: $filtroSeleccionado",
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                          const Divider(),

                          // TEXTO PARA WHATSAPP
                          Container(
                            padding: const EdgeInsets.all(12),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: SelectableText(
                              prov['texto'] ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: prov['texto']),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Texto copiado'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copiar'),
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Text(
                            "Análisis de Costos (Últimos 3 meses)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // LISTA INTERACTIVA DE PRODUCTOS Y COSTOS
                          ...itemsDetalle.map((item) {
                            final double? costo = item['costo_minimo'];
                            final bool tieneIva = item['tiene_iva'] ?? false;
                            final String costoStr = costo != null
                                ? "\$${costo.toStringAsFixed(3)}"
                                : "No reg.";
                            final String ivaStr = tieneIva ? "+ IVA" : "0% IVA";

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.white,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['nombre_producto'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          "Código: ${item['codigo_producto']} | Cant: ${item['cantidad_pedida']}",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.blueGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        costoStr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: costo != null
                                              ? Colors.green.shade700
                                              : Colors.red,
                                        ),
                                      ),
                                      Text(
                                        ivaStr,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.history,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'Ver historial de costos',
                                    onPressed: () => _mostrarHistorialCostos(
                                      context,
                                      item['codigo_producto'],
                                      item['nombre_producto'],
                                      prov['proveedor'],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
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
  }

  Widget _buildFilterChip(String label, IconData icon) {
    final isSelected = filtroSeleccionado == label;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.blue.shade700 : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blue.shade900 : Colors.black87,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white,
      selectedColor: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? Colors.blue.shade200 : Colors.grey.shade300,
        ),
      ),
      onSelected: (val) {
        setState(() => filtroSeleccionado = label);
        // Aquí puedes agregar la lógica para re-filtrar la variable `proveedoresTextos`
      },
    );
  }
}

// =========================================================================
// BOTTOM SHEET: HISTORIAL DE COSTOS
// =========================================================================
class _HistorialCostosSheet extends StatefulWidget {
  final String codigo;
  final String nombre;
  final String proveedor;

  const _HistorialCostosSheet({
    required this.codigo,
    required this.nombre,
    required this.proveedor,
  });

  @override
  State<_HistorialCostosSheet> createState() => _HistorialCostosSheetState();
}

class _HistorialCostosSheetState extends State<_HistorialCostosSheet> {
  final PedidosService service = PedidosService();
  bool isLoading = true;
  List<dynamic> historial = [];
  int mesesBusqueda = 5;

  @override
  void initState() {
    super.initState();
    cargarHistorial();
  }

  Future<void> cargarHistorial() async {
    setState(() => isLoading = true);
    try {
      final res = await service.obtenerHistorialCostos(
        widget.codigo,
        widget.proveedor,
        mesesBusqueda,
      );
      if (mounted) {
        setState(() {
          historial = res;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String formatearFecha(String? fechaIso) {
    if (fechaIso == null) return "";
    return fechaIso.split("T").first;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Historial: ${widget.nombre}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              widget.proveedor,
              style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                const Text("Periodo: "),
                DropdownButton<int>(
                  value: mesesBusqueda,
                  items: const [
                    DropdownMenuItem(value: 3, child: Text("Últimos 3 meses")),
                    DropdownMenuItem(value: 5, child: Text("Últimos 5 meses")),
                    DropdownMenuItem(value: 12, child: Text("Último año")),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => mesesBusqueda = val);
                      cargarHistorial();
                    }
                  },
                ),
              ],
            ),
            const Divider(),

            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : historial.isEmpty
                  ? const Center(
                      child: Text(
                        "No hay registros de compras en este periodo.",
                      ),
                    )
                  : ListView.builder(
                      itemCount: historial.length,
                      itemBuilder: (context, index) {
                        final h = historial[index];
                        final bool tieneIva = h['tiene_iva'] ?? false;
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(
                              Icons.attach_money,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            "\$${h['costo'].toStringAsFixed(3)} ${tieneIva ? '(+ IVA)' : ''}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text("Doc: ${h['documento'] ?? 'N/A'}"),
                          trailing: Text(
                            formatearFecha(h['fecha']),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
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
  }
}
