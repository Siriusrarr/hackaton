import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

part 'empresa.dart';

void main() => runApp(const FacturinApp());

typedef Json = Map<String, dynamic>;

const backend = String.fromEnvironment(
  'API_BASE',
  defaultValue: '',
);

final api = Api();

class Api {
  String? session;

  Future<Json> request(
    String path, {
    Json? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.base.resolve('$backend$path').replace(queryParameters: query);
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer $session',
    };

    final http.Response response;
    try {
      response = body == null
          ? await http.get(uri, headers: headers)
          : await http.post(uri, headers: headers, body: jsonEncode(body));
    } on http.ClientException {
      throw Exception('No se pudo conectar con el servidor de Facturín. '
          'Comprueba que backend/server.mjs esté ejecutándose.');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded is Map
          ? decoded['message'] ?? 'HTTP ${response.statusCode}'
          : 'HTTP ${response.statusCode}');
    }
    return Json.from(decoded as Map);
  }

  Future<void> login(String email, String password) async {
    final result = await request('/session', body: {
      'email': email.trim(),
      'password': password,
    });
    session = result['session'] as String;
  }

  Future<void> logout() async {
    try {
      await request('/logout', body: {});
    } finally {
      session = null;
    }
  }
}

List<Json> rows(Json response) {
  dynamic data = response['data'];
  if (data is Map) data = data['data'];
  if (data is! List) return [];
  return data.whereType<Map>().map((v) => Json.from(v)).toList();
}

