class ProductBalance {
  final String codigo;
  final String nombre;
  final double stock;
  final String? marca;
  final String? clase;
  final double precio; // <-- Se añade la variable precio

  ProductBalance({
    required this.codigo,
    required this.nombre,
    required this.stock,
    this.marca,
    this.clase,
    this.precio = 0.0, // <-- Valor por defecto a 0.0 por seguridad
  });

  factory ProductBalance.fromJson(Map<String, dynamic> json) {
    return ProductBalance(
      codigo: json['Codigo']?.toString() ?? '',
      nombre: json['Nombre']?.toString() ?? '',
      stock: double.tryParse(json['Stock']?.toString() ?? '0') ?? 0.0,
      marca: json['Marca']?.toString(),
      clase: json['Clase']?.toString(),
      // <-- Se extrae el precio desde el campo "Precio" del JSON
      precio: double.tryParse(json['Precio']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Codigo': codigo,
      'Nombre': nombre,
      'Stock': stock,
      'Marca': marca,
      'Clase': clase,
      'Precio': precio, // <-- Se incluye al convertir a JSON
    };
  }
}
