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

  List<String> classes = [];
  List<String> providers = [];
  List<ProductBalance> products = [];

  String? _lastSearchText;
  String? _lastSearchClass;
  String? _lastSearchProvider;
  bool _initialDataLoaded = false;

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

      selectedClass = null;
      selectedProvider = null;
      _lastSearchText = null;
      _lastSearchClass = null;
      _lastSearchProvider = null;
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

  Future<void> refresh() async {
    _initialDataLoaded = false;
    await loadInitialData(forceRefresh: true);
  }

  Future<void> search(String text) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      await loadDataset(forceRefresh: true, keepFilters: true);
      return;
    }

    if (_lastSearchText == cleanText &&
        _lastSearchClass == selectedClass &&
        _lastSearchProvider == selectedProvider &&
        products.isNotEmpty) {
      return;
    }

    _setLoading(true);
    try {
      products = await _service.searchProducts(
        text: cleanText,
        clase: selectedClass,
        proveedor: selectedProvider,
        limit: 30,
      );

      _lastSearchText = cleanText;
      _lastSearchClass = selectedClass;
      _lastSearchProvider = selectedProvider;
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
    if (!forceRefresh &&
        _lastSearchText == null &&
        selectedClass == null &&
        selectedProvider == null &&
        products.isNotEmpty) {
      return;
    }

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

      _lastSearchText = null;
      _lastSearchClass = null;
      _lastSearchProvider = null;
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
    if (selectedClass == clase && products.isNotEmpty) return;

    selectedClass = clase;
    _lastSearchText = null;
    _lastSearchClass = null;
    _lastSearchProvider = null;

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
      _clearError();
      notifyListeners();
    } catch (e) {
      products = [];
      _setError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> filterByProvider(String? proveedor) async {
    if (selectedProvider == proveedor && products.isNotEmpty) return;

    selectedProvider = proveedor;
    _lastSearchText = null;
    _lastSearchClass = null;
    _lastSearchProvider = null;

    if (selectedClass != null && selectedClass!.isNotEmpty) {
      await filterByClass(selectedClass);
      return;
    }

    await loadDataset(forceRefresh: true, keepFilters: true);
  }

  void _setLoading(bool value) {
    if (isLoading == value) return;
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
      errorMessage = 'Ocurrió un error inesperado. Intenta nuevamente.';
      technicalError = error.toString();
    }
    notifyListeners();
  }
}