String message(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception: '), '');

class ErrorText extends StatelessWidget {
  const ErrorText(this.value, {super.key});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SelectableText(
        value,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

enum DocumentKind {
  invoice('Factura de venta', '21', 'bills'),
  credit('Nota crédito', '22', 'credit-notes'),
  support('Documento soporte', '24', 'support-documents'),
  adjustment('Nota de ajuste', '25', 'adjustment-notes');

  const DocumentKind(this.label, this.rangeCode, this.route);

  final String label;
  final String rangeCode;
  final String route;

  bool get supplier => this == support || this == adjustment;
  bool get correction => this == credit || this == adjustment;
}

class FacturinApp extends StatelessWidget {
  const FacturinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Facturín',
      builder: (context, child) => Stack(fit: StackFit.expand, children: [
        const RepaintBoundary(child: CustomPaint(painter: JardinAero())),
        if (child != null) child,
      ]),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: aquaAero,
          primary: azulAero,
          secondary: const Color(0xff537900),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          backgroundColor: const Color(0xff103e49),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xfffcfefd),
          elevation: 2,
          shadowColor: const Color(0x55004778),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xff91b0b0))),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(text: 'sandboxv2@factus.com.co');
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });

    try {
      await api.login(email.text, password.text);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AeroHero(
                  titulo: 'Facturín',
                  detalle: 'Facturación y recaudos · Sandbox',
                  icono: Icons.public,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo de facturación'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  onSubmitted: (_) => login(),
                  decoration: const InputDecoration(labelText: 'Clave privada de la demo'),
                ),
                if (error != null) ErrorText(error!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : login,
                  child: Text(busy ? 'Conectando…' : 'Ingresar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final search = TextEditingController();
  List<Json> bills = [];
  int page = 1;
  int lastPage = 1;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load(1);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load(int target) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.request('/v2/bills', query: {
        'page': '$target',
        if (search.text.trim().isNotEmpty) 'filter[names]': search.text.trim(),
      });
      final data = result['data'];
      final pagination = data is Map
          ? data['pagination'] ?? result['pagination']
          : result['pagination'];
      if (!mounted) return;
      setState(() {
        bills = rows(result);
        page = target;
        lastPage = pagination is Map
            ? int.tryParse('${pagination['last_page']}') ?? target
            : target;
        if (lastPage < 1) lastPage = 1;
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openForm(DocumentKind kind, {bool rapida = false}) async {
    final issued = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DocumentPage(kind: kind, rapida: rapida)),
    );
    if (mounted && issued == true) await load(1);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {
      // El cliente limpia la sesión local incluso si el servidor no responde.
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturín · Sandbox'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PortadaFacturacion(onEmitir: () => openForm(DocumentKind.invoice, rapida: true)),
              const SizedBox(height: 18),
              AccesoPanel(ancho: double.infinity, icono: Icons.inventory_2_outlined, titulo: 'Inventario',
                detalle: 'Productos, existencias y movimientos',
                onAbrir: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventarioPage()))),
              const SizedBox(height: 10),              LayoutBuilder(builder: (context, constraints) {
                final ancho = constraints.maxWidth >= 580 ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                return Wrap(spacing: 12, runSpacing: 10, children: [
                  AccesoPanel(ancho: ancho, icono: Icons.people_outline, titulo: 'Clientes',
                    detalle: 'Directorio y datos de contacto',
                    onAbrir: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientesPage()))),
                  AccesoPanel(ancho: ancho, icono: Icons.insights_outlined, titulo: 'Mi empresa',
                    detalle: 'Catálogo, recaudos e IVA del mes',
                    onAbrir: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmpresaPage()))),
                ]);
              }),
              const SizedBox(height: 14),
              Card(child: ExpansionTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: const Text('Documentos electrónicos'),
                subtitle: const Text('Factura completa, notas y documento soporte'),
                children: [
                  for (final kind in DocumentKind.values)
                    ListTile(title: Text(kind.label), trailing: const Icon(Icons.chevron_right),
                      onTap: () => openForm(kind)),
                ],
              )),
              const SizedBox(height: 24),
              Text('Facturas emitidas', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                onSubmitted: (_) => load(1),
                decoration: InputDecoration(
                  labelText: 'Buscar por nombre del cliente',
                  suffixIcon: IconButton(
                    onPressed: busy ? null : () => load(1),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null) ErrorText(error!),
              if (!busy && error == null && bills.isEmpty)
                const ListTile(title: Text('No se encontraron facturas.')),
              for (final bill in bills)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text('${bill['number'] ?? 'Sin número'}'),
                    subtitle: Text('${bill['names'] ?? bill['reference_code'] ?? ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: bill['number'] == null ? null : () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => BillPage(number: '${bill['number']}'),
                      ));
                    },
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: busy || page <= 1 ? null : () => load(page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Página $page de $lastPage'),
                  IconButton(
                    onPressed: busy || page >= lastPage ? null : () => load(page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              TextButton(
                onPressed: busy ? null : () => load(page),
                child: const Text('Actualizar listado'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Item {
  String? sku;
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();
  final tax = TextEditingController(text: '19');

  int get units => int.tryParse(quantity.text.trim()) ?? 0;

  static int cents(String value) {
    final text = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(text)) return 0;
    final parts = text.split('.');
    final decimals = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    return (int.tryParse(parts[0]) ?? 0) * 100 + (int.tryParse(decimals) ?? 0);
  }

  static String decimal(int value) =>
      '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

  int get total {
    final base = units * cents(price.text);
    final iva = (base * cents(tax.text) + 5000) ~/ 10000;
    return base + iva;
  }

  Json toJson(int index) => {
    'code_reference': sku == null ? 'ITEM-${index + 1}' : 'INV-$sku',
    'name': name.text.trim(),
    'quantity': units,
    'price': decimal(cents(price.text)),
    'discount_rate': '0.00',
    'unit_measure_code': '94',
    'standard_code': '999',
    'taxes': [
      {'code': '01', 'rate': decimal(cents(tax.text))},
    ],
  };

  void dispose() {
    for (final c in [name, quantity, price, tax]) {
      c.dispose();
    }
  }
}

class DocumentPage extends StatefulWidget {
  const DocumentPage({super.key, required this.kind, this.rapida = false});
  final bool rapida;
  final DocumentKind kind;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  final form = GlobalKey<FormState>();
  final id = TextEditingController();
  final dv = TextEditingController();
  final name = TextEditingController();
  final address = TextEditingController();
  final email = TextEditingController();
  final city = TextEditingController();
  final original = TextEditingController();
  final telefono = TextEditingController();
  final items = [Item()];
  final reference = 'HACK-${DateTime.now().microsecondsSinceEpoch}';

  List<Json> ranges = [];
  int? rangeId;
  String documentType = '13';
  String organization = '2';
  String concept = '1';
  String paymentForm = '1';
  String method = '10';
  bool finalConsumer = false;
  bool busy = false;
  bool loadingRanges = true;
  String? error;

  int get total => items.fold<int>(0, (sum, item) => sum + item.total);

  @override
  void initState() {
    super.initState();
    loadRanges();
  }

  @override
  void dispose() {
    for (final c in [id, dv, name, address, email, city, original, telefono]) {
      c.dispose();
    }
    for (final item in items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> loadRanges() async {
    setState(() {
      loadingRanges = true;
      error = null;
    });
    try {
      final result = await api.request('/v2/numbering-ranges', query: {
        'filter[document]': widget.kind.rangeCode,
        'filter[is_active]': '1',
      });
      final available = rows(result).where((r) =>
          r['is_expired'] != true &&
          r['deleted_at'] == null &&
          int.tryParse('${r['id']}') != null).toList();

      if (!mounted) return;
      setState(() {
        ranges = available;
        rangeId = ranges.isEmpty ? null : int.parse('${ranges.first['id']}');
        if (ranges.isEmpty) {
          error = 'No se encontró un rango activo para ${widget.kind.label}.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => loadingRanges = false);
    }
  }

  Future<void> agregarDesdeCatalogo() async {
    try {
      final servicios = rows(await api.request('/inventario/catalogo'));
      if (!mounted) return;

      if (servicios.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agrega un producto en Inventario o un servicio en Mi empresa.')),
        );
        return;
      }

      final elegido = await showModalBottomSheet<Json>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Productos y servicios', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 10),
              for (final servicio in servicios)
                ListTile(
                  leading: Icon(servicio['sku'] == null ? Icons.design_services : Icons.inventory_2_outlined),
                  title: Text(servicio['sku'] == null ? '${servicio['nombre']}' : '${servicio['nombre']} · ${servicio['disponible']} disp.'),
                  subtitle: Text(
                    '${pesos(servicio['precio'])} antes de IVA · IVA ${servicio['iva']}%',
                  ),
                  onTap: servicio['sku'] != null && widget.kind == DocumentKind.invoice && servicio['disponible'] == 0 ? null : () => Navigator.pop(ctx, servicio),
                ),
            ],
          ),
        ),
      );

      if (!mounted || elegido == null) return;
      setState(() {
        final vacio = items.length == 1 &&
            items.first.name.text.trim().isEmpty &&
            items.first.price.text.trim().isEmpty;
        final reemplazar = vacio || widget.rapida;
        final item = reemplazar ? items.first : Item();
        item.sku = elegido['sku'] as String?;
        item.name.text = '${elegido['nombre']}';
        item.quantity.text = '1';
        item.price.text = (elegido['precio'] as num).toStringAsFixed(2);
        item.tax.text = (elegido['iva'] as num).toStringAsFixed(2);
        if (!reemplazar) items.add(item);
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
  }

  String? requiredText(String? value) =>
      (value ?? '').trim().isEmpty ? 'Campo obligatorio' : null;

  String? decimalValidator(String? value, {bool tax = false}) {
    final text = (value ?? '').trim();
    if (!RegExp(r'^\d{1,9}([.,]\d{1,2})?$').hasMatch(text)) {
      return 'Escribe un valor con máximo dos decimales';
    }
    final amount = Item.cents(text);
    if (tax && amount > 10000) return 'El IVA debe estar entre 0 y 100';
    if (!tax && amount <= 0) return 'El precio debe ser mayor que cero';
    return null;
  }

  Widget field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validate,
    TextInputType keyboard = TextInputType.text,
    bool updateTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: validate ?? requiredText,
        onChanged: updateTotal ? (_) => setState(() {}) : null,
      ),
    );
  }

  Widget choice(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> update,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => update(v));
        },
      ),
    );
  }

  Future<void> prepararComercial(Plantilla tipo) async {
    if (busy || !form.currentState!.validate()) return;
    final lineas = [for (var i = 0; i < items.length; i++) items[i].toJson(i)];
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentoComercial(
      tipo: tipo, referencia: reference, cliente: party(), lineas: lineas,
      total: total / 100,
    )));
  }

  Widget documentosPrevios({bool habilitado = true}) => Wrap(spacing: 8, children: [
    for (final tipo in [Plantilla.cotizacion, Plantilla.orden])
      OutlinedButton(onPressed: busy || !habilitado ? null : () => prepararComercial(tipo),
        child: Text(tipo.titulo)),
  ]);

  Widget facturaRapida() {
    final item = items.first;
    final seleccionado = item.name.text.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Factura rápida')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: Form(key: form, child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AeroHero(titulo: 'Factura rápida', detalle: 'Una unidad del catálogo · Persona natural', icono: Icons.bolt),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : agregarDesdeCatalogo,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(seleccionado ? 'Cambiar producto o servicio' : 'Elegir producto o servicio'),
            ),
            if (seleccionado) Card(child: ListTile(
              title: Text(item.name.text),
              subtitle: Text('Precio: ${pesos(Item.cents(item.price.text) / 100)} · IVA ${item.tax.text}%'),
              trailing: Text(pesos(total / 100)),
            )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.contacts), label: const Text('Elegir cliente registrado'),
              onPressed: busy ? null : () async {
                final cliente = await Navigator.push<Json>(context,
                  MaterialPageRoute(builder: (_) => const ClientesPage(elegir: true)));
                if (cliente == null || !mounted) return;
                setState(() {
                  documentType = cliente['tipo'];
                  name.text = cliente['nombre'];
                  id.text = cliente['documento'];
                  telefono.text = cliente['telefono'];
                });
              },
            ),
            field('Nombre completo', name),
            choice('Tipo de documento', documentType, {
              '13': 'Cédula de ciudadanía', '22': 'Cédula de extranjería', '41': 'Pasaporte',
            }, (v) => documentType = v),
            field('Número de documento', id),
            field('Teléfono', telefono, keyboard: TextInputType.phone, validate: (v) {
              final text = (v ?? '').trim();
              final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
              return RegExp(r'^\+?[0-9 ()-]+$').hasMatch(text) && digits.length >= 7 && digits.length <= 15
                  ? null : 'Escribe un teléfono válido';
            }),
            choice('Método de pago · Contado', method, {
              '10': 'Efectivo', '47': 'Transferencia', '48': 'Tarjeta crédito', '49': 'Tarjeta débito',
            }, (v) => method = v),
            if (loadingRanges) const LinearProgressIndicator(),
            if (ranges.length > 1) DropdownButtonFormField<int>(
              initialValue: rangeId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Rango de numeración'),
              items: [for (final r in ranges) DropdownMenuItem(
                value: int.parse('${r['id']}'), child: Text('${r['prefix']} · ${r['id']}'),
              )], onChanged: busy ? null : (v) => setState(() => rangeId = v),
            ),
            if (!loadingRanges && rangeId == null)
              TextButton(onPressed: loadRanges, child: const Text('Recargar rangos')),
            if (error != null) ErrorText(error!),
            documentosPrevios(habilitado: seleccionado),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy || !seleccionado || rangeId == null ? null : submit,
              icon: const Icon(Icons.receipt_long),
              label: Text(busy ? 'Emitiendo…' : 'Emitir en sandbox · ${pesos(total / 100)}'),
            ),
          ],
        )),
      )),
    );
  }

  Json party() {
    if (widget.rapida) {
      return {
        'legal_organization_code': '2',
        'identification_document_code': documentType,
        'identification': id.text.trim(),
        'names': name.text.trim(),
        'phone': telefono.text.replaceAll(RegExp(r'[^0-9]'), ''),
      };
    }
    if (finalConsumer && widget.kind == DocumentKind.invoice) {
      return {
        'identification_document_code': '13',
        'identification': '22222222222',
        'names': 'Consumidor Final',
      };
    }

    return {
      'identification_document_code': documentType,
      'identification': id.text.trim(),
      if (documentType == '31') 'dv': dv.text.trim(),
      'legal_organization_code': organization,
      if (organization == '1') 'company': name.text.trim(),
      if (organization == '2' || widget.kind.supplier) 'names': name.text.trim(),
      'address': address.text.trim(),
      'country_code': 'CO',
      'municipality_code': city.text.trim(),
      if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
      if (!widget.kind.supplier) 'tribute_code': 'ZZ',
      if (!widget.kind.supplier) 'responsibilities': ['R-99-PN'],
    };
  }

  Json payload() {
    final kind = widget.kind;
    final due = DateTime.now().add(const Duration(days: 30));

    return {
      'reference_code': reference,
      'numbering_range_id': rangeId,
      if (kind == DocumentKind.invoice) 'document': '01',
      if (kind == DocumentKind.credit) ...{
        'customization_id': '20',
        'bill_number': original.text.trim(),
      },
      if (kind == DocumentKind.adjustment)
        'support_document_number': original.text.trim(),
      if (kind.correction) 'correction_concept_code': concept,
      (kind.supplier ? 'provider' : 'customer'): party(),
      'payment_details': [
        {
          'payment_form': paymentForm,
          'payment_method_code': method,
          'amount': Item.decimal(total),
          if (paymentForm == '2')
            'due_date': due.toIso8601String().substring(0, 10),
        },
      ],
      'items': [
        for (var i = 0; i < items.length; i++) items[i].toJson(i),
      ],
    };
  }

  Future<void> submit() async {
    if (busy || rangeId == null || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result = await api.request(
        '/v2/${widget.kind.route}/validate',
        body: payload(),
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${widget.kind.label} · Sandbox'),
          content: SelectableText(
            '${result['message'] ?? 'Solicitud aceptada'}\n\nReferencia: $reference',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    if (widget.rapida) return facturaRapida();
    final titleStyle = Theme.of(context).textTheme.titleLarge;

    return Scaffold(
      appBar: AppBar(title: Text(kind.label)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (loadingRanges) const LinearProgressIndicator(),
                DropdownButtonFormField<int>(
                  key: ValueKey('rango-${rangeId ?? 0}'),
                  initialValue: rangeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Rango de numeración'),
                  items: [
                    for (final r in ranges)
                      DropdownMenuItem(
                        value: int.parse('${r['id']}'),
                        child: Text('${r['prefix']} · ${r['document']}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => rangeId = v),
                ),
                if (!loadingRanges && ranges.isEmpty)
                  TextButton(onPressed: loadRanges, child: const Text('Recargar rangos')),
                const SizedBox(height: 16),

                if (kind.correction) ...[
                  field(
                    kind == DocumentKind.credit
                        ? 'Número de factura original'
                        : 'Número del documento soporte original',
                    original,
                  ),
                  choice('Motivo', concept, {
                    '1': 'Devolución parcial',
                    '2': 'Anulación',
                    '3': 'Descuento',
                  }, (v) => concept = v),
                ],

                Text(kind.supplier ? 'Proveedor' : 'Cliente', style: titleStyle),
                const SizedBox(height: 10),

                if (kind == DocumentKind.invoice)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Facturar a consumidor final'),
                    value: finalConsumer,
                    onChanged: (v) => setState(() => finalConsumer = v),
                  ),

                if (!finalConsumer) ...[
                  choice('Tipo de documento', documentType, {
                    '13': 'Cédula de ciudadanía',
                    '31': 'NIT',
                  }, (v) => documentType = v),
                  field('Número de identificación', id),
                  if (documentType == '31')
                    field('Dígito de verificación', dv,
                        validate: (v) => RegExp(r'^\d$').hasMatch(v ?? '')
                            ? null : 'Escribe un dígito'),
                  choice('Tipo de persona', organization, {
                    '2': 'Persona natural',
                    '1': 'Persona jurídica',
                  }, (v) => organization = v),
                  field(organization == '1' ? 'Razón social' : 'Nombre completo', name),
                  field('Dirección', address),
                  field('Código DANE del municipio (ej. 23001 para Montería)', city,
                      keyboard: TextInputType.number,
                      validate: (v) => RegExp(r'^\d{5}$').hasMatch(v?.trim() ?? '')
                          ? null : 'Escribe el código de 5 dígitos'),
                  field('Correo electrónico', email,
                      keyboard: TextInputType.emailAddress,
                      validate: (v) {
                        final text = (v ?? '').trim();
                        if (kind.supplier && text.isEmpty) return null;
                        return text.contains('@') ? null : 'Revisa el correo';
                      }),
                ],

                const SizedBox(height: 10),
                Text('Productos o servicios', style: titleStyle),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : agregarDesdeCatalogo,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Elegir del catálogo de la empresa'),
                ),

                for (final item in items)
                  Card(
                    key: ObjectKey(item),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(children: [
                        field('Descripción', item.name),
                        field('Cantidad', item.quantity,
                            keyboard: TextInputType.number,
                            updateTotal: true,
                            validate: (v) =>
                                RegExp(r'^[1-9]\d{0,5}$').hasMatch(v?.trim() ?? '')
                                    ? null : 'Escribe una cantidad entera positiva'),
                        field('Precio unitario sin IVA', item.price,
                            keyboard: TextInputType.number,
                            updateTotal: true,
                            validate: (v) => decimalValidator(v)),
                        field('IVA (%)', item.tax,
                            keyboard: TextInputType.number,
                            updateTotal: true,
                            validate: (v) => decimalValidator(v, tax: true)),
                        if (items.length > 1)
                          TextButton(
                            onPressed: () {
                              setState(() => items.remove(item));
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                item.dispose();
                              });
                            },
                            child: const Text('Quitar producto'),
                          ),
                      ]),
                    ),
                  ),

                TextButton.icon(
                  onPressed: () => setState(() => items.add(Item())),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar producto manualmente'),
                ),
                choice('Forma de pago', paymentForm, {
                  '1': 'Contado',
                  '2': 'Crédito a 30 días',
                }, (v) => paymentForm = v),
                choice('Método de pago', method, {
                  '10': 'Efectivo',
                  '47': 'Transferencia',
                  '48': 'Tarjeta crédito',
                  '49': 'Tarjeta débito',
                }, (v) => method = v),

                Text('Total con IVA: ${pesos(total / 100)}', style: titleStyle),
                const SizedBox(height: 8),
                SelectableText('Referencia: $reference'),
                if (kind == DocumentKind.invoice) documentosPrevios(),
                if (error != null) ErrorText(error!),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy || rangeId == null ? null : submit,
                  icon: const Icon(Icons.send),
                  label: Text(busy ? 'Enviando…' : 'Emitir en sandbox'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BillPage extends StatefulWidget {
  const BillPage({super.key, required this.number});
  final String number;

  @override
  State<BillPage> createState() => _BillPageState();
}

class _BillPageState extends State<BillPage> {
  Json? bill;
  Json customer = {};
  Json emisor = {};
  List<Json> products = [];
  Json? collection;
  String? error;
  bool busy = false;

  String get billPath => '/v2/bills/${Uri.encodeComponent(widget.number)}';
  String get reference => 'FACT-${widget.number}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
    final response = await api.request(billPath);
    final data = Json.from(response['data'] as Map);
    final details = data['bill'] is Map ? Json.from(data['bill']) : data;
    final rawCustomer = data['customer'] ?? details['customer'];
    final rawItems = data['items'] ?? details['items'];

    if (!mounted) return;
    setState(() {
      final totals = details['totals'];
      bill = {...details, 'total': totals is Map ? totals['total'] ?? details['total'] : details['total']};
      final empresa = data['company'] ?? details['company'];
      emisor = empresa is Map ? Json.from(empresa) : {};
      customer = rawCustomer is Map ? Json.from(rawCustomer) : {};
      products = rawItems is List
          ? rawItems.whereType<Map>().map((e) => Json.from(e)).toList()
          : [];
    });
  });

  Future<void> pdf() => run(() async {
    final response = await api.request('$billPath/download-pdf');
    final data = response['data'];
    final raw = data is Map ? data['pdf_base_64_encoded'] : null;
    if (raw is! String || raw.isEmpty) {
      throw Exception('Factus no devolvió el PDF de esta factura.');
    }
    final bytes = base64Decode(raw.split(',').last);
    await Printing.layoutPdf(
      name: '${widget.number}.pdf',
      onLayout: (_) async => bytes,
    );
  });

  Future<void> createQr() => run(() async {
    final amount = double.tryParse('${bill?['total']}');
    if (amount == null || amount < 1000 || amount > 12100000) {
      throw Exception('El QR admite montos entre COP 1.000 y COP 12.100.000.');
    }
    final response = await api.request('/v1/collections', body: {
      'reference_code': reference,
      'amount': amount,
      'expiration': 900,
    });
    if (mounted) {
      setState(() => collection = Json.from(response['data'] as Map));
    }
  });

  Future<void> checkPayment() => run(() async {
    final response = await api.request(
      '/v1/collections/${Uri.encodeComponent(reference)}',
    );
    if (mounted) {
      setState(() => collection = Json.from(response['data'] as Map));
    }
  });

  Future<void> derivado(Plantilla tipo) => run(() async {
    Json? pago;
    if (tipo == Plantilla.recibo) {
      final r = await api.request('/v1/collections/${Uri.encodeComponent(reference)}');
      pago = Json.from(r['data'] as Map);
      if (pago['status'] != 'paid' || pago['reference_code'] != reference ||
          num.tryParse('${pago['amount']}') == null || pago['collected_at'] == null) {
        throw Exception('Se necesita un pago confirmado por Factus Pay para esta referencia.');
      }
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentoComercial(
      tipo: tipo, referencia: widget.number, cliente: customer, emisor: emisor,
      lineas: products, total: num.tryParse('${bill?['total']}'), pago: pago,
    )));
  });

  Widget qrWidget(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const SizedBox.shrink();
    try {
      return Image.memory(
        base64Decode(raw.split(',').last),
        width: 240,
        height: 240,
        fit: BoxFit.contain,
      );
    } on FormatException {
      return const Text('Recaudo generado. El QR llegó en un formato inesperado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = collection?['status'] == 'paid';
    final totalFactura = num.tryParse('${bill?['total']}');

    return Scaffold(
      appBar: AppBar(title: Text('Factura ${widget.number}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null) ErrorText(error!),
              if (bill == null && !busy)
                TextButton(onPressed: load, child: const Text('Reintentar consulta')),
              if (bill != null) ...[
                AeroHero(
                  titulo: totalFactura == null ? widget.number : pesos(totalFactura),
                  detalle: 'Factura ${widget.number}',
                  icono: Icons.receipt_long,
                ),
                const SizedBox(height: 16),
                SelectableText('Referencia: ${bill!['reference_code'] ?? '—'}'),
                SelectableText('CUFE: ${bill!['cufe'] ?? '—'}'),
                const Divider(),
                Text('${customer['company'] ?? customer['names'] ?? 'Cliente'}'),
                for (final product in products)
                  ListTile(
                    title: Text('${product['name'] ?? ''}'),
                    subtitle: Text('Cantidad: ${product['quantity'] ?? ''}'),
                    trailing: Text('COP ${product['price'] ?? ''}'),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy ? null : pdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Abrir / imprimir PDF'),
                ),
                ExpansionTile(
                  title: const Text('Documentos de esta factura'),
                  leading: const Icon(Icons.folder_copy_outlined),
                  children: [for (final t in [Plantilla.remision, Plantilla.cobro, Plantilla.recibo])
                    ListTile(title: Text(t.titulo), subtitle: Text(t.ayuda),
                      onTap: busy ? null : () => derivado(t))],
                ),
                FilledButton.icon(
                  onPressed: busy || paid ? null : createQr,
                  icon: const Icon(Icons.qr_code),
                  label: Text(collection == null ? 'Generar QR de cobro' : 'Renovar QR'),
                ),
                TextButton(
                  onPressed: busy ? null : checkPayment,
                  child: const Text('Consultar recaudo existente'),
                ),
                if (collection != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    paid ? 'Pago recibido' : 'Estado del recaudo: ${collection!['status']}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (!paid) Center(child: qrWidget(collection!['qr'])),
                  if (!paid && collection!['breb_key'] != null)
                    SelectableText('Llave: ${collection!['breb_key']}'),
                  if (!paid && collection!['qr_expires_at'] != null)
                    Text('Vence: ${collection!['qr_expires_at']}'),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
const tiposCliente = {
  '13':'Cédula de ciudadanía', '22':'Cédula de extranjería',
  '41':'Pasaporte', '31':'NIT',
};

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key, this.elegir = false});
  final bool elegir;
  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  List<Json> clientes = [];
  String filtro = '';
  String? aviso;
  bool cargando = true;

  @override
  void initState() { super.initState(); cargar(); }

  Future<void> cargar() async {
    setState(() { cargando = true; aviso = null; });
    try {
      final lista = rows(await api.request('/empresa/clientes'));
      if (mounted) setState(() => clientes = lista);
    } catch(e) {
      if (mounted) setState(() => aviso = message(e));
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> editar([Json? cliente]) async {
    final guardado = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => FichaCliente(cliente: cliente)));
    if (guardado == true && mounted) await cargar();
  }

  Future<void> eliminar(Json cliente) async {
    final confirma = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('Eliminar del registro'),
        content: Text('¿Quitar a ${cliente["nombre"]} del registro de clientes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('Eliminar')),
        ]));
    if (confirma != true || !mounted) return;
    try {
      await api.request('/empresa/clientes/eliminar',body:{'id':cliente['id']});
      if (mounted) await cargar();
    } catch(e) { if(mounted) setState(() => aviso = message(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = clientes.where((c) =>
      (!widget.elegir || c['tipo'] != '31') &&
      "${c['nombre']} ${c['documento']} ${c['telefono']}".toLowerCase().contains(filtro));
    return Scaffold(appBar: AppBar(title: Text(widget.elegir ? 'Elegir cliente' : 'Clientes')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth:780),
        child: ListView(padding: const EdgeInsets.all(16), children:[
          AeroHero(titulo: 'Directorio', detalle: widget.elegir
            ? 'Elige una persona para completar la factura rápida.'
            : 'Clientes y contactos de tu empresa', icono: Icons.contacts),
          const SizedBox(height:16),
          TextField(decoration: const InputDecoration(prefixIcon:Icon(Icons.search),
            labelText:'Buscar por nombre, documento o teléfono'),
            onChanged:(v)=>setState(()=>filtro=v.trim().toLowerCase())),
          const SizedBox(height:10),
          FilledButton.icon(onPressed:()=>editar(), icon:const Icon(Icons.person_add),
            label:const Text('Registrar cliente')),
          if(cargando) const LinearProgressIndicator(),
          if(aviso!=null) ...[ErrorText(aviso!),TextButton(onPressed:cargar,child:const Text('Reintentar'))],
          if(!cargando && aviso==null && visibles.isEmpty)
            const Card(child:ListTile(title:Text('Sin clientes para esta búsqueda.'))),
          for(final c in visibles) Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.person_outline)),
            title:Text(c['nombre']), isThreeLine:true,
            subtitle:Text('${tiposCliente[c["tipo"]]} · ${c["documento"]}\n${c["telefono"]}'),
            onTap:()=>widget.elegir ? Navigator.pop(context,c) : editar(c),
            trailing:widget.elegir ? const Icon(Icons.chevron_right) :
              IconButton(tooltip:'Eliminar cliente',icon:const Icon(Icons.delete_outline),onPressed:()=>eliminar(c)),
          )),
        ]))));
  }
}

class FichaCliente extends StatefulWidget {
  const FichaCliente({super.key,this.cliente});
  final Json? cliente;
  @override
  State<FichaCliente> createState()=>_FichaClienteState();
}

class _FichaClienteState extends State<FichaCliente> {
  final form = GlobalKey<FormState>();
  late final datos = <String,String>{
    for(final key in ['nombre','documento','telefono']) key: '${widget.cliente?[key] ?? ""}',
    'tipo': '${widget.cliente?["tipo"] ?? "13"}',
  };
  bool busy=false;
  String? aviso;

  Future<void> guardar() async {
    if(busy || !form.currentState!.validate()) return;
    setState(() {busy=true; aviso=null;});
    try {
      await api.request('/empresa/clientes',body:{
        ...datos, if(widget.cliente!=null) 'id':widget.cliente!['id'],
      });
      if(mounted) Navigator.pop(context,true);
    } catch(e) { if(mounted) setState(()=>aviso=message(e)); }
    finally { if(mounted) setState(()=>busy=false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar:AppBar(title:Text(widget.cliente==null?'Nuevo cliente':'Editar cliente')),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),
        child:Form(key:form,child:ListView(padding:const EdgeInsets.all(16),children:[
          DropdownButtonFormField<String>(initialValue:datos['tipo'],
            decoration:const InputDecoration(labelText:'Tipo de documento'),
            items:[for(final e in tiposCliente.entries) DropdownMenuItem(value:e.key,child:Text(e.value))],
            onChanged:(v){if(v!=null)setState(()=>datos['tipo']=v);}),
          for(final key in ['nombre','documento','telefono']) Padding(
            padding:const EdgeInsets.only(top:12),
            child:TextFormField(initialValue:datos[key],
              decoration:InputDecoration(labelText:{'nombre':'Nombre o razón social','documento':'Número de documento','telefono':'Teléfono'}[key]),
              keyboardType:key=='telefono'?TextInputType.phone:TextInputType.text,
              onChanged:(v)=>datos[key]=v.trim(),
              validator:(v)=>(v??'').trim().isEmpty?'Campo obligatorio':null)),
          if(aviso!=null) ErrorText(aviso!),
          const SizedBox(height:14),
          FilledButton(onPressed:busy?null:guardar,child:Text(busy?'Guardando…':'Guardar cliente')),
        ])))));
  }
}

// Paisaje vectorial. Las hojas y los reflejos se concentran en los márgenes.
class JardinAero extends CustomPainter {
  const JardinAero();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xffd1e9e6), Color(0xfff3f7f2), Color(0xffe9f4f1), Color(0xffbcdedb)],
      stops: [0, .34, .70, 1],
    ).createShader(bounds));

    // Tres capas de vidrio curvo, como la orilla de una laguna.
    for (var i = 0; i < 3; i++) {
      final y = h * (.83 + i * .055);
      final ola = Path()..moveTo(-2,y)
        ..cubicTo(w*.27,y+h*.13,w*.62,y-h*.14,w+2,y-h*.06)
        ..lineTo(w+2,h+2)..lineTo(-2,h+2)..close();
      canvas.drawPath(ola,Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,end: Alignment.bottomCenter,
        colors:[Color(0x628ec4bd),Color(0x137eb4b0)],
      ).createShader(bounds));
      canvas.drawPath(ola,Paint()..style=PaintingStyle.stroke..strokeWidth=1..color=Colors.white60);
    }

    // Una sola rama en el margen. El centro permanece abierto para el texto.
    canvas.save();
    canvas.translate(w*.03,h*.92);
    final escala=(w/1200).clamp(.36,1.15).toDouble();
    canvas.scale(escala,escala);
    final rama=Path()..moveTo(-52,74)..quadraticBezierTo(39,-25,39,-158);
    canvas.drawPath(rama,Paint()..style=PaintingStyle.stroke..strokeWidth=2..color=const Color(0x94669d86));
    for(var i=0;i<7;i++){
      canvas.save();
      canvas.translate(8+i*5,-i*20);
      canvas.rotate(i.isEven ? -.75 : .78);
      final hoja=Path()..moveTo(0,0)..quadraticBezierTo(-17,-23,0,-55)
        ..quadraticBezierTo(18,-30,0,0)..close();
      canvas.drawPath(hoja,Paint()..shader=const LinearGradient(
        colors:[Color(0xb883b69b),Color(0xadcee3ab),Color(0xd5e7f4d7)]
      ).createShader(const Rect.fromLTWH(-18,-55,36,55)));
      canvas.drawLine(Offset.zero,const Offset(0,-48),Paint()..color=Colors.white60);
      canvas.restore();
    }
    canvas.restore();

    // Burbujas ópticas: reflejos pequeños y un borde nacarado.
    for(final gota in const [(.965,.17,48.0),(.933,.215,17.0),(.983,.255,9.0),(.026,.65,20.0),(.062,.62,8.0)]){
      final centro=Offset(w*gota.$1,h*gota.$2);
      final radio=gota.$3*(w/900).clamp(.50,1.1);
      final caja=Rect.fromCircle(center:centro,radius:radio);
      canvas.drawCircle(centro,radio,Paint()..shader=const RadialGradient(
        center:Alignment(-.42,-.55),radius:1.17,
        colors:[Color(0xcfffffff),Color(0x2687cfce),Color(0x115faaa7),Color(0x929ac9cb),Color(0xbbffffff)],
        stops:[0,.2,.59,.91,1],
      ).createShader(caja));
      canvas.drawCircle(centro,radio,Paint()..style=PaintingStyle.stroke..color=Colors.white70);
      canvas.drawArc(caja.deflate(radio*.14),3.62,.84,false,Paint()..style=PaintingStyle.stroke
        ..strokeCap=StrokeCap.round..strokeWidth=1.7..color=Colors.white70);
    }
  }

  @override
  bool shouldRepaint(JardinAero oldDelegate) => false;
}
class AccesoPanel extends StatelessWidget {
  const AccesoPanel({super.key, required this.ancho, required this.icono,
    required this.titulo, required this.detalle, required this.onAbrir});
  final double ancho;
  final IconData icono;
  final String titulo, detalle;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) => SizedBox(width: ancho,
    child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
      child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        leading: CircleAvatar(backgroundColor: const Color(0xffd8eee6),
          foregroundColor: const Color(0xff125748), child: Icon(icono)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(detalle), trailing: const Icon(Icons.arrow_forward_ios, size: 15),
        onTap: onAbrir)));
}

