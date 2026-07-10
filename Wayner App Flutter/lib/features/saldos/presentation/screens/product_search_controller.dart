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

  Future<void> toggleDeepSearch(bool value) async {
    isDeepSearch = value;
    notifyListeners();

    if (selectedProvider != null) {
      await filterByProvider(selectedProvider);
    } else if (selectedClass != null) {
      await filterByClass(selectedClass);
    } else {
      await loadDataset(forceRefresh: true, keepFilters: true);
    }

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
            // ---> CORREGIDO: Usamos searchProducts en vez de buscarRapido <---
            : _service.searchProducts(text: ''),
      ]);

      classes = results[0] as List<String>;
      providers = results[1] as List<String>;

      // ---> CORREGIDO: searchProducts ya devuelve List<ProductBalance> parseado <---
      products = results[2] as List<ProductBalance>;

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
        final results = await _service.busquedaProfundaKardex(cleanText);
        products = results
            .map((json) => ProductBalance.fromJson(json))
            .toList();
      } else {
        // ---> CORREGIDO: Usamos el método unificado que ya mapea a objetos <---
        products = await _service.searchProducts(
          text: cleanText,
          proveedor: selectedProvider,
        );
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
    if (isLoading && !forceRefresh) return;

    _setLoading(true);
    try {
      if (isDeepSearch) {
        products = await _service.getDataset(
          limit: 200,
          proveedor: selectedProvider,
        );
      } else {
        // ---> CORREGIDO <---
        products = await _service.searchProducts(
          text: '',
          proveedor: selectedProvider,
        );
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

  Future<void> filterByClass(String? clase) async {
    if (isLoading) return;

    selectedClass = clase;
    if (clase == null || clase.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      if (isDeepSearch) {
        products = await _service.getProductsByClass(
          clase,
          limit: 5000,
          proveedor: selectedProvider,
        );
      } else {
        // ---> CORREGIDO <---
        products = await _service.searchProducts(
          text: '',
          proveedor: selectedProvider,
          clase: clase,
        );
      }

      _masterProductsList = List.from(products);

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

  Future<void> filterByProvider(String? proveedor) async {
    if (isLoading) return;

    selectedProvider = proveedor;

    if (proveedor == null) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    _setLoading(true);
    try {
      if (isDeepSearch) {
        products = await _service.getDataset(limit: 5000, proveedor: proveedor);
      } else {
        // ---> CORREGIDO <---
        products = await _service.searchProducts(
          text: '',
          proveedor: proveedor,
        );
      }

      _masterProductsList = List.from(products);

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
