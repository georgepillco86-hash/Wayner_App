import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../data/models/visita_model.dart';
import '../../data/services/cronograma_service.dart';
import 'cronograma_form_screen.dart';

class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  final _cronogramaService = CronogramaService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Visita>> _visitasMes = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _cargarMes(_focusedDay.year, _focusedDay.month);
  }

  Future<void> _cargarMes(int year, int month) async {
    setState(() => _isLoading = true);
    try {
      final visitas = await _cronogramaService.obtenerVisitasDelMes(
        year,
        month,
      );

      // Agrupar visitas por día exacto para el calendario
      final Map<DateTime, List<Visita>> visitasAgrupadas = {};
      for (var v in visitas) {
        // Ignorar la hora para la agrupación en el calendario
        final fechaDia = DateTime(
          v.fechaProgramada.year,
          v.fechaProgramada.month,
          v.fechaProgramada.day,
        );
        if (visitasAgrupadas[fechaDia] == null) visitasAgrupadas[fechaDia] = [];
        visitasAgrupadas[fechaDia]!.add(v);
      }

      setState(() => _visitasMes = visitasAgrupadas);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Función para obtener eventos de un día específico
  List<Visita> _getVisitasDelDia(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _visitasMes[normalizedDay] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final visitasSeleccionadas = _selectedDay != null
        ? _getVisitasDelDia(_selectedDay!)
        : [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario de Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Programar Nuevo',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CronogramaFormScreen(
                  onSaved: () =>
                      _cargarMes(_focusedDay.year, _focusedDay.month),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. EL CALENDARIO
          TableCalendar<Visita>(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            eventLoader: _getVisitasDelDia,
            startingDayOfWeek: StartingDayOfWeek.monday,

            // Cuando el usuario cambia de mes deslizando
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
              _cargarMes(focusedDay.year, focusedDay.month);
            },

            // Cuando el usuario toca un día
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              }
            },

            // Estilos
            calendarStyle: const CalendarStyle(
              markerDecoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Colors.blueGrey,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
          ),

          const Divider(),
          const Text(
            'Pedidos para este día:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 2. LISTA DE PEDIDOS DEL DÍA SELECCIONADO
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visitasSeleccionadas.isEmpty
                ? const Center(
                    child: Text('No hay pedidos programados para esta fecha.'),
                  )
                : ListView.builder(
                    itemCount: visitasSeleccionadas.length,
                    itemBuilder: (context, index) {
                      final visita = visitasSeleccionadas[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.local_shipping),
                          ),
                          title: Text(
                            visita.proveedor,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Hora: ${DateFormat('HH:mm').format(visita.fechaProgramada)}\n'
                            'Responsables: ${visita.usuariosVinculados.join(", ")}',
                          ),
                          trailing: Chip(
                            label: Text(
                              visita.estado,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                            backgroundColor: visita.estado == 'Pendiente'
                                ? Colors.orange
                                : Colors.green,
                            padding: EdgeInsets.zero,
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