class PortadaFacturacion extends StatelessWidget {
  const PortadaFacturacion({super.key, required this.onEmitir});
  final VoidCallback onEmitir;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final amplia = box.maxWidth >= 560;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x30336861), blurRadius: 18, offset: Offset(0, 6))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(26),
        child: Container(decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [Color(0xff102f42),Color(0xff124e57),Color(0xff25806d)],
          begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Stack(children: [
            Positioned.fill(child: ExcludeSemantics(child: IgnorePointer(
              child: Align(alignment: Alignment.centerRight, child: SizedBox(
                width: amplia ? 270 : 80, height: amplia ? 210 : 115,
                child: const RepaintBoundary(child: RocioVivo())))))),
            Padding(padding: EdgeInsets.fromLTRB(amplia ? 30 : 20, 24, amplia ? 250 : 72, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('OPERACIONES   /   FACTURÍN', style: TextStyle(
                  color: Color(0xffc5f2d5), fontWeight: FontWeight.w700, letterSpacing: 1.7, fontSize: 11)),
                const SizedBox(height: 10),
                Text('Facturación', style: TextStyle(color: Colors.white, fontSize: amplia ? 40 : 31,
                  height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -1)),
                const SizedBox(height: 6),
                const Text('Emite una venta desde tu catálogo.', style: TextStyle(color: Color(0xffe1f4ee))),
                const SizedBox(height: 18),
                FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xffd5f6a7),
                  foregroundColor: const Color(0xff183b31)), onPressed: onEmitir,
                  icon: const Icon(Icons.bolt, size: 19), label: const Text('Factura rápida')),
              ])),
          ]))));
  });
}

