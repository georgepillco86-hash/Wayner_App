import 'package:flutter/foundation.dart' show kIsWeb; // <-- 1. Importado kIsWeb
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/storage/session_storage.dart';
import 'features/auth/models/auth_user.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/saldos/presentation/screens/product_search_screen.dart';
import 'features/saldos/presentation/screens/product_search_controller.dart';
import 'features/scanner/screens/scanner_price_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _requestInitialPermissions();

  final AuthUser? user = await SessionStorage.getUser();

  runApp(FerrotiendaApp(user: user));
}

Future<void> _requestInitialPermissions() async {
  // <-- 2. Si es web, saltamos la petición de permisos nativos
  if (kIsWeb) {
    debugPrint("Ejecutando en Web: Saltando petición de permisos nativos.");
    return;
  }

  await [
    Permission.camera,
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.location,
  ].request();
}

class FerrotiendaApp extends StatelessWidget {
  final AuthUser? user;

  const FerrotiendaApp({super.key, required this.user});

  Widget _buildHome(AuthUser user) {
    if (user.rol.toUpperCase() == 'ESCANER') {
      return const ScannerPriceScreen();
    }

    return const ProductSearchScreen();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProductSearchController()..loadInitialData(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Ferrotienda',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F8B)),
          useMaterial3: true,
        ),
        home: user == null ? const LoginScreen() : _buildHome(user!),
      ),
    );
  }
}
