import 'package:flutter/material.dart';

import '../../../core/storage/session_storage.dart';
import '../../saldos/presentation/screens/product_search_screen.dart';
import '../../scanner/screens/scanner_price_screen.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService authService = AuthService();

  final TextEditingController usuarioController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool ocultarPassword = true;
  bool biometricAvailable = false;
  bool biometricEnabled = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _cargarEstadoBiometria();
  }

  Future<void> _cargarEstadoBiometria() async {
    final available = await BiometricAuthService.isAvailable();
    final enabled = await BiometricAuthService.isEnabled();

    if (!mounted) return;

    setState(() {
      biometricAvailable = available;
      biometricEnabled = enabled;
    });
  }

  void _goToHome(AuthUser user) {
    if (user.rol.toUpperCase() == 'ESCANER') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ScannerPriceScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ProductSearchScreen(),
        ),
      );
    }
  }

  Future<void> login() async {
    final usuario = usuarioController.text.trim();
    final password = passwordController.text.trim();

    if (usuario.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = "Ingresa usuario y contraseña";
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    AuthUser? user;

    try {
      user = await authService.login(
        nombreUsuario: usuario,
        password: password,
      );

      await SessionStorage.saveUser(user);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = "Usuario o contraseña incorrectos";
        isLoading = false;
      });

      return;
    }

    if (!mounted) return;

    if (biometricAvailable && !biometricEnabled) {
      final activar = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Activar ingreso con huella'),
            content: const Text(
              '¿Deseas activar el ingreso con huella para entrar más rápido la próxima vez?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Ahora no'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Activar'),
              ),
            ],
          );
        },
      );

      if (activar == true) {
        try {
          final authenticated = await BiometricAuthService.authenticate();

          if (authenticated) {
            await BiometricAuthService.enableBiometricLogin(
              userData: user.toJson(),
            );

            if (mounted) {
              setState(() {
                biometricEnabled = true;
              });
            }
          }
        } catch (e) {
          debugPrint('Error activando biometría: $e');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No se pudo activar la huella, pero el ingreso fue correcto.',
                ),
              ),
            );
          }
        }
      }
    }

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    _goToHome(user);
  }

  Future<void> loginConHuella() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final authenticated = await BiometricAuthService.authenticate();

      if (!authenticated) {
        setState(() {
          errorMessage = 'No se pudo validar la huella';
        });
        return;
      }

      final savedData = await BiometricAuthService.getSavedUserData();

      if (savedData == null) {
        await BiometricAuthService.disableBiometricLogin();

        if (!mounted) return;

        setState(() {
          biometricEnabled = false;
          errorMessage = 'No existe una sesión biométrica guardada';
        });

        return;
      }

      final user = AuthUser.fromJson(savedData);

      await SessionStorage.saveUser(user);

      if (!mounted) return;
      _goToHome(user);
    } catch (e) {
      setState(() {
        errorMessage = 'Error al ingresar con huella';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    usuarioController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1F6F8B);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/wyner_logo.png',
                        height: 90,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) {
                          return const Icon(
                            Icons.storefront,
                            size: 64,
                            color: primaryColor,
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Ferrotienda",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text("Ingreso de trabajadores"),
                      const SizedBox(height: 24),

                      TextField(
                        controller: usuarioController,
                        decoration: const InputDecoration(
                          labelText: "Nombre de usuario",
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextField(
                        controller: passwordController,
                        obscureText: ocultarPassword,
                        decoration: InputDecoration(
                          labelText: "Contraseña",
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              ocultarPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                ocultarPassword = !ocultarPassword;
                              });
                            },
                          ),
                        ),
                        onSubmitted: (_) => login(),
                      ),

                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : login,
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            isLoading ? "Ingresando..." : "Ingresar",
                          ),
                        ),
                      ),

                      if (biometricAvailable && biometricEnabled) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: isLoading ? null : loginConHuella,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Ingresar con huella'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}