class RocioVivo extends StatefulWidget {
  const RocioVivo({super.key});
  @override
  State<RocioVivo> createState() => _RocioVivoState();
}

class _RocioVivoState extends State<RocioVivo> with SingleTickerProviderStateMixin {
  late final reloj = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      reloj.stop();
      reloj.value = 0;
    } else if (!reloj.isAnimating) {
      reloj.repeat();
    }
  }
  @override
  void dispose() { reloj.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PintarRocio(reloj), size: Size.infinite);
}

class _PintarRocio extends CustomPainter {
  _PintarRocio(this.reloj) : super(repaint: reloj);
  final Animation<double> reloj;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 240, size.height / 185);
    if (scale <= 0) return;
    canvas.save();
    canvas.translate((size.width - 240 * scale) / 2, (size.height - 185 * scale) / 2);
    canvas.scale(scale);
    final t = reloj.value * 2 * math.pi;
    final stem = Path()..moveTo(15, 197)..quadraticBezierTo(100, 117, 202, 53);
    canvas.drawPath(stem,Paint()..style=PaintingStyle.stroke..strokeWidth=2.2..color=const Color(0xff98d3a4));
    for (var i=0;i<6;i++) {
      canvas.save();
      canvas.translate(46+i*23,166-i*17);
      canvas.rotate(i.isEven ? -.95 : .52);
      final leaf=Path()..moveTo(0,0)..quadraticBezierTo(-14,-18,0,-43)
        ..quadraticBezierTo(17,-19,0,0)..close();
      canvas.drawPath(leaf,Paint()..shader=const LinearGradient(
        colors:[Color(0xff5fa682),Color(0xffc8df91)]).createShader(const Rect.fromLTWH(-14,-43,31,43)));
      canvas.drawLine(Offset.zero,const Offset(0,-37),Paint()..color=Colors.white54);
      canvas.restore();
    }
    const gotas = [(142.0,76.0,43.0),(201.0,37.0,18.0),(85.0,46.0,11.0),(201.0,129.0,22.0)];
    for (var i=0;i<gotas.length;i++) {
      final g=gotas[i];
      final centro=Offset(g.$1+2*math.cos(t+i),g.$2+4*math.sin(t+i));
      final bounds=Rect.fromCircle(center:centro,radius:g.$3);
      canvas.drawCircle(centro,g.$3,Paint()..shader=const RadialGradient(center:Alignment(-.4,-.55),radius:1.1,
        colors:[Color(0xffecffff),Color(0x805ce3db),Color(0x40448b9c),Color(0xc6c9ffeb)],
        stops:[0,.22,.72,1]).createShader(bounds));
      canvas.drawCircle(centro,g.$3,Paint()..style=PaintingStyle.stroke..color=Colors.white60);
      canvas.drawArc(bounds.deflate(g.$3*.15),3.6,.9,false,Paint()..style=PaintingStyle.stroke
        ..strokeCap=StrokeCap.round..strokeWidth=2..color=Colors.white70);
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(_PintarRocio old) => reloj != old.reloj;
}

