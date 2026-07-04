class Merma {
  final int? id;
  final String codigo;
  final String nombreProducto;
  final double cantidad;
  final String? proveedor;
  final String novedad;
  final String? comentario;
  final DateTime? fechaRegistro;
  final String estado;
  final String usuario;
  final bool activo;

  Merma({
    this.id,
    required this.codigo,
    required this.nombreProducto,
    required this.cantidad,
    this.proveedor,
    required this.novedad,
    this.comentario,
    this.fechaRegistro,
    required this.estado,
    required this.usuario,
    required this.activo,
  });

  factory Merma.fromJson(Map<String, dynamic> json) {
    return Merma(
      id: json['id'],
      codigo: json['codigo'] ?? '',
      nombreProducto: json['nombre_producto'] ?? '',
      cantidad: double.tryParse(json['cantidad']?.toString() ?? '0') ?? 0.0,
      proveedor: json['proveedor'],
      novedad: json['novedad'] ?? '',
      comentario: json['comentario'],
      fechaRegistro: json['fecha_registro'] != null
          ? DateTime.parse(json['fecha_registro'])
          : null,
      estado: json['estado'] ?? 'Pendiente',
      usuario: json['usuario'] ?? '',
      activo: json['activo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'codigo': codigo,
      'nombre_producto': nombreProducto,
      'cantidad': cantidad,
      'novedad': novedad,
      'comentario': comentario,
    };
  }
}
