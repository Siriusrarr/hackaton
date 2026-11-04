import pathUtil from 'node:path';
import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

import {
  listarServicios,
  guardarServicio,
  eliminarServicio,
  guardarDescontable,
  registrarDocumento,
  resumenMensual,
} from './empresa.mjs';

const config = process.env;
for (const key of ['FACTUS_CLIENT_ID','FACTUS_CLIENT_SECRET','FACTUS_PASSWORD','DEMO_PASSWORD']) {
  if (!config[key]) throw new Error('Falta configurar ' + key);
}
const publicRoot = fileURLToPath(new URL('../public/', import.meta.url));
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript','.mjs':'text/javascript',
  '.json':'application/json','.wasm':'application/wasm','.png':'image/png','.css':'text/css',
  '.svg':'image/svg+xml','.woff2':'font/woff2','.woff':'font/woff','.ttf':'font/ttf',
  '.otf':'font/otf','.ico':'image/x-icon','.webmanifest':'application/manifest+json'};
const FACTUS = 'https://api-sandbox.factus.com.co';
const PAY = 'https://pay-api-sandbox.factus.com.co';
const WEB_ORIGIN = process.env.RENDER_EXTERNAL_URL || 'http://localhost:8787';

const clientes = new DatabaseSync(fileURLToPath(new URL('./facturin.sqlite', import.meta.url)));
clientes.exec(`CREATE TABLE IF NOT EXISTS clientes (
  id TEXT PRIMARY KEY, tipo TEXT NOT NULL, documento TEXT NOT NULL,
  nombre TEXT NOT NULL, telefono TEXT NOT NULL, UNIQUE(tipo, documento)
)`);

function guardarCliente(body) {
  const tipo = String(body.tipo || '');
  const documento = String(body.documento || '').trim().toUpperCase();
  const nombre = String(body.nombre || '').trim();
  const telefono = String(body.telefono || '').trim();
  if (!['13','22','41','31'].includes(tipo) || !/^[A-Z0-9-]{1,30}$/.test(documento) ||
      !nombre || nombre.length > 140 || !/^\+?[0-9 ()-]+$/.test(telefono) ||
      !/^\d{7,15}$/.test(telefono.replace(/\D/g,''))) {
    throw error(422, 'Revisa el nombre, el documento y el teléfono del cliente.');
  }
  const id = body.id || randomUUID();
  const duplicado = clientes.prepare('SELECT id FROM clientes WHERE tipo=? AND documento=?').get(tipo, documento);
  if (duplicado && duplicado.id !== id) throw error(409, 'Ya existe un cliente con ese documento.');
  if (body.id) {
    const cambios = clientes.prepare('UPDATE clientes SET tipo=?, documento=?, nombre=?, telefono=? WHERE id=?')
      .run(tipo, documento, nombre, telefono, id);
    if (!cambios.changes) throw error(404,'El cliente ya no está en el registro.');
  } else {
    clientes.prepare('INSERT INTO clientes(id,tipo,documento,nombre,telefono) VALUES(?,?,?,?,?)')
      .run(id,tipo,documento,nombre,telefono);
  }
  return {id};
}

const sessions = new Map();
let payTokenPromise;

function error(status, message) {
  return Object.assign(new Error(message), { status });
}

