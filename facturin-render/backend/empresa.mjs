import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const db = new DatabaseSync(
  fileURLToPath(new URL('./facturin.sqlite', import.meta.url)),
);

db.exec(`
  CREATE TABLE IF NOT EXISTS servicios (
    id TEXT PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio INTEGER NOT NULL,
    iva INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS ventas (
    tipo TEXT NOT NULL,
    referencia TEXT NOT NULL,
    fecha TEXT NOT NULL,
    metodo TEXT NOT NULL,
    lineas TEXT NOT NULL,
    PRIMARY KEY (tipo, referencia)
  );

  CREATE TABLE IF NOT EXISTS descontables (
    mes TEXT PRIMARY KEY,
    centavos INTEGER NOT NULL
  );
`);

function invalido(mensaje) {
  return Object.assign(new Error(mensaje), { status: 422 });
}

function mesValido(mes) {
  if (typeof mes !== 'string' || !/^\d{4}-(0[1-9]|1[0-2])$/.test(mes)) {
    throw invalido('El mes debe tener formato AAAA-MM.');
  }
  return mes;
}

function centavos(valor, maximo = 1000000000000) {
  const texto = String(valor ?? '').trim().replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(texto)) {
    throw invalido('Escribe un importe con máximo dos decimales.');
  }

  const numero = Number(texto);
  if (!Number.isFinite(numero) || numero > maximo) {
    throw invalido('El importe está fuera del rango permitido.');
  }

  return Math.round(numero * 100);
}

function hoyColombia() {
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'America/Bogota',
  }).format(new Date());
}

function sumar(mapa, clave, importe) {
  mapa.set(clave, (mapa.get(clave) || 0) + importe);
}

function enPesos(mapa) {
  return Object.fromEntries(
    [...mapa.entries()].map(([clave, valor]) => [clave, valor / 100]),
  );
}

export function listarServicios() {
  const datos = db.prepare(`
    SELECT id, nombre, precio / 100.0 AS precio, iva / 100.0 AS iva
    FROM servicios
    ORDER BY nombre COLLATE NOCASE
  `).all();

  return { data: datos };
}

export function guardarServicio(datos) {
  const nombre = String(datos.nombre ?? '').trim();
  if (!nombre || nombre.length > 100) {
    throw invalido('El nombre del servicio debe tener entre 1 y 100 caracteres.');
  }

  const precio = centavos(datos.precio);
  const iva = centavos(datos.iva, 100);
  if (precio <= 0) throw invalido('El precio debe ser mayor que cero.');

  const id = datos.id || randomUUID();

  db.prepare(`
    INSERT INTO servicios(id, nombre, precio, iva)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      nombre = excluded.nombre,
      precio = excluded.precio,
      iva = excluded.iva
  `).run(id, nombre, precio, iva);

  return listarServicios();
}

export function eliminarServicio(id) {
  db.prepare('DELETE FROM servicios WHERE id = ?').run(id);
  return listarServicios();
}

export function guardarDescontable(datos) {
  const mes = mesValido(datos.mes);
  const valor = centavos(datos.valor);

  db.prepare(`
    INSERT INTO descontables(mes, centavos) VALUES (?, ?)
    ON CONFLICT(mes) DO UPDATE SET centavos = excluded.centavos
  `).run(mes, valor);

  return { ok: true };
}

// Se llama después de que Factus acepta la operación.
// Guardamos los importes del formulario vigente en el momento de emitir.
// Editar un servicio mañana no modifica las ventas de hoy.
export function registrarDocumento(ruta, enviado, respuesta) {
  const esFactura = ruta === '/v2/bills/validate';
  const esNota = ruta === '/v2/credit-notes/validate';
  if (!esFactura && !esNota) return;

  const datos = respuesta?.data;
  const documento = esFactura
    ? datos?.bill ?? datos
    : datos?.credit_note ?? datos;

  if (!documento?.number) return;
  if ([0, '0', false].includes(documento.status)) return;

  const lineas = enviado.items.map((item) => {
    const base = Math.round(
      Number(item.quantity) *
      centavos(item.price) *
      (1 - Number(item.discount_rate || 0) / 100),
    );

    const iva = (item.taxes || [])
      .filter((impuesto) => impuesto.code === '01')
      .reduce(
        (total, impuesto) =>
          total + Math.round(base * Number(impuesto.rate) / 100),
        0,
      );

    return {
      nombre: String(item.name),
      base,
      iva,
    };
  });

  const fecha =
    String(documento.created_at || '').match(/^\d{4}-\d{2}-\d{2}/)?.[0] ||
    hoyColombia();

  db.prepare(`
    INSERT OR IGNORE INTO ventas(tipo, referencia, fecha, metodo, lineas)
    VALUES (?, ?, ?, ?, ?)
  `).run(
    esFactura ? 'factura' : 'credito',
    enviado.reference_code,
    fecha,
    String(enviado.payment_details?.[0]?.payment_method_code || 'otro'),
    JSON.stringify(lineas),
  );
}

export function resumenMensual(mes) {
  mesValido(mes);

  const documentos = db.prepare(`
    SELECT tipo, fecha, metodo, lineas
    FROM ventas
    WHERE substr(fecha, 1, 7) = ?
    ORDER BY fecha
  `).all(mes);

  let ventas = 0;
  let notasCredito = 0;
  let ivaVentas = 0;
  let ivaNotas = 0;

  const porDia = new Map();
  const porServicio = new Map();
  const porMetodo = new Map();

  for (const doc of documentos) {
    for (const linea of JSON.parse(doc.lineas)) {
      const total = linea.base + linea.iva;

      if (doc.tipo === 'credito') {
        notasCredito += total;
        ivaNotas += linea.iva;
        continue;
      }

      ventas += total;
      ivaVentas += linea.iva;
      sumar(porDia, doc.fecha, total);
      sumar(porServicio, linea.nombre, linea.base);
      sumar(porMetodo, doc.metodo, total);
    }
  }

  const descontable = db.prepare(
    'SELECT centavos FROM descontables WHERE mes = ?',
  ).get(mes)?.centavos || 0;

  return {
    ventas: ventas / 100,
    notasCredito: notasCredito / 100,
    ventasNetas: (ventas - notasCredito) / 100,
    ivaVentas: ivaVentas / 100,
    ivaNotas: ivaNotas / 100,
    descontable: descontable / 100,
    saldoEstimado: (ivaVentas - ivaNotas - descontable) / 100,
    porDia: enPesos(porDia),
    porServicio: enPesos(porServicio),
    porMetodo: enPesos(porMetodo),
  };
}