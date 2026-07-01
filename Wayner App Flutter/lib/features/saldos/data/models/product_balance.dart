class ProductBalance {
  final String codigo;
  final String nombre;
  final double stock;
  final String? marca;
  final String? clase;

  ProductBalance({
    required this.codigo,
    required this.nombre,
    required this.stock,
    this.marca,
    this.clase,
  });

  factory ProductBalance.fromJson(Map<String, dynamic> json) {
    return ProductBalance(
      codigo: json['Codigo']?.toString() ?? '',
      nombre: json['Nombre']?.toString() ?? '',
      stock: double.tryParse(json['Stock']?.toString() ?? '0') ?? 0,
      marca: json['Marca']?.toString(),
      clase: json['Clase']?.toString(),
    );
  }
}
