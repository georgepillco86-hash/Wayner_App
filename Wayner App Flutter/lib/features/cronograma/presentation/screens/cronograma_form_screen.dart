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

  // ---> MODIFICADO: Variables para manejar ambas fechas <---
  DateTime? _fechaSeleccionada; // Fecha de Visita
  TimeOfDay? _horaSeleccionada; // Hora de Visita
  DateTime? _fechaEntregaSeleccionada; // Fecha de Entrega de mercadería

  int _frecuenciaSeleccionada = 1;

  List<Usuario> _usuariosDb = [];
  List<String> _proveedoresDb = [];
  final List<String> _usuariosVinculados = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

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

  // 1. Selector de Fecha de VISITA
  Future<void> _seleccionarFechaHora() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada ?? DateTime.now(),
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

      // Si ya había una fecha de entrega y resulta que ahora es ANTES de la nueva visita, la borramos
      if (_fechaEntregaSeleccionada != null &&
          _fechaEntregaSeleccionada!.isBefore(_fechaSeleccionada!)) {
        _fechaEntregaSeleccionada = null;
      }
    });
  }

  // 2. ---> NUEVO: Selector de Fecha de ENTREGA <---
  Future<void> _seleccionarFechaEntrega() async {
    if (_fechaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero selecciona la fecha de visita del proveedor'),
        ),
      );
      return;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaEntregaSeleccionada ?? _fechaSeleccionada!,
      // Bloqueamos el calendario para que no puedan elegir un día antes de la visita
      firstDate: _fechaSeleccionada!,
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _fechaEntregaSeleccionada = picked;
      });
    }
  }

  Future<void> _guardar() async {
    // Validamos que todos los campos estén llenos, incluyendo la entrega
    if (_proveedorController.text.isEmpty ||
        _fechaSeleccionada == null ||
        _horaSeleccionada == null ||
        _fechaEntregaSeleccionada == null || // <-- Validación añadida
        _usuariosVinculados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor complete todos los campos (Visita y Entrega) y asigne al menos un usuario.',
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

    // Formateamos la fecha de entrega con una hora por defecto (ej: 12:00 PM)
    final fechaEntregaCompleta = DateTime(
      _fechaEntregaSeleccionada!.year,
      _fechaEntregaSeleccionada!.month,
      _fechaEntregaSeleccionada!.day,
      12,
      0,
    );

    try {
      await _cronogramaService.crearProgramacion(
        proveedor: _proveedorController.text,
        frecuencia: _frecuenciaSeleccionada,
        fechaInicio: fechaCompleta,
        // ---> NUEVO: Pasamos la fecha de entrega al servicio <---
        fechaEntrega: fechaEntregaCompleta,
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
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return DropdownMenu<String>(
                        width: constraints.maxWidth,
                        controller: _proveedorController,
                        enableFilter: true,
                        requestFocusOnTap: true,
                        label: const Text('Nombre del Proveedor'),
                        leadingIcon: const Icon(Icons.business),
                        inputDecorationTheme: const InputDecorationTheme(
                          border: OutlineInputBorder(),
                        ),
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

                  // ---> UI ACTUALIZADA: Dos botones para las fechas <---
                  // 1. Botón de Visita
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
                          ? '1. Seleccionar Día de Visita'
                          : 'Visita: ${DateFormat('dd/MM/yyyy').format(_fechaSeleccionada!)} a las ${_horaSeleccionada!.format(context)}',
                    ),
                    onTap: _seleccionarFechaHora,
                  ),
                  const SizedBox(height: 12),

                  // 2. Botón de Entrega
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    leading: const Icon(
                      Icons.local_shipping,
                      color: Colors.green,
                    ),
                    title: Text(
                      _fechaEntregaSeleccionada == null
                          ? '2. Seleccionar Día de Entrega'
                          : 'Llegada: ${DateFormat('dd/MM/yyyy').format(_fechaEntregaSeleccionada!)}',
                    ),
                    onTap: _seleccionarFechaEntrega,
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