class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});
  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  Json? almacen;
  String filtro = '';
  String? aviso;
  bool cargando = false;

  @override
  void initState() { super.initState(); cargar(); }

  Future<void> cargar() async {
    setState(() { cargando = true; aviso = null; });
    try {
      final datos = await api.request('/inventario');
      if (mounted) setState(() => almacen = datos);
    } catch(e) {
      if (mounted) setState(() => aviso = message(e));
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> abrirFicha([Json? producto]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => FichaStock(producto: producto)));
    if (mounted && ok == true) await cargar();
  }

  Future<void> conciliar(String ref) async {
    String accion = 'confirmar', numero = '';
    final form = GlobalKey<FormState>();
    final datos = await showDialog<Json>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, actualizar) => AlertDialog(title: const Text('Conciliar reserva'),
        content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children:[
          SelectableText('Comprueba en Factus el resultado de la referencia $ref antes de continuar.'),
          DropdownButtonFormField<String>(initialValue: accion, isExpanded:true,
            items: const [
              DropdownMenuItem(value:'confirmar',child:Text('Verifiqué que fue emitida')),
              DropdownMenuItem(value:'liberar',child:Text('Verifiqué que no fue emitida')),
            ], onChanged:(v) => actualizar(()=>accion=v!)),
          if(accion=='confirmar') TextFormField(decoration:const InputDecoration(labelText:'Número verificado de factura'),
            onChanged:(v)=>numero=v.trim(),validator:(v)=>(v??'').trim().isEmpty?'Escribe el número':null),
        ]))),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
          FilledButton(onPressed:(){if(form.currentState!.validate()) Navigator.pop(ctx,{'ref':ref,'accion':accion,'numero':numero});},
            child:Text(accion=='confirmar'?'Registrar venta':'Liberar unidades')),
        ])));
    if(datos==null || !mounted) return;
    try {
      await api.request('/inventario/conciliar',body:datos);
      if(mounted) await cargar();
    } catch(e){if(mounted) setState(()=>aviso=message(e));}
  }

  @override
  Widget build(BuildContext context) {
    final productos = almacen==null ? <Json>[] : rows(almacen!);
    final visibles=productos.where((p)=>"${p['sku']} ${p['nombre']}".toLowerCase().contains(filtro));
    return Scaffold(appBar:AppBar(title:const Text('Inventario')),body:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:850),child:ListView(padding:const EdgeInsets.all(16),children:[
        const AeroHero(titulo:'Inventario',detalle:'Productos físicos y unidades disponibles',icono:Icons.inventory_2_outlined),
        const SizedBox(height:14),
        Wrap(spacing:10,children:[
          FilledButton.icon(onPressed:()=>abrirFicha(),icon:const Icon(Icons.add),label:const Text('Nuevo producto')),
          TextButton.icon(onPressed:cargando?null:cargar,icon:const Icon(Icons.refresh),label:const Text('Actualizar')),
        ]),
        const SizedBox(height:12),
        TextField(decoration:const InputDecoration(labelText:'Buscar por código o nombre',prefixIcon:Icon(Icons.search)),
          onChanged:(v)=>setState(()=>filtro=v.trim().toLowerCase())),
        if(cargando) const LinearProgressIndicator(),
        if(aviso!=null) ErrorText(aviso!),
        if(almacen!=null && visibles.isEmpty) const Card(child:ListTile(title:Text('Sin productos para mostrar'))),
        for(final p in visibles) Card(child:ListTile(
          title:Text(p['nombre']),isThreeLine:true,
          subtitle:Text("${p['sku']} · ${pesos(p['precio'])} antes de IVA\n${p['disponible']} disponibles · ${p['reservado']} reservadas"),
          trailing:const Icon(Icons.swap_vert),onTap:()=>abrirFicha(p))),
        if(almacen!=null) ...[
          for(final r in almacen!['pendientes']) Card(child:ListTile(
            leading:const Icon(Icons.pending_actions),title:const Text('Reserva pendiente'),
            subtitle:Text(r['ref']),trailing:const Icon(Icons.chevron_right),onTap:()=>conciliar(r['ref']))),
          const SizedBox(height:16),
          Text('Últimos movimientos',style:Theme.of(context).textTheme.titleLarge),
          if((almacen!['movimientos'] as List).isEmpty) const Text('Aún no hay movimientos registrados.'),
          for(final m in almacen!['movimientos']) Card(child:ListTile(
            leading:Icon(m['unidades']>0?Icons.south_west:Icons.north_east),
            title:Text("${m['sku']} · ${m['motivo']}"),
            subtitle:Text("${m['fecha']} UTC"),trailing:Text("${m['unidades']>0?'+':''}${m['unidades']}"))),
        ],
      ]))));
  }
}

