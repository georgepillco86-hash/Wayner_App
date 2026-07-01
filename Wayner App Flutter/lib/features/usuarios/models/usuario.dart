class Usuario {
  final int id;
  final String nombreUsuario;
  final String? nombreCompleto;
  final String rol;
  final bool activo;
  final String? fechaCreacion;
  final String? ultimoLogin;

  Usuario({
    required this.id,
    required this.nombreUsuario,
    required this.nombreCompleto,
    required this.rol,
    required this.activo,
    required this.fechaCreacion,
    required this.ultimoLogin,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as int,
      nombreUsuario: json['nombre_usuario']?.toString() ?? '',
      nombreCompleto: json['nombre_completo']?.toString(),
      rol: json['rol']?.toString() ?? '',
      activo: json['activo'] == true,
      fechaCreacion: json['fecha_creacion']?.toString(),
      ultimoLogin: json['ultimo_login']?.toString(),
    );
  }
}