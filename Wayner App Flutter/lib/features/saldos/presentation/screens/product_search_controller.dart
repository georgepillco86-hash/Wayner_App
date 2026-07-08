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

  // Alternar Búsqueda
  void toggleDeepSearch(bool value) {
    isDeepSearch = value;
    notifyListeners();
    // Si ya había una búsqueda, la actualiza con el nuevo modo
    if (_lastSearchText != null) search(_lastSearchText!);
  }

  Future<void> loadInitialData({bool forceRefresh = false}) async {
    if (_initialDataLoaded && !forceRefresh) return;

    _setLoading(true);
    try {
      final results = await Future.wait([
        _service.getClasses(),
        _service.getProviders(),
        _service.getDataset(limit: 20),
      ]);

      classes = results[0] as List<String>;
      providers = results[1] as List<String>;
      products = results[2] as List<ProductBalance>;

      // Guardamos la base inicial en la lista maestra
      _masterProductsList = List.from(products);

      _initialDataLoaded = true;
      _clearError();
      notifyListeners();
    } catch (e) {
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
    final cleanText = text.trim();
    final lowerQuery = cleanText.toLowerCase();

    // --- 1. FILTRADO LOCAL EN MEMORIA ---
    // Si hay un Proveedor o una Clase seleccionada, filtramos la lista maestra.
    if (selectedProvider != null || selectedClass != null) {
      if (cleanText.isEmpty) {
        products = List.from(_masterProductsList);
      } else {
        products = _masterProductsList.where((p) {
          return p.nombre.toLowerCase().contains(lowerQuery) ||
              p.codigo.toLowerCase().contains(lowerQuery) ||
              (p.codigoBarra?.toLowerCase().contains(lowerQuery) ?? false);
        }).toList();
      }
      _lastSearchText = cleanText;
      notifyListeners();
      return; // 🛑 Terminamos aquí, NO hacemos peticiones al servidor
    }

    // --- 2. BÚSQUEDA GLOBAL AL SERVIDOR ---
    if (cleanText.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      if (isDeepSearch) {
        // Búsqueda en Kardex General
        final results = await _service.busquedaProfundaKardex(cleanText);
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      } else {
        // Búsqueda Rápida en Proveedores (Espejo)
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

  Future<void> loadDataset({
    bool forceRefresh = false,
    bool keepFilters = false,
  }) async {
    _setLoading(true);
    try {
      products = await _service.getDataset(
        limit: 20,
        proveedor: selectedProvider,
      );
      _masterProductsList = List.from(products); // Actualizamos memoria

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

  Future<void> filterByClass(String? clase) async {
    selectedClass = clase;
    if (clase == null || clase.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }
    _setLoading(true);
    try {
      // Mandamos un límite muy alto para traer todos los productos de esa clase
      products = await _service.getProductsByClass(
        clase,
        limit: 5000,
        proveedor: selectedProvider,
      );
      _masterProductsList = List.from(
        products,
      ); // Guardamos para filtrar localmente

      // Si ya había un texto escrito en el buscador, lo aplicamos de inmediato al nuevo filtro
      if (_lastSearchText != null && _lastSearchText!.isNotEmpty) {
        final lowerQuery = _lastSearchText!.toLowerCase();
        products = _masterProductsList
            .where(
              (p) =>
                  p.nombre.toLowerCase().contains(lowerQuery) ||
                  p.codigo.toLowerCase().contains(lowerQuery) ||
                  (p.codigoBarra?.toLowerCase().contains(lowerQuery) ?? false),
            )
            .toList();
      }

      notifyListeners();
    } catch (e) {
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> filterByProvider(String? proveedor) async {
    selectedProvider = proveedor;

    if (proveedor == null) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      // Buscamos TODOS los productos del proveedor.
      // Al enviar texto vacío, el backend enviará todo sin límites.
      final results = await _service.buscarRapido('', proveedor: proveedor);
      products = results.map((json) => ProductBalance.fromJson(json)).toList();

      _masterProductsList = List.from(products); // Guardamos la lista maestra

      // Filtramos de inmediato si ya había texto en el buscador
      if (_lastSearchText != null && _lastSearchText!.isNotEmpty) {
        final lowerQuery = _lastSearchText!.toLowerCase();
        products = _masterProductsList
            .where(
              (p) =>
                  p.nombre.toLowerCase().contains(lowerQuery) ||
                  p.codigo.toLowerCase().contains(lowerQuery) ||
                  (p.codigoBarra?.toLowerCase().contains(lowerQuery) ?? false),
            )
            .toList();
      }

      notifyListeners();
    } catch (e) {
      products = [];
      _setError(e);
    } finally {
      _setLoading(false);
    }
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