class FichaStock extends StatefulWidget {
  const FichaStock({super.key,this.producto});
  final Json? producto;
  @override
  State<FichaStock> createState()=>_FichaStockState();
}

class _FichaStockState extends State<FichaStock> {
  final form=GlobalKey<FormState>();
  final datos=<String,String>{'iva':'19','inicial':'0','cantidad':'1'};
  String tipo='entrada';
  bool busy=false;
  String? aviso;

  Widget campo(String key,String label,{bool entero=false,bool decimal=false}) =>
    Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(
      initialValue:datos[key]??'',decoration:InputDecoration(labelText:label),
      keyboardType:entero||decimal?TextInputType.number:TextInputType.text,
      onChanged:(v)=>datos[key]=v.trim(),validator:(v){
        final s=(v??'').trim();
        if(s.isEmpty)return 'Campo obligatorio';
        if(entero && !RegExp(r'^\d{1,6}$').hasMatch(s))return 'Usa un número entero de hasta seis dígitos';
        if(decimal && !RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(s))return 'Usa hasta dos decimales';
        return null;
      }));

  Future<void> guardar() async {
    if(busy||!form.currentState!.validate()) return;
    setState((){busy=true;aviso=null;});
    try {
      if(widget.producto==null){
        await api.request('/inventario/productos',body:{
          'sku':datos['sku'],'nombre':datos['nombre'],'precio':datos['precio']!.replaceAll(',','.'),
          'iva':datos['iva']!.replaceAll(',','.'),'inicial':int.parse(datos['inicial']!),
        });
      } else {
        await api.request('/inventario/movimientos',body:{
          'sku':widget.producto!['sku'],'tipo':tipo,'cantidad':int.parse(datos['cantidad']!),'motivo':datos['motivo'],
        });
      }
      if(mounted) Navigator.pop(context,true);
    } catch(e){if(mounted)setState(()=>aviso=message(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }

  @override
  Widget build(BuildContext context) {
    final p=widget.producto;
    return Scaffold(appBar:AppBar(title:Text(p==null?'Nuevo producto':'Movimiento de inventario')),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),
        child:Form(key:form,child:ListView(padding:const EdgeInsets.all(16),children:[
          if(p==null)...[
            campo('sku','Código único (ej. CAF-01)'),campo('nombre','Nombre del producto'),
            campo('precio','Precio por unidad antes de IVA (COP)',decimal:true),
            campo('iva','IVA (%)',decimal:true),campo('inicial','Unidades iniciales',entero:true),
          ]else ...[
            Text("${p['nombre']} · ${p['disponible']} disponibles",style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(initialValue:tipo,decoration:const InputDecoration(labelText:'Movimiento'),
              items:const [DropdownMenuItem(value:'entrada',child:Text('Entrada')),DropdownMenuItem(value:'salida',child:Text('Salida'))],
              onChanged:(v)=>setState(()=>tipo=v!)),
            const SizedBox(height:12),campo('cantidad','Unidades',entero:true),campo('motivo','Motivo del movimiento'),
          ],
          if(aviso!=null)ErrorText(aviso!),
          FilledButton(onPressed:busy?null:guardar,child:Text(busy?'Guardando…':'Guardar')),
        ])))));
  }
}

