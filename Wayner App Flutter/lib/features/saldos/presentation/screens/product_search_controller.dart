import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/product_balance.dart';
import '../../data/services/saldos_api_service.dart';

class ProductSearchController extends ChangeNotifier {
  final SaldosApiService _service;

  ProductSearchController({SaldosApiService? service})
    : _service = service ?? SaldosApiService();

  bool isLoading = false;
  String? errorMessage;
  String? technicalError;

  String? selectedClass;
  String? selectedProvider;

  // Estado del Interruptor
  bool isDeepSearch = false;

  List<String> classes = [];
  List<String> providers = [];
  List<ProductBalance> products = [];

  // --- NUEVO: Lista maestra para filtrado local en memoria ---
  List<ProductBalance> _masterProductsList = [];

  String? _lastSearchText;
  String? _lastSearchClass;
  String? _lastSearchProvider;
  bool _initialDataLoaded = false;

  // Alternar Búsqueda (CORREGIDO)
  Future<void> toggleDeepSearch(bool value) async {
    isDeepSearch = value;
    notifyListeners();

    // Si cambiamos de modo, la lista maestra anterior ya no sirve.
    // Recargamos los datos respetando los filtros que el usuario tenga activos.
    if (selectedProvider != null) {
      await filterByProvider(selectedProvider);
    } else if (selectedClass != null) {
      await filterByClass(selectedClass);
    } else {
      await loadDataset(forceRefresh: true, keepFilters: true);
    }

    // Si había texto en el buscador, lo reaplicamos localmente
    if (_lastSearchText != null && _lastSearchText!.isNotEmpty) {
      await search(_lastSearchText!);
    }
  }

