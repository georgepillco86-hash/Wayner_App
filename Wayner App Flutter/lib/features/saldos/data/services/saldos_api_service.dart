import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../products/data/models/product_price.dart';
import '../../../products/data/models/sales_summary.dart';
import '../models/product_balance.dart';

class SaldosApiService {
  final ApiClient _apiClient;

  SaldosApiService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  List<dynamic> _extractData(dynamic response) {
    if (response is Map && response['data'] is List) {
      return response['data'] as List;
    }
    return [];
  }

  Map<String, dynamic>? _extractMap(dynamic response) {
    if (response is Map && response['data'] is Map<String, dynamic>) {
      return response['data'] as Map<String, dynamic>;
    }
    return null;
  }

  Future<List<ProductBalance>> searchProducts({
    required String text,
    String? clase,
    String? proveedor,
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      '${ApiConfig.saldosBasePath}/buscar',
      queryParameters: {
        'texto': text,
        if (clase != null && clase.isNotEmpty) 'clase': clase,
        if (proveedor != null && proveedor.isNotEmpty) 'proveedor': proveedor,
        'limit': limit,
      },
    );

    return _extractData(
      response,
    ).whereType<Map<String, dynamic>>().map(ProductBalance.fromJson).toList();
  }

  Future<ProductBalance?> getProductByCode(String code) async {
    final response = await _apiClient.get(
      '${ApiConfig.saldosBasePath}/producto/$code',
    );
    final data = _extractMap(response);
    if (data == null) return null;
    return ProductBalance.fromJson(data);
  }

  Future<List<ProductBalance>> getDataset({
    int limit = 20,
    String? proveedor,
  }) async {
    final response = await _apiClient.get(
      '${ApiConfig.saldosBasePath}/dataset',
      queryParameters: {
        'limit': limit,
        if (proveedor != null && proveedor.isNotEmpty) 'proveedor': proveedor,
      },
    );

    return _extractData(
      response,
    ).whereType<Map<String, dynamic>>().map(ProductBalance.fromJson).toList();
  }

  // 1. Obtener clases ahora usa la ruta rápida de PostgreSQL
  Future<List<String>> getClasses() async {
    try {
      final response = await _apiClient.get('/api/proveedores/clases');
      if (response is List) return response.map((e) => e.toString()).toList();
      return [];
    } catch (e) {
      print("❌ ERROR AL CARGAR CLASES EN FLUTTER: $e");
      return [];
    }
  }

  // 2. Obtener proveedores ahora usa la ruta rápida de PostgreSQL
  Future<List<String>> getProviders() async {
    try {
      final response = await _apiClient.get('/api/proveedores/');
      if (response is List) return response.map((e) => e.toString()).toList();
      return [];
    } catch (e) {
      print("❌ ERROR AL CARGAR PROVEEDORES EN FLUTTER: $e");
      return [];
    }
  }

  Future<List<ProductBalance>> getProductsByClass(
    String clase, {
    int limit = 20,
    String? proveedor,
  }) async {
    final response = await _apiClient.get(
      '${ApiConfig.saldosBasePath}/clase/$clase',
      queryParameters: {
        'limit': limit,
        if (proveedor != null && proveedor.isNotEmpty) 'proveedor': proveedor,
      },
    );

    return _extractData(
      response,
    ).whereType<Map<String, dynamic>>().map(ProductBalance.fromJson).toList();
  }

  Future<List<SalesSummary>> getSalesSummary(
    String codigoBarra,
    String desde,
    String hasta,
  ) async {
    final response = await _apiClient.get(
      '/api/productos/$codigoBarra/ventas-resumen',
      queryParameters: {'desde': desde, 'hasta': hasta},
    );

    return _extractData(
      response,
    ).whereType<Map<String, dynamic>>().map(SalesSummary.fromJson).toList();
  }

  Future<ProductPrice> getProductPrice(String codigoBarra) async {
    final response = await _apiClient.get(
      '/api/productos/escanear/$codigoBarra',
    );

    final data = _extractMap(response);
    if (data == null) {
      throw const ApiException(
        'No se pudo obtener el precio del producto.',
        type: ApiErrorType.invalidResponse,
      );
    }

    return ProductPrice.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> getKardexTable(
    String codigoBarra,
    String desde,
    String hasta,
  ) async {
    final response = await _apiClient.get(
      '/api/productos/$codigoBarra/kardex-tabla',
      queryParameters: {'desde': desde, 'hasta': hasta},
    );

    return _extractData(response).whereType<Map<String, dynamic>>().toList();
  }

  // 1. Búsqueda profunda de emergencia en Kardex
  Future<List<dynamic>> busquedaProfundaKardex(String termino) async {
    try {
      final response = await _apiClient.get(
        '/api/proveedores/busqueda-profunda',
        queryParameters: {'q': termino},
      );

      if (response is List) return response;
      if (response is Map && response['data'] is List) return response['data'];
      return [];
    } catch (e) {
      return [];
    }
  }

  // 2. Consulta ultrarrápida del precio en vivo
  Future<Map<String, dynamic>> obtenerPrecioVivo(String codigo) async {
    try {
      final response = await _apiClient.get(
        '/api/proveedores/producto/$codigo/precio-vivo',
      );

      if (response is Map<String, dynamic>) {
        if (response.containsKey('data')) return response['data'];
        return response;
      }
      return {"precio_vivo": 0.0, "iva_vivo": 0.0, "costo_vivo": 0.0};
    } catch (e) {
      return {"precio_vivo": 0.0, "iva_vivo": 0.0, "costo_vivo": 0.0};
    }
  }

  // Obtener la lista de proveedores para el menú desplegable
  Future<List<String>> obtenerProveedores() async {
    try {
      final response = await _apiClient.get('/api/proveedores/');
      if (response is List) return response.map((e) => e.toString()).toList();
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- CORREGIDO: La nueva búsqueda ultrarrápida ahora acepta 'clase' ---
  Future<List<dynamic>> buscarRapido(
    String query, {
    String? proveedor,
    String? clase,
  }) async {
    try {
      final params = {'q': query};

      if (proveedor != null && proveedor.isNotEmpty) {
        params['proveedor'] = proveedor;
      }

      if (clase != null && clase.isNotEmpty) {
        params['clase'] = clase;
      }

      final response = await _apiClient.get(
        '/api/proveedores/buscar-rapido',
        queryParameters: params,
      );

      if (response is List) return response;
      if (response is Map && response.containsKey('data')) {
        return response['data'];
      }
      return [];
    } catch (e, stacktrace) {
      // 🚨 AQUÍ ESTABA LA TRAMPA: Flutter ocultaba el error. Ahora lo veremos.
      print("❌ ERROR FATAL EN BUSCAR RAPIDO (FLUTTER): $e");
      print(stacktrace);
      return [];
    }
  }
}