enum Plantilla {
  cotizacion('Cotización', 'COT', 'Propuesta con precios, IVA y vigencia.'),
  orden('Orden de servicio', 'OS', 'Trabajo solicitado, alcance y responsable.'),
  remision('Remisión de entrega', 'REM', 'Artículos y cantidades que se entregan.'),
  cobro('Cuenta de cobro', 'CC', 'Solicitud por el saldo que confirmes como pendiente.'),
  recibo('Comprobante de pago', 'REC', 'Importe y fecha de un recaudo confirmado por Factus Pay.');

  const Plantilla(this.titulo, this.prefijo, this.ayuda);
  final String titulo, prefijo, ayuda;
}

class DocumentoComercial extends StatefulWidget {
  const DocumentoComercial({super.key, required this.tipo, required this.referencia,
    required this.cliente, required this.lineas, required this.total,
    this.emisor = const {}, this.pago});
  final Plantilla tipo;
  final String referencia;
  final Json cliente, emisor;
  final List<Json> lineas;
  final num? total;
  final Json? pago;
  @override
  State<DocumentoComercial> createState() => _DocumentoComercialState();
}

String datoComercial(Json datos, List<String> campos) {
  for (final campo in campos) {
    final valor = datos[campo];
    if (valor is String && valor.trim().isNotEmpty) return valor.trim();
    if (valor is num) return valor.toString();
  }
  return '';
}

class _DocumentoComercialState extends State<DocumentoComercial> {
  final form = GlobalKey<FormState>();
  late String emisor = datoComercial(widget.emisor,['company','name','graphic_representation_name','names']);
  late String identificacion = datoComercial(widget.emisor,['nit','identification']);
  String responsable='', lugar='', nota='', saldo='';
  late final DateTime hoy = DateTime.now().toUtc().subtract(const Duration(hours:5));
  late DateTime fecha = DateTime(hoy.year,hoy.month,hoy.day).add(
    Duration(days:widget.tipo==Plantilla.cotizacion || widget.tipo==Plantilla.cobro ? 15 : 0));
  bool generando=false;
  String? aviso;

  String dia(DateTime d) => d.toIso8601String().substring(0,10);

  Widget campo(String label,String valor,ValueChanged<String> editar,
      {bool requerido=true,bool dinero=false,int maxLines=1}) => Padding(
    padding:const EdgeInsets.only(bottom:12),
    child:TextFormField(initialValue:valor, onChanged:(v)=>editar(v.trim()),
      maxLength:maxLines>1?750:140, maxLines:maxLines,
      keyboardType:dinero?const TextInputType.numberWithOptions(decimal:true):null,
      decoration:InputDecoration(labelText:label,counterText:''),
      validator:(v){
        final texto=(v??'').trim();
        if(requerido && texto.isEmpty) return 'Campo obligatorio';
        if(dinero){
          final n=num.tryParse(texto.replaceAll(',','.'));
          if(!RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(texto) || n==null || n<=0 ||
              widget.total==null || n>widget.total!) return 'Indica un saldo positivo de hasta el total de la factura.';
        }
        return null;
      }));

