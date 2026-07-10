import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/storage/session_storage.dart';
import '../models/visita_model.dart';
import '../models/notificacion_model.dart';

class CronogramaService {
  final String baseUrl =
      'http://localhost:8000/api/cronograma'; // Ajusta la IP si pruebas en móvil físico

  Future<Map<String, String>> _getHeaders() async {
    final user = await SessionStorage.getUser();
    return {
      'Content-Type': 'application/json',
      'X-Usuario': user?.nombreUsuario ?? 'Desconocido',
    };
  }

  // 1. Crear una nueva programación
  Future<bool> crearProgramacion({
    required String proveedor,
    required int frecuencia,
    required DateTime fechaInicio,
    required DateTime fechaEntrega, // ---> NUEVO PARÁMETRO
    required List<String> usuariosVinculados,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'proveedor': proveedor,
        'frecuencia': frecuencia,
        'fecha_inicio': fechaInicio
            .toIso8601String(), // Formato seguro para el backend
        'fecha_entrega': fechaEntrega
            .toIso8601String(), // ---> NUEVA PROPIEDAD AL PAYLOAD
        'usuarios_vinculados': usuariosVinculados,
      }),
    );

    if (response.statusCode == 200) return true;
    throw Exception('Error al crear el cronograma');
  }

  // 2. Obtener las visitas para pintar el calendario
  Future<List<Visita>> obtenerVisitasDelMes(int anio, int mes) async {
    final response = await http.get(
      Uri.parse('$baseUrl/calendario/$anio/$mes'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => Visita.fromJson(item)).toList();
    }
    throw Exception('Error al cargar el calendario');
  }

  // 3. Obtener alertas del usuario actual
  Future<List<Notificacion>> misNotificaciones() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notificaciones'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => Notificacion.fromJson(item)).toList();
    }
    throw Exception('Error al cargar notificaciones');
  }

  // 4. Marcar alerta como leída
  Future<bool> marcarComoLeida(int idNotificacion) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notificaciones/$idNotificacion/leer'),
      headers: await _getHeaders(),
    );
    return response.statusCode == 200;
  }

  // --- Obtener lista de proveedores para el autocompletado ---
  Future<List<String>> obtenerProveedores() async {
    // Apuntamos al endpoint de proveedores que creamos en Python
    final url = baseUrl.replaceAll('/cronograma', '/proveedores');
    final response = await http.get(
      Uri.parse('$url/'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => item.toString()).toList();
    }
    // Si hay un error, devolvemos una lista vacía para no romper la pantalla
    return [];
  }
}
