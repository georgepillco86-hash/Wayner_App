import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/merma_model.dart';
import '../../data/services/merma_service.dart';
import '../widgets/merma_form_dialog.dart';
import 'merma_chat_screen.dart';

class MermaScreen extends StatefulWidget {
  final String usuarioActual;
  final String rolUsuario;
  final bool esModoReporte;

  const MermaScreen({
    super.key,
    required this.usuarioActual,
    required this.rolUsuario,
    this.esModoReporte = false,
  });

  @override
  State<MermaScreen> createState() => _MermaScreenState();
}

class _MermaScreenState extends State<MermaScreen> {
  final MermaService _mermaService = MermaService();
  final TextEditingController _searchController = TextEditingController();

  List<Merma> _mermas = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarMermas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarMermas() async {
    setState(() => _isLoading = true);
    try {
      final mermas = await _mermaService.listarMermas();
      setState(() => _mermas = mermas);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conectar con el servidor: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- NUEVA LÓGICA DE FILTRADO ---
  List<Merma> get _filteredMermas {
    if (_searchQuery.isEmpty) return _mermas;

    final query = _searchQuery.toLowerCase();

    return _mermas.where((merma) {
      return merma.codigo.toLowerCase().contains(query) ||
          merma.nombreProducto.toLowerCase().contains(query) ||
          merma.novedad.toLowerCase().contains(query) ||
          merma.estado.toLowerCase().contains(query) ||
          merma.usuario.toLowerCase().contains(query) ||
          (merma.proveedor?.toLowerCase().contains(query) ?? false) ||
          (merma.comentario?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  bool _puedeEditar(Merma merma) {
    if (widget.rolUsuario == 'ADMIN') return true;
    if (merma.usuario != widget.usuarioActual) return false;
    if (merma.fechaRegistro == null) return true;
    final diferencia = DateTime.now().difference(merma.fechaRegistro!);
    return diferencia.inDays < 3;
  }

  void _abrirFormulario({Merma? merma}) {
    showDialog(
      context: context,
      builder: (context) =>
          MermaFormDialog(merma: merma, onSave: () => _cargarMermas()),
    );
  }

  void _mostrarOpcionesSeguimiento(Merma merma) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MermaChatScreen(merma: merma, onUpdate: _cargarMermas),
      ),
    );
  }

  Color _getColorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'EN PROCESO':
      case 'NOTIFICADO':
        return Colors.orange;
      case 'RESUELTO':
        return Colors.green;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final esPersonalAutorizado =
        widget.rolUsuario == 'ADMIN' || widget.rolUsuario == 'BODEGUERO';
    final listaFiltrada =
        _filteredMermas; // Guardamos en variable local para la UI

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.esModoReporte ? 'Reporte de Mermas' : 'Ingreso de Mermas',
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarMermas),
        ],
      ),
      body: Column(
        children: [
          // --- BARRA DE BÚSQUEDA ---
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar merma...',
                hintText: 'Código, producto, estado, usuario...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          FocusScope.of(context).unfocus(); // Cierra el teclado
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // --- LISTA DE RESULTADOS ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _cargarMermas,
                    child: listaFiltrada.isEmpty
                        ? const Center(
                            child: Text(
                              'No se encontraron mermas para mostrar',
                            ),
                          )
                        : ListView.builder(
                            itemCount: listaFiltrada.length,
                            itemBuilder: (context, index) {
                              final merma = listaFiltrada[index];
                              final puedeEditar = _puedeEditar(merma);

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  onTap: esPersonalAutorizado
                                      ? () => _mostrarOpcionesSeguimiento(merma)
                                      : null,
                                  title: Text(
                                    '${merma.nombreProducto} (x${merma.cantidad})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Código: ${merma.codigo}\n'
                                    'Condición: ${merma.novedad}\n'
                                    'Proveedor: ${merma.proveedor ?? "Sin proveedor"}\n'
                                    'Registrado por: ${merma.usuario} (${merma.fechaRegistro != null ? DateFormat("dd/MM/yyyy HH:mm").format(merma.fechaRegistro!) : "-"})',
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Chip(
                                        label: Text(
                                          merma.estado,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                          ),
                                        ),
                                        backgroundColor: _getColorEstado(
                                          merma.estado,
                                        ),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Expanded(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (puedeEditar &&
                                                merma.estado.toUpperCase() !=
                                                    'RESUELTO')
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.edit,
                                                  size: 20,
                                                  color: Colors.amber,
                                                ),
                                                onPressed: () =>
                                                    _abrirFormulario(
                                                      merma: merma,
                                                    ),
                                              ),
                                            if (widget.rolUsuario == 'ADMIN' ||
                                                merma.usuario ==
                                                    widget.usuarioActual)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  size: 20,
                                                  color: Colors.red,
                                                ),
                                                onPressed: () async {
                                                  final ok = await _mermaService
                                                      .eliminarMerma(merma.id!);
                                                  if (ok) _cargarMermas();
                                                },
                                              ),
                                            if (esPersonalAutorizado)
                                              const Icon(
                                                Icons.chevron_right,
                                                color: Colors.grey,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: widget.esModoReporte
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              label: const Text('Agregar Merma'),
              icon: const Icon(Icons.add),
            ),
    );
  }
}
