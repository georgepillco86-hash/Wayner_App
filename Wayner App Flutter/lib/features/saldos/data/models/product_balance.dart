class ProductBalance {
  final String codigo;
  final String nombre;
  final double stock;
  final String? marca;
  final String? clase;

  // Quitamos la palabra "final" para poder actualizar los precios en vivo
  double precio;
  double iva;
  double costo;

  ProductBalance({
    required this.codigo,
    required this.nombre,
    required this.stock,
    this.marca,
    this.clase,
    this.precio = 0.0,
    this.iva = 0.0,
    this.costo = 0.0,
  });

  factory ProductBalance.fromJson(Map<String, dynamic> json) {
    return ProductBalance(
      codigo: json['Codigo']?.toString() ?? '',
      nombre: json['Nombre']?.toString() ?? '',
      stock: double.tryParse(json['Stock']?.toString() ?? '0') ?? 0.0,
      marca: json['Marca']?.toString(),
      clase: json['Clase']?.toString(),
      precio: double.tryParse(json['Precio']?.toString() ?? '0') ?? 0.0,
      iva: double.tryParse(json['IVA']?.toString() ?? '0') ?? 0.0,
      costo: double.tryParse(json['Costo']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Codigo': codigo,
      'Nombre': nombre,
      'Stock': stock,
      'Marca': marca,
      'Clase': clase,
      'Precio': precio,
      'IVA': iva,
      'Costo': costo,
    };
  }
}