function jsonPost(body) {
  return {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

async function callApi(base, path, options = {}) {
  const response = await fetch(base + path, {
    ...options,
    redirect: 'error',
    signal: AbortSignal.timeout(30000),
    headers: {
      Accept: 'application/json',
      ...options.headers,
    },
  });

  const data = await response.json().catch(() => ({}));

  if (!response.ok) {
    const service = base === PAY ? 'Factus Pay' : 'Facturación';
    const detail = data.data?.errors || data.errors;
    const description =
      data.message ||
      data.error_description ||
      data.error ||
      'Solicitud rechazada';

    throw error(
      response.status,
      `${service} · ${options.method || 'GET'} ${path.split('?')[0]}` +
        ` · HTTP ${response.status}\n${description}` +
        (detail ? '\n' + JSON.stringify(detail, null, 2) : ''),
    );
  }

  return data;
}

function oauth(fields) {
  return callApi(FACTUS, '/oauth/token', {
    method: 'POST',
    body: new URLSearchParams({
      client_id: config.FACTUS_CLIENT_ID,
      client_secret: config.FACTUS_CLIENT_SECRET,
      ...fields,
    }),
  });
}

function saveTokens(session, tokens) {
  session.access = tokens.access_token;
  session.refresh = tokens.refresh_token || session.refresh;
  session.expires =
    Date.now() + (Number(tokens.expires_in || 600) - 30) * 1000;
}

async function billingToken(session) {
  if (Date.now() < session.expires) return session.access;

  session.refreshing ??= oauth({
    grant_type: 'refresh_token',
    refresh_token: session.refresh,
  })
    .then((tokens) => {
      saveTokens(session, tokens);
      return session.access;
    })
    .finally(() => {
      session.refreshing = null;
    });

  return session.refreshing;
}

function payToken() {
  if (!config.PAY_EMAIL || !config.PAY_PASS) {
    throw error(503, 'Faltan las credenciales de recaudos en backend/env.json.');
  }

  payTokenPromise ??= callApi(
    PAY,
    '/auth',
    jsonPost({
      email: config.PAY_EMAIL,
      password: config.PAY_PASS,
    }),
  )
    .then((data) => {
      if (!data.token) throw error(502, 'Factus Pay no devolvió un token.');
      return data.token;
    })
    .catch((cause) => {
      payTokenPromise = undefined;
      throw cause;
    });

  return payTokenPromise;
}

async function readBody(req) {
  const chunks = [];
  let size = 0;

  for await (const chunk of req) {
    size += chunk.length;
    if (size > 256000) throw error(413, 'Solicitud demasiado grande.');
    chunks.push(chunk);
  }

  try {
    const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error();
    }
    return data;
  } catch {
    throw error(400, 'La solicitud debe contener un objeto JSON válido.');
  }
}

const billingGets =
  /^\/v2\/(?:numbering-ranges|bills(?:\/[\w.-]+(?:\/download-pdf)?)?)$/;

const billingPosts =
  /^\/v2\/(?:bills|credit-notes|support-documents|adjustment-notes)\/validate$/;

async function handle(req) {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  if (req.method === 'POST' && path === '/session') {
    const { email, password } = await readBody(req);

    if (email !== 'sandboxv2@factus.com.co' || typeof password !== 'string') {
      throw error(401, 'Usa la cuenta de facturación Sandbox V2.');
    }

    if (password !== config.DEMO_PASSWORD) throw error(401, 'Clave de la demo incorrecta.');
    const tokens = await oauth({
      grant_type: 'password',
      username: email,
      password: config.FACTUS_PASSWORD,
    });

    const id = randomUUID();
    const session = { end: Date.now() + 8 * 60 * 60 * 1000 };
    saveTokens(session, tokens);
    sessions.set(id, session);

    return { session: id };
  }

  const id = req.headers.authorization?.replace(/^Bearer /, '');
  const session = sessions.get(id);

  if (!session || session.end <= Date.now()) {
    throw error(401, 'La sesión local terminó. Vuelve a ingresar.');
  }

  if (req.method === 'POST' && path === '/logout') {
    sessions.delete(id);
    return {};
  }

  // Datos locales de la empresa.
  if (req.method === 'GET' && path === '/empresa/servicios') {
    return listarServicios();
  }
  if (req.method === 'GET' && path === '/empresa/clientes') {
    return {data:clientes.prepare('SELECT * FROM clientes ORDER BY nombre COLLATE NOCASE, documento').all()};
  }
  if (req.method === 'POST' && path === '/empresa/clientes') {
    return guardarCliente(await readBody(req));
  }
  if (req.method === 'POST' && path === '/empresa/clientes/eliminar') {
    const {id} = await readBody(req);
    clientes.prepare('DELETE FROM clientes WHERE id=?').run(id);
    return {ok:true};
  }

  if (req.method === 'POST' && path === '/empresa/servicios') {
    return guardarServicio(await readBody(req));
  }

  if (req.method === 'POST' && path === '/empresa/servicios/eliminar') {
    const body = await readBody(req);
    return eliminarServicio(body.id);
  }

  if (req.method === 'GET' && path === '/empresa/resumen') {
    return resumenMensual(url.searchParams.get('mes'));
  }

  if (req.method === 'POST' && path === '/empresa/descontable') {
    return guardarDescontable(await readBody(req));
  }

  if(req.method==='GET' && path==='/inventario/catalogo') return {data:[...listarServicios().data,...articulos()]};
  if(req.method==='GET' && path==='/inventario') return {
    data:articulos(),
    movimientos:clientes.prepare('SELECT * FROM movimientos ORDER BY id DESC LIMIT 100').all(),
    pendientes:clientes.prepare("SELECT ref FROM pedidos_stock WHERE estado='pendiente'").all(),
  };
  if(req.method==='POST' && path==='/inventario/productos') return nuevoProducto(await readBody(req));
  if(req.method==='POST' && path==='/inventario/movimientos') return ajusteStock(await readBody(req));
  if(req.method==='POST' && path==='/inventario/conciliar') return resolverReserva(await readBody(req));
  // Operaciones remotas permitidas.
  const isPay =
    (req.method === 'POST' && path === '/v1/collections') ||
    (req.method === 'GET' && path === '/v1/collections') ||
    (req.method === 'GET' && /^\/v1\/collections\/[\w.-]+$/.test(path));

  const isBilling =
    (req.method === 'GET' && billingGets.test(path)) ||
    (req.method === 'POST' && billingPosts.test(path));

  if (!isPay && !isBilling) throw error(404, 'Ruta desconocida.');

  const enviado = req.method === 'POST' ? await readBody(req) : null;
  const options = enviado === null ? {} : jsonPost(enviado);

  const execute = (token) =>
    callApi(isPay ? PAY : FACTUS, path + url.search, {
      ...options,
      headers: {
        ...options.headers,
        Authorization: `Bearer ${token}`,
      },
    });

  if (isPay) {
    const pending = payToken();
    const token = await pending;

    try {
      return await execute(token);
    } catch (cause) {
      if (cause.status !== 401) throw cause;
      if (payTokenPromise === pending) payTokenPromise = undefined;
      return execute(await payToken());
    }
  }

  const token = await billingToken(session);
  const result = path === '/v2/bills/validate' && enviado
    ? await facturarConStock(enviado, () => execute(token))
    : await execute(token);

  if (enviado !== null) {
    try {
      registrarDocumento(path, enviado, result);
    } catch (cause) {
      console.error('Registro local pendiente:', cause.message);
      return {
        ...result,
        message:
          `${result.message || 'Documento aceptado'}. Factus recibió el documento. ` +
          'Queda pendiente conciliarlo en el panel local.',
      };
    }
  }

  return result;
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');

  try {
    if (req.headers.origin && req.headers.origin !== WEB_ORIGIN) {
      throw error(403, 'Abre la aplicación en su dirección de Render.');
    }

    res.setHeader('Access-Control-Allow-Origin', WEB_ORIGIN);
    res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      return res.end();
    }

    const route = new URL(req.url, 'http://localhost').pathname;
    if (route === '/healthz' && req.method === 'GET') {
      return res.end(JSON.stringify({ok:true}));
    }
    if (['GET','HEAD'].includes(req.method) && !/^\/(session|logout|v1|v2|empresa|inventario)(\/|$)/.test(route)) {
      const filename = pathUtil.resolve(publicRoot,'.'+decodeURIComponent(route === '/' ? '/index.html' : route));
      if (!filename.startsWith(publicRoot)) throw error(404,'Archivo no encontrado.');
      let content;
      try { content=await readFile(filename); }
      catch { throw error(404,'Archivo no encontrado.'); }
      res.setHeader('Content-Type', mime[pathUtil.extname(filename)] || 'application/octet-stream');
      return res.end(req.method === 'HEAD' ? undefined : content);
    }
    const result = await handle(req);
    res.end(JSON.stringify(result));
  } catch (cause) {
    res.writeHead(cause.status || 502);
    res.end(JSON.stringify({
      message: cause.status
        ? cause.message
        : 'No se pudo completar la operación. Si estabas emitiendo, consulta la referencia antes de repetir.',
    }));
  }
});