  Future<void> loadInitialData({bool forceRefresh = false}) async {
    if (_initialDataLoaded && !forceRefresh) return;

    _setLoading(true);
    try {
      final results = await Future.wait([
        _service.getClasses(),
        _service.getProviders(),
        isDeepSearch
            ? _service.getDataset(limit: 200)
            : _service.buscarRapido(''),
      ]);

      classes = results[0] as List<String>;
      providers = results[1] as List<String>;

      // --- CORRECCIÓN DEL PARSEO PARA EVITAR CRASH SILENCIOSO ---
      final rawProducts = results[2] as List<dynamic>;

      if (rawProducts.isNotEmpty) {
        try {
          products = rawProducts
              .map(
                (json) =>
                    ProductBalance.fromJson(Map<String, dynamic>.from(json)),
              )
              .toList();
        } catch (parseError) {
          print("❌ ERROR CONVIRTIENDO PRODUCTOS EN FLUTTER: $parseError");
          products = [];
        }
      } else {
        products = [];
      }

      _masterProductsList = List.from(products);
      _initialDataLoaded = true;
      _clearError();
      notifyListeners();
    } catch (e) {
      print("❌ ERROR GENERAL EN LOAD INITIAL DATA: $e");
      products = [];
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  void refresh() {
    if (_lastSearchText != null && _lastSearchText!.isNotEmpty) {
      search(_lastSearchText!);
    } else {
      loadInitialData(forceRefresh: true);
    }
  }

  Future<void> search(String text) async {
    // 🛡️ ESCUDO: Si ya está buscando, ignora peticiones repetidas al servidor
    if (isLoading) return;

    final cleanText = text.trim();
    final lowerQuery = cleanText.toLowerCase();

    // --- 1. FILTRADO LOCAL EN MEMORIA ---
    if (selectedProvider != null || selectedClass != null) {
      if (cleanText.isEmpty) {
        products = List.from(_masterProductsList);
      } else {
        _applyLocalSearchText(lowerQuery);
      }
      _lastSearchText = cleanText;
      notifyListeners();
      return;
    }

    // --- 2. BÚSQUEDA GLOBAL AL SERVIDOR ---
    if (cleanText.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      if (isDeepSearch) {
        // Búsqueda en Kardex General (MySQL)
        final results = await _service.busquedaProfundaKardex(cleanText);
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      } else {
        // Búsqueda Rápida en Proveedores (PostgreSQL)
        final results = await _service.buscarRapido(
          cleanText,
          proveedor: selectedProvider,
        );
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      }

      _lastSearchText = cleanText;
      _clearError();
      notifyListeners();
    } catch (e) {
      products = [];
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  // Carga de Dataset base (CORREGIDO)
  Future<void> loadDataset({
    bool forceRefresh = false,
    bool keepFilters = false,
  }) async {
    // 🛡️ ESCUDO: Evita cargar múltiples veces a la vez (salvo si forzamos recarga)
    if (isLoading && !forceRefresh) return;

    _setLoading(true);
    try {
      if (isDeepSearch) {
        // Va a MySQL
        products = await _service.getDataset(
          limit: 200,
          proveedor: selectedProvider,
        );
      } else {
        // Va a PostgreSQL
        final results = await _service.buscarRapido(
          '',
          proveedor: selectedProvider,
        );
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      }

      _masterProductsList = List.from(products);

      if (!keepFilters) {
        selectedClass = null;
        selectedProvider = null;
      }
      _clearError();
      notifyListeners();
    } catch (e) {
      products = [];
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  // Filtro por Clase (CORREGIDO)
  Future<void> filterByClass(String? clase) async {
    // 🛡️ ESCUDO: Evita el spam si el usuario toca la clase repetidamente
    if (isLoading) return;

    selectedClass = clase;
    if (clase == null || clase.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      if (isDeepSearch) {
        // MySQL: Filtra directo en saldos
        products = await _service.getProductsByClass(
          clase,
          limit: 5000,
          proveedor: selectedProvider,
        );
      } else {
        // PostgreSQL: Asegúrate de que buscarRapido envíe el parámetro clase al backend
        final results = await _service.buscarRapido(
          '',
          proveedor: selectedProvider,
          clase: clase,
        );
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      }

      _masterProductsList = List.from(products);

      // Sub-filtro si ya había texto escrito
      if (_lastSearchText != null && _lastSearchText!.isNotEmpty) {
        _applyLocalSearchText(_lastSearchText!.toLowerCase());
      }

      notifyListeners();
    } catch (e) {
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  // Filtro por Proveedor (CORREGIDO)
  Future<void> filterByProvider(String? proveedor) async {
    // 🛡️ ESCUDO: Evita el spam si se selecciona proveedor repetidamente
    if (isLoading) return;

    selectedProvider = proveedor;

    if (proveedor == null) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      if (isDeepSearch) {
        // MySQL: Búsqueda en kardex limitando por proveedor (dataset ya soporta proveedor en tu backend)
        products = await _service.getDataset(limit: 5000, proveedor: proveedor);
      } else {
        // PostgreSQL: Catálogo espejo
        final results = await _service.buscarRapido('', proveedor: proveedor);
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      }

      _masterProductsList = List.from(products);

      // Sub-filtro si ya había texto escrito
      if (_lastSearchText != null && _lastSearchText!.isNotEmpty) {
        _applyLocalSearchText(_lastSearchText!.toLowerCase());
      }

      notifyListeners();
    } catch (e) {
      products = [];
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  // Método Helper para DRY (Don't Repeat Yourself)
  void _applyLocalSearchText(String lowerQuery) {
    products = _masterProductsList.where((p) {
      return p.nombre.toLowerCase().contains(lowerQuery) ||
          p.codigo.toLowerCase().contains(lowerQuery) ||
          (p.codigoBarra?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    errorMessage = null;
    technicalError = null;
  }

  void _setError(Object error) {
    if (error is ApiException) {
      errorMessage = error.message;
      technicalError = error.technicalMessage;
    } else {
      errorMessage = 'Error inesperado.';
      technicalError = error.toString();
    }
    notifyListeners();
  }
}
