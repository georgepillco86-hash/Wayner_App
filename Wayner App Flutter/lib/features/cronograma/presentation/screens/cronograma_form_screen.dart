import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/services/cronograma_service.dart';
import '../../../usuarios/services/usuarios_service.dart';
import '../../../usuarios/models/usuario.dart';

class CronogramaFormScreen extends StatefulWidget {
  final VoidCallback onSaved;
  final String?
  proveedorInicial; // <-- NUEVO: Para recibir el redireccionamiento directo

  const CronogramaFormScreen({
    super.key,
    required this.onSaved,
    this.proveedorInicial,
  });

  @override
  State<CronogramaFormScreen> createState() => _CronogramaFormScreenState();
}

class _CronogramaFormScreenState extends State<CronogramaFormScreen> {
  final _cronogramaService = CronogramaService();
  final _usuariosService = UsuariosService();

  final _proveedorController = TextEditingController();
  final _celularController =
      TextEditingController(); // 🔥 NUEVO: Controlador para el WhatsApp
  String? _proveedorSeleccionado;

  // ---> MODIFICADO: Frecuencia ahora es tipo String para empalmar con el Backend
  String _frecuenciaSeleccionada = 'Semanal';
  final List<String> _opcionesFrecuencia = ['Semanal', 'Quincenal', 'Mensual'];

  // ---> NUEVO: Duración de la secuencia (Repetir secuencia)
  int _repetirMeses = 1;
  final Map<int, String> _opcionesDuracion = {
    1: '1 Mes',
    6: 'Medio Año (6 meses)',
    12: '1 Año',
    60: 'Para Siempre (Proyectar 5 años)',
  };

  // ---> NUEVO: Lista dinámica de Pares Relacionales (Visita conectada a su Entrega)
  List<Map<String, DateTime>> _paresVisitaEntrega = [];