setInterval(() => {
  for (const [id, session] of sessions) {
    if (session.end <= Date.now()) sessions.delete(id);
  }
}, 60000).unref();

server.listen(Number(process.env.PORT || 8787), '0.0.0.0', () => {
  console.log('Facturín listo para recibir peticiones');
});

// Inventario de artículos físicos. Los servicios siguen en su catálogo original.
clientes.exec(`
  CREATE TABLE IF NOT EXISTS productos (
    sku TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio INTEGER NOT NULL, iva INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS movimientos (
    id INTEGER PRIMARY KEY, sku TEXT NOT NULL, unidades INTEGER NOT NULL,
    motivo TEXT NOT NULL, fecha TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  );
  CREATE TABLE IF NOT EXISTS pedidos_stock (
    ref TEXT PRIMARY KEY, estado TEXT NOT NULL, lineas TEXT NOT NULL, respuesta TEXT
  );
  CREATE TABLE IF NOT EXISTS reservas_stock (
    ref TEXT NOT NULL, sku TEXT NOT NULL, unidades INTEGER NOT NULL, PRIMARY KEY(ref,sku)
  );
  CREATE INDEX IF NOT EXISTS mov_sku ON movimientos(sku);
  CREATE INDEX IF NOT EXISTS reserva_sku ON reservas_stock(sku);
`);
const transaccion = fn => {
  clientes.exec('BEGIN IMMEDIATE');
  try { const dato=fn(); clientes.exec('COMMIT'); return dato; }
  catch(e) { clientes.exec('ROLLBACK'); throw e; }
};
const consultaProductos = `
 SELECT p.sku,p.nombre,p.precio/100.0 AS precio,p.iva/100.0 AS iva,
   COALESCE((SELECT SUM(unidades) FROM movimientos WHERE sku=p.sku),0) AS existencia,
   COALESCE((SELECT SUM(unidades) FROM reservas_stock WHERE sku=p.sku),0) AS reservado FROM productos p`;
