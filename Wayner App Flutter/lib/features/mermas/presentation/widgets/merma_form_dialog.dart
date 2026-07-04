import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/models/merma_model.dart';
import '../../data/services/merma_service.dart';
import '../../../saldos/data/services/saldos_api_service.dart';
import '../../../saldos/data/models/product_balance.dart';
import '../../../saldos/presentation/screens/barcode_scanner_screen.dart';

class MermaFormDialog extends StatefulWidget {
  final Merma? merma;
  final VoidCallback onSave;

  const MermaFormDialog({super.key, this.merma, required this.onSave});

  @override
  State<MermaFormDialog> createState() => _MermaFormDialogState();
}

class _MermaFormDialogState extends State<MermaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _mermaService = MermaService();
  final _saldosService = SaldosApiService(); // Instancia para buscar productos

  final _codigoController = TextEditingController();
  final _nombreController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _comentarioController = TextEditingController();

  String? _novedadSeleccionada;
  final List<String> _opcionesNovedad = [
    'Producto Expirado',
    'Producto con envase comprometido',
    'Producto contaminado',
    'Producto no requerido',
    'Rebate',
  ];

  bool _isSaving = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.merma != null) {
      _codigoController.text = widget.merma!.codigo;
      _nombreController.text = widget.merma!.nombreProducto;
      _cantidadController.text = widget.merma!.cantidad.toString();
      _comentarioController.text = widget.merma!.comentario ?? '';

      _novedadSeleccionada = widget.merma!.novedad;
      // Si la novedad guardada no está en la lista (registros viejos), la agregamos
      if (!_opcionesNovedad.contains(_novedadSeleccionada)) {
        _opcionesNovedad.add(_novedadSeleccionada!);
      }
    }
  }

  // --- FUNCIÓN PARA ABRIR LA CÁMARA ---
  Future<void> _abrirEscaner(
    TextEditingController autocompleteController,
  ) async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      if (!mounted) return;
      final code = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      );

      if (code != null && code.isNotEmpty && mounted) {
        // Llenar el campo visual y la variable de control
        autocompleteController.text = code;
        _codigoController.text = code;

        // Buscar el producto en la BD para autocompletar el nombre
        setState(() => _isSearching = true);
        try {
          final producto = await _saldosService.getProductByCode(code);
          if (producto != null) {
            setState(() {
              _nombreController.text = producto.nombre;
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Código escaneado no encontrado en el sistema'),
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _isSearching = false);
          }
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se requiere permiso de cámara para escanear'),
        ),
      );
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_codigoController.text.isEmpty) return;

    FocusScope.of(context).unfocus(); // Ocultar teclado
    setState(() => _isSaving = true);

    if (widget.merma == null) {
      final nuevaMerma = Merma(
        codigo: _codigoController.text,
        nombreProducto: _nombreController.text,
        cantidad: double.parse(_cantidadController.text),
        novedad: _novedadSeleccionada!,
        comentario: _comentarioController.text,
        estado: 'Pendiente',
        usuario: '', // Se llenará automáticamente en el backend vía Headers
        activo: true,
      );
      await _mermaService.crearMerma(nuevaMerma);
    } else {
      await _mermaService.actualizarMerma(widget.merma!.id!, {
        'cantidad': double.parse(_cantidadController.text),
        'novedad': _novedadSeleccionada,
        'comentario': _comentarioController.text,
      });
    }

    widget.onSave();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.merma != null;

    return AlertDialog(
      title: Text(esEdicion ? 'Modificar Registro' : 'Registrar Nueva Merma'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- 1. AUTOCOMPLETADO Y ESCÁNER ---
                Autocomplete<ProductBalance>(
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    if (textEditingValue.text.length < 3) {
                      return const Iterable<ProductBalance>.empty();
                    }
                    try {
                      final results = await _saldosService.searchProducts(
                        text: textEditingValue.text,
                        limit: 10,
                      );
                      return results;
                    } catch (e) {
                      return const Iterable<ProductBalance>.empty();
                    }
                  },
                  displayStringForOption: (ProductBalance option) =>
                      option.codigo,
                  onSelected: (ProductBalance selection) {
                    _codigoController.text = selection.codigo;
                    _nombreController.text = selection.nombre;
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                        if (esEdicion && controller.text.isEmpty) {
                          controller.text = widget.merma!.codigo;
                        }
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Código / Últimos dígitos',
                            // --- AQUÍ REGRESA EL BOTÓN DEL ESCÁNER ---
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Escanear con cámara',
                              onPressed: esEdicion
                                  ? null
                                  : () => _abrirEscaner(controller),
                            ),
                          ),
                          enabled: !esEdicion,
                          onChanged: (val) => _codigoController.text = val,
                          validator: (v) => v!.isEmpty ? 'Requerido' : null,
                        );
                      },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 250,
                            maxWidth: 300,
                          ),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                title: Text(
                                  option.codigo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  option.nombre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // --- 2. NOMBRE DEL PRODUCTO ---
                TextFormField(
                  controller: _nombreController,
                  decoration: InputDecoration(
                    labelText: 'Nombre del Producto',
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  enabled: false,
                  validator: (v) =>
                      v!.isEmpty ? 'Seleccione un producto' : null,
                ),
                const SizedBox(height: 12),

                // --- 3. CANTIDAD ---
                TextFormField(
                  controller: _cantidadController,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  keyboardType: TextInputType.number,
                  validator: (v) => double.tryParse(v ?? '') == null
                      ? 'Ingrese un número válido'
                      : null,
                ),
                const SizedBox(height: 12),

                // --- 4. CONDICIÓN (MENÚ DESPLEGABLE) ---
                DropdownButtonFormField<String>(
                  value: _novedadSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Condición (Novedad)',
                  ),
                  isExpanded: true,
                  items: _opcionesNovedad.map((String val) {
                    return DropdownMenuItem(
                      value: val,
                      child: Text(val, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _novedadSeleccionada = val;
                    });
                  },
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Seleccione una opción' : null,
                ),
                const SizedBox(height: 12),

                // --- 5. COMENTARIO ---
                TextFormField(
                  controller: _comentarioController,
                  decoration: const InputDecoration(
                    labelText: 'Comentario Opcional',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.pop(context);
          },
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _guardar,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