  Future<void> generar() async {
    if(generando || !form.currentState!.validate()) return;
    setState((){generando=true;aviso=null;});
    try {
      final tipo=widget.tipo;
      final previo=tipo==Plantilla.cotizacion || tipo==Plantilla.orden;
      final cliente=datoComercial(widget.cliente,['company','names','graphic_representation_name','trade_name']);
      final datosCliente=[
        cliente, datoComercial(widget.cliente,['identification']),
        datoComercial(widget.cliente,['phone']), datoComercial(widget.cliente,['email']),
      ].where((v)=>v.isNotEmpty).join('  /  ');
      final clave='${tipo.prefijo}-${widget.referencia}';
      final detalles=<String,String>{
        if(tipo==Plantilla.cotizacion) 'Vigente hasta':dia(fecha),
        if(tipo==Plantilla.orden) 'Fecha programada':dia(fecha),
        if(tipo==Plantilla.remision) 'Fecha de entrega prevista':dia(fecha),
        if(tipo==Plantilla.cobro) 'Fecha límite de pago':dia(fecha),
        if(responsable.isNotEmpty) (tipo==Plantilla.remision?'Persona que recibe':'Responsable del servicio'):responsable,
        if(lugar.isNotEmpty) 'Lugar':lugar,
        if(tipo==Plantilla.recibo) ...{
          'Referencia de recaudo':'${widget.pago!['reference_code']}',
          'Fecha de pago':'${widget.pago!['collected_at']}',
          'Canal':'Factus Pay · Sandbox',
        },
      };
      final tabla=<List<String>>[];
      final incluirLineas=tipo==Plantilla.cotizacion || tipo==Plantilla.orden || tipo==Plantilla.remision;
      if(incluirLineas){
        for(final item in widget.lineas){
          tabla.add([
            '${item['name']??''}', '${item['quantity']??''}',
            if(tipo==Plantilla.cotizacion) pesos(num.parse('${item['price']}')),
            if(tipo==Plantilla.cotizacion) ((item['taxes'] as List?)??[]).map((t)=>"${t['rate']}%").join(', '),
          ]);
        }
        if(tabla.isEmpty) throw Exception('Faltan los artículos o servicios para crear el documento.');
      }
      final importes=<String,String>{
        if(tipo==Plantilla.cotizacion) 'Total cotizado con IVA':pesos(widget.total!),
        if(tipo==Plantilla.cobro) ...{
          'Total de la factura':pesos(widget.total!),
          'Saldo solicitado':pesos(num.parse(saldo.replaceAll(',','.'))),
        },
        if(tipo==Plantilla.recibo) 'Pago confirmado':pesos(num.parse('${widget.pago!['amount']}')),
      };
      final bytes=await pdfComercial(tipo:tipo,clave:clave,fecha:dia(hoy),emisor:emisor,
        idEmisor:identificacion,cliente:datosCliente,
        origen:"${previo?'Referencia de propuesta':'Factura de origen'}: ${widget.referencia}",
        detalles:detalles,tabla:tabla,importes:importes,nota:nota);
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(
        appBar:AppBar(title:Text(tipo.titulo)),
        body:PdfPreview(build:(_)=>bytes, pdfFileName:'$clave.pdf',
          canChangeOrientation:false,canChangePageFormat:false,canDebug:false))));
    } catch(e){if(mounted)setState(()=>aviso=message(e));}
    finally{if(mounted)setState(()=>generando=false);}
  }

  @override
  Widget build(BuildContext context) {
    final tipo=widget.tipo;
    final etiquetaFecha=switch(tipo){
      Plantilla.cotizacion=>'Vigente hasta', Plantilla.orden=>'Fecha programada',
      Plantilla.remision=>'Entrega prevista', _=>'Fecha límite de pago',
    };
    return Scaffold(appBar:AppBar(title:Text(tipo.titulo)),body:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:680),child:Form(key:form,child:ListView(
        padding:const EdgeInsets.all(16),children:[
          AeroHero(titulo:tipo.titulo,detalle:tipo.ayuda,icono:Icons.description_outlined),
          const SizedBox(height:16),
          campo('Nombre o razón social del emisor',emisor,(v)=>emisor=v),
          campo('Documento o NIT del emisor',identificacion,(v)=>identificacion=v),
          if(tipo!=Plantilla.recibo) ListTile(
            title:Text(etiquetaFecha),subtitle:Text(dia(fecha)),trailing:const Icon(Icons.calendar_today),
            onTap:() async{
              final f=await showDatePicker(context:context,initialDate:fecha,
                firstDate:DateTime(hoy.year-5),lastDate:DateTime(hoy.year+10));
              if(f!=null && mounted)setState(()=>fecha=f);
            }),
          if(tipo==Plantilla.orden || tipo==Plantilla.remision)...[
            campo(tipo==Plantilla.orden?'Responsable del servicio':'Persona que recibe',responsable,(v)=>responsable=v),
            campo('Lugar de prestación o entrega',lugar,(v)=>lugar=v),
          ],
          if(tipo==Plantilla.cobro)...[
            Text('Total facturado: ${widget.total==null?"sin dato":pesos(widget.total!)}'),
            const Text('Confirma el saldo después de descontar abonos y notas crédito.'),
            const SizedBox(height:10),
            campo('Saldo pendiente confirmado (COP)',saldo,(v)=>saldo=v,dinero:true),
          ],
          campo(tipo==Plantilla.orden?'Alcance del trabajo':'Observaciones (opcional)',nota,
            (v)=>nota=v,requerido:tipo==Plantilla.orden,maxLines:3),
          if(aviso!=null)ErrorText(aviso!),
          FilledButton.icon(onPressed:generando?null:generar,icon:const Icon(Icons.picture_as_pdf),
            label:Text(generando?'Generando…':'Vista previa del PDF')),
        ])))));
  }
}

Future<Uint8List> pdfComercial({required Plantilla tipo,required String clave,
  required String fecha,required String emisor,required String idEmisor,
  required String cliente,required String origen,required Map<String,String> detalles,
  required List<List<String>> tabla,required Map<String,String> importes,required String nota}) {
  final doc=pw.Document(title:tipo.titulo,author:emisor);
  final tinta=PdfColor.fromHex('#123F4B');
  final fuerte=pw.TextStyle(fontWeight:pw.FontWeight.bold,color:tinta);
  doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(38),
    footer:(ctx)=>pw.Text('Facturín / Sandbox     ·     ${ctx.pageNumber} / ${ctx.pagesCount}',
      style:const pw.TextStyle(fontSize:9,color:PdfColors.grey700)),
    build:(_)=>[
      pw.Text('FACTURÍN  /  DOCUMENTO COMERCIAL DE DEMOSTRACIÓN',style:fuerte),
      pw.SizedBox(height:12),pw.Text(tipo.titulo,style:pw.TextStyle(fontSize:27,color:tinta)),
      pw.Text('$clave   /   $fecha'),pw.Divider(),pw.SizedBox(height:8),
      pw.Text('Emisor',style:fuerte),pw.Text('$emisor   /   $idEmisor'),
      pw.SizedBox(height:8),pw.Text('Cliente o destinatario',style:fuerte),
      pw.Text(cliente.isEmpty?'Sin identificación en el documento de origen':cliente),
      pw.SizedBox(height:8),pw.Text(origen),
      for(final e in detalles.entries) pw.Text('${e.key}: ${e.value}'),
      pw.SizedBox(height:16),
      if(tabla.isNotEmpty) pw.TableHelper.fromTextArray(
        headers:['Producto o servicio','Cantidad',if(tipo==Plantilla.cotizacion)...['Precio sin IVA','IVA']],
        data:tabla,headerDecoration:pw.BoxDecoration(color:tinta),
        headerStyle:pw.TextStyle(color:PdfColors.white,fontWeight:pw.FontWeight.bold),
        cellStyle:const pw.TextStyle(fontSize:10),cellAlignment:pw.Alignment.centerLeft),
      for(final e in importes.entries) pw.Padding(padding:const pw.EdgeInsets.only(top:8),
        child:pw.Text('${e.key}: COP ${e.value}',style:fuerte)),
      if(nota.isNotEmpty)...[pw.SizedBox(height:14),pw.Text('Detalle',style:fuerte),pw.Text(nota)],
      if(tipo==Plantilla.remision)...[
        pw.SizedBox(height:36),pw.Text('Recibido por: ____________________    Fecha: ______________'),
      ],
    ]));
  return doc.save();
}
