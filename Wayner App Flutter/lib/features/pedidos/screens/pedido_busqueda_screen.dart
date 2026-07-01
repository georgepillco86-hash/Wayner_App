import 'package:flutter/material.dart';

import '../models/pedido_item.dart';
import '../services/pedidos_service.dart';
import 'pedido_carrito_screen.dart';
import '../../../screens/scanner/scanner_screen.dart';
import '../../../core/storage/pedido_draft_storage.dart';
import '../../../core/storage/session_storage.dart';

class PedidoBusquedaScreen extends StatefulWidget {
  const PedidoBusquedaScreen({super.key});

  @override
  State<PedidoBusquedaScreen> createState() => _PedidoBusquedaScreenState();
}

class _PedidoBusquedaScreenState extends State<PedidoBusquedaScreen> {
  final PedidosService service = PedidosService();

  final TextEditingController searchController = TextEditingController();
  final TextEditingController secondSearchController = TextEditingController();

  List<String> proveedores = [];

  String? proveedorSeleccionado;
  bool esAdmin = false;

  List<String> unidadesMedida = ['UNIDADES'];

  List<dynamic> resultados = [];
  List<PedidoItem> carrito = [];

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    cargarUnidadesMedida();
    cargarBorradorCarrito();
    cargarSesionYProveedores();
  }

  Future<void> cargarSesionYProveedores() async {
    final user = await SessionStorage.getUser();
    final rol = user?.rol.trim().toUpperCase() ?? "";

    if (!mounted) return;

    setState(() {
      esAdmin = rol == "ADMIN";
    });

    if (!esAdmin) return;

    try {
      final data = await service.obtenerProveedores();

      if (!mounted) return;

      setState(() {
        proveedores = data;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        proveedores = [];
      });
    }
  }

  Future<void> cargarUnidadesMedida() async {
    try {
      final unidades = await service.obtenerUnidadesMedida();

      if (!mounted) return;

      setState(() {
        unidadesMedida = unidades.isEmpty ? ['UNIDADES'] : unidades;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        unidadesMedida = ['UNIDADES'];
      });
    }
  }

  Future<void> buscar(String query) async {
    if (query.trim().length < 2) {
      if (!mounted) return;

      setState(() {
        resultados = [];
        errorMessage = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await service.buscarProductos(
        query.trim(),
        query2: secondSearchController.text.trim(),
        proveedor: esAdmin ? proveedorSeleccionado : null,
      );

      if (!mounted) return;

      setState(() {
        resultados = data;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = "No se pudieron cargar productos para el pedido.";
        resultados = [];
      });
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> buscarPorCodigo(String codigo) async {
    if (codigo.trim().isEmpty) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final producto = await service.getProductoPorCodigo(codigo.trim());

      if (producto.isNotEmpty) {
        await agregarProducto(producto);
      } else {
        if (!mounted) return;

        setState(() {
          errorMessage = "No se encontró el producto escaneado.";
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        errorMessage = "No se pudo consultar el producto escaneado.";
      });
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  void abrirScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          onDetect: (codigo) async {
            await buscarPorCodigo(codigo);
          },
        ),
      ),
    );
  }

  Widget buildProveedorAutocomplete() {
    if (!esAdmin) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 10),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();

            if (query.isEmpty) {
              return proveedores.take(20);
            }

            return proveedores.where(
              (proveedor) => proveedor.toLowerCase().contains(query),
            );
          },
          displayStringForOption: (option) => option,
          onSelected: (String proveedor) {
            setState(() {
              proveedorSeleccionado = proveedor;
            });

            if (searchController.text.trim().length >= 2) {
              buscar(searchController.text);
            }
          },
          fieldViewBuilder: (
            context,
            textEditingController,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'Filtrar por proveedor',
                hintText: 'Escriba el nombre del proveedor',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.local_shipping_outlined),
                suffixIcon: textEditingController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          textEditingController.clear();

                          setState(() {
                            proveedorSeleccionado = null;
                          });

                          if (searchController.text.trim().length >= 2) {
                            buscar(searchController.text);
                          }
                        },
                      ),
              ),
              onChanged: (value) {
                final cleanValue = value.trim();

                setState(() {
                  proveedorSeleccionado = cleanValue.isEmpty ? null : cleanValue;
                });

                if (searchController.text.trim().length >= 2) {
                  buscar(searchController.text);
                }
              },
              onSubmitted: (value) {
                final cleanValue = value.trim();

                setState(() {
                  proveedorSeleccionado = cleanValue.isEmpty ? null : cleanValue;
                });

                if (searchController.text.trim().length >= 2) {
                  buscar(searchController.text);
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 260,
                    maxWidth: 420,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final proveedor = options.elementAt(index);

                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(
                          proveedor,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(proveedor),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> agregarProducto(dynamic item) async {
    final TextEditingController cantidadController =
        TextEditingController(text: "1");

    final TextEditingController notaCompraController =
        TextEditingController();

    String unidadSeleccionada =
        unidadesMedida.isNotEmpty ? unidadesMedida.first : 'UNIDADES';

    String tipoDestinoSeleccionado = "VENTA";

    Map<String, dynamic>? cantidadRecomendada;

    try {
      final codigoProducto = item["codigo"]?.toString() ?? "";

      if (codigoProducto.isNotEmpty) {
        cantidadRecomendada =
            await service.obtenerCantidadRecomendadaProducto(codigoProducto);
      }
    } catch (_) {
      cantidadRecomendada = null;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Agregar al pedido"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item["nombre"]?.toString() ?? "Producto sin nombre",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Código: ${item["codigo"] ?? ""}"),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Marca: ${item["marca"] ?? ""}"),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Stock: ${item["stock_actual"] ?? 0}"),
                    ),
                    if ((item["proveedor"]?.toString() ?? "").isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Proveedor: ${item["proveedor"]}"),
                      ),

                    if (cantidadRecomendada != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Cantidad recomendada",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Últimos 7 días: ${cantidadRecomendada["recomendacion_semanal"] ?? 0} unidades",
                            ),
                            Text(
                              "Promedio semanal según últimos 30 días: ${cantidadRecomendada["recomendacion_mensual"] ?? 0} unidades",
                            ),
                            Text(
                              "Ventas últimos 30 días: ${cantidadRecomendada["ventas_30_dias"] ?? 0} unidades",
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    TextField(
                      controller: cantidadController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Cantidad a pedir",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unidadSeleccionada,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Unidad de medida",
                        border: OutlineInputBorder(),
                      ),
                      items: unidadesMedida.map((unidad) {
                        return DropdownMenuItem<String>(
                          value: unidad,
                          child: Text(unidad),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          unidadSeleccionada = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Destino del producto",
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text("VENTA"),
                          avatar: Icon(
                            Icons.shopping_cart,
                            size: 18,
                            color: tipoDestinoSeleccionado == "VENTA"
                                ? Colors.blue.shade900
                                : null,
                          ),
                          selected: tipoDestinoSeleccionado == "VENTA",
                          selectedColor: Colors.blue.shade100,
                          onSelected: (_) {
                            setDialogState(() {
                              tipoDestinoSeleccionado = "VENTA";
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text("GASTO"),
                          avatar: Icon(
                            Icons.local_fire_department,
                            size: 18,
                            color: tipoDestinoSeleccionado == "GASTO"
                                ? Colors.orange.shade900
                                : null,
                          ),
                          selected: tipoDestinoSeleccionado == "GASTO",
                          selectedColor: Colors.orange.shade100,
                          onSelected: (_) {
                            setDialogState(() {
                              tipoDestinoSeleccionado = "GASTO";
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notaCompraController,
                      maxLines: 3,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: "Nota de compra",
                        hintText: "Nota opcional para este producto",
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, false);
                  },
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  child: const Text("Agregar"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmado != true) {
      return;
    }

    final cantidad = int.tryParse(cantidadController.text.trim()) ?? 1;
    final notaCompra = notaCompraController.text.trim();

    final nuevo = PedidoItem(
      codigo: item["codigo"]?.toString() ?? "",
      nombre: item["nombre"]?.toString() ?? "",
      marca: item["marca"]?.toString() ?? "",
      clase: item["clase"]?.toString(),
      stockActual: double.tryParse(
            (item["stock_actual"] ?? 0).toString(),
          ) ??
          0,
      cantidad: cantidad <= 0 ? 1 : cantidad,
      proveedor: item["proveedor"]?.toString(),
      unidad: unidadSeleccionada,
      notaCompra: notaCompra.isEmpty ? null : notaCompra,
      tipoDestino: tipoDestinoSeleccionado,
    );

    setState(() {
      carrito.add(nuevo);
    });

    await PedidoDraftStorage.save(carrito);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tipoDestinoSeleccionado == "GASTO"
              ? "Producto agregado como GASTO"
              : "Producto agregado como VENTA",
        ),
      ),
    );
  }

  Future<void> abrirCarrito() async {
    final enviado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoCarritoScreen(carrito: carrito),
      ),
    );

    if (enviado == true) {
      await PedidoDraftStorage.clear();

      setState(() {
        carrito.clear();
        resultados.clear();
        searchController.clear();
        secondSearchController.clear();
        proveedorSeleccionado = null;
      });
    } else {
      await PedidoDraftStorage.save(carrito);
      setState(() {});
    }
  }

  Future<void> cargarBorradorCarrito() async {
    final borrador = await PedidoDraftStorage.load();

    if (!mounted || borrador.isEmpty) return;

    setState(() {
      carrito = borrador;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Se restauró un borrador con ${borrador.length} producto(s)",
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    secondSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Realizar Pedido"),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: "Escanear código",
            onPressed: abrirScanner,
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            tooltip: "Ver carrito",
            onPressed: abrirCarrito,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: "Buscar producto, código, marca o clase",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: buscar,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: secondSearchController,
                  decoration: const InputDecoration(
                    hintText: "Refinar búsqueda opcional",
                    prefixIcon: Icon(Icons.filter_alt),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (searchController.text.trim().length >= 2) {
                      buscar(searchController.text);
                    }
                  },
                ),
                buildProveedorAutocomplete(),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: resultados.isEmpty && !isLoading
                ? const Center(
                    child: Text(
                      "Busca o escanea un producto para agregar al pedido",
                    ),
                  )
                : ListView.builder(
                    itemCount: resultados.length,
                    itemBuilder: (_, i) {
                      final item = resultados[i];

                      final proveedor =
                          item["proveedor"]?.toString().trim() ?? "";

                      return ListTile(
                        title: Text(
                          item["nombre"]?.toString() ?? "Sin nombre",
                        ),
                        subtitle: Text(
                          "Código: ${item["codigo"] ?? ""}\n"
                          "Marca: ${item["marca"] ?? ""} | "
                          "Stock: ${item["stock_actual"] ?? 0}"
                          "${proveedor.isNotEmpty ? "\nProveedor: $proveedor" : ""}",
                        ),
                        isThreeLine: proveedor.isNotEmpty,
                        trailing: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => agregarProducto(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}