  List<Usuario> _usuariosDb = [];
  List<String> _proveedoresDb = [];
  final List<String> _usuariosVinculados = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _inicializarParVacio();
    _cargarDatosIniciales();
  }

  @override
  void dispose() {
    _proveedorController.dispose();
    _celularController.dispose(); // 🔥 NUEVO: Dispose del controlador
    super.dispose();
  }

  void _inicializarParVacio() {
    final ahora = DateTime.now();
    _paresVisitaEntrega.add({
      'visita': DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
        9,
        0,
      ), // 09:00 AM por defecto
      'entrega': DateTime(
        ahora.year,
        ahora.month,
        ahora.day + 2,
        12,
        0,
      ), // 2 días después
    });
  }

  void _agregarOtroPar() {
    setState(() {
      final ahora = DateTime.now();
      _paresVisitaEntrega.add({
        'visita': DateTime(ahora.year, ahora.month, ahora.day, 9, 0),
        'entrega': DateTime(ahora.year, ahora.month, ahora.day + 2, 12, 0),
      });
    });
  }

  void _eliminarPar(int index) {
    if (_paresVisitaEntrega.length > 1) {
      setState(() {
        _paresVisitaEntrega.removeAt(index);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debe configurar al menos una secuencia de visita y entrega.',
          ),
        ),
      );
    }
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final usuarios = await _usuariosService.listarUsuarios();
      final proveedores = await _cronogramaService.obtenerProveedores();

      if (mounted) {
        setState(() {
          _usuariosDb = usuarios;
          _proveedoresDb = proveedores;

          // Si nos enviaron un proveedor desde el inventario, lo pre-seleccionamos
          if (widget.proveedorInicial != null &&
              widget.proveedorInicial!.isNotEmpty) {
            _proveedorSeleccionado = widget.proveedorInicial;
            _proveedorController.text = widget.proveedorInicial!;
          }

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

  // Selector unificado de fecha y hora para la lista de pares
  Future<void> _seleccionarFechaHoraPar(int index, String tipoKey) async {
    final DateTime fechaBase = _paresVisitaEntrega[index][tipoKey]!;

    final fecha = await showDatePicker(
      context: context,
      initialDate: fechaBase,
      firstDate: DateTime.now().subtract(
        const Duration(days: 365),
      ), // Permitir margen histórico si se edita
      lastDate: DateTime(2035),
    );
    if (fecha == null) return;

    if (!mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(fechaBase),
    );
    if (hora == null) return;

    setState(() {
      _paresVisitaEntrega[index][tipoKey] = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );

      // Validación relacional automática: Si la entrega queda antes que la visita, la movemos hacia adelante
      if (tipoKey == 'visita') {
        final entregaActual = _paresVisitaEntrega[index]['entrega']!;
        if (entregaActual.isBefore(_paresVisitaEntrega[index]['visita']!)) {
          _paresVisitaEntrega[index]['entrega'] =
              _paresVisitaEntrega[index]['visita']!.add(
                const Duration(days: 1),
              );
        }
      }
    });
  }

  Future<void> _guardar() async {
    final nombreProveedor = _proveedorController.text.trim();
    // Aquí puedes capturar el celular si necesitas mandarlo al backend más adelante
    // final numeroCelular = _celularController.text.trim();

    if (nombreProveedor.isEmpty || _usuariosVinculados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor asigne un Proveedor y al menos un Usuario responsable.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // El repositorio procesará la lista de pares relacionales y aplicará
      // la sobreescritura automática limpia sobre ferrotienda.cronograma_visitas
      await _cronogramaService.crearProgramacion(
        proveedor: nombreProveedor,
        frecuencia: _frecuenciaSeleccionada,
        paresVisitaEntrega: _paresVisitaEntrega,
        repetirMeses: _repetirMeses,
        usuariosVinculados: _usuariosVinculados,
      );

      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cronograma guardado con éxito. Secuencias futuras generadas.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar el cronograma: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Programar Secuencia de Pedidos')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- SECCIÓN 1: PROVEEDOR MAESTRO ---
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
                        initialSelection: _proveedorSeleccionado,
                        dropdownMenuEntries: _proveedoresDb.map((prov) {
                          return DropdownMenuEntry<String>(
                            value: prov,
                            label: prov,
                          );
                        }).toList(),
                        onSelected: (val) =>
                            setState(() => _proveedorSeleccionado = val),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 🔥 NUEVO: Campo de Contacto Celular para los reportes de WhatsApp
                  TextFormField(
                    controller: _celularController,
                    decoration: const InputDecoration(
                      labelText: "Contacto Celular (WhatsApp)",
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                      hintText: "Ej: 0991234567",
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  // --- SECCIÓN 2: FRECUENCIA Y DURACIÓN (PARALELOS) ---
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _frecuenciaSeleccionada,
                          decoration: const InputDecoration(
                            labelText: 'Frecuencia de Ciclo',
                            border: OutlineInputBorder(),
                          ),
                          items: _opcionesFrecuencia.map((frec) {
                            String label = frec;
                            if (frec == 'Mensual') {
                              label = '1 vez al mes (Mensual)';
                            }
                            if (frec == 'Quincenal') {
                              label = '2 veces al mes (Quincenal)';
                            }
                            if (frec == 'Semanal') {
                              label = '4 veces al mes (Semanal)';
                            }
                            return DropdownMenuItem(
                              value: frec,
                              child: Text(label),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _frecuenciaSeleccionada = val!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _repetirMeses,
                          decoration: const InputDecoration(
                            labelText: 'Repetir Secuencia por:',
                            border: OutlineInputBorder(),
                          ),
                          items: _opcionesDuracion.entries.map((entry) {
                            return DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _repetirMeses = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- SECCIÓN 3: PARES RELACIONALES DINÁMICOS ---
                  const Row(
                    children: [
                      Icon(Icons.link, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Configuración de Visitas y Entregas Conectadas:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _paresVisitaEntrega.length,
                    itemBuilder: (context, index) {
                      final par = _paresVisitaEntrega[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Punto de Conexión #${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  if (_paresVisitaEntrega.length > 1)
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () => _eliminarPar(index),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Sub-botón 1: Día de Visita
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.calendar_today,
                                  color: Colors.blue,
                                ),
                                title: const Text(
                                  'Día y Hora de Visita (Toma de Pedido)',
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'EEEE, dd/MM/yyyy - HH:mm',
                                  ).format(par['visita']!),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                ),
                                onTap: () =>
                                    _seleccionarFechaHoraPar(index, 'visita'),
                              ),
                              const Divider(height: 8),
                              // Sub-botón 2: Día de Entrega Relacionado
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.local_shipping,
                                  color: Colors.orange,
                                ),
                                title: const Text(
                                  'Día y Hora de Entrega (Llegada Física)',
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'EEEE, dd/MM/yyyy - HH:mm',
                                  ).format(par['entrega']!),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                ),
                                onTap: () =>
                                    _seleccionarFechaHoraPar(index, 'entrega'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  OutlinedButton.icon(
                    onPressed: _agregarOtroPar,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text(
                      'Añadir otra visita/entrega semanal a este proveedor',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- SECCIÓN 4: USUARIOS VINCULADOS ---
                  const Text(
                    'Usuarios Asignados para Alertas:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _usuariosDb.length,
                      itemBuilder: (context, index) {
                        final u = _usuariosDb[index];
                        final isSelected = _usuariosVinculados.contains(
                          u.nombreUsuario,
                        );
                        return CheckboxListTile(
                          dense: true,
                          title: Text(
                            u.nombreUsuario,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
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
                  const SizedBox(height: 28),

                  // --- BOTÓN FINAL GUARDAR ---
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    onPressed: _guardar,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text(
                      'Proyectar y Generar Calendario',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
