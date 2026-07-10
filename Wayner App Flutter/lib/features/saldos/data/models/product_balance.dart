class ProductBalance {
  final String codigo;
  final String? codigoBarra;
  final String nombre;
  final double stock;
  final String? marca;
  final String? clase;

  // Quitamos la palabra "final" para poder actualizar los precios en vivo
  double precio;
  double iva;
  double costo;

  // --- NUEVAS PROPIEDADES PREDICTIVAS ---
  final double vdp; // Venta Diaria Promedio
  final int leadTimeDias; // Días de demora del proveedor

  ProductBalance({
    required this.codigo,
    this.codigoBarra,
    required this.nombre,
    required this.stock,
    this.marca,
    this.clase,
    this.precio = 0.0,
    this.iva = 0.0,
    this.costo = 0.0,
    this.vdp = 0.0,
    this.leadTimeDias =
        3, // Por defecto 3 días si el proveedor no tiene uno asignado
  });

  factory ProductBalance.fromJson(Map<String, dynamic> json) {
    return ProductBalance(
      codigo: json['Codigo']?.toString() ?? '',
      codigoBarra: json['CodigoBarra']?.toString(),
      nombre: json['Nombre']?.toString() ?? '',
      stock: double.tryParse(json['Stock']?.toString() ?? '0') ?? 0.0,
      marca: json['Marca']?.toString(),
      clase: json['Clase']?.toString(),
      precio: double.tryParse(json['Precio']?.toString() ?? '0') ?? 0.0,
      iva: double.tryParse(json['IVA']?.toString() ?? '0') ?? 0.0,
      costo: double.tryParse(json['Costo']?.toString() ?? '0') ?? 0.0,
      // Extraemos los nuevos campos desde el backend
      vdp:
          double.tryParse(
            json['vdp']?.toString() ?? json['VDP']?.toString() ?? '0',
          ) ??
          0.0,
      leadTimeDias:
          int.tryParse(
            json['lead_time_dias']?.toString() ??
                json['LeadTime']?.toString() ??
                '3',
          ) ??
          3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Codigo': codigo,
      'CodigoBarra': codigoBarra,
      'Nombre': nombre,
      'Stock': stock,
      'Marca': marca,
      'Clase': clase,
      'Precio': precio,
      'IVA': iva,
      'Costo': costo,
      'vdp': vdp,
      'lead_time_dias': leadTimeDias,
    };
  }

  // ==========================================
  // LÓGICA DE INVENTARIO INTELIGENTE
  // ==========================================

  /// Calcula el stock mínimo matemático
  /// [diasCobertura] = Cuántos días quieres que te dure la mercadería (ej. 7, 14, 30)
  double calcularStockMinimo({int diasCobertura = 7}) {
    // Si no tiene historial de ventas (VDP = 0), su stock mínimo no se puede calcular
    if (vdp <= 0) return 0;

    // Fórmula: (Ventas diarias * Días de exhibición) + (Ventas diarias * Días que tarda en llegar)
    return (vdp * diasCobertura) + (vdp * leadTimeDias);
  }

  /// Evalúa la salud actual del producto comparando el stock físico con el mínimo
  String calcularNivelStock({int diasCobertura = 7}) {
    if (stock <= 0) return 'Agotado';

    final stockMinimo = calcularStockMinimo(diasCobertura: diasCobertura);

    // Si es un producto nuevo o sin ventas recientes, lo marcamos como Normal
    if (stockMinimo == 0) return 'Normal';

    final ratio = stock / stockMinimo;

    if (ratio <= 0.5)
      return 'Bajo'; // Tiene menos de la mitad de lo que necesita
    if (ratio <= 1.0)
      return 'Medio'; // Tiene casi lo justo, debería pedir pronto
    if (ratio <= 2.0) return 'Normal'; // Tiene suficiente para cubrir la meta
    return 'Alto'; // Tiene más del doble de lo que necesita (Sobre-stock)
  }
}
