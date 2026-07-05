import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/services/cronograma_service.dart';
import '../../../usuarios/services/usuarios_service.dart';
import '../../../usuarios/models/usuario.dart';

class CronogramaFormScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const CronogramaFormScreen({super.key, required this.onSaved});

  @override
  State<CronogramaFormScreen> createState() => _CronogramaFormScreenState();
}

class _CronogramaFormScreenState extends State<CronogramaFormScreen> {
  final _cronogramaService = CronogramaService();
  final _usuariosService = UsuariosService();

  final _proveedorController = TextEditingController();
  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;
  int _frecuenciaSeleccionada = 1;

  List<Usuario> _usuariosDb = [];
  List<String> _proveedoresDb = []; // <-- NUEVO: Lista de proveedores
  final List<String> _usuariosVinculados = [];

  bool _isLoading = true; // Inicia en true para mostrar la carga al abrir

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  // --- NUEVO: Carga usuarios y proveedores al mismo tiempo ---
  Future<void> _cargarDatosIniciales() async {
    try {
      final usuarios = await _usuariosService.listarUsuarios();
      final proveedores = await _cronogramaService.obtenerProveedores();

      if (mounted) {
        setState(() {
          _usuariosDb = usuarios;
          _proveedoresDb = proveedores;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    }
  }

  Future<void> _seleccionarFechaHora() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (fecha == null) return;

    if (!mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (hora == null) return;

    setState(() {
      _fechaSeleccionada = fecha;
      _horaSeleccionada = hora;
    });
  }

  Future<void> _guardar() async {
    if (_proveedorController.text.isEmpty ||
        _fechaSeleccionada == null ||
        _horaSeleccionada == null ||
        _usuariosVinculados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor complete todos los campos y asigne al menos un usuario.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final fechaCompleta = DateTime(
      _fechaSeleccionada!.year,
      _fechaSeleccionada!.month,
      _fechaSeleccionada!.day,
      _horaSeleccionada!.hour,
      _horaSeleccionada!.minute,
    );

    try {
      await _cronogramaService.crearProgramacion(
        proveedor: _proveedorController.text,
        frecuencia: _frecuenciaSeleccionada,
        fechaInicio: fechaCompleta,
        usuariosVinculados: _usuariosVinculados,
      );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Programar Pedido')),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            ) // Muestra cargando mientras trae los datos de BD
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- NUEVO: Menú Autocompletable de Proveedores ---
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return DropdownMenu<String>(
                        width: constraints
                            .maxWidth, // Ocupa todo el ancho disponible
                        controller: _proveedorController,
                        enableFilter: true, // ¡La magia del buscador!
                        requestFocusOnTap: true,
                        label: const Text('Nombre del Proveedor'),
                        leadingIcon: const Icon(Icons.business),
                        inputDecorationTheme: const InputDecorationTheme(
                          border: OutlineInputBorder(),
                        ),
                        // Transforma la lista de strings en opciones del menú
                        dropdownMenuEntries: _proveedoresDb.map((prov) {
                          return DropdownMenuEntry<String>(
                            value: prov,
                            label: prov,
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Frecuencia
                  DropdownButtonFormField<int>(
                    value: _frecuenciaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia de Visitas',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 1,
                        child: Text('1 vez al mes (Única)'),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text('2 veces al mes (Quincenal)'),
                      ),
                      DropdownMenuItem(
                        value: 4,
                        child: Text('4 veces al mes (Semanal)'),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _frecuenciaSeleccionada = val!),
                  ),
                  const SizedBox(height: 16),

                  // Fecha y Hora
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    leading: const Icon(
                      Icons.calendar_today,
                      color: Colors.blue,
                    ),
                    title: Text(
                      _fechaSeleccionada == null
                          ? 'Seleccionar Fecha y Hora'
                          : 'Inicio: ${DateFormat('dd/MM/yyyy').format(_fechaSeleccionada!)} a las ${_horaSeleccionada!.format(context)}',
                    ),
                    onTap: _seleccionarFechaHora,
                  ),
                  const SizedBox(height: 24),

                  // Selección de Usuarios
                  const Text(
                    'Usuarios Asignados (Recibirán alertas):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _usuariosDb.length,
                      itemBuilder: (context, index) {
                        final u = _usuariosDb[index];
                        final isSelected = _usuariosVinculados.contains(
                          u.nombreUsuario,
                        );
                        return CheckboxListTile(
                          title: Text(u.nombreUsuario),
                          subtitle: Text(u.rol),
                          value: isSelected,
                          onChanged: (bool? checked) {
                            setState(() {
                              if (checked == true) {
                                _usuariosVinculados.add(u.nombreUsuario);
                              } else {
                                _usuariosVinculados.remove(u.nombreUsuario);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _guardar,
                    icon: const Icon(Icons.save),
                    label: const Text(
                      'Generar Cronograma',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