function articulos() {
  return clientes.prepare(consultaProductos+' ORDER BY nombre COLLATE NOCASE').all()
    .map(p=>({...p,disponible:p.existencia-p.reservado}));
}
function cantidad(n) {
  if(!Number.isSafeInteger(n)||n<1||n>999999) throw error(422,'Usa entre 1 y 999999 unidades.');
  return n;
}
function importe(v,max) {
  if(!/^\d+(\.\d{1,2})?$/.test(String(v)) || Number(v)>max) throw error(422,'Revisa el precio y el IVA.');
  return Math.round(Number(v)*100);
}
function nuevoProducto(b) {
  const sku=String(b.sku||'').trim().toUpperCase(), nombre=String(b.nombre||'').trim();
  if(!/^[A-Z0-9][A-Z0-9_-]{0,23}$/.test(sku)||!nombre||nombre.length>100) throw error(422,'Revisa el código y el nombre.');
  const precio=importe(b.precio,999999999), iva=importe(b.iva,100);
  if(precio===0) throw error(422,'El precio debe ser positivo.');
  const inicial=b.inicial===0?0:cantidad(b.inicial);
  return transaccion(()=>{
    if(clientes.prepare('SELECT 1 FROM productos WHERE sku=?').get(sku)) throw error(409,'Ese código ya existe.');
    clientes.prepare('INSERT INTO productos VALUES(?,?,?,?)').run(sku,nombre,precio,iva);
    if(inicial) movimiento(sku,inicial,'Inventario inicial');
    return {ok:true};
  });
}
function movimiento(sku,unidades,motivo) {
  clientes.prepare('INSERT INTO movimientos(sku,unidades,motivo) VALUES(?,?,?)').run(sku,unidades,motivo);
}
function disponible(sku) {
  const p=clientes.prepare(consultaProductos+' WHERE p.sku=?').get(sku);
  if(!p) throw error(404,'Producto desconocido: '+sku);
  return p.existencia-p.reservado;
}
function ajusteStock(b) {
  const n=cantidad(b.cantidad), motivo=String(b.motivo||'').trim();
  if(!['entrada','salida'].includes(b.tipo)||!motivo||motivo.length>160) throw error(422,'Indica tipo y motivo del movimiento.');
  return transaccion(()=>{
    const saldo=disponible(b.sku);
    if(b.tipo==='salida'&&n>saldo) throw error(409,'Existencias insuficientes.');
    movimiento(b.sku,b.tipo==='entrada'?n:-n,motivo);
    return {ok:true};
  });
}
const enCurso=new Set();
function cerrarReserva(ref,respuesta) {
  return transaccion(()=>{
    const reservas=clientes.prepare('SELECT * FROM reservas_stock WHERE ref=?').all(ref);
    if(respuesta) for(const r of reservas) movimiento(r.sku,-r.unidades,'Factura '+ref);
    clientes.prepare('DELETE FROM reservas_stock WHERE ref=?').run(ref);
    if(respuesta) clientes.prepare("UPDATE pedidos_stock SET estado='emitida',respuesta=? WHERE ref=?").run(JSON.stringify(respuesta),ref);
    else clientes.prepare('DELETE FROM pedidos_stock WHERE ref=?').run(ref);
    return {ok:true};
  });
}
async function facturarConStock(body,emitir) {
  const ref=body.reference_code, lineas=new Map();
  for(const item of body.items||[]) {
    const codigo=String(item.code_reference||'');
    if(!codigo.startsWith('INV-')) continue;
    const sku=codigo.slice(4);
    lineas.set(sku,(lineas.get(sku)||0)+cantidad(Number(item.quantity)));
  }
  const previo=clientes.prepare('SELECT * FROM pedidos_stock WHERE ref=?').get(ref);
  if(previo) {
    if(previo.lineas!==JSON.stringify(body)) throw error(409,'Ya existe una operación diferente con esta referencia.');
    if(previo.estado==='emitida') return JSON.parse(previo.respuesta);
    throw error(409,'Esta factura tiene existencias reservadas. Consulta su referencia en Inventario.');
  }
  if(!lineas.size) return emitir();
  transaccion(()=>{
    clientes.prepare('INSERT INTO pedidos_stock VALUES(?,?,?,NULL)').run(ref,'pendiente',JSON.stringify(body));
    for(const [sku,n] of lineas) {
      if(n>disponible(sku)) throw error(409,'Stock insuficiente para '+sku+'.');
      clientes.prepare('INSERT INTO reservas_stock VALUES(?,?,?)').run(ref,sku,n);
    }
  });
  enCurso.add(ref);
  try {
    const result=await emitir();
    const doc=result?.data?.bill??result?.data;
    if(!doc?.number || [0,'0',false].includes(doc.status)) throw error(502,'Emisión sin confirmar. Revisa la reserva en Inventario.');
    cerrarReserva(ref,result);
    return result;
  } catch(e) {
    if([400,401,403,404,422,429].includes(e.status)) cerrarReserva(ref,null);
    throw e;
  } finally {enCurso.delete(ref);}
}
function resolverReserva(b) {
  if(enCurso.has(b.ref)) throw error(409,'La emisión sigue en curso.');
  const p=clientes.prepare("SELECT * FROM pedidos_stock WHERE ref=? AND estado='pendiente'").get(b.ref);
  if(!p) throw error(404,'Reserva ya resuelta.');
  if(b.accion==='liberar') return cerrarReserva(b.ref,null);
  const numero=String(b.numero||'').trim();
  if(b.accion!=='confirmar'||!numero) throw error(422,'Indica el número de factura verificado.');
  const r={message:'Factura conciliada',data:{bill:{number:numero,status:1}}};
  cerrarReserva(b.ref,r);
  registrarDocumento('/v2/bills/validate',JSON.parse(p.lineas),r);
  return {ok:true};
}
