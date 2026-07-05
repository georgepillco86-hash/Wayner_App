import 'dart:convert';

class Visita {
  final int id;
  final String proveedor;
  final DateTime fechaProgramada;
  final String estado;
  final List<String> usuariosVinculados;

  Visita({
    required this.id,
    required this.proveedor,
    required this.fechaProgramada,
    required this.estado,
    required this.usuariosVinculados,
  });

  factory Visita.fromJson(Map<String, dynamic> json) {
    // Manejo seguro del JSONB que viene de Postgres
    List<String> usuarios = [];
    if (json['usuarios_vinculados'] != null) {
      if (json['usuarios_vinculados'] is String) {
        usuarios = List<String>.from(jsonDecode(json['usuarios_vinculados']));
      } else {
        usuarios = List<String>.from(json['usuarios_vinculados']);
      }
    }

    return Visita(
      id: json['id'],
      proveedor: json['proveedor'],
      fechaProgramada: DateTime.parse(json['fecha_programada']),
      estado: json['estado'],
      usuariosVinculados: usuarios,
    );
  }
}
