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

  // --- NUEVO: Estado del Interruptor ---
  bool isDeepSearch = false;

  List<String> classes = [];
  List<String> providers = [];
  List<ProductBalance> products = [];

  String? _lastSearchText;
  String? _lastSearchClass;
  String? _lastSearchProvider;
  bool _initialDataLoaded = false;

  // --- NUEVO: Alternar Búsqueda ---
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

  Future<void> search(String text) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      // --- LOGICA HÍBRIDA ---
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

  // --- RESTO DE MÉTODOS (filterByClass, filterByProvider, etc) ---
  // Se mantienen idénticos, garantizando que printer, métricas y detalles sigan funcionando
  // ya que solo modificamos la forma en que 'products' se llena.

  Future<void> filterByClass(String? clase) async {
    selectedClass = clase;
    if (clase == null || clase.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }
    _setLoading(true);
    try {
      products = await _service.getProductsByClass(
        clase,
        limit: 30,
        proveedor: selectedProvider,
      );
      notifyListeners();
    } catch (e) {
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> filterByProvider(String? proveedor) async {
    selectedProvider = proveedor;
    await loadDataset(forceRefresh: true, keepFilters: true);
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
