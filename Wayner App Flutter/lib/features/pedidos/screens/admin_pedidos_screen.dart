import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pedidos_service.dart';
import 'admin_pedido_detalle_screen.dart';
import '../widgets/generar_pedido_proveedor_dialog.dart';

class AdminPedidosScreen extends StatefulWidget {
  const AdminPedidosScreen({super.key});

  @override
  State<AdminPedidosScreen> createState() => _AdminPedidosScreenState();
}

class _AdminPedidosScreenState extends State<AdminPedidosScreen> {
  final PedidosService service = PedidosService();

  bool isLoading = true;
  String? errorMessage;

  // Lista original con todos los datos
  List<dynamic> pedidos = [];
  // Lista que se mostrará en pantalla según los filtros
  List<dynamic> pedidosFiltrados = [];

  // Mapa para almacenar el progreso cargado desde la caché
  Map<int, Map<String, int>> progresos = {};

  // Controladores para los filtros
  final TextEditingController searchController = TextEditingController();
  DateTime? fechaFiltro;

  @override
  void initState() {
    super.initState();
    cargarPedidos();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> cargarPedidos() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await service.listarPedidosAdmin();

      // Cargamos los progresos desde SharedPreferences para toda la lista
      final prefs = await SharedPreferences.getInstance();
      Map<int, Map<String, int>> nuevosProgresos = {};

      for (var p in data) {
        int id = int.tryParse(p["id"].toString()) ?? 0;
        int total = prefs.getInt('pedido_${id}_total') ?? 0;
        List<String> sent = prefs.getStringList('pedido_${id}_sent') ?? [];
        nuevosProgresos[id] = {'total': total, 'sent': sent.length};
      }

      setState(() {
        pedidos = data;
        pedidosFiltrados = data; // Al inicio, mostramos todos
        progresos = nuevosProgresos;
      });

      // Re-aplicar el filtro por si el usuario recarga mientras busca
      filtrarPedidos();
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

  // Función maestra que aplica tanto la búsqueda de texto como el filtro de fecha
  void filtrarPedidos() {
    final query = searchController.text.toLowerCase();

    setState(() {
      pedidosFiltrados = pedidos.where((pedido) {
        // 1. Extraer todos los campos para la búsqueda por texto
        final id = pedido['id']?.toString().toLowerCase() ?? '';
        final usuario = pedido['usuario']?.toString().toLowerCase() ?? '';
        final estado = pedido['estado']?.toString().toLowerCase() ?? '';
        final items = pedido['total_items']?.toString().toLowerCase() ?? '';
        final fechaStrFormateada = formatearFecha(
          pedido['fecha_creacion'],
        ).toLowerCase();
        final proveedores =
            pedido['proveedores']?.toString().toLowerCase() ?? 'varios';

        // 2. Verificar si el texto coincide con ALGUNO de los campos
        final coincideTexto =
            id.contains(query) ||
            usuario.contains(query) ||
            estado.contains(query) ||
            items.contains(query) ||
            fechaStrFormateada.contains(query) ||
            proveedores.contains(query);

        // 3. Verificar el filtro de fecha (si hay uno seleccionado)
        bool coincideFecha = true;
        if (fechaFiltro != null) {
          final fechaOriginal = pedido['fecha_creacion']?.toString() ?? '';
          if (fechaOriginal.isNotEmpty) {
            try {
              final fechaPedido = DateTime.parse(fechaOriginal);
              coincideFecha =
                  fechaPedido.year == fechaFiltro!.year &&
                  fechaPedido.month == fechaFiltro!.month &&
                  fechaPedido.day == fechaFiltro!.day;
            } catch (e) {
              coincideFecha = false;
            }
          } else {
            coincideFecha = false;
          }
        }

        // El pedido se muestra solo si cumple con ambos filtros
        return coincideTexto && coincideFecha;
      }).toList();
    });
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
      body: Column(
        children: [
          // 🔥 SECCIÓN DE FILTROS AÑADIDA
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.white,
            child: Column(
              children: [
                // Buscador de texto (Todos los campos)
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar por N°, usuario, proveedor...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              filtrarPedidos();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) => filtrarPedidos(),
                ),
                const SizedBox(height: 10),
                // Selector de Fecha
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30.0),
                          ),
                        ),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          fechaFiltro == null
                              ? "Filtrar por fecha"
                              : "Fecha: ${fechaFiltro!.day.toString().padLeft(2, '0')}/${fechaFiltro!.month.toString().padLeft(2, '0')}/${fechaFiltro!.year}",
                        ),
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: fechaFiltro ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              fechaFiltro = picked;
                            });
                            filtrarPedidos();
                          }
                        },
                      ),
                    ),
                    if (fechaFiltro != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: "Borrar fecha",
                        onPressed: () {
                          setState(() {
                            fechaFiltro = null;
                          });
                          filtrarPedidos();
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // 🔥 LISTA DE PEDIDOS (Usando pedidosFiltrados)
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                ? Center(child: Text(errorMessage!))
                : pedidosFiltrados.isEmpty
                ? const Center(child: Text("No se encontraron pedidos"))
                : ListView.builder(
                    itemCount: pedidosFiltrados.length,
                    itemBuilder: (context, index) {
                      final pedido = pedidosFiltrados[index];
                      final estado =
                          pedido["estado"]?.toString() ?? "SIN ESTADO";
                      final pedidoId =
                          int.tryParse(pedido["id"].toString()) ?? 0;

                      // Lógica de lectura de progreso
                      final prog = progresos[pedidoId];
                      final totalProv = prog != null ? prog['total'] ?? 0 : 0;
                      final sentProv = prog != null ? prog['sent'] ?? 0 : 0;
                      final double progressValue = totalProv == 0
                          ? 0.0
                          : sentProv / totalProv;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => GenerarPedidoProveedorDialog(
                                pedidoId: pedidoId,
                              ),
                            ).then((_) {
                              cargarPedidos();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: colorEstado(estado),
                                  child: const Icon(
                                    Icons.assignment,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Orden de pedido #$pedidoId",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Usuario: ${pedido["usuario"] ?? ""}",
                                      ),
                                      Text("Estado: $estado"),
                                      Text(
                                        "Items: ${pedido["total_items"] ?? 0}",
                                      ),
                                      Text(
                                        "Fecha: ${formatearFecha(pedido["fecha_creacion"])}",
                                      ),
                                      Text(
                                        "Proveedores: ${pedido["proveedores"] ?? 'Varios'}",
                                        style: const TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.blueGrey,
                                          fontSize: 13,
                                        ),
                                      ),

                                      // BARRA DE PROGRESO
                                      if (estado == "BORRADOR" &&
                                          totalProv > 0) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              "Progreso envíos:",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              "$sentProv/$totalProv provs.",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value: progressValue,
                                          backgroundColor: Colors.grey.shade300,
                                          color: Colors.green,
                                          minHeight: 6,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blueGrey,
                                      ),
                                      tooltip: "Editar Pedido",
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AdminPedidoDetalleScreen(
                                                  pedidoId: pedidoId,
                                                ),
                                          ),
                                        ).then((_) => cargarPedidos());
                                      },
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
