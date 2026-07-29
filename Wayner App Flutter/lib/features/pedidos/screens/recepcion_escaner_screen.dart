import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Importa tu escáner existente
import '../../saldos/presentation/screens/barcode_scanner_screen.dart';

class RecepcionEscanerScreen extends StatefulWidget {
  final int pedidoId;
  final int documentoId;

  const RecepcionEscanerScreen({
    super.key,
    required this.pedidoId,
    required this.documentoId,
  });

  @override
  State<RecepcionEscanerScreen> createState() => _RecepcionEscanerScreenState();
}

class _RecepcionEscanerScreenState extends State<RecepcionEscanerScreen> {
  bool isLoading = true;
  String? errorMessage;

  String proveedor = "";
  List<dynamic> itemsEsperados = [];
  List<dynamic> itemsExtra = [];

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final url = Uri.parse(
        "http://192.168.2.79:5000/api/pedidos/rpa/comparar-xml-orden/${widget.documentoId}",
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['success'] == true) {
          final data = res['data'];
          setState(() {
            proveedor = data['proveedor'];
            itemsEsperados = List<dynamic>.from(data['items_esperados']);
            itemsExtra = List<dynamic>.from(data['items_no_solicitados']);
          });
        } else {
          errorMessage = res['error'] ?? "Error desconocido en el servidor";
        }
      } else {
        errorMessage = "Error de red: ${response.statusCode}";
      }
    } catch (e) {
      errorMessage = "No se pudo conectar con el servidor: $e";
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // 🔥 Función para abrir la cámara y sumar cantidades
  Future<void> iniciarEscaneo() async {
    final String? codigoEscaneado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (codigoEscaneado != null && codigoEscaneado.isNotEmpty) {
      final soloNumeros = codigoEscaneado.replaceAll(RegExp(r'[^0-9]'), '');
      procesarCodigoEscaneado(soloNumeros);
    }
  }

  void procesarCodigoEscaneado(String codigo) {
    bool encontrado = false;

    setState(() {
      for (var item in itemsEsperados) {
        if (item['codigo_producto'].toString() == codigo) {
          item['cantidad_escaneada'] = (item['cantidad_escaneada'] ?? 0) + 1;
          encontrado = true;
          break;
        }
      }
    });

    if (!encontrado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("El código $codigo no pertenece a esta orden."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 🔥 Convierte un item no solicitado en uno esperado
  void aceptarItemExtra(Map<String, dynamic> extra) {
    setState(() {
      itemsExtra.remove(extra);

      // Lo transformamos al formato de los esperados
      itemsEsperados.add({
        "item_id":
            0, // 0 indica que es un item nuevo (extra) no pedido originalmente
        "codigo_producto": extra['codigo_xml'],
        "nombre_producto": extra['descripcion_xml'],
        "cantidad_pedida": 0.0, // No se pidió originalmente
        "cantidad_xml": extra['cantidad_xml'],
        "cantidad_escaneada": 0,
        "coincidencia_xml": true,
        "descripcion_facturada": extra['descripcion_xml'],
        "es_ingreso_extra": true, // Flag para UI
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Producto añadido a la orden de ingreso."),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> finalizarRecepcion() async {
    // Aquí implementaremos en el futuro la llamada al backend para
    // guardar las cantidades finales escaneadas.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Enviando resultados de la recepción al backend..."),
        backgroundColor: Colors.blue,
      ),
    );
    Navigator.pop(context);
  }

  Widget _buildItemEsperado(Map<String, dynamic> item) {
    final double pedido = (item['cantidad_pedida'] ?? 0).toDouble();
    final double xml = (item['cantidad_xml'] ?? 0).toDouble();
    final int escaneado = item['cantidad_escaneada'] ?? 0;
    final bool esExtra = item['es_ingreso_extra'] == true;

    // Lógica de colores según el progreso de escaneo
    Color bgColor = Colors.white;
    Color borderColor = Colors.grey.shade300;

    if (escaneado > 0) {
      if (escaneado == xml) {
        bgColor = Colors.green.shade50;
        borderColor = Colors.green;
      } else if (escaneado > xml) {
        bgColor = Colors.red.shade50;
        borderColor = Colors.red;
      } else {
        bgColor = Colors.yellow.shade50;
        borderColor = Colors.orange;
      }
    }

    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (esExtra)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "INGRESO EXTRA",
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              item['nombre_producto'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              "CÓDIGO: ${item['codigo_producto']}",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    const Text(
                      "Pedido",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      pedido.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text(
                      "XML Factura",
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                    Text(
                      xml.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text(
                      "Físico",
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                    Text(
                      "$escaneado",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Controles manuales (por si el código de barras no lee)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                  onPressed: () {
                    if (escaneado > 0) {
                      setState(() {
                        item['cantidad_escaneada'] = escaneado - 1;
                      });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.green,
                  ),
                  onPressed: () {
                    setState(() {
                      item['cantidad_escaneada'] = escaneado + 1;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemExtra(Map<String, dynamic> extra) {
    return Card(
      color: Colors.grey.shade100,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange,
          size: 30,
        ),
        title: Text(
          extra['descripcion_xml'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Cod: ${extra['codigo_xml']} | Cant: ${extra['cantidad_xml']}",
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          onPressed: () => aceptarItemExtra(extra),
          child: const Text("Aceptar"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Escáner de Recepción"),
          bottom: TabBar(
            tabs: [
              Tab(text: "Esperados (${itemsEsperados.length})"),
              Tab(
                child: Badge(
                  isLabelVisible: itemsExtra.isNotEmpty,
                  label: Text("${itemsExtra.length}"),
                  child: const Text("Extras (No Pedidos)"),
                ),
              ),
            ],
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? Center(
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : TabBarView(
                children: [
                  // PESTAÑA 1: PRODUCTOS ESPERADOS
                  ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: itemsEsperados.length,
                    itemBuilder: (context, index) {
                      return _buildItemEsperado(itemsEsperados[index]);
                    },
                  ),

                  // PESTAÑA 2: PRODUCTOS EXTRA (NO SOLICITADOS)
                  itemsExtra.isEmpty
                      ? const Center(
                          child: Text(
                            "No hay productos extras en la factura.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: itemsExtra.length,
                          itemBuilder: (context, index) {
                            return _buildItemExtra(itemsExtra[index]);
                          },
                        ),
                ],
              ),
        floatingActionButton: isLoading
            ? null
            : FloatingActionButton.extended(
                onPressed: iniciarEscaneo,
                icon: const Icon(Icons.barcode_reader),
                label: const Text("Escanear Caja"),
                backgroundColor: Colors.blue.shade900,
                foregroundColor: Colors.white,
              ),
        bottomNavigationBar: isLoading
            ? null
            : Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: finalizarRecepcion,
                  child: const Text(
                    "COMPLETAR RECEPCIÓN",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
      ),
    );
  }
}
