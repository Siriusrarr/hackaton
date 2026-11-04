part of 'main.dart';



const azulAero = Color(0xff073b71);
const aquaAero = Color(0xff007e91);
const limaAero = Color(0xffc7fa4c);

String pesos(num valor) {
  final partes = valor.abs().toStringAsFixed(2).split('.');
  final entero = partes[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final decimales = partes[1] == '00' ? '' : ',${partes[1]}';
  return '${valor < 0 ? '-' : ''}\$$entero$decimales';
}

String mesTexto(DateTime fecha) =>
    '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

String nombreMes(DateTime fecha) {
  const nombres = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
  return '${nombres[fecha.month - 1]} ${fecha.year}';
}

class AeroHero extends StatelessWidget {
  const AeroHero({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.icono,
  });

  final String titulo;
  final String detalle;
  final IconData icono;

  Widget esfera(double tamano, Color color) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70),
        gradient: RadialGradient(
          center: const Alignment(-0.45, -0.65),
          radius: 1.05,
          colors: [Colors.white, color, azulAero],
          stops: const [0, 0.35, 1],
        ),
        boxShadow: [
          BoxShadow(color: color.withAlpha(90), blurRadius: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff081c62), Color(0xff005c91), Color(0xff08bfb0)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x44064f85), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -36, top: -49, child: esfera(150, limaAero)),
          Positioned(right: 52, bottom: -44,
              child: esfera(100, const Color(0xff55efff))),
          Positioned(right: 77, top: 15,
              child: esfera(21, const Color(0xffecbcff))),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 78, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icono, color: limaAero, size: 30),
                const SizedBox(height: 9),
                Text(titulo, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900,
                  fontSize: 30, height: 1.05, letterSpacing: -1,
                )),
                const SizedBox(height: 8),
                Text(detalle, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmpresaPage extends StatefulWidget {
  const EmpresaPage({super.key});

  @override
  State<EmpresaPage> createState() => _EmpresaPageState();
}

class _EmpresaPageState extends State<EmpresaPage> {
  DateTime mes = DateTime.now().toUtc().subtract(const Duration(hours: 5));
  Json? resumen;
  List<Json> servicios = [];
  Map<String, double> cobros = {};
  String? errorPanel;
  String? errorPay;
  bool cargando = false;
  bool cargandoPay = false;
  int version = 0;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    final turno = ++version;
    final periodo = mesTexto(mes);

    setState(() {
      cargando = true;
      cargandoPay = true;
      errorPanel = null;
      errorPay = null;
      resumen = null;
      cobros = {};
    });

    // Un fallo de Pay no impide abrir el catálogo o consultar el IVA.
    cargarCobros(periodo, turno);

    try {
      final resultados = await Future.wait([
        api.request('/empresa/resumen', query: {'mes': periodo}),
        api.request('/empresa/servicios'),
      ]);
      if (!mounted || turno != version) return;
      setState(() {
        resumen = resultados[0];
        servicios = rows(resultados[1]);
      });
    } catch (e) {
      if (mounted && turno == version) {
        setState(() => errorPanel = message(e));
      }
    } finally {
      if (mounted && turno == version) setState(() => cargando = false);
    }
  }

  String diaCobro(String raw) {
    // Formato documentado por Pay: 24-10-2026 12:26:54 PM.
    final local = RegExp(r'^(\d{2})-(\d{2})-(\d{4})').firstMatch(raw);
    if (local != null) {
      return '${local[3]}-${local[2]}-${local[1]}';
    }
    final iso = DateTime.tryParse(raw);
    if (iso == null) throw FormatException('Fecha de recaudo desconocida: $raw');
    final fecha = iso.isUtc ? iso.subtract(const Duration(hours: 5)) : iso;
    return fecha.toIso8601String().substring(0, 10);
  }

  Future<void> cargarCobros(String periodo, int turno) async {
    try {
      final porDia = <String, double>{};
      final vistos = <String>{};
      int pagina = 1;
      int ultima = 1;

      do {
        final r = await api.request('/v1/collections', query: {
          'status': 'paid',
          'page': '$pagina',
        });
        if (!mounted || turno != version) return;

        for (final pago in rows(r)) {
          if (pago['status'] != 'paid') continue;
          final dia = diaCobro('${pago['collected_at']}');
          if (!dia.startsWith('$periodo-')) continue;

          final referencia = '${pago['reference_code']}';
          if (!vistos.add(referencia)) continue;

          final importe = double.parse('${pago['amount']}');
          porDia[dia] = (porDia[dia] ?? 0) + importe;
        }

        final meta = r['meta'];
        ultima = meta is Map ? int.tryParse('${meta['last_page']}') ?? pagina : pagina;
        pagina++;
      } while (pagina <= ultima);

      if (mounted && turno == version) setState(() => cobros = porDia);
    } catch (e) {
      if (mounted && turno == version) setState(() => errorPay = message(e));
    } finally {
      if (mounted && turno == version) setState(() => cargandoPay = false);
    }
  }

  Future<void> editarServicio([Json? anterior]) async {
    String nombre = '${anterior?['nombre'] ?? ''}';
    String precio = '${anterior?['precio'] ?? ''}';
    String iva = '${anterior?['iva'] ?? '19'}';
    final llave = GlobalKey<FormState>();

    final datos = await showDialog<Json>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(anterior == null ? 'Nuevo servicio' : 'Editar servicio'),
        content: SingleChildScrollView(
          child: Form(
            key: llave,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                initialValue: nombre,
                decoration: const InputDecoration(labelText: 'Nombre del servicio'),
                onChanged: (v) => nombre = v.trim(),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: precio,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Precio sin IVA (COP)'),
                onChanged: (v) => precio = v.trim(),
                validator: (v) => validarNumero(v, positivo: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: iva,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'IVA (%)'),
                onChanged: (v) => iva = v.trim(),
                validator: (v) => validarNumero(v, maximo: 100),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (!llave.currentState!.validate()) return;
              Navigator.pop(ctx, {
                if (anterior != null) 'id': anterior['id'],
                'nombre': nombre,
                'precio': precio.replaceAll(',', '.'),
                'iva': iva.replaceAll(',', '.'),
              });
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (datos == null || !mounted) return;
    await cambiarCatalogo('/empresa/servicios', datos);
  }

  String? validarNumero(String? valor, {bool positivo = false, num? maximo}) {
    final texto = (valor ?? '').trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(texto)) {
      return 'Usa máximo dos decimales';
    }
    final numero = double.tryParse(texto);
    if (numero == null || (positivo && numero <= 0) ||
        (maximo != null && numero > maximo)) return 'Revisa el valor';
    return null;
  }

  Future<void> cambiarCatalogo(String ruta, Json datos) async {
    try {
      final r = await api.request(ruta, body: datos);
      if (mounted) setState(() => servicios = rows(r));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message(e))));
      }
    }
  }

  Future<void> descontable() async {
    final periodo = mesTexto(mes);
    String valor = '${resumen?['descontable'] ?? 0}';
    final llave = GlobalKey<FormState>();

    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('IVA descontable · $periodo'),
        content: Form(
          key: llave,
          child: TextFormField(
            initialValue: valor,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Total revisado del mes (COP)'),
            validator: (v) => validarNumero(v),
            onChanged: (v) => valor = v.trim(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (llave.currentState!.validate()) Navigator.pop(ctx, valor);
            },
            child: const Text('Guardar total'),
          ),
        ],
      ),
    );

    if (nuevo == null || !mounted) return;
    try {
      await api.request('/empresa/descontable', body: {
        'mes': periodo, 'valor': nuevo.replaceAll(',', '.'),
      });
      if (mounted) await cargar();
    } catch (e) {
      if (mounted) setState(() => errorPanel = message(e));
    }
  }

  void moverMes(int delta) {
    mes = DateTime(mes.year, mes.month + delta, 1);
    cargar();
  }

  Widget cifra(String nombre, String valor, IconData icono, Color color) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color.alphaBlend(color.withAlpha(38), Colors.white)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x22165976), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, color: color),
        const SizedBox(height: 8),
        Text(nombre),
        Text(valor, style: const TextStyle(
          fontSize: 23, fontWeight: FontWeight.w900, color: azulAero,
        )),
      ]),
    );
  }

  Widget grafica(String titulo, Map datos, Color color, {bool ranking = false}) {
    final entradas = datos.entries.map((e) =>
        MapEntry('${e.key}', (e.value as num).toDouble())).toList();

    if (ranking) {
      entradas.sort((a, b) => b.value.compareTo(a.value));
    } else {
      entradas.sort((a, b) => a.key.compareTo(b.key));
    }

    final maximo = entradas.fold<double>(0, (a, b) => a > b.value ? a : b.value);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 17, color: azulAero,
          )),
          const SizedBox(height: 10),
          if (entradas.isEmpty) const Text('Sin movimientos en este mes.'),
          for (final e in (ranking ? entradas.take(8) : entradas)) ...[
            Wrap(spacing: 12, children: [
              Text(e.key),
              Text(pesos(e.value), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 3),
            LinearProgressIndicator(
              value: maximo == 0 ? 0 : (e.value / maximo).clamp(0, 1).toDouble(),
              minHeight: 10,
              borderRadius: BorderRadius.circular(8),
              color: color,
              backgroundColor: color.withAlpha(27),
            ),
            const SizedBox(height: 9),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    const metodos = {
      '10': 'Efectivo', '47': 'Transferencia',
      '48': 'Tarjeta crédito', '49': 'Tarjeta débito',
    };
    final porMetodo = <String, dynamic>{};
    if (r != null) {
      for (final e in (r['porMetodo'] as Map).entries) {
        porMetodo[metodos['${e.key}'] ?? 'Método ${e.key}'] = e.value;
      }
    }

    final cobrado = cobros.values.fold<double>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi empresa')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const AeroHero(
                titulo: 'Mi empresa',
                detalle: 'Servicios, ventas y recaudos en un solo lugar',
                icono: Icons.bubble_chart,
              ),
              const SizedBox(height: 14),
              Row(children: [
                IconButton(tooltip: 'Mes anterior',
                    onPressed: () => moverMes(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(child: Text(nombreMes(mes), textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
                IconButton(tooltip: 'Mes siguiente',
                    onPressed: () => moverMes(1), icon: const Icon(Icons.chevron_right)),
                IconButton(tooltip: 'Actualizar', onPressed: cargar,
                    icon: const Icon(Icons.refresh)),
              ]),
              if (cargando) const LinearProgressIndicator(),
              if (errorPanel != null) ErrorText(errorPanel!),
              Wrap(spacing: 10, runSpacing: 10, children: [
                if (r != null)
                  cifra('Ventas netas con IVA', pesos(r['ventasNetas']),
                      Icons.receipt_long, azulAero),
                cifra('Cobrado por QR', cargandoPay ? 'Consultando…'
                    : errorPay != null ? 'Sin conexión' : pesos(cobrado),
                    Icons.qr_code_2, aquaAero),
                if (r != null)
                  cifra('IVA de ventas', pesos(r['ivaVentas']),
                      Icons.account_balance, const Color(0xff8852a8)),
              ]),
              if (errorPay != null) ErrorText(errorPay!),
              const SizedBox(height: 16),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Catálogo de servicios',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const Text('Guarda el precio sin IVA y la tarifa de cada servicio.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => editarServicio(),
                    icon: const Icon(Icons.add), label: const Text('Nuevo servicio'),
                  ),
                  for (final s in servicios)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${s['nombre']}'),
                      subtitle: Text('${pesos(s['precio'])} antes de IVA · IVA ${s['iva']}%'),
                      onTap: () => editarServicio(s),
                      trailing: IconButton(
                        tooltip: 'Eliminar del catálogo',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final borrar = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('¿Eliminar ${s['nombre']} del catálogo?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancelar')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Eliminar')),
                              ],
                            ),
                          );
                          if (borrar == true && mounted) {
                            await cambiarCatalogo('/empresa/servicios/eliminar', {'id': s['id']});
                          }
                        },
                      ),
                    ),
                ]),
              )),
              if (r != null) ...[
                grafica('Ventas por día · con IVA', r['porDia'], aquaAero),
                grafica('Servicios más vendidos · valor antes de IVA',
                    r['porServicio'], const Color(0xff52820c), ranking: true),
                grafica('Métodos registrados en las facturas · con IVA',
                    porMetodo, const Color(0xff7950a5), ranking: true),
              ],
              if (!cargandoPay && errorPay == null)
                grafica('Cobros QR confirmados por día', cobros, const Color(0xff0075ba)),
              if (r != null)
                Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Estimación mensual de IVA',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('IVA generado en ventas: ${pesos(r['ivaVentas'])}'),
                    Text('IVA que reducen las notas crédito: ${pesos(r['ivaNotas'])}'),
                    Text('IVA descontable registrado: ${pesos(r['descontable'])}'),
                    const Divider(),
                    Text(
                      (r['saldoEstimado'] as num) >= 0
                          ? 'Saldo estimado: ${pesos(r['saldoEstimado'])}'
                          : 'Diferencia estimada a favor: ${pesos((r['saldoEstimado'] as num).abs())}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    TextButton(onPressed: descontable,
                        child: const Text('Registrar total de IVA descontable')),
                    const Text('Ventas y notas emitidas desde esta instalación. '
                        'La estimación requiere conciliar retenciones, saldos y demás ajustes del período.'),
                  ]),
                )),
            ],
          ),
        ),
      ),
    );
  }
}