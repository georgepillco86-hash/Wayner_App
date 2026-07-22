import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/merma_model.dart';
import '../models/merma_historial_model.dart';
import '../../../../core/storage/session_storage.dart';

class MermaService {
  final String baseUrl = 'http://localhost:5000/api/mermas';

  Future<Map<String, String>> _getHeaders() async {
    final user = await SessionStorage.getUser();
    return {
      'Content-Type': 'application/json',
      'X-Usuario': user?.nombreUsuario ?? 'Desconocido',
      'X-Rol': user?.rol ?? '',
    };
  }

  Future<List<Merma>> listarMermas() async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/',
      ), // 🔥 CORREGIDO: Slash devuelto para evitar el 307 Redirect
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => Merma.fromJson(item)).toList();
    }
    throw Exception('Error al cargar mermas');
  }

  Future<List<MermaHistorial>> obtenerHistorial(int mermaId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/$mermaId/historial'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      List<dynamic> body = jsonDecode(response.body);
      return body.map((item) => MermaHistorial.fromJson(item)).toList();
    }
    throw Exception('Error al cargar el historial de la merma');
  }

  Future<bool> crearMerma(Merma merma) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/',
      ), // 🔥 CORREGIDO: Slash devuelto para evitar el 307 Redirect
      headers: await _getHeaders(),
      body: jsonEncode(merma.toJson()),
    );
    return response.statusCode == 200;
  }

  Future<bool> actualizarMerma(int id, Map<String, dynamic> datos) async {
    final response = await http.put(
      Uri.parse('$baseUrl/$id'),
      headers: await _getHeaders(),
      body: jsonEncode(datos),
    );
    return response.statusCode == 200;
  }

  Future<bool> cambiarEstado({
    required int id,
    required String estado,
    required String comentario,
    String? notaCredito,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/$id/estado'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'estado': estado,
        'comentario': comentario,
        'nota_credito': notaCredito,
      }),
    );
    if (response.statusCode == 200) return true;

    final error = jsonDecode(response.body);
    throw Exception(error['detail'] ?? 'Error al cambiar estado');
  }

  Future<bool> eliminarMerma(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/$id'),
      headers: await _getHeaders(),
    );
    return response.statusCode == 200;
  }
}
