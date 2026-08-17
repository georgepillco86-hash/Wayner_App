import 'package:flutter/material.dart';

import '../services/conversiones_service.dart';
import '../widgets/realizar_conversion_dialog.dart';
import '../../../core/storage/session_storage.dart';
import 'conversiones_busqueda_screen.dart'; // 🔥 IMPORTAMOS LA PANTALLA DEL CARRITO

class ConversionesScreen extends StatefulWidget {
  const ConversionesScreen({super.key});

  @override
  State<ConversionesScreen> createState() => _ConversionesScreenState();
}

class _ConversionesScreenState extends State<ConversionesScreen> {
  final ConversionesService _service = ConversionesService();

  int _vistaActual = 0;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _fechaFiltro;

  List<dynamic> requerimientosOriginales = [];
  List<dynamic> requerimientosFiltrados = [];
  bool isLoading = true;
  String _nombreUsuario = "Desconocido";

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
    _cargarRequerimientos();
  }

  Future<void> _cargarUsuario() async {
    final user = await SessionStorage.getUser();
    if (mounted && user != null) {
      setState(() => _nombreUsuario = user.nombreUsuario);
    }
  }

  Future<void> _cargarRequerimientos() async {
    setState(() => isLoading = true);
    try {
      final data = await _service.listarRequerimientos();
      setState(() {
        requerimientosOriginales = data;
        _filtrar();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error al cargar: $e")));
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _filtrar() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      requerimientosFiltrados = requerimientosOriginales.where((req) {
        final orden = req['orden_trabajo']?.toString().toLowerCase() ?? '';
        final desc = req['descripcion_tarea']?.toString().toLowerCase() ?? '';
        final estado = req['estado']?.toString().toLowerCase() ?? '';
        final fechaStr = req['fecha_creacion']?.toString() ?? '';

        final coincideTexto =
            query.isEmpty ||
            orden.contains(query) ||
            desc.contains(query) ||
            estado.contains(query);

        bool coincideFecha = true;
        if (_fechaFiltro != null && fechaStr.length >= 10) {
          final fechaReqStr = fechaStr.substring(0, 10);
          final filtroStr =
              "${_fechaFiltro!.year}-${_fechaFiltro!.month.toString().padLeft(2, '0')}-${_fechaFiltro!.day.toString().padLeft(2, '0')}";
          coincideFecha = fechaReqStr == filtroStr;
        }

        return coincideTexto && coincideFecha;
      }).toList();
    });
  }

  // 🔥 VUELVE A ABRIR LA PANTALLA COMPLETA DEL CARRITO 🔥
  void _abrirBusqueda() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConversionesBusquedaScreen()),
    );
    if (resultado == true) {
      _cargarRequerimientos();
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<dynamic>> agrupados = {};
    for (var req in requerimientosFiltrados) {
      final orden = req['orden_trabajo']?.toString() ?? 'Req #${req['id']}';
      if (!agrupados.containsKey(orden)) agrupados[orden] = [];
      agrupados[orden]!.add(req);
    }
    final llavesOrdenes = agrupados.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Conversiones"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarRequerimientos,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar requerimiento u orden...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filtrar();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (_) => _filtrar(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _fechaFiltro == null
                              ? "Filtrar por fecha"
                              : "${_fechaFiltro!.day}/${_fechaFiltro!.month}/${_fechaFiltro!.year}",
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fechaFiltro ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _fechaFiltro = picked);
                            _filtrar();
                          }
                        },
                      ),
                    ),
                    if (_fechaFiltro != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          setState(() => _fechaFiltro = null);
                          _filtrar();
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text("Tareas pendientes"),
                        selected: _vistaActual == 0,
                        onSelected: (val) => setState(() => _vistaActual = 0),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("Conversiones"),
                        selected: _vistaActual == 1,
                        onSelected: (val) => setState(() => _vistaActual = 1),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("Etiquetado"),
                        selected: _vistaActual == 2,
                        onSelected: (val) => setState(() => _vistaActual = 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : _vistaActual == 2
                ? const Center(
                    child: Text(
                      "Pantalla de Etiquetado (Próximamente)",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : llavesOrdenes.isEmpty
                ? const Center(child: Text("No se encontraron registros"))
                : ListView.builder(
                    itemCount: llavesOrdenes.length,
                    itemBuilder: (context, index) {
                      final orden = llavesOrdenes[index];
                      final itemsOrden = agrupados[orden]!;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Orden $orden",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.indigo.shade800,
                                    ),
                                  ),
                                  Text(
                                    "${itemsOrden.length} item(s)",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24, thickness: 1.2),

                              ...itemsOrden.map((req) {
                                final bool esPendiente =
                                    req['estado'] == 'PENDIENTE';
                                final creador =
                                    req['usuario_creacion'] ?? 'Sistema';
                                final actualizador =
                                    req['usuario_actualizacion'] ?? 'Sistema';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              req['descripcion_tarea'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              req['estado'] ?? 'PENDIENTE',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            backgroundColor: esPendiente
                                                ? Colors.orange
                                                : Colors.green,
                                            padding: EdgeInsets.zero,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Origen: ${req['codigo_origen']} (${req['cantidad']})",
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (req['codigo_destino'] != null)
                                              Text(
                                                "Destino: ${req['codigo_destino']}",
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),

                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.person_add,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              "Creado: ${req['fecha_creacion']?.toString().split(' ')[0]} por $creador",
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.manage_accounts,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    "Actualizado: ${req['fecha_actualizacion']?.toString().split(' ')[0]} por $actualizador",
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            "Avance: ${req['porcentaje_avance'] ?? 0}%",
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),

                                      if (_vistaActual == 1 && esPendiente) ...[
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                barrierDismissible: false,
                                                builder: (_) =>
                                                    RealizarConversionDialog(
                                                      requerimiento: req,
                                                    ),
                                              ).then(
                                                (_) => _cargarRequerimientos(),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.sync_alt,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              "Realizar conversión",
                                            ),
                                          ),
                                        ),
                                      ],
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
      floatingActionButton: _vistaActual == 0
          ? FloatingActionButton.extended(
              onPressed: _abrirBusqueda,
              icon: const Icon(Icons.add),
              label: const Text("Añadir Tarea"),
            )
          : null,
    );
  }
}
