// Construye el sidebar de navegación y protege la página con autenticación.
const NAV_ITEMS = [
  { key: 'dashboard', label: 'Inicio', href: 'dashboard.html' },
  { key: 'agenda', label: 'Agenda', href: 'agenda.html' },
  { key: 'diagnosticos', label: 'Diagnósticos', href: 'diagnosticos.html' },
  { key: 'cotizaciones', label: 'Cotizaciones', href: 'cotizaciones.html' },
  { key: 'ordenes', label: 'Órdenes de trabajo', href: 'ordenes.html' },
  { key: 'inspecciones', label: 'Inspecciones', href: 'inspecciones.html' },
  { key: 'clientes', label: 'Clientes', href: 'clientes.html' },
  { key: 'vehiculos', label: 'Vehículos', href: 'vehiculos.html' },
  { key: 'trabajos', label: 'Catálogo de trabajos', href: 'trabajos.html' },
  { key: 'inventario', label: 'Inventario', href: 'inventario.html' },
  { key: 'pagos', label: 'Pagos', href: 'pagos.html' },
  { key: 'referidos', label: 'Club Autonova', href: 'referidos.html' },
  { key: 'contabilidad', label: 'Contabilidad', href: 'contabilidad.html' },
  { key: 'configuracion', label: 'Configuración', href: 'configuracion.html' },
];

// Secciones de Configuración: el ítem «Configuración» del menú se despliega y lleva directo a cada una
// (configuracion.html#id). «Todo» muestra la página completa con cada sección plegable.
const SECCIONES_CONFIG = [
  { id: 'todo', label: 'Todo' },
  { id: 'taller', label: 'Datos del taller' },
  { id: 'valores', label: 'Valores e IVA' },
  { id: 'reparto', label: 'Reparto de mano de obra' },
  { id: 'bodegaje', label: 'Bodegaje' },
  { id: 'politicas-legales', label: 'Políticas y términos legales' },
  { id: 'whatsapp', label: 'Mensajes de la agenda' },
  { id: 'patentes', label: 'Consulta de patentes' },
  { id: 'planes-inspeccion', label: 'Planes de inspección' },
  { id: 'domicilio', label: 'Atención a domicilio' },
  { id: 'club', label: 'Club Autonova (referidos)' },
  { id: 'encuesta', label: 'Encuesta y reseñas' },
  { id: 'correo', label: 'Correo automático' },
  { id: 'mensajes-correo', label: 'Mensajes al cliente' },
  { id: 'registro-correos', label: 'Correos enviados' },
  { id: 'horario', label: 'Horario de atención' },
  { id: 'bloqueos', label: 'Bloqueos de agenda' },
  { id: 'politicas-servicio', label: 'Políticas de servicio' },
];

// Estados con su etiqueta y color de badge
const ESTADOS_COTIZACION = {
  borrador:   { label: 'Borrador',   badge: 'badge-gray' },
  enviada:    { label: 'Enviada',    badge: 'badge-blue' },
  aprobada:   { label: 'Aprobada',   badge: 'badge-green' },
  rechazada:  { label: 'Rechazada',  badge: 'badge-red' },
  convertida: { label: 'Convertida a OT', badge: 'badge-purple' },
};

const ESTADOS_ORDEN = {
  recepcion:   { label: 'Recepción',   badge: 'badge-gray' },
  diagnostico: { label: 'Diagnóstico', badge: 'badge-yellow' },
  en_proceso:  { label: 'En proceso',  badge: 'badge-blue' },
  listo:       { label: 'Listo',       badge: 'badge-green' },
  entregado:   { label: 'Entregado',   badge: 'badge-purple' },
  cancelado:   { label: 'Cancelado',   badge: 'badge-red' },
};

const METODOS_PAGO = {
  efectivo: 'Efectivo',
  tarjeta_debito: 'Tarjeta débito',
  tarjeta_credito: 'Tarjeta crédito',
  transferencia: 'Transferencia',
  otro: 'Otro',
};

// Tipos de ítem de cotización / orden de trabajo
const TIPO_ITEM = {
  mano_obra:       { label: 'Mano de obra',     badge: 'badge-blue' },
  repuesto:        { label: 'Repuesto',         badge: 'badge-purple' },
  insumo_taller:   { label: 'Insumo taller',    badge: 'badge-yellow' },
  insumo_vehiculo: { label: 'Insumo vehículo',  badge: 'badge-green' },
  trabajo:         { label: 'Trabajo externo',  badge: 'badge-orange' },   // «Otro» clasificado como trabajo externo
  insumo:          { label: 'Insumo',           badge: 'badge-yellow' },   // «Otro» clasificado como insumo
  otro:            { label: 'Otro',             badge: 'badge-gray' },
};

function badgeItem(tipo) {
  const t = TIPO_ITEM[tipo] || TIPO_ITEM.otro;
  return `<span class="badge ${t.badge}">${t.label}</span>`;
}

function fmtMoneda(n) {
  if (n == null || isNaN(Number(n))) return '–';
  return Number(n).toLocaleString('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 });
}

function fmtFecha(d) {
  if (!d) return '–';
  // Una fecha sola (AAAA-MM-DD) se lee a mediodía: a medianoche UTC en Chile mostraba el día anterior
  if (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d)) d = d + 'T12:00:00';
  return new Date(d).toLocaleDateString('es-CL', { dateStyle: 'short' });
}

function fmtFechaHora(d) {
  if (!d) return '–';
  return new Date(d).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' });
}

function badgeEstado(estado, mapa) {
  const e = mapa[estado] || { label: estado, badge: 'badge-gray' };
  return `<span class="badge ${e.badge}">${e.label}</span>`;
}

// Número de documento con prefijo: COT-0001 / OT-0001
function fmtNumero(prefijo, numero) {
  return `${prefijo}-${String(numero ?? 0).padStart(4, '0')}`;
}

// ---------- Descuento (en % o en pesos, SOLO sobre mano de obra) ----------
// Un descuento se guarda como { tipo: 'pct' | 'monto', pct, monto, base }:
//  · 'pct': un porcentaje de la mano de obra; el monto en pesos se recalcula si cambian los ítems.
//  · 'monto': un valor fijo en pesos; el % es solo una referencia y cambia con los ítems.
//  · base: 'mano_obra' (lo normal: nunca toca repuestos, insumos ni trabajos externos) o 'total'
//    (documentos anteriores a v43, que conservan su cálculo para no alterar totales ya emitidos).
// En las tablas viven en descuento_tipo, descuento_pct, descuento_monto y descuento_base.
// Acepta un número (porcentaje, como antes), una fila de la base o { tipo, pct, monto, base }.
function normalizarDescuento(d) {
  if (d == null || d === '') return { tipo: 'pct', pct: 0, monto: 0, base: 'mano_obra' };
  if (typeof d === 'number' || typeof d === 'string') return { tipo: 'pct', pct: Number(d) || 0, monto: 0, base: 'mano_obra' };
  const tipo = (d.tipo || d.descuento_tipo) === 'monto' ? 'monto' : 'pct';
  return {
    tipo,
    pct: Number(d.pct ?? d.descuento_pct ?? 0) || 0,
    monto: Number(d.monto ?? d.descuento_monto ?? 0) || 0,
    base: (d.base || d.descuento_base) === 'total' ? 'total' : 'mano_obra',
  };
}

// ¿El ítem es mano de obra? El subtipo elegido en «Otro» manda sobre el tipo genérico.
// Repuestos, insumos del taller o del vehículo y trabajos externos NO lo son.
function esManoDeObra(item) {
  const sub = (item.tipo === 'otro' && item.tipo_otro) ? item.tipo_otro : item.tipo;
  return sub === 'mano_obra';
}

// ---------- Líneas de cotización / OT / diagnóstico: tipo, horas de trabajo y cantidad ----------
// Cada línea cumple siempre total = cantidad × precio_unitario (así se calcula todo). Para que el cliente entienda
// la mano de obra, las líneas del catálogo guardan además:
//   · horas     = horas de trabajo POR TRABAJO
//   · por_hora  = true si precio_unitario es el valor de la HORA (cantidad = horas × veces);
//                 false si es el precio de cada trabajo (cantidad = veces)
// Las líneas antiguas sin ese detalle se muestran como siempre (sin horas).

// Insignia de color con el tipo de la línea (el subtipo elegido en «Otro» manda sobre el genérico).
function badgeItemDe(item) {
  return badgeItem((item.tipo === 'otro' && item.tipo_otro) ? item.tipo_otro : item.tipo);
}

const fmtNumItem = (n) => Number(n).toLocaleString('es-CL', { maximumFractionDigits: 2 });

// { horas, cantidad, precio, porHora, total }: lo que se muestra en las columnas separadas.
function lineaVista(item) {
  const cantidad = Number(item.cantidad) || 0;
  const precio = Number(item.precio_unitario) || 0;
  let horas = null, veces = cantidad, porHora = false;
  if (esManoDeObra(item) && item.horas != null && item.horas !== '' && Number(item.horas) >= 0) {
    horas = Number(item.horas);
    if (item.por_hora && horas > 0) { porHora = true; veces = Math.round((cantidad / horas) * 100) / 100; }
  }
  return { horas, cantidad: veces, precio, porHora, total: cantidad * precio };
}

// Celdas de una fila (HTML): horas de trabajo · cantidad · precio unitario · total. `estilo` se aplica a cada celda.
function celdasLinea(item, estilo = '') {
  const v = lineaVista(item);
  const td = (etiqueta, extra, html) => `<td data-label="${etiqueta}" style="${estilo}${extra}">${html}</td>`;
  return td('Horas de trabajo', 'text-align:center; white-space:nowrap;', v.horas != null ? `${fmtNumItem(v.horas)} h` : '–')
    + td('Cantidad', 'text-align:center;', fmtNumItem(v.cantidad))
    + td('Precio unit.', 'text-align:right; white-space:nowrap;', `${fmtMoneda(v.precio)}${v.porHora ? '<small style="color:#6b7280;">/h</small>' : ''}`)
    + td('Total', 'text-align:right; white-space:nowrap;', `<strong>${fmtMoneda(v.total)}</strong>`);
}

// Edición en línea (tablas de cotización y diagnóstico): mantiene total = cantidad × precio_unitario coherente
// con las columnas «Horas de trabajo» y «Cantidad».
function cambiarCantidadLinea(item, veces) {
  const v = lineaVista(item);
  veces = Number(veces) || 0;
  item.cantidad = v.porHora ? veces * v.horas : veces;
}
function cambiarHorasLinea(item, horas) {
  horas = Math.max(0, Number(horas) || 0);
  const v = lineaVista(item);
  item.horas = horas;
  if (item.por_hora) item.cantidad = (v.porHora ? v.cantidad : 1) * horas;
}

// Celdas editables «Horas de trabajo» y «Cantidad» de la tabla de edición.
function celdasHorasCantidadEditor(item, idx) {
  const v = lineaVista(item);
  return `<td style="text-align:center;">${v.horas != null
      ? `<input type="number" class="cell-horas" data-idx="${idx}" value="${v.horas}" min="0" step="0.25" />`
      : '<span style="color:var(--color-text-muted);">–</span>'}</td>
    <td><input type="number" class="cell-cant" data-idx="${idx}" value="${v.cantidad}" min="0" step="0.25" /></td>`;
}

// Campos de detalle (horas / por_hora) de una línea, para copiarlos al guardar o al pasar de un documento a otro.
function detalleItem(item) {
  return { horas: item.horas ?? null, por_hora: item.por_hora ?? null };
}

// Datos de una línea de mano de obra del catálogo.
//   t: trabajo · n: veces · opcion: opción elegida (combo) o null · horasPorTrabajo: solo si se cobra por hora
// Devuelve { cantidad, precio_unitario, horas, por_hora } (total = cantidad × precio_unitario, como siempre).
function datosManoObra(t, n, valorHora, { opcion = null, horasPorTrabajo = null } = {}) {
  n = Math.max(1, Number(n) || 1);
  const cobraPorHora = !opcion && t.precio_fijo == null;
  if (cobraPorHora) {
    const h = horasPorTrabajo != null ? Number(horasPorTrabajo) : Number(t.horas_estimadas || 0);
    return { cantidad: h * n, precio_unitario: Number(valorHora), horas: h, por_hora: true };
  }
  const precio = opcion ? Number(opcion.precio) : Number(t.precio_fijo);
  const h = opcion && opcion.horas != null && opcion.horas !== '' ? Number(opcion.horas) : Number(t.horas_estimadas || 0);
  return { cantidad: n, precio_unitario: precio, horas: h > 0 ? h : null, por_hora: false };
}

// Inserta líneas en cotizacion_items / orden_items / diagnostico_items. Si aún no se ejecutó v56 (columnas
// horas y por_hora), las guarda igual sin ese detalle para no impedir el guardado.
async function insertarItems(tabla, filas) {
  let r = await supabaseClient.from(tabla).insert(filas);
  if (r.error && /horas|por_hora|schema cache|PGRST204|42703/i.test(`${r.error.code || ''} ${r.error.message || ''}`)) {
    const sinDetalle = filas.map(({ horas, por_hora, ...resto }) => resto);
    r = await supabaseClient.from(tabla).insert(sinDetalle);
  }
  return r;
}

// Descuento de un documento sobre sus ítems ({ cantidad, precio_unitario, tipo, tipo_otro }).
// El descuento corre solo sobre la mano de obra (salvo documentos antiguos con base 'total').
// Devuelve { subtotal, subtotalMO, base, sobre, tipo, monto, pct, neto }.
function descuentoDeItems(items, d) {
  const n = normalizarDescuento(d);
  let subtotal = 0, subtotalMO = 0;
  (items || []).forEach(i => {
    const v = (Number(i.cantidad) * Number(i.precio_unitario)) || 0;
    subtotal += v;
    if (esManoDeObra(i)) subtotalMO += v;
  });
  const base = n.base === 'total' ? subtotal : subtotalMO;
  const c = calcularDescuento(base, n);
  return { subtotal, subtotalMO, base, sobre: n.base, tipo: c.tipo, monto: c.monto, pct: c.pct, neto: subtotal - c.monto };
}

// Texto de la línea de descuento, para que el cliente vea sobre qué se aplica.
function etiquetaDescuento(sobre, pct, base) {
  return sobre === 'total'
    ? `Descuento (${fmtPorcentaje(pct)}%)`
    : `Descuento sobre mano de obra (${fmtPorcentaje(pct)}% de ${fmtMoneda(base)})`;
}

// Descuento real sobre un subtotal: { tipo, monto (pesos), pct (% efectivo) }.
// El monto nunca supera el subtotal ni el % pasa de 100.
function calcularDescuento(subtotal, d) {
  const n = normalizarDescuento(d);
  subtotal = Number(subtotal) || 0;
  let monto;
  if (n.tipo === 'monto') monto = Math.min(Math.max(n.monto, 0), subtotal);
  else monto = subtotal * Math.min(100, Math.max(0, n.pct)) / 100;
  const pct = subtotal > 0 ? monto / subtotal * 100 : (n.tipo === 'pct' ? Math.min(100, Math.max(0, n.pct)) : 0);
  return { tipo: n.tipo, monto, pct };
}

// Para guardar en la base. Si es en pesos, también se deja el % equivalente de ese momento
// como referencia (lo leen sin problema pantallas que solo conocen el %).
// `base` es el monto sobre el que corre el descuento (la mano de obra): ver descuentoDeItems().
function campoDescuento(d, base) {
  const n = normalizarDescuento(d);
  if (n.tipo === 'monto') {
    const c = calcularDescuento(base, n);
    return { descuento_tipo: 'monto', descuento_monto: Math.round(n.monto), descuento_pct: Math.round(c.pct * 100) / 100, descuento_base: n.base };
  }
  return { descuento_tipo: 'pct', descuento_pct: Math.min(100, Math.max(0, n.pct)), descuento_monto: 0, descuento_base: n.base };
}

// Igual que campoDescuento, calculando la base a partir de los ítems del documento.
function campoDescuentoItems(d, items) {
  return campoDescuento(d, descuentoDeItems(items, d).base);
}

// Total (con IVA si corresponde) de una cotización, tomando de su OT los ítems, el descuento y el
// IVA cuando la OT ya existe (la OT manda). `cot` trae cotizacion_items y, si se quiere seguir la
// OT, ordenes(descuento_tipo, descuento_pct, descuento_monto, descuento_base, con_iva,
// orden_items(cantidad, precio_unitario, tipo, tipo_otro)). Los ítems deben traer tipo y tipo_otro:
// sin ellos no se sabe cuál es mano de obra.
function totalVigenteCotizacion(cot, ivaPct = 19) {
  const neto = netoVigenteCotizacion(cot);
  const o = (cot.ordenes || [])[0];
  const fuente = o || cot;
  return fuente.con_iva !== false ? neto * (1 + Number(ivaPct) / 100) : neto;
}

// Valor NETO (sin IVA) de una cotización, con su descuento aplicado. Si ya tiene OT, valen los
// ítems y el descuento de la OT. Es el valor que se muestra al cliente en agenda y recordatorios.
function netoVigenteCotizacion(cot) {
  const o = (cot.ordenes || [])[0];
  const fuente = o || cot;
  const items = o ? (o.orden_items || []) : (cot.cotizacion_items || []);
  return descuentoDeItems(items, fuente).neto;
}

// Opciones obligatorias (combos) de un trabajo: [{ nombre, precio (neto, mano de obra), horas }].
// Si tiene opciones, el servicio no se vende solo: al agregarlo se elige una.
function opcionesDeTrabajo(trabajo) {
  const o = trabajo && trabajo.opciones;
  return Array.isArray(o) ? o.filter(x => x && String(x.nombre || '').trim() && Number(x.precio) >= 0 && x.precio !== '' && x.precio != null) : [];
}

// Precio NETO (sin IVA) de la mano de obra de un trabajo del catálogo: el menor precio de sus
// opciones ("desde"), su precio fijo, o horas de taller x valor hora. null si no se puede calcular.
function precioNetoTrabajo(trabajo, valorHora) {
  if (!trabajo) return null;
  const ops = opcionesDeTrabajo(trabajo);
  if (ops.length) return Math.min(...ops.map(o => Number(o.precio)));
  if (trabajo.precio_fijo != null && trabajo.precio_fijo !== '') return Number(trabajo.precio_fijo);
  const horas = Number(trabajo.horas_estimadas ?? trabajo.horas);
  const vh = Number(valorHora);
  return (horas > 0 && vh > 0) ? horas * vh : null;
}

// Pregunta con qué opción se agrega un servicio que no se vende solo. Devuelve la opción elegida
// o null si se cancela. No depende de ninguna pantalla: arma su propia ventana.
function elegirOpcionTrabajo(trabajo) {
  return new Promise((resolve) => {
    const ops = opcionesDeTrabajo(trabajo);
    const fondo = document.createElement('div');
    fondo.className = 'modal-backdrop abierto';
    fondo.style.zIndex = '200';
    fondo.innerHTML = `
      <div class="modal" role="dialog" aria-modal="true">
        <h3>${htmlSeguro(trabajo.nombre)}</h3>
        <p style="color:var(--color-text-muted); font-size:0.85rem; margin-top:0;">
          Este servicio no se realiza solo. ¿Con qué opción? (valor de mano de obra, sin IVA)
        </p>
        ${ops.map((o, i) => `
          <button type="button" class="opcion-servicio" data-i="${i}" style="display:flex; justify-content:space-between; align-items:center; gap:1rem; width:100%; text-align:left; margin:0.4rem 0; padding:0.8rem 1rem; background:#fff; color:var(--color-text); border:1px solid var(--color-border); font-weight:600;">
            <span>${htmlSeguro(o.nombre)}</span>
            <span style="white-space:nowrap;">${fmtMoneda(o.precio)} <small style="font-weight:400; color:var(--color-text-muted);">+ IVA</small></span>
          </button>`).join('')}
        <div class="modal-acciones"><button type="button" class="btn-secondary" id="opcion-cancelar">Cancelar</button></div>
      </div>`;
    const cerrar = (valor) => { fondo.remove(); document.removeEventListener('keydown', alEsc); resolve(valor); };
    const alEsc = (e) => { if (e.key === 'Escape') cerrar(null); };
    fondo.addEventListener('click', (e) => {
      if (e.target === fondo || e.target.id === 'opcion-cancelar') return cerrar(null);
      const b = e.target.closest('.opcion-servicio');
      if (b) cerrar(ops[Number(b.dataset.i)]);
    });
    document.addEventListener('keydown', alEsc);
    document.body.appendChild(fondo);
  });
}

function fmtPorcentaje(n) {
  return Number(n || 0).toLocaleString('es-CL', { maximumFractionDigits: 2 });
}

// Controles de pantalla: <select id=idTipo> (% / $) + <input id=idValor>, y opcionalmente
// un <small id="{idValor}-equiv"> donde se muestra la otra unidad ("= $22.000" o "= 9,09 %").
// La base del descuento ('mano_obra' | 'total') viaja en data-base del <input> de valor: los
// documentos nuevos y todo descuento que se edite quedan sobre mano de obra.
function leerDescuentoUI(idValor, idTipo) {
  const tipo = document.getElementById(idTipo).value === 'monto' ? 'monto' : 'pct';
  const el = document.getElementById(idValor);
  const v = Math.max(0, Number(el.value) || 0);
  const base = el.dataset.base === 'total' ? 'total' : 'mano_obra';
  return tipo === 'monto' ? { tipo, pct: 0, monto: v, base } : { tipo, pct: Math.min(100, v), monto: 0, base };
}
// Nota bajo el control (<small id="{idValor}-base">): aclara que el descuento es solo sobre mano de obra.
function actualizarNotaDescuentoUI(idValor) {
  const nota = document.getElementById(idValor + '-base');
  if (!nota) return;
  const legado = document.getElementById(idValor).dataset.base === 'total';
  nota.textContent = legado
    ? 'Descuento anterior, aplicado sobre el total. Si lo modificas, pasa a ser solo sobre mano de obra.'
    : 'Solo sobre la mano de obra: no afecta repuestos, insumos ni trabajos externos.';
}
function escribirDescuentoUI(idValor, idTipo, d) {
  const n = normalizarDescuento(d);
  const tipoEl = document.getElementById(idTipo);
  tipoEl.value = n.tipo;
  tipoEl.dataset.tipoPrevio = n.tipo;     // para convertir bien si luego se cambia de unidad
  const el = document.getElementById(idValor);
  activarPesos(el, n.tipo === 'monto');   // en pesos se ve "$5.000"; en % queda como número
  el.value = n.tipo === 'monto' ? Math.round(n.monto) : n.pct;
  el.max = n.tipo === 'monto' ? '' : '100';
  el.step = n.tipo === 'monto' ? '1' : '0.5';
  el.dataset.base = n.base;
  actualizarNotaDescuentoUI(idValor);
}
// `base` = monto sobre el que corre el descuento (la mano de obra), no el total del documento.
function actualizarEquivDescuentoUI(idValor, idTipo, base) {
  const el = document.getElementById(idValor + '-equiv');
  if (!el) return;
  const d = leerDescuentoUI(idValor, idTipo);
  const c = calcularDescuento(base, d);
  if (!(c.monto > 0)) { el.textContent = ''; return; }
  el.textContent = d.tipo === 'pct' ? `= ${fmtMoneda(c.monto)}` : `= ${fmtPorcentaje(c.pct)} %`;
}
// Al cambiar de % a pesos (o al revés) el descuento sigue siendo el mismo: solo se expresa en la otra unidad.
// getSubtotal() entrega el monto de mano de obra vigente (la base); onChange() vuelve a calcular totales.
// Registrar ANTES de los listeners que recalculan totales: al tocar el valor, el descuento pasa a
// ser sobre mano de obra.
function setupDescuentoUI(idValor, idTipo, getSubtotal, onChange) {
  const tipoEl = document.getElementById(idTipo);
  if (!tipoEl || tipoEl.dataset.descuentoUi) return;
  tipoEl.dataset.descuentoUi = '1';
  tipoEl.dataset.tipoPrevio = tipoEl.value;
  const valorInput = document.getElementById(idValor);
  const aManoDeObra = () => {
    if (valorInput.dataset.base !== 'mano_obra') { valorInput.dataset.base = 'mano_obra'; actualizarNotaDescuentoUI(idValor); }
  };
  valorInput.addEventListener('input', aManoDeObra);
  tipoEl.addEventListener('change', () => {
    aManoDeObra();
    const subtotal = Number(getSubtotal()) || 0;
    const valorEl = document.getElementById(idValor);
    const anterior = tipoEl.dataset.tipoPrevio === 'monto' ? 'monto' : 'pct';
    const actual = { tipo: anterior, pct: anterior === 'pct' ? Number(valorEl.value) || 0 : 0, monto: anterior === 'monto' ? Number(valorEl.value) || 0 : 0 };
    const c = calcularDescuento(subtotal, actual);
    const destino = tipoEl.value === 'monto' ? 'monto' : 'pct';
    const nuevo = destino === 'monto'
      ? { tipo: 'monto', pct: 0, monto: Math.round(c.monto) }
      : { tipo: 'pct', pct: Math.round(c.pct * 100) / 100, monto: 0 };
    escribirDescuentoUI(idValor, idTipo, nuevo);
    onChange();
  });
}

// Combobox de autocompletado: un campo de texto que, al escribir, muestra
// una lista desplegable con las coincidencias (por nombre). El <select>
// oculto sigue siendo la fuente de verdad (value + evento "change"), así
// el resto del código que ya lee/escucha ese <select> no necesita cambiar.
// dataArray se lee por referencia en cada apertura, así que basta con que
// el array se actualice en el sitio (push/sort) para que el buscador vea
// los cambios sin tener que volver a llamar a esta función.
// Minúsculas y sin tildes, para comparar textos al buscar ("Cámbio" = "cambio").
function normalizarBusqueda(s) {
  return String(s ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

// Busca por TODAS las palabras escritas (en cualquier orden, sin importar tildes ni
// mayúsculas; "frenos" también encuentra "freno") y ordena por parecido: primero las
// que empiezan con lo escrito o con la frase completa, luego las que lo contienen.
// Sin texto devuelve la lista tal cual.
function buscarCoincidencias(items, query, labelFn, limite = 30) {
  const frase = normalizarBusqueda(query).trim();
  const palabras = frase.split(/\s+/).filter(Boolean).map(p => (p.length > 3 && p.endsWith('s')) ? p.slice(0, -1) : p);
  if (!palabras.length) return items.slice(0, limite);
  const res = [];
  items.forEach((item, idx) => {
    const etiqueta = normalizarBusqueda(labelFn(item));
    let puntaje = 0;
    for (const p of palabras) {
      const i = etiqueta.indexOf(p);
      if (i < 0) return;                                              // falta una palabra: no coincide
      puntaje += i === 0 ? 30 : (/[\s(\-·/]/.test(etiqueta[i - 1]) ? 20 : 5);   // inicio de palabra vale más
    }
    if (etiqueta.startsWith(frase)) puntaje += 40;
    else if (etiqueta.includes(frase)) puntaje += 15;
    puntaje -= etiqueta.length / 200;                                 // a igual parecido, el más corto primero
    res.push({ item, puntaje, idx });
  });
  res.sort((a, b) => b.puntaje - a.puntaje || a.idx - b.idx);
  return res.slice(0, limite).map(r => r.item);
}

// opciones (todas opcionales):
//   limite: máximo de resultados a mostrar (30 por defecto).
//   extra: { id, label } opción fija al final de la lista, aunque nada coincida (ej. "Otro...").
function setupCombobox(inputId, selectId, listId, dataArray, labelFn, opciones = {}) {
  const input = document.getElementById(inputId);
  const select = document.getElementById(selectId);
  const list = document.getElementById(listId);
  if (!input || !select || !list) return;
  const { limite = 30, extra = null } = opciones;
  let resultados = [];
  let resaltado = -1;

  function seleccionar(item) {
    const esExtra = !!extra && item === extra;
    const etiqueta = esExtra ? extra.label : labelFn(item);
    // Si el <select> oculto no tiene esa opción (ej. la opción fija, o un <select> sin poblar), se crea
    // para poder guardar su valor
    if (![...select.options].some(o => o.value === item.id)) select.add(new Option(etiqueta, item.id));
    select.value = item.id;
    input.value = etiqueta;
    list.style.display = 'none';
    select.dispatchEvent(new Event('change'));
  }

  function marcarResaltado() {
    list.querySelectorAll('.combobox-item').forEach((el, i) => el.classList.toggle('resaltado', i === resaltado));
  }

  function render(query) {
    const encontrados = buscarCoincidencias(dataArray, query, labelFn, limite);
    resultados = extra ? [...encontrados, extra] : encontrados;
    resaltado = -1;
    if (!resultados.length) {
      list.innerHTML = '<div class="combobox-vacio">Sin coincidencias</div>';
    } else {
      list.innerHTML =
        (!encontrados.length ? '<div class="combobox-vacio">Sin coincidencias en la lista</div>' : '') +
        resultados.map(d => `<div class="combobox-item${d === extra ? ' combobox-extra' : ''}">${htmlSeguro(d === extra ? extra.label : labelFn(d))}</div>`).join('');
      list.querySelectorAll('.combobox-item').forEach((el, i) =>
        el.addEventListener('mousedown', (e) => { e.preventDefault(); seleccionar(resultados[i]); }));
    }
    list.style.display = 'block';
  }

  input.addEventListener('input', () => { select.value = ''; render(input.value); });
  input.addEventListener('focus', () => render(input.value));
  input.addEventListener('blur', () => setTimeout(() => { list.style.display = 'none'; }, 150));
  input.addEventListener('keydown', (e) => {
    if (list.style.display === 'none' || !resultados.length) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); resaltado = Math.min(resaltado + 1, resultados.length - 1); marcarResaltado(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); resaltado = Math.max(resaltado - 1, 0); marcarResaltado(); }
    else if (e.key === 'Enter') { if (resaltado >= 0) { e.preventDefault(); seleccionar(resultados[resaltado]); } }
    else if (e.key === 'Escape') { list.style.display = 'none'; }
  });
}

// Reemplaza el contenido de un array "en el sitio": los buscadores (setupCombobox) leen
// su lista por referencia, así ven los cambios sin tener que volver a configurarse.
function reemplazarEnSitio(arr, nuevos) {
  arr.splice(0, arr.length, ...(nuevos || []));
  return arr;
}

// Mantiene al día, en pantallas que ya están abiertas, datos que cambian en otro lado
// (ej. trabajos o repuestos nuevos): vuelve a ejecutar `recargar` cuando la persona
// regresa a la pestaña, como máximo cada `minSegundos`. Un error al refrescar no
// molesta a quien está trabajando.
function mantenerCatalogoAlDia(recargar, minSegundos = 20) {
  let ultimo = Date.now(), corriendo = false;
  const ejecutar = async () => {
    if (corriendo || document.visibilityState === 'hidden') return;
    if (Date.now() - ultimo < minSegundos * 1000) return;
    corriendo = true;
    try { await recargar(); } catch (e) { console.warn('No se pudo refrescar el catálogo', e); }
    ultimo = Date.now();
    corriendo = false;
  };
  document.addEventListener('visibilitychange', ejecutar);
  window.addEventListener('focus', ejecutar);
}

// Link wa.me con el mensaje prellenado. Acepta teléfonos chilenos
// con o sin +56 (ej: "+56 9 8765 4321" o "987654321").
function linkWhatsApp(telefono, mensaje) {
  if (!telefono) return null;
  let digits = String(telefono).replace(/\D/g, '');
  if (digits.length === 9 && digits.startsWith('9')) digits = '56' + digits;
  return `https://wa.me/${digits}?text=${encodeURIComponent(mensaje)}`;
}

// ---------- Correo electrónico ----------
function correoValido(valor) {
  return /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]{2,}$/.test(String(valor || '').trim());
}

// Envía un correo con el «script de correo» del taller: un Google Apps Script publicado con su cuenta de Gmail
// (Configuración → Correo automático). Devuelve { estado }:
//   'enviado' · 'sin_configurar' · 'error' (+ mensaje: el script rechazó el envío) ·
//   'incierto' (+ mensaje: no se pudo leer la respuesta, el correo puede haber salido: revisar «Enviados»).
// ref (opcional): de qué se trata el correo, para el registro y el expediente del vehículo:
//   { evento, tabla, id, cliente_id, vehiculo_id }
async function enviarCorreo({ para, asunto, texto, ref }) {
  const cfg = await getTallerConfig();
  const url = cfg && cfg.correo_script_url, clave = cfg && cfg.correo_script_clave;
  if (!url || !clave) return { estado: 'sin_configurar' };
  if (!correoValido(para)) return { estado: 'error', mensaje: 'El correo del cliente no es válido.' };
  const r = await enviarPorScript(url, clave, cfg, String(para).trim(), asunto, texto);
  respaldarCorreo(cfg, { para: String(para).trim(), asunto, texto, ref }, r);   // sin esperar
  return r;
}

// ---------- Correo con diseño (HTML) ----------
// TODOS los correos salen con el mismo diseño: logo, colores del taller, botones en los links,
// «Síguenos en Instagram» destacado y el botón de reserva al final. El texto plano viaja igual, de respaldo.
// La MISMA lógica está en SQL (_correo_html, sql/v69) para los correos automáticos: si se cambia una, cambiar la otra.
// Necesita el script de Gmail versión 2 (Configuración → Correo automático); con el antiguo, sale el texto plano.
const BOTONES_CORREO = [
  ['#condiciones', '📋 Ver condiciones completas'],
  ['/encuesta.html', '⭐ Responder la encuesta (30 segundos)'],
  ['/inspeccion-ingreso.html', '✍️ Revisar y firmar la inspección'],
  ['/inspeccion.html', '📋 Ver el informe de inspección'],
  ['/cotizacion.html', '📄 Ver y aprobar la cotización'],
  ['/diagnostico.html', '🔎 Ver el informe de diagnóstico'],
  ['/portal.html', '🚗 Seguir mi vehículo'],
  ['/reservar.html', '📅 Reservar hora'],
  ['/club.html', '🎁 Compartir mi código'],
];
const escCorreo = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
function botonCorreo(url) {
  const e = BOTONES_CORREO.find(([p]) => url.includes(p));
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 20px;"><tr><td style="border-radius:10px;background:#d4a84b;">` +
    `<a href="${escCorreo(url)}" target="_blank" style="display:inline-block;padding:13px 24px;font-family:Arial,Helvetica,sans-serif;font-size:15px;font-weight:bold;color:#15181e;text-decoration:none;border-radius:10px;">${e ? e[1] : 'Abrir enlace'}</a></td></tr></table>`;
}
function lineaCorreo(l) {
  let h = escCorreo(l).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" style="color:#b8260c;word-break:break-all;">$1</a>');
  if (/^[▸•-] /.test(l)) h = '<span style="color:#d4a84b;font-weight:bold;">▸</span>&nbsp;' + h.slice(2);
  // Línea en MAYÚSCULAS = subtítulo destacado (ej. «CLUB AUTONOVA · RECOMIENDA Y GANA»)
  if (!/[a-záéíóúüñ]/.test(l) && /[A-ZÁÉÍÓÚÑ]{3}/.test(l)) h = '<strong style="font-family:Impact,Arial Black,Arial,sans-serif;font-weight:normal;font-size:20px;letter-spacing:1px;color:#0d0e11;">' + h + '</strong>';
  return h;
}
function correoHtml(asunto, texto, cfg) {
  cfg = cfg || {};
  const app = String(cfg.app_url || window.location.origin).replace(/\/+$/, '');
  const taller = cfg.nombre || 'Autonova';
  const ig = instagramUrl(clubConfig(cfg));
  const igUsuario = ig ? '@' + ig.replace(/^https:\/\/instagram\.com\//, '') : '';
  let titulo = String(asunto || '').trim();
  if (titulo.toLowerCase().endsWith(taller.toLowerCase())) titulo = titulo.slice(0, -taller.length).replace(/\s*[·—-]\s*$/, '').trim();
  const P = 'margin:0 0 16px;font-family:Arial,Helvetica,sans-serif;font-size:16px;line-height:1.6;color:#2b3038;';
  const partes = [];
  let parrafo = [];
  const cerrar = () => { if (parrafo.length) partes.push(`<p style="${P}">${parrafo.join('<br>')}</p>`); parrafo = []; };
  for (const bruta of String(texto || '').split('\n')) {
    const l = bruta.trim();
    if (/instagram\.com/i.test(l)) continue;             // Instagram va destacado al final
    if (!l) { cerrar(); continue; }
    if (/^━+$/.test(l)) { cerrar(); partes.push('<div style="height:2px;background:#d4a84b;margin:6px 0 20px;font-size:0;line-height:0;">&nbsp;</div>'); continue; }
    let m = l.match(/^(https?:\/\/\S+)$/);
    if (m) { cerrar(); partes.push(botonCorreo(m[1])); continue; }
    m = l.match(/^(.*):\s*(https?:\/\/\S+)$/);
    if (m) { parrafo.push(lineaCorreo(m[1] + ':')); cerrar(); partes.push(botonCorreo(m[2])); continue; }
    parrafo.push(lineaCorreo(l));
  }
  cerrar();
  const previa = (String(texto || '').split('\n').map(s => s.trim()).find(s => s && !/^hola\b/i.test(s) && !/https?:/.test(s)) || '').slice(0, 110);
  const F = "font-family:Impact,'Arial Black',Arial,Helvetica,sans-serif;";
  const bloqueIg = ig ? `
  <tr><td class="pad" style="padding:6px 36px 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0d0e11;border-radius:14px;"><tr><td align="center" style="padding:26px 22px;">
      <div style="${F}font-size:13px;letter-spacing:4px;color:#d4a84b;text-transform:uppercase;">📸 Síguenos en Instagram</div>
      <div style="${F}font-size:30px;line-height:1.2;color:#ffffff;margin:8px 0 6px;">${escCorreo(igUsuario)}</div>
      <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#c9ced6;margin:0 0 18px;">Mecánica honesta, explicada para que entiendas qué se le hace a tu auto.</div>
      <a href="${escCorreo(ig)}" target="_blank" style="display:inline-block;background:#d6249f;background-image:linear-gradient(45deg,#fdb045,#fd5949 40%,#d6249f 70%,#285aeb);color:#ffffff;text-decoration:none;font-family:Arial,Helvetica,sans-serif;font-weight:bold;font-size:15px;padding:13px 28px;border-radius:999px;">Seguir a ${escCorreo(igUsuario)} →</a>
    </td></tr></table>
  </td></tr>` : '';
  return `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escCorreo(titulo)}</title>
<style>@keyframes latido{0%,100%{transform:scale(1)}50%{transform:scale(1.05)}}.latido{animation:latido 2.4s ease-in-out infinite}@media (max-width:620px){.contenedor{width:100%!important}.pad{padding-left:20px!important;padding-right:20px!important}}</style></head>
<body style="margin:0;padding:0;background:#eceef2;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${escCorreo(previa)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#eceef2;"><tr><td align="center" style="padding:24px 10px;">
<table role="presentation" class="contenedor" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;">
  <tr><td align="center" style="background:#0d0e11;padding:22px 20px 16px;"><a href="${escCorreo(app)}/reservar.html" target="_blank"><img src="${escCorreo(app)}/assets/img/logo-correo.jpg" width="200" alt="${escCorreo(taller)}" style="display:block;width:200px;max-width:70%;height:auto;border:0;"></a></td></tr>
  <tr><td style="height:5px;background:#e1341e;background-image:linear-gradient(90deg,#e1341e,#d4a84b);font-size:0;line-height:0;">&nbsp;</td></tr>
  <tr><td class="pad" style="padding:30px 36px 6px;">
    <h1 style="margin:0 0 20px;${F}font-weight:normal;font-size:26px;line-height:1.2;letter-spacing:0.5px;text-transform:uppercase;color:#0d0e11;">${escCorreo(titulo)}</h1>
    ${partes.join('\n    ')}
  </td></tr>${bloqueIg}
  <tr><td class="pad" align="center" style="padding:22px 36px 30px;">
    <div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;color:#3a3f48;margin:0 0 14px;">¿Necesitas otra hora? Reserva en línea en menos de 1 minuto.</div>
    <a class="latido" href="${escCorreo(app)}/reservar.html" target="_blank" style="display:inline-block;background:#e1341e;color:#ffffff;text-decoration:none;font-family:Arial,Helvetica,sans-serif;font-weight:bold;font-size:17px;padding:15px 34px;border-radius:12px;">📅 Reservar hora</a>
  </td></tr>
  <tr><td style="background:#f4f5f7;padding:18px 36px;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.6;color:#6a727f;text-align:center;">
    <strong style="color:#15181e;">${escCorreo(taller)}</strong>${cfg.telefono ? ` · ${escCorreo(cfg.telefono)}` : ''}<br>Recibes este correo por un servicio o una reserva en ${escCorreo(taller)}.
  </td></tr>
</table></td></tr></table></body></html>`;
}
// Texto plano de respaldo (si el correo del cliente no muestra diseño): también lleva Instagram y la reserva
function textoCorreoConPie(texto, cfg) {
  const ig = instagramUrl(clubConfig(cfg));
  const app = String((cfg && cfg.app_url) || window.location.origin).replace(/\/+$/, '');
  const t = String(texto || '');
  const extra = [];
  if (ig && !/instagram\.com/i.test(t)) extra.push(`📸 Síguenos en Instagram: ${ig}`);
  if (!t.includes('/reservar.html')) extra.push(`📅 Reserva tu hora en línea: ${app}/reservar.html`);
  return extra.length ? `${t}\n\n${extra.join('\n')}` : t;
}

async function enviarPorScript(url, clave, cfg, para, asunto, texto) {
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },   // sin «preflight»: Apps Script no lo responde
      body: JSON.stringify({ clave, para, asunto, texto: textoCorreoConPie(texto, cfg), html: correoHtml(asunto, texto, cfg), nombre: (cfg && cfg.nombre) || 'Autonova' }),
    });
    let j = null;
    try { j = await r.json(); } catch (e) { j = null; }
    if (j && j.ok) return { estado: 'enviado', version: Number(j.version) || 1 };
    if (j && j.error) return { estado: 'error', mensaje: j.error };
    return { estado: 'incierto', mensaje: `respuesta inesperada (HTTP ${r.status})` };
  } catch (e) {
    return { estado: 'incierto', mensaje: e && e.message ? e.message : 'sin respuesta' };
  }
}

// Respaldo de cada correo al cliente: queda en el registro (correos_enviados, v62), aparece en la campanita
// (los que fallan, como no leídos) y, si se pidió en Configuración, llega una copia al correo del taller.
async function respaldarCorreo(cfg, { para, asunto, texto, ref }, r) {
  ref = ref || {};
  try {
    const { error } = await supabaseClient.from('correos_enviados').insert({
      para, asunto, texto, estado: r.estado, error: r.mensaje || null,
      evento: ref.evento || null, ref_tabla: ref.tabla || null, ref_id: ref.id || null,
      cliente_id: ref.cliente_id || null, vehiculo_id: ref.vehiculo_id || null,
    });
    void error;   // sin v62 no hay registro, pero el correo ya salió
  } catch (e) { /* sin conexión: el correo igual se intentó */ }
  try {
    const ok = r.estado === 'enviado';
    const { error } = await supabaseClient.from('notificaciones').insert({
      tipo: ok ? 'correo_enviado' : 'correo_error',
      titulo: ok ? `✉ Correo enviado a ${para}` : `⚠ No se confirmó el correo a ${para}`,
      detalle: ok ? asunto : `${asunto} — ${r.mensaje || 'sin respuesta'}. Revisa «Enviados» en tu Gmail.`,
      url: 'configuracion.html#registro-correos',
      leida: ok,   // los enviados quedan como respaldo; los que fallan avisan
    });
    void error;
  } catch (e) { /* ok */ }
  const copiaA = cfg && cfg.email;
  if (r.estado === 'enviado' && cfg && cfg.correo_eventos && cfg.correo_eventos._copia && correoValido(copiaA) && copiaA.toLowerCase() !== para.toLowerCase()) {
    enviarPorScript(cfg.correo_script_url, cfg.correo_script_clave, cfg, copiaA.trim(),
      `Copia: ${asunto}`, `Copia del correo enviado a ${para} el ${new Date().toLocaleString('es-CL')}.\n\n────────────────\n\n${texto}`);
  }
}

// Aviso flotante breve (esquina inferior derecha). tipo: 'ok' | 'aviso' | 'error'. Se cierra tocándolo.
function mostrarToast(texto, tipo = 'ok', ms = 7000) {
  const colores = { ok: ['#eef7ee', '#1b6e3c', '#14532d'], aviso: ['#fff8e6', '#c98a0b', '#5b4a12'], error: ['#fff4f2', '#c0392b', '#7a1f14'] }[tipo] || ['#eef7ee', '#1b6e3c', '#14532d'];
  let caja = document.getElementById('toast-autonova');
  if (!caja) {
    caja = document.createElement('div');
    caja.id = 'toast-autonova';
    caja.setAttribute('role', 'status');
    caja.addEventListener('click', () => { caja.style.display = 'none'; });
    (document.body || document.documentElement).appendChild(caja);
  }
  caja.style.cssText = `position:fixed; right:1rem; bottom:1rem; z-index:410; max-width:min(380px, calc(100vw - 2rem)); background:${colores[0]};` +
    `border:1px solid ${colores[1]}; border-left:5px solid ${colores[1]}; border-radius:8px; padding:0.7rem 0.9rem; color:${colores[2]};` +
    'box-shadow:0 8px 24px rgba(0,0,0,0.22); font-size:0.88rem; cursor:pointer; display:block;';
  caja.textContent = texto;
  clearTimeout(mostrarToast.temporizador);
  mostrarToast.temporizador = setTimeout(() => { caja.style.display = 'none'; }, ms);
}

// ---------- Correos automáticos al cliente ----------
// Salen solos con el envío configurado (Configuración → Correo automático) si el cliente tiene correo y
// el aviso está activado (Configuración → Avisos automáticos). El WhatsApp sigue siendo manual en cada pantalla.
const EVENTOS_CORREO = {
  ot_ingreso:         'Ingreso del vehículo al taller (al crear la OT)',
  ot_diagnostico:     'OT pasa a «Diagnóstico»',
  ot_en_proceso:      'OT pasa a «En proceso»',
  ot_listo:           'Vehículo listo para retiro',
  ot_entregado:       'Vehículo entregado',
  cotizacion_enviada: 'Cotización marcada como enviada (con su link)',
  inspeccion:         'Inspección precompra terminada (con su informe)',
  recordatorio_cotizacion: 'Recordatorios de cotizaciones sin respuesta (días 3 y 5, y el último día de validez)',
  cobranza_ot:        'Cobranza de OT entregadas con saldo (días 3, 5 y 15, después de confirmarla en Inicio)',
  premio_referido:    'Club: cupón de premio al cliente que recomendó (cuando su referido paga la OT)',
  encuesta:           'Encuesta de satisfacción a los 7 días de entregado (la envía Supabase sola, desde las 10:00)',
};
// Los recordatorios y la cobranza los envía Supabase solo, cada día desde las 10:00 (sql/v64), aunque la app esté cerrada.

async function correoEventoActivo(evento) {
  const cfg = await getTallerConfig();
  if (!cfg || !cfg.correo_script_url || !cfg.correo_script_clave) return false;
  return !(cfg.correo_eventos && cfg.correo_eventos[evento] === false);
}

function avisarResultadoCorreo(r, para) {
  if (r.estado === 'enviado') mostrarToast(`✉ Correo enviado a ${para}`, 'ok');
  else if (r.estado === 'error') mostrarToast(`No se pudo enviar el correo a ${para}: ${r.mensaje}`, 'error', 12000);
  else if (r.estado === 'incierto') mostrarToast(`No pude confirmar si el correo a ${para} salió (${r.mensaje}). Revisa «Enviados» en tu Gmail.`, 'aviso', 15000);
}

// Aviso automático de un evento. No interrumpe: si no hay correo, el aviso está apagado o no hay envío
// configurado, no hace nada. Devuelve el resultado (para esperar el envío antes de cambiar de página).
async function correoAutomatico(evento, { para, asunto, texto, ref }) {
  try {
    para = String(para || '').trim();
    if (!correoValido(para)) return { estado: 'sin_correo' };
    if (!(await correoEventoActivo(evento))) return { estado: 'desactivado' };
    const r = await enviarCorreo({ para, asunto, texto, ref: { evento, ...(ref || {}) } });
    avisarResultadoCorreo(r, para);
    return r;
  } catch (e) {
    return { estado: 'error', mensaje: e && e.message };
  }
}

// Botones «✉ Correo»: con el envío configurado sale directo; si no, se abre Gmail con el correo redactado.
async function enviarCorreoOAbrirGmail(para, asunto, texto, ref) {
  const cfg = await getTallerConfig();
  if (cfg && cfg.correo_script_url && cfg.correo_script_clave) {
    const r = await enviarCorreo({ para, asunto, texto, ref: { evento: 'manual', ...(ref || {}) } });
    avisarResultadoCorreo(r, para);
    return r;
  }
  abrirEnlace(linkGmail(para, asunto, texto));
  return { estado: 'gmail' };
}

// Despedida de los correos: nombre, dirección y teléfono del taller
function firmaCorreoTaller(cfg) {
  cfg = cfg || {};
  const contacto = [cfg.direccion, cfg.telefono].filter(Boolean).join(' · ');
  return `Saludos,\n${cfg.nombre || 'El taller'}${contacto ? `\n${contacto}` : ''}`;
}
function pieCorreoTaller(cfg) {
  return `\n\n${firmaCorreoTaller(cfg)}`;
}

// ---------- Mensajes de correo editables (Configuración → Mensajes de correo) ----------
// Cada mensaje tiene asunto y texto con {variables} que se reemplazan al enviar. Lo que el taller edite se
// guarda en taller_config.correo_plantillas ({ clave: { asunto, texto } }); si no editó un mensaje, se usa este.
const PLANTILLAS_CORREO = {
  ot_ingreso: {
    titulo: 'Ingreso del vehículo (al crear la OT)',
    asunto: 'Recibimos su vehículo — {ot} · {taller}',
    texto: 'Hola {nombre},\n\nLe informamos que recibimos {vehiculo} en {taller}. Su orden de trabajo es la {ot} y pronto comenzaremos el diagnóstico.{bloque_inspeccion}{bloque_seguimiento}\n\n{firma}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'taller', 'bloque_inspeccion', 'bloque_seguimiento', 'firma'],
  },
  ot_diagnostico: {
    titulo: 'OT pasa a «Diagnóstico»',
    asunto: 'Su vehículo está en diagnóstico — {ot} · {taller}',
    texto: 'Hola {nombre},\n\nLe informamos que {vehiculo} está en diagnóstico ({ot}). Le enviaremos el detalle a la brevedad.{bloque_seguimiento}\n\n{firma}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'taller', 'bloque_seguimiento', 'firma'],
  },
  ot_en_proceso: {
    titulo: 'OT pasa a «En proceso»',
    asunto: 'Estamos trabajando en su vehículo — {ot} · {taller}',
    texto: 'Hola {nombre},\n\nLe informamos que {vehiculo} ya está siendo trabajado en nuestro taller ({ot}).{bloque_seguimiento}\n\n{firma}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'taller', 'bloque_seguimiento', 'firma'],
  },
  ot_listo: {
    titulo: 'Vehículo listo para retiro',
    asunto: 'Su vehículo está listo para retiro — {ot} · {taller}',
    texto: 'Hola {nombre},\n\nLe informamos que {vehiculo} está listo para retiro ({ot}). Lo esperamos en nuestro horario de atención.{bloque_seguimiento}\n\n{firma}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'taller', 'bloque_seguimiento', 'firma'],
  },
  ot_entregado: {
    titulo: 'Vehículo entregado',
    asunto: 'Gracias por su visita — {ot} · {taller}',
    texto: 'Hola {nombre},\n\nGracias por confiar en nosotros para el servicio de {vehiculo} ({ot}). Si tiene cualquier consulta sobre el trabajo realizado, estamos para ayudarle.{bloque_club}\n\n{firma}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'taller', 'bloque_club', 'codigo', 'link_compartir', 'instagram', 'firma'],
  },
  cotizacion_enviada: {
    titulo: 'Cotización (al marcarla enviada y botón ✉ Correo)',
    asunto: 'Cotización {cotizacion} - {taller}',
    texto: 'Hola {nombre},\n\nEn {taller} preparamos la cotización {cotizacion} para {vehiculo}:\n\n{detalle}\n\nTotal: {total} ({iva}). Válida por {validez} días.\n\nPuede revisarla y aprobarla aquí:\n{link}\n\n{firma}',
    variables: ['nombre', 'cotizacion', 'vehiculo', 'detalle', 'total', 'iva', 'validez', 'link', 'taller', 'firma'],
  },
  diagnostico: {
    titulo: 'Informe de diagnóstico (botón ✉ Correo)',
    asunto: 'Informe de diagnóstico {diagnostico} - {taller}',
    texto: 'Hola {nombre},\n\nEn {taller} revisamos {vehiculo} y preparamos el informe de diagnóstico {diagnostico}.\n\n{resumen}\n\nPuede ver el informe completo, con fotos, y avisarnos si desea realizar los trabajos aquí:\n{link}\n\n{firma}',
    variables: ['nombre', 'diagnostico', 'vehiculo', 'resumen', 'link', 'taller', 'firma'],
  },
  inspeccion: {
    titulo: 'Inspección precompra terminada',
    asunto: 'Inspección precompra {numero} - {taller}',
    texto: 'Hola {nombre},\n\nLe enviamos el resultado de la inspección precompra {numero} de {vehiculo}:\n\nPuntaje: {puntaje}/100 — {resumen}.\n{recomendacion}\n\nInforme completo, con fotos:\n{link}\n\n{firma}',
    variables: ['nombre', 'numero', 'vehiculo', 'patente', 'plan', 'puntaje', 'resumen', 'recomendacion', 'link', 'taller', 'firma'],
  },
  // Recordatorios automáticos (los envía sql/v64: mantener los textos iguales allá)
  cotizacion_recordatorio_1: {
    titulo: 'Recordatorio de cotización — día 3',
    asunto: 'Su cotización {cotizacion} sigue disponible - {taller}',
    texto: 'Hola {nombre},\n\nLe recordamos la cotización {cotizacion} para {vehiculo}, por un total de {total} ({iva}). Aún le quedan {dias_restantes} de validez (hasta el {vence}).\n\nPuede revisarla y aprobarla aquí:\n{link}\n\nSi desea agendar el trabajo, reserve su hora aquí:\n{link_reserva}\n\nCualquier duda, estamos para ayudarle.\n\n{firma}',
    variables: ['nombre', 'cotizacion', 'vehiculo', 'total', 'iva', 'dias_restantes', 'vence', 'link', 'link_reserva', 'taller', 'firma'],
  },
  cotizacion_recordatorio_2: {
    titulo: 'Recordatorio de cotización — día 5',
    asunto: '¿Agendamos su trabajo? Cotización {cotizacion} - {taller}',
    texto: 'Hola {nombre},\n\nQueríamos saber si pudo revisar la cotización {cotizacion} para {vehiculo} ({total}, {iva}). Le quedan {dias_restantes} de validez (hasta el {vence}); después de esa fecha los valores pueden cambiar.\n\nVer y aprobar la cotización:\n{link}\n\nReservar su hora:\n{link_reserva}\n\n{firma}',
    variables: ['nombre', 'cotizacion', 'vehiculo', 'total', 'iva', 'dias_restantes', 'vence', 'link', 'link_reserva', 'taller', 'firma'],
  },
  cotizacion_recordatorio_3: {
    titulo: 'Recordatorio de cotización — último día de validez',
    asunto: 'Último día de su cotización {cotizacion} - {taller}',
    texto: 'Hola {nombre},\n\nHoy es el último día de validez de la cotización {cotizacion} para {vehiculo} ({total}, {iva}). A partir de mañana deja de ser válida y los valores pueden cambiar.\n\nSi desea mantener estos valores, apruébela hoy aquí:\n{link}\n\nO reserve su hora directamente:\n{link_reserva}\n\n{firma}',
    variables: ['nombre', 'cotizacion', 'vehiculo', 'total', 'iva', 'vence', 'link', 'link_reserva', 'taller', 'firma'],
  },
  cobranza_1: {
    titulo: 'Cobranza de OT — día 3',
    asunto: 'Saldo pendiente de su {ot} - {taller}',
    texto: 'Hola {nombre},\n\nLe recordamos que el servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}, tiene un saldo pendiente de {saldo} (total {total}, pagado {pagado}).\n\nSi ya realizó el pago, por favor envíenos el comprobante y disculpe la molestia.\n\n{firma}',
    variables: ['nombre', 'ot', 'vehiculo', 'fecha_entrega', 'saldo', 'total', 'pagado', 'taller', 'firma'],
  },
  cobranza_2: {
    titulo: 'Cobranza de OT — día 5',
    asunto: 'Recordatorio de pago - {ot} · {taller}',
    texto: 'Hola {nombre},\n\nLe escribimos nuevamente por el saldo pendiente de {saldo} del servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}.\n\nLe agradeceremos regularizarlo a la brevedad. Si ya pagó, envíenos el comprobante para actualizar su cuenta.\n\n{firma}',
    variables: ['nombre', 'ot', 'vehiculo', 'fecha_entrega', 'saldo', 'total', 'pagado', 'taller', 'firma'],
  },
  cobranza_3: {
    titulo: 'Cobranza de OT — día 15',
    asunto: 'Último aviso: saldo pendiente de su {ot} - {taller}',
    texto: 'Hola {nombre},\n\nEste es nuestro último aviso por el saldo pendiente de {saldo} del servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}.\n\nLe pedimos regularizar el pago o comunicarse con nosotros para acordar cómo hacerlo. Si ya pagó, envíenos el comprobante y disculpe la molestia.\n\n{firma}',
    variables: ['nombre', 'ot', 'vehiculo', 'fecha_entrega', 'saldo', 'total', 'pagado', 'taller', 'firma'],
  },
  // Lo envía Supabase solo (sql/v67, procesar_referidos): si se cambia el texto por defecto, cambiarlo también allá
  premio_referido: {
    titulo: 'Club: premio por referido (cupón; lo envía Supabase solo)',
    asunto: '🎁 Ganaste un cupón de {descuento} en {taller}',
    texto: 'Hola {nombre},\n\n¡Gracias por recomendarnos! {referido} ya hizo su servicio con nosotros gracias a ti, así que ganaste un cupón de {descuento} de descuento{tope_texto} para tu próxima visita.\n\n🎟 Tu cupón: {cupon}\n📅 Válido hasta el {vence}.\n\nCómo usarlo: escríbelo al reservar en línea o dilo al dejar tu vehículo (después ya no se puede aplicar).\nReserva aquí: {link_reserva}\n\nCondiciones: es personal e intransferible, se usa una sola vez y va un cupón por orden de trabajo. El descuento es sobre el valor del trabajo sin IVA{tope_texto}, no se acumula con otras promociones, no aplica a bodegaje y no es canjeable por dinero.\n\nSigue compartiendo tu código {codigo}: por cada amigo que venga ganas un cupón nuevo.\n{link_compartir}\n\n{firma}',
    variables: ['nombre', 'referido', 'descuento', 'tope_texto', 'cupon', 'vence', 'link_reserva', 'codigo', 'link_compartir', 'taller', 'firma'],
  },
  // Lo envía Supabase solo (sql/v70, enviar_encuestas): si se cambia el texto por defecto, cambiarlo también allá
  encuesta_7dias: {
    titulo: 'Encuesta de satisfacción (a los 7 días de entregado; la envía Supabase sola)',
    asunto: '⭐ ¿Cómo le fue con nosotros? — {ot} · {taller}',
    texto: 'Hola {nombre},\n\nHace unos días le entregamos {vehiculo} ({ot}). ¿Cómo le ha funcionado?\n\nSu opinión nos ayuda a mejorar y nos toma solo 30 segundos:\n{link_encuesta}\n\nSi algo no quedó como esperaba, cuéntenos en la encuesta: lo revisamos personalmente.\n\n{firma}',
    variables: ['nombre', 'vehiculo', 'ot', 'link_encuesta', 'taller', 'firma'],
  },
};

// ---------- Mensajes de WhatsApp editables (Configuración → Mensajes al cliente) ----------
// Igual que los correos, sin asunto. Lo editado se guarda en taller_config.correo_plantillas con la misma clave.
// (Los de la agenda: confirmación y recordatorio de cita, mantención y revisión técnica, están en «Mensajes de la agenda».)
const PLANTILLAS_WHATSAPP = {
  wa_cotizacion: {
    titulo: 'Cotización (botón WhatsApp)',
    texto: 'Hola {nombre}, le saluda {taller}.\nLe enviamos la cotización {cotizacion} para {vehiculo}:\n{detalle}\nTotal: {total} ({iva}). Válida por {validez} días.\nPuede revisar y aprobar la cotización aquí: {link}',
    variables: ['nombre', 'cotizacion', 'vehiculo', 'detalle', 'total', 'iva', 'validez', 'link', 'taller'],
  },
  wa_cotizacion_recordatorio: {
    titulo: 'Recordatorio de cotización (botón WhatsApp en Inicio)',
    texto: 'Hola {nombre}, le saluda {taller}. Le recordamos la cotización {cotizacion} para {vehiculo}, por {total} ({iva}). {validez_texto}\nVer y aprobar: {link}\nReservar su hora: {link_reserva}',
    variables: ['nombre', 'cotizacion', 'vehiculo', 'total', 'iva', 'validez_texto', 'dias_restantes', 'vence', 'link', 'link_reserva', 'taller'],
  },
  wa_diagnostico: {
    titulo: 'Informe de diagnóstico (botón WhatsApp)',
    texto: 'Hola {nombre}, le saluda {taller}.\nRevisamos {vehiculo} y le enviamos el informe de diagnóstico {diagnostico}.\n{resumen}\nPuede ver el informe completo, con fotos, y avisarnos si desea realizar los trabajos aquí: {link}',
    variables: ['nombre', 'diagnostico', 'vehiculo', 'resumen', 'link', 'taller'],
  },
  wa_inspeccion_ingreso: {
    titulo: 'Inspección de ingreso para firmar (diagnóstico y OT)',
    texto: 'Hola {nombre}, le saluda {taller}. Le compartimos el detalle de la inspección de ingreso de {vehiculo} ({documento}). Puede revisarla y firmarla aquí:\n{link}',
    variables: ['nombre', 'vehiculo', 'documento', 'link', 'taller'],
  },
  wa_ot_recepcion: {
    titulo: 'OT — recibimos su vehículo',
    texto: 'Hola {nombre}, le saluda {taller}: recibimos {vehiculo} y pronto comenzaremos el diagnóstico ({ot}).{bloque_seguimiento}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'bloque_seguimiento', 'taller'],
  },
  wa_ot_diagnostico: {
    titulo: 'OT — en diagnóstico',
    texto: 'Hola {nombre}, le saluda {taller}: {vehiculo} está en diagnóstico; le enviaremos el detalle a la brevedad ({ot}).{bloque_seguimiento}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'bloque_seguimiento', 'taller'],
  },
  wa_ot_en_proceso: {
    titulo: 'OT — en proceso',
    texto: 'Hola {nombre}, le saluda {taller}: {vehiculo} está siendo trabajado en nuestro taller ({ot}).{bloque_seguimiento}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'bloque_seguimiento', 'taller'],
  },
  wa_ot_listo: {
    titulo: 'OT — listo para retiro',
    texto: 'Hola {nombre}, le saluda {taller}: {vehiculo} está listo para retiro ({ot}).{bloque_seguimiento}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'bloque_seguimiento', 'taller'],
  },
  wa_ot_entregado: {
    titulo: 'OT — entregado',
    texto: 'Hola {nombre}, le saluda {taller}: gracias por confiar en nosotros para el servicio de {vehiculo} ({ot}).{bloque_club}',
    variables: ['nombre', 'vehiculo', 'patente', 'ot', 'bloque_seguimiento', 'bloque_club', 'codigo', 'link_compartir', 'instagram', 'taller'],
  },
  wa_club_codigo: {
    titulo: 'Club: enviarle a un cliente su código (botón en Club Autonova)',
    texto: 'Hola {nombre}, le saluda {taller} 🎁\nTu código personal del Club es *{codigo}*.\n• Tu amigo: {descuento} de descuento en su primera visita{tope_texto}.\n• Tú: un cupón de {descuento}{tope_texto} por cada amigo que pague y retire su vehículo.\nTu amigo debe dar el código al reservar o al dejar su vehículo (después ya no se aplica).\nCompártelo y revisa las condiciones aquí: {link_compartir}',
    variables: ['nombre', 'codigo', 'descuento', 'tope_texto', 'link_compartir', 'instagram', 'taller'],
  },
  wa_premio_referido: {
    titulo: 'Club: avisar el premio por referido (botón en Club Autonova)',
    texto: 'Hola {nombre}, le saluda {taller} 🎁\n¡Gracias por recomendarnos! {referido} ya hizo su servicio gracias a ti, así que ganaste un cupón de {descuento} de descuento{tope_texto} para tu próxima visita: *{cupon}*\n📅 Válido hasta el {vence}. Úsalo escribiéndolo al reservar o diciéndolo al dejar tu vehículo (después ya no se aplica).\nEs personal, de un solo uso, uno por orden de trabajo, sobre el valor sin IVA y no se acumula con otras promociones.\nReserva aquí: {link_reserva}',
    variables: ['nombre', 'referido', 'descuento', 'tope_texto', 'cupon', 'vence', 'link_reserva', 'codigo', 'taller'],
  },
  wa_compartir_codigo: {
    titulo: 'Club: mensaje que el cliente le manda a sus amigos (botón «Compartir»)',
    texto: 'Te recomiendo {taller} 🔧 me atendieron muy bien.\nCon mi código *{codigo}* tienes {descuento} de descuento en tu primera visita{tope_texto}.\n⚠ Dilo al reservar o al dejar tu auto (después ya no se aplica).\nReserva y condiciones 👉 {link_club}',
    variables: ['codigo', 'descuento', 'tope_texto', 'link_club', 'taller'],
  },
  wa_encuesta: {
    titulo: 'Encuesta de satisfacción (botón WhatsApp en Inicio)',
    texto: 'Hola {nombre}, le saluda {taller} 👋\nHace unos días le entregamos {vehiculo} ({ot}). ¿Cómo le ha funcionado?\nSu opinión nos ayuda mucho y toma solo 30 segundos: {link_encuesta}',
    variables: ['nombre', 'vehiculo', 'ot', 'link_encuesta', 'taller'],
  },
  wa_cobranza: {
    titulo: 'Cobranza de OT (botón WhatsApp en Inicio)',
    texto: 'Hola {nombre}, le saluda {taller}. Le recordamos que el servicio de {vehiculo} ({ot}), entregado el {fecha_entrega}, tiene un saldo pendiente de {saldo}. Si ya realizó el pago, por favor envíenos el comprobante. ¡Muchas gracias!',
    variables: ['nombre', 'ot', 'vehiculo', 'fecha_entrega', 'saldo', 'total', 'pagado', 'taller'],
  },
  wa_inspeccion: {
    titulo: 'Inspección precompra (botón WhatsApp)',
    texto: 'Hola {nombre}, le saluda {taller}.\nResultado de la inspección precompra {numero} de {vehiculo}:\nPlan: {plan}\nPuntaje: {puntaje}/100 — {resumen}.\n{recomendacion}\nInforme completo, con fotos: {link}',
    variables: ['nombre', 'numero', 'vehiculo', 'patente', 'plan', 'puntaje', 'resumen', 'recomendacion', 'link', 'taller'],
  },
};

// Texto de un WhatsApp con sus valores (mismas reglas que armarCorreo)
function armarWhatsApp(clave, valores, cfg) {
  const base = PLANTILLAS_WHATSAPP[clave];
  const propia = (cfg && cfg.correo_plantillas && cfg.correo_plantillas[clave]) || {};
  const tpl = String(propia.texto || '').trim() ? propia.texto : base.texto;
  const todos = { taller: (cfg && cfg.nombre) || 'el taller', ...valores };
  return String(tpl).replace(/\{(\w+)\}/g, (m, k) => (todos[k] != null ? String(todos[k]) : m))
    .replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

// Qué es cada variable (ayuda en Configuración)
const DESCRIPCION_VARIABLES_CORREO = {
  nombre: 'nombre del cliente',
  vehiculo: 'el vehículo con su patente y modelo',
  patente: 'solo la patente',
  ot: 'número de la OT (ej. OT-0015)',
  taller: 'nombre del taller',
  bloque_inspeccion: 'párrafo con el link de la inspección de ingreso (solo si se registró)',
  bloque_seguimiento: 'párrafo con el link para seguir el estado del vehículo',
  firma: 'despedida con nombre, dirección y teléfono del taller',
  cotizacion: 'número de la cotización (ej. COT-0007)',
  detalle: 'lista de trabajos y repuestos con su valor',
  total: 'total a pagar',
  iva: '«IVA incluido» o «sin IVA»',
  validez: 'días de validez',
  link: 'link para que el cliente lo vea en línea',
  diagnostico: 'número del diagnóstico (ej. DIAG-0003)',
  resumen: 'resumen del resultado',
  numero: 'número de la inspección (ej. INS-0003)',
  plan: 'plan de inspección elegido (ej. Compra Segura Pro)',
  puntaje: 'puntaje de 0 a 100',
  recomendacion: 'recomendación final',
  dias_restantes: 'días de validez que le quedan (ej. «12 días»)',
  vence: 'fecha en que vence (la cotización o el cupón)',
  bloque_club: 'párrafo del Club: Instagram, el código personal del cliente y el link para compartirlo',
  codigo: 'código personal del cliente en el Club (ej. JUAN-4K7)',
  link_compartir: 'link donde el cliente comparte su código con sus amigos',
  link_club: 'link que reciben los amigos (muestra el descuento y lleva a reservar)',
  instagram: 'link al Instagram del taller',
  referido: 'nombre del amigo que llegó recomendado',
  descuento: 'porcentaje del descuento (ej. 15%)',
  tope_texto: 'el máximo del descuento, ej. « (máximo $30.000)»',
  cupon: 'código del cupón de premio (ej. PREMIO-7QX2M)',
  link_encuesta: 'link de la encuesta de satisfacción (30 segundos)',
  validez_texto: 'frase con los días que le quedan o «hoy es el último día»',
  link_reserva: 'link para reservar hora en línea (queda anotado el N° de cotización)',
  fecha_entrega: 'fecha en que se entregó el vehículo',
  saldo: 'saldo pendiente por pagar',
  pagado: 'lo ya pagado',
  documento: 'número del documento (ej. OT-0015 o DIAG-0003)',
};

// Arma asunto y texto de un mensaje con sus valores. Las {variables} desconocidas quedan tal cual (así se nota
// un error de tipeo al revisar el ejemplo).
function armarCorreo(clave, valores, cfg) {
  const base = PLANTILLAS_CORREO[clave];
  const propia = (cfg && cfg.correo_plantillas && cfg.correo_plantillas[clave]) || {};
  const asuntoTpl = String(propia.asunto || '').trim() ? propia.asunto : base.asunto;
  const textoTpl = String(propia.texto || '').trim() ? propia.texto : base.texto;
  const todos = { taller: (cfg && cfg.nombre) || 'el taller', firma: firmaCorreoTaller(cfg), ...valores };
  const reemplazar = (s) => String(s).replace(/\{(\w+)\}/g, (m, k) => (todos[k] != null ? String(todos[k]) : m));
  return {
    asunto: reemplazar(asuntoTpl).replace(/\s+/g, ' ').trim(),
    texto: reemplazar(textoTpl).replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim(),
  };
}

// Correo de una OT según su estado (recepción = ingreso del vehículo). null para estados sin aviso (cancelado).
// o: { id, numero, clientes: { nombre }, vehiculos: { patente, marca, modelo }, checklist_recepcion, checklist_firma_png, firma_cliente_url }
function correoEstadoOT(o, estado, cfg) {
  const clave = { recepcion: 'ot_ingreso', diagnostico: 'ot_diagnostico', en_proceso: 'ot_en_proceso', listo: 'ot_listo', entregado: 'ot_entregado' }[estado];
  if (!clave) return null;
  const v = o.vehiculos;
  const modelo = v ? [v.marca, v.modelo].filter(Boolean).join(' ') : '';
  const firmada = !!(o.checklist_firma_png || o.firma_cliente_url);
  return armarCorreo(clave, {
    nombre: (o.clientes && o.clientes.nombre) || '',
    vehiculo: v ? `su vehículo ${v.patente}${modelo ? ` (${modelo})` : ''}` : 'su vehículo',
    patente: (v && v.patente) || '',
    ot: fmtNumero('OT', o.numero),
    bloque_inspeccion: (o.id && Array.isArray(o.checklist_recepcion) && o.checklist_recepcion.length)
      ? `\n\nPuede revisar la inspección de ingreso de su vehículo${firmada ? '' : ' (y firmarla)'} aquí:\n${window.location.origin}/inspeccion-ingreso.html?id=${o.id}` : '',
    bloque_seguimiento: (v && v.patente)
      ? `\n\nPuede seguir el estado de su vehículo aquí:\n${window.location.origin}/portal.html?patente=${encodeURIComponent(v.patente)}&ot=${o.numero}` : '',
    ...valoresClub(o.clientes && o.clientes.codigo_referido, cfg),
  }, cfg);
}

// ---------- Club Autonova (referidos) ----------
// Configuración en taller_config.club (Configuración → Club Autonova). Los mismos valores por defecto que _club_cfg() (sql/v67).
const CLUB_POR_DEFECTO = { activo: true, pct: 15, tope: 30000, premio_dias: 90, instagram: '_autonova_' };

// ---------- Encuesta de satisfacción (sql/v70) ----------
// Configuración en taller_config.encuesta (Configuración → Encuesta y reseñas). Mismos valores que _encuesta_cfg().
const ENCUESTA_POR_DEFECTO = { activa: true, dias: 7, google_url: '' };
function encuestaConfig(cfg) {
  return { ...ENCUESTA_POR_DEFECTO, ...((cfg && cfg.encuesta) || {}) };
}
// Qué podemos mejorar: clave guardada → texto (las claves válidas están también en encuesta_responder, sql/v70)
const MEJORAS_ENCUESTA = {
  tiempo: '⏱ Tiempo de entrega',
  comunicacion: '💬 Comunicación y avisos',
  precio: '💲 Precio',
  calidad: '🔧 Calidad del trabajo',
  explicacion: '📋 Explicación de lo que se hizo',
  limpieza: '🧽 Limpieza del vehículo',
  atencion: '🤝 Atención',
  agenda: '📅 Facilidad para agendar',
  nada: '✨ Nada, todo excelente',
};
const linkEncuesta = (id) => `${window.location.origin}/encuesta.html?e=${id}`;
function clubConfig(cfg) {
  return { ...CLUB_POR_DEFECTO, ...((cfg && cfg.club) || {}) };
}
function instagramUrl(club) {
  const u = String((club && club.instagram) || '').trim().replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//i, '').replace(/\/.*$/, '');
  return u ? `https://instagram.com/${u}` : '';
}
function topeClubTexto(tope) {
  return Number(tope) > 0 ? ` (máximo ${fmtMoneda(tope)})` : '';
}
function linkClub(codigo, compartir) {
  return `${window.location.origin}/club.html?c=${encodeURIComponent(codigo)}${compartir ? '&compartir=1' : ''}`;
}
// Condiciones del Club: UNA sola redacción para la página pública (club.html), los mensajes y la app.
// Regla del plazo (decisión del dueño): el código se da al reservar o al dejar el vehículo; después no corre (sql/v68).
function condicionesClub(c, taller) {
  c = { ...CLUB_POR_DEFECTO, ...(c || {}) };
  taller = taller || 'el taller';
  const pct = `${fmtPorcentaje(c.pct)}%`;
  const topeNum = Number(c.tope) > 0 ? Number(c.tope) : 0;
  const tope = topeNum ? fmtMoneda(topeNum) : '';
  const dias = Number(c.premio_dias) || 90;
  const ejemplo = (monto) => {
    const descuento = Math.min(monto * Number(c.pct) / 100, topeNum || Infinity);
    return { monto, descuento, paga: monto - descuento, conTope: !!topeNum && descuento >= topeNum };
  };
  const ejemplos = [ejemplo(100000)];
  if (topeNum && Number(c.pct) > 0) ejemplos.push(ejemplo(Math.ceil(topeNum / (Number(c.pct) / 100) * 1.5 / 50000) * 50000));
  return {
    pct, tope, dias, ejemplos,
    amigo: [
      `Es para personas que nunca se han atendido en ${taller}, en su primera orden de trabajo.`,
      `${pct} de descuento sobre el valor del trabajo sin IVA (mano de obra y repuestos)${tope ? `, con un máximo de ${tope} de descuento` : ''}. El IVA se calcula sobre el valor ya descontado.`,
      'El código se da al reservar en línea o al dejar el vehículo. Si se menciona después (por ejemplo, al pagar), ya no se aplica.',
      'Un solo código de recomendación por persona y por vehículo. No vale para el dueño del código (mismo RUT, teléfono o vehículo).',
      'No se acumula con otros descuentos ni promociones y no aplica a cobros de bodegaje.',
    ],
    cliente: [
      `Ganas un cupón de ${pct}${tope ? ` (máximo ${tope})` : ''} por cada amigo que pague completo y retire su vehículo. Sin límite de amigos.`,
      `Te lo enviamos por correo (o WhatsApp si no tenemos tu correo) y vence a los ${dias} días de emitido.`,
      'Es personal e intransferible, se usa una sola vez y va un cupón por orden de trabajo. Se da al reservar o al dejar tu vehículo; después ya no se aplica.',
      'No es canjeable por dinero ni se acumula con otros descuentos.',
      'Si el trabajo de tu amigo se anula o no se paga, no se genera cupón.',
    ],
    general: `${taller} puede modificar o terminar el programa avisando en esta página; los cupones ya emitidos se respetan hasta su vencimiento.`,
  };
}

// Valores del Club para los mensajes (al entregar el vehículo y botones de Club Autonova).
// canal: 'correo' (bloque completo, con cómo funciona y condiciones) o 'whatsapp' (resumido, con link a las condiciones).
function valoresClub(codigo, cfg, canal = 'correo') {
  const club = clubConfig(cfg);
  const ig = instagramUrl(club);
  const descuento = `${fmtPorcentaje(club.pct)}%`;
  const tope_texto = topeClubTexto(club.tope);
  const base = { codigo: codigo || '', instagram: ig, descuento, tope_texto, link_compartir: '', link_club: '' };
  if (!codigo || club.activo === false) return { ...base, bloque_club: ig ? `\n\n📸 Síganos en Instagram: ${ig}` : '' };
  const taller = (cfg && cfg.nombre) || 'el taller';
  const compartir = linkClub(codigo, true);
  const maximo = Number(club.tope) > 0 ? ` (máximo ${fmtMoneda(club.tope)})` : '';
  const bloque = canal === 'whatsapp'
    ? [
      ig ? `📸 Instagram: ${ig}` : '',
      '',
      `🎁 *Club ${taller}* — su código: *${codigo}*`,
      `• Su amigo: ${descuento} de descuento en su primera visita${maximo}.`,
      `• Usted: un cupón de ${descuento}${maximo} por cada amigo que pague y retire su vehículo.`,
      'Su amigo debe dar el código al reservar o al dejar su vehículo (después ya no se aplica).',
      `Compartir y condiciones: ${compartir}`,
    ]
    : [
      ig ? `📸 Síganos en Instagram: ${ig}` : '',
      '',
      '━━━━━━━━━━━━━━━━━━━━',
      `🎁 CLUB ${String(taller).toUpperCase()} · RECOMIENDA Y GANA`,
      `Su código personal: ${codigo}`,
      '',
      `▸ Su amigo: ${descuento} de descuento en su primera visita${maximo}.`,
      `▸ Usted: un cupón de ${descuento}${maximo} por CADA amigo que pague y retire su vehículo.`,
      '',
      'Cómo funciona:',
      `1) Comparta su código o este link: ${compartir}`,
      '2) Su amigo da el código al reservar en línea o al dejar su vehículo.',
      `3) Cuando su amigo pague y retire su vehículo, le enviamos su cupón (personal, de un solo uso, vence a los ${Number(club.premio_dias) || 90} días).`,
      '',
      'Importante: el descuento es solo para personas que nunca se han atendido con nosotros, es sobre el valor sin IVA, no se acumula con otras promociones y no aplica a bodegaje. Si el código se menciona después de dejar el vehículo, ya no se aplica.',
      `Condiciones completas: ${compartir}#condiciones`,
    ];
  return { ...base, link_compartir: compartir, link_club: linkClub(codigo), bloque_club: `\n\n${bloque.filter((l, i, a) => l !== '' || (a[i - 1] && a[i + 1])).join('\n')}` };
}

// Aviso automático de una OT (ingreso o cambio de estado) al correo del cliente
async function avisarCorreoOT(o, estado) {
  const cfg = await getTallerConfig();
  // Al entregar va el código del Club del cliente: si la OT no lo trae, se busca en su ficha
  if (estado === 'entregado' && o.cliente_id && !(o.clientes && o.clientes.codigo_referido)) {
    const { data } = await supabaseClient.from('clientes').select('codigo_referido').eq('id', o.cliente_id).maybeSingle();
    if (data && data.codigo_referido) o = { ...o, clientes: { ...(o.clientes || {}), codigo_referido: data.codigo_referido } };
  }
  const msg = correoEstadoOT(o, estado, cfg);
  if (!msg) return { estado: 'sin_aviso' };
  return correoAutomatico(estado === 'recepcion' ? 'ot_ingreso' : `ot_${estado}`, {
    para: o.clientes && o.clientes.email, ...msg,
    ref: { tabla: 'ordenes', id: o.id, cliente_id: o.cliente_id, vehiculo_id: o.vehiculo_id },
  });
}

// ---------- RUT, teléfono y patente (Chile) ----------
// Los campos se van formateando solos mientras se escribe: RUT con puntos y guion,
// teléfono con +56 y patente en mayúsculas.
function rutLimpio(valor) {
  return String(valor == null ? '' : valor).replace(/[^0-9kK]/g, '').toUpperCase();
}

function formatearRut(valor) {
  const crudo = String(valor == null ? '' : valor);
  // Pasaportes u otros documentos con letras: no se tocan
  if (/[A-JL-Z]/i.test(crudo)) return crudo;
  const v = rutLimpio(crudo);
  if (v.length < 2) return v;
  const cuerpo = v.slice(0, -1).replace(/\D/g, '').replace(/^0+(?=\d)/, '');
  return cuerpo.replace(/\B(?=(\d{3})+(?!\d))/g, '.') + '-' + v.slice(-1);
}

// Dígito verificador (módulo 11). Acepta cuerpos de 6 a 8 dígitos.
function rutValido(valor) {
  const v = rutLimpio(valor);
  if (v.length < 7 || v.length > 9) return false;
  const cuerpo = v.slice(0, -1);
  if (!/^\d+$/.test(cuerpo)) return false;
  let suma = 0, mul = 2;
  for (let i = cuerpo.length - 1; i >= 0; i--) {
    suma += Number(cuerpo[i]) * mul;
    mul = mul === 7 ? 2 : mul + 1;
  }
  const r = 11 - (suma % 11);
  const esperado = r === 11 ? '0' : r === 10 ? 'K' : String(r);
  return v.slice(-1) === esperado;
}

// Formato único del teléfono: "+56 9 1234 5678" (celular), "+56 2 1234 5678" (fijo de Santiago) o
// "+56 41 234 5678" (fijo de región). Un número de otro país (+51, +54…) se deja como se escribió.
// `borrando` evita que el prefijo "+56" quede pegado cuando se borra con la tecla retroceso.
function agruparNacional(n) {
  const grupos = (s) => s.match(/.{1,4}/g) || [];
  if (n.startsWith('9')) return n.length <= 1 ? n : '9 ' + grupos(n.slice(1)).join(' ');
  if (n.startsWith('2')) return n.length <= 1 ? n : '2 ' + grupos(n.slice(1)).join(' ');
  return [n.slice(0, 2), n.slice(2, 5), n.slice(5, 9)].filter(Boolean).join(' ');
}

function formatearTelefonoCL(valor, borrando) {
  let crudo = String(valor == null ? '' : valor).trim();
  if (/^00\d/.test(crudo)) crudo = '+' + crudo.slice(2);   // 0056… = +56…
  const d = crudo.replace(/\D/g, '');
  if (!d) return crudo.startsWith('+') ? '+' : '';
  let nacional = d;
  if (crudo.startsWith('+')) {
    if (!d.startsWith('56')) return d === '5' ? '+5' : '+' + d.slice(0, 15);   // "+5" aún puede ser +56
    nacional = d.slice(2);
  }
  // Ningún número chileno parte con 56: si aparece, es el código de país escrito de nuevo
  // (el campo ya trae "+56 " y la persona tipea 56 9…). Se descarta.
  for (let i = 0; i < 2 && nacional.startsWith('56'); i++) nacional = nacional.slice(2);
  nacional = nacional.replace(/^0+/, '').slice(0, 9);
  if (!nacional) return borrando ? '' : (crudo.startsWith('+') || d.startsWith('56') ? '+56 ' : '');
  return '+56 ' + agruparNacional(nacional);
}

function telefonoNacional(valor) {
  let d = String(valor == null ? '' : valor).replace(/\D/g, '');
  if (d.startsWith('56') && d.length > 9) d = d.slice(2);
  return d.replace(/^0+/, '');
}

function telefonoValidoCL(valor) {
  const crudo = String(valor == null ? '' : valor).trim();
  const d = crudo.replace(/\D/g, '');
  if (crudo.startsWith('+') && !d.startsWith('56')) return d.length >= 8 && d.length <= 15;   // otro país
  return telefonoNacional(valor).length === 9;
}

function normalizarPatente(valor) {
  return String(valor == null ? '' : valor).toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
}

// Autos nuevos (ABCD12), antiguos (AB1234) y motos (ABC12 / AB123).
function patenteValida(valor) {
  const p = normalizarPatente(valor);
  return /^[A-Z]{4}\d{2}$/.test(p) || /^[A-Z]{2}\d{4}$/.test(p) || /^[A-Z]{3}\d{2}$/.test(p) || /^[A-Z]{2}\d{3}$/.test(p);
}

function enlazarFormato(input, formateador, alCambiar) {
  const el = typeof input === 'string' ? document.getElementById(input) : input;
  if (!el || el.dataset.formatoEnlazado) return;
  el.dataset.formatoEnlazado = '1';
  el.addEventListener('input', () => {
    const nuevo = formateador(el.value);
    if (nuevo !== el.value) el.value = nuevo;
    if (alCambiar) alCambiar(nuevo);
  });
}

// ---- Formato único en TODA la app ----
// Cualquier casilla de RUT o teléfono (por su id o type="tel", incluidas las que aparecen en
// ventanas emergentes) se formatea sola al escribir. Para excluir una: data-formato="ninguno";
// para forzar una: data-formato="rut" | "telefono".
function tipoCampoChile(el) {
  if (!el || el.tagName !== 'INPUT') return null;
  const t = (el.type || 'text').toLowerCase();
  if (t !== 'text' && t !== 'tel') return null;
  const f = el.dataset && el.dataset.formato;
  if (f === 'ninguno') return null;
  if (f === 'rut' || f === 'telefono') return f;
  const id = (el.id || '').toLowerCase();
  if (/(^|[-_])rut($|[-_])/.test(id)) return 'rut';
  if (t === 'tel' || /(^|[-_])(tel|telefono|fono|celular|whatsapp|wa)($|[-_])/.test(id)) return 'telefono';
  return null;
}

function aplicarFormatoChile(el, borrando) {
  const tipo = tipoCampoChile(el);
  if (!tipo) return;
  const nuevo = tipo === 'rut' ? formatearRut(el.value) : formatearTelefonoCL(el.value, borrando);
  if (nuevo !== el.value) el.value = nuevo;
}

document.addEventListener('input', (e) => {
  aplicarFormatoChile(e.target, !!(e.inputType && e.inputType.startsWith('delete')));
});
// Datos cargados desde la base con otro formato quedan unificados al tocar la casilla
document.addEventListener('focusin', (e) => {
  if (e.target.value) aplicarFormatoChile(e.target, false);
});

// ---------- Montos en pesos: "$45.000" mientras se escribe ----------
// Toda casilla de precio (id o clase con precio / monto / costo / valor, o data-formato="precio") muestra el
// signo peso y los puntos de miles, pero su .value sigue entregando el número limpio ("45000", "1234.5"),
// así el código de cada página no cambia. data-formato="ninguno" la deja como número normal.
const VALOR_INPUT = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');

// "$1.234,5" → "1234.5"  ('' si no hay número)
function montoDesdeTexto(txt) {
  const s = String(txt == null ? '' : txt).trim();
  const negativo = /^-|^\$\s*-/.test(s);
  const partes = s.replace(/[^\d,]/g, '').split(',');
  const entero = partes[0].replace(/^0+(?=\d)/, '');
  const decimales = partes.length > 1 ? partes.slice(1).join('').slice(0, 2) : '';
  if (!entero && !decimales) return '';
  return (negativo ? '-' : '') + (entero || '0') + (decimales ? '.' + decimales : '');
}
// "1234.5" → "$1.234,5"
function textoDeMonto(n) {
  if (n === '' || n == null) return '';
  const negativo = String(n).startsWith('-');
  const [entero, decimales] = String(n).replace('-', '').split('.');
  return (negativo ? '-' : '') + '$' + (entero || '0').replace(/\B(?=(\d{3})+(?!\d))/g, '.') + (decimales ? ',' + decimales : '');
}
// Mientras se escribe se respeta la coma de decimales recién tecleada ("$1.234,")
function textoMontoEscribiendo(txt) {
  const s = String(txt == null ? '' : txt);
  const n = montoDesdeTexto(s);
  if (!n) return '';
  const coma = s.indexOf(',');
  if (coma >= 0 && !n.includes('.')) return textoDeMonto(n) + ',';
  return textoDeMonto(n);
}

function esCampoPrecio(el) {
  if (!el || el.tagName !== 'INPUT' || el.dataset.montoListo) return false;
  const f = el.dataset.formato;
  if (f === 'precio') return true;
  if (f === 'ninguno' || el.type !== 'number') return false;
  const patron = /(^|[-_])(precio|monto|costo|valor)([-_]|$)/;
  return patron.test(el.id || '') || [...el.classList].some(c => patron.test(c));
}

function campoEnPesos(el) {
  return el.dataset.formato !== 'ninguno';
}

// Convierte la casilla: su .value entrega el número limpio y lo que se ve lleva $ y puntos
function prepararCampoPrecio(el) {
  if (!el || el.dataset.montoListo) return;
  el.dataset.montoListo = '1';
  const inicial = VALOR_INPUT.get.call(el);
  Object.defineProperty(el, 'value', {
    configurable: true,
    get() {
      const visto = VALOR_INPUT.get.call(this);
      return campoEnPesos(this) ? montoDesdeTexto(visto) : visto;
    },
    set(v) {
      if (!campoEnPesos(this)) { VALOR_INPUT.set.call(this, v); return; }
      let n = '';
      if (v !== '' && v != null) n = Number.isFinite(Number(v)) ? String(Math.round(Number(v) * 100) / 100) : montoDesdeTexto(v);
      VALOR_INPUT.set.call(this, textoDeMonto(n));
    },
  });
  el.addEventListener('input', () => {
    if (!campoEnPesos(el)) return;
    const visto = VALOR_INPUT.get.call(el);
    const pos = el.selectionStart == null ? visto.length : el.selectionStart;
    const cifrasAntes = visto.slice(0, pos).replace(/[^\d,]/g, '').length;
    const nuevo = textoMontoEscribiendo(visto);
    if (nuevo === visto) return;
    VALOR_INPUT.set.call(el, nuevo);
    // El cursor queda después de la misma cantidad de cifras que había antes
    let i = nuevo.indexOf('$') + 1, c = 0;
    while (i < nuevo.length && c < cifrasAntes) { if (/[\d,]/.test(nuevo[i])) c++; i++; }
    try { el.setSelectionRange(i, i); } catch (e) { /* algunos tipos no admiten cursor */ }
  });
  activarPesos(el, true, inicial);
}

// Casillas que cambian de unidad (descuento en % o en $): activo = muestra pesos
function activarPesos(el, activo, valor) {
  if (!el) return;
  if (!el.dataset.montoListo) { if (!activo) return; prepararCampoPrecio(el); }
  const crudo = valor !== undefined ? valor : el.value;
  if (activo) {
    el.dataset.formato = 'precio';
    if (el.type !== 'text') el.type = 'text';
    el.inputMode = 'numeric';
    el.autocomplete = 'off';
  } else {
    el.dataset.formato = 'ninguno';
    if (el.type !== 'number') el.type = 'number';
    el.removeAttribute('inputmode');
  }
  el.value = crudo;
}

function prepararCamposPrecio(raiz) {
  (raiz || document).querySelectorAll('input').forEach(el => { if (esCampoPrecio(el)) prepararCampoPrecio(el); });
}
// Las casillas que aparecen después (tablas, ventanas) también se convierten
new MutationObserver((cambios) => {
  for (const m of cambios) {
    for (const n of m.addedNodes) {
      if (n.nodeType !== 1) continue;
      if (n.tagName === 'INPUT') { if (esCampoPrecio(n)) prepararCampoPrecio(n); }
      else if (n.querySelector && n.querySelector('input')) prepararCamposPrecio(n);
      // Las casillas de varias filas que ya traen texto se muestran completas
      if (n.matches && n.matches('textarea[data-autoalto]')) ajustarAltoTextarea(n);
      else if (n.querySelectorAll) n.querySelectorAll('textarea[data-autoalto]').forEach(ajustarAltoTextarea);
    }
  }
}).observe(document.documentElement, { childList: true, subtree: true });
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => prepararCamposPrecio());
else prepararCamposPrecio();

// ---------- Fechas en hora de Chile ----------
// new Date().toISOString() entrega la fecha en UTC: después de las 21:00 en Chile ya es «mañana».
// Estas funciones usan siempre la hora de Chile, estés donde estés.
function ymdChile(fecha) {
  return (fecha ? new Date(fecha) : new Date()).toLocaleDateString('en-CA', { timeZone: 'America/Santiago' });
}
function hoyChile() { return ymdChile(); }
// Suma (o resta) días a una fecha YYYY-MM-DD sin depender de la zona horaria.
function sumarDiasYmd(ymd, n) {
  const d = new Date(`${ymd}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
// Último día de validez de una cotización (AAAA-MM-DD): fecha + días de validez. El día siguiente, si sigue
// «enviada» y sin ingreso del vehículo, el servidor la deja rechazada (v66).
function venceCotizacion(c) {
  return sumarDiasYmd(String((c && (c.fecha || c.creado_en)) || hoyChile()).slice(0, 10), Number(c && c.validez_dias) || 15);
}
// Instantes UTC (ISO) de las 00:00 y las 23:59:59 de un día en Chile, para filtrar por fecha_hora.
function limitesDiaChile(ymd) {
  const ref = new Date(`${ymd}T12:00:00Z`);
  const p = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Santiago', hour12: false, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).formatToParts(ref).reduce((o, x) => { o[x.type] = x.value; return o; }, {});
  const comoUtc = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), Number(p.hour) % 24, Number(p.minute), Number(p.second));
  const offsetMs = ref.getTime() - comoUtc;                 // 3 h (verano) o 4 h (invierno)
  const ini = new Date(Date.parse(`${ymd}T00:00:00Z`) + offsetMs);
  return { desde: ini.toISOString(), hasta: new Date(ini.getTime() + 86400000 - 1000).toISOString() };
}

// ---------- Horas: decimales y minutos ----------
// Toda casilla de horas (de trabajo, diagnóstico, registro de horas, catálogo…) acepta cualquier
// decimal (0,5 · 0,33 · 1,25) y trae al lado un campo «o minutos»: se escribe 30 y la casilla de
// horas queda en 0,5. Los dos campos se mantienen iguales entre sí.
// Se detectan por id (…horas…) o con data-horas; para excluir una: data-horas="no".
function minutosAHoras(min) { return Math.round((Number(min) || 0) / 60 * 100) / 100; }
function horasAMinutos(h) { return Math.round((Number(h) || 0) * 60); }

const PARES_HORAS = [];
function esCampoHoras(el) {
  if (!el || el.tagName !== 'INPUT' || (el.type !== 'number' && el.type !== 'text')) return false;
  if (el.dataset.horas === 'no') return false;
  if (el.dataset.horas !== undefined) return true;
  return /(^|[-_])horas($|[-_])/.test((el.id || '').toLowerCase());
}

function enlazarCampoHoras(input) {
  if (!esCampoHoras(input) || input.dataset.horasPar) return;
  input.dataset.horasPar = '1';
  if (input.type === 'number') { input.step = 'any'; input.min = '0'; }
  const caja = document.createElement('span');
  caja.className = 'horas-min';
  caja.innerHTML = '<span>o minutos</span><input type="number" min="0" step="1" inputmode="numeric" placeholder="min" aria-label="Minutos">';
  input.insertAdjacentElement('afterend', caja);
  const min = caja.querySelector('input');

  const sincronizar = () => {
    if (document.activeElement === min) return;
    const h = Number(String(input.value).replace(',', '.'));
    const m = h > 0 ? horasAMinutos(h) : '';
    if (String(min.value) !== String(m)) min.value = m;
  };
  min.addEventListener('input', () => {
    const m = Number(min.value);
    input.value = m > 0 ? String(minutosAHoras(m)) : '';
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
  min.addEventListener('change', () => input.dispatchEvent(new Event('change', { bubbles: true })));
  input.addEventListener('input', sincronizar);
  PARES_HORAS.push({ input, sincronizar });
  sincronizar();
}

function enlazarCamposHoras(raiz) {
  (raiz || document).querySelectorAll('input').forEach(enlazarCampoHoras);
}
// Campos que se crean después (ventanas emergentes, tablas que se redibujan): se enlazan al tocarlos
document.addEventListener('focusin', (e) => enlazarCampoHoras(e.target));
// Los valores que la página escribe por código (al abrir un registro) también se reflejan en «minutos»
setInterval(() => {
  for (let i = PARES_HORAS.length - 1; i >= 0; i--) {
    if (!PARES_HORAS[i].input.isConnected) PARES_HORAS.splice(i, 1);
    else PARES_HORAS[i].sincronizar();
  }
}, 600);
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => enlazarCamposHoras());
else enlazarCamposHoras();

// El registro entrega MARCA Y MODELO EN MAYÚSCULAS: se pasan a "Marca Modelo" dejando
// en mayúsculas las siglas cortas y los códigos (WRX, 2.0T, AWD).
function tituloVehiculo(texto) {
  return String(texto || '').trim().split(/\s+/).map(p => {
    if (p.length < 5 || /\d/.test(p)) return p;
    return p.charAt(0) + p.slice(1).toLowerCase();
  }).join(' ');
}


// Fecha de vencimiento de la clave de patentes (viene dentro de la propia clave). null si no se puede leer.
function claveVence(clave) {
  try {
    const partes = String(clave || '').trim().split('.');
    if (partes.length < 2) return null;
    const json = JSON.parse(atob(partes[1].replace(/-/g, '+').replace(/_/g, '/')));
    return json && json.exp ? new Date(json.exp * 1000) : null;
  } catch (e) { return null; }
}

// Primer valor no vacío entre varios nombres posibles de un campo del registro de vehículos.
function tomarCampo(obj, ...nombres) {
  for (const n of nombres) {
    const v = obj && obj[n];
    if (v != null && String(v).trim() !== '') return String(v).trim();
  }
  return '';
}

// Cualquier dato del registro que el sistema aún no conoce, para no perder nada: { campo: valor }.
function camposDesconocidos(d) {
  const conocidos = new Set(['plate', 'dv', 'make', 'model', 'year', 'type', 'engine', 'gas_type', 'kilometers',
    'color', 'colour', 'vin', 'chassis', 'chasis', 'chassis_number', 'engine_size', 'displacement', 'engine_displacement',
    'cilindrada', 'cc', 'transmission', 'transmission_type', 'gearbox', 'version', 'trim', 'doors', 'door_count', 'num_doors',
    'manufacturer', 'country', 'country_of_origin', 'origin', 'region', 'owner']);
  const otros = {};
  Object.keys(d || {}).forEach(k => {
    const v = d[k];
    if (!conocidos.has(k) && v != null && typeof v !== 'object' && String(v).trim() !== '') otros[k] = String(v).trim();
  });
  return otros;
}

// Combustible del registro (GASOLINA, DIESEL, ELECTRICO…) -> nombre normal para la ficha.
function normalizarCombustible(texto) {
  const t = String(texto || '').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  if (!t) return '';
  if (/gasolina|bencina|nafta/.test(t)) return 'Gasolina';
  if (/diesel|diésel|petroleo/.test(t)) return 'Diésel';
  if (/hibrid|hybrid/.test(t)) return 'Híbrido';
  if (/electric/.test(t)) return 'Eléctrico';
  if (/\bgas\b|glp|gnc|gnv/.test(t)) return 'Gas';
  return String(texto).trim().charAt(0).toUpperCase() + String(texto).trim().slice(1).toLowerCase();
}

// Qué se guarda de los datos del registro de vehículos: campos propios de la ficha y un texto con
// lo que no tiene campo (versión, puertas, fabricante, origen y cualquier dato nuevo del registro).
function fichaDesdeRegistro(d) {
  d = d || {};
  const columnas = {};
  if (d.kilometraje) columnas.kilometraje = d.kilometraje;
  if (d.cilindrada) columnas.motor = d.cilindrada;
  const comb = normalizarCombustible(d.combustible);
  if (comb) columnas.combustible = comb;
  if (d.tipo) columnas.tipo_vehiculo = d.tipo;
  if (d.numero_motor) columnas.numero_motor = d.numero_motor;
  if (d.color) columnas.color = tituloVehiculo(d.color);
  if (d.vin) columnas.vin = d.vin;
  if (d.transmision) columnas.transmision = /auto|cvt|dct|tiptronic/i.test(d.transmision) ? 'Automática' : (/manual|mec/i.test(d.transmision) ? 'Manual' : tituloVehiculo(d.transmision));
  const otros = [];
  if (d.version) otros.push(`Versión: ${d.version}`);
  if (d.puertas) otros.push(`Puertas: ${d.puertas}`);
  if (d.fabricante) otros.push(`Fabricante: ${d.fabricante}`);
  if (d.origen) otros.push(`Origen: ${d.origen}`);
  Object.entries(d.otros || {}).forEach(([k, v]) => otros.push(`${k}: ${v}`));
  return { columnas, notas: otros.join(' · ') };
}

// Si aún no se ejecutó v51, los campos nuevos no existen: se pasan a texto en Notas para no perderlos.
const ETIQUETAS_FICHA = { combustible: 'Combustible', tipo_vehiculo: 'Tipo', numero_motor: 'N° de motor', color: 'Color', transmision: 'Transmisión' };
function columnasConocidasHoy(columnas) {
  const propias = {}, comoTexto = [];
  Object.entries(columnas).forEach(([k, v]) => {
    if (ETIQUETAS_FICHA[k]) comoTexto.push(`${ETIQUETAS_FICHA[k]}: ${v}`); else propias[k] = v;
  });
  return { propias, texto: comoTexto.join(' · ') };
}
function faltaColumnaNueva(error) {
  return !!error && /column|42703|PGRST204|schema cache/i.test(`${error.code || ''} ${error.message || ''}`) && !/duplicate|unique/i.test(error.message || '');
}
const TIPOS_VEHICULO = { 'AUTOMOVIL': 'Automóvil', 'CAMION': 'Camión', 'FURGON': 'Furgón', 'MINIBUS': 'Minibús', 'TRACTOCAMION': 'Tractocamión' };

// Datos públicos del vehículo por patente (boostr.cl). La clave vive en Configuración
// (taller_config.api_patentes_key), nunca en el código. Siempre devuelve { estado, ... }:
//   ok · sin_clave · clave_invalida · no_encontrado · invalida · limite · error
async function consultarPatente(patente) {
  const p = normalizarPatente(patente);
  if (!patenteValida(p)) return { estado: 'invalida' };
  const cfg = await getTallerConfig();
  const clave = cfg && cfg.api_patentes_key;
  // Cada consulta gasta cupo del plan: lo ya consultado en esta pestaña no se vuelve a pedir
  const llaveCache = 'patente:' + p;
  try {
    const guardado = JSON.parse(sessionStorage.getItem(llaveCache) || 'null');
    if (guardado && guardado.estado) return guardado;
  } catch (e) { /* sin almacenamiento: se consulta igual */ }
  if (!clave) return { estado: 'sin_clave' };
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 9000);
  try {
    const r = await fetch(`https://api.boostr.cl/vehicle/${encodeURIComponent(p)}.json`, {
      headers: { 'X-API-KEY': clave },
      signal: ctrl.signal,
    });
    let j = null;
    try { j = await r.json(); } catch (e) { j = null; }
    if (r.ok && j && j.status === 'success' && j.data) {
      const d = j.data;
      const cupoHeader = r.headers.get('ratelimit-remaining');
      const resultado = {
        cupo: cupoHeader != null && cupoHeader !== '' ? Number(cupoHeader) : null,
        estado: 'ok',
        datos: {
          marca: tituloVehiculo(d.make),
          modelo: tituloVehiculo(d.model),
          anio: Number(d.year) > 1900 ? Number(d.year) : null,
          tipo: d.type ? (TIPOS_VEHICULO[String(d.type).trim().toUpperCase()] || tituloVehiculo(d.type)) : '',
          numero_motor: d.engine ? String(d.engine).trim() : '',
          combustible: d.gas_type ? String(d.gas_type).trim() : '',
          kilometraje: Number(d.kilometers) > 0 ? Math.round(Number(d.kilometers)) : null,
          // Datos que el registro entrega en planes ampliados (los nombres pueden variar): se toman si vienen
          color: tomarCampo(d, 'color', 'colour'),
          vin: tomarCampo(d, 'vin', 'chassis', 'chasis', 'chassis_number'),
          cilindrada: tomarCampo(d, 'engine_size', 'displacement', 'engine_displacement', 'cilindrada', 'cc'),
          transmision: tomarCampo(d, 'transmission', 'transmission_type', 'gearbox'),
          version: tomarCampo(d, 'version', 'trim'),
          puertas: tomarCampo(d, 'doors', 'door_count', 'num_doors'),
          fabricante: tomarCampo(d, 'manufacturer'),
          origen: tomarCampo(d, 'country', 'country_of_origin', 'origin', 'region'),
          otros: camposDesconocidos(d),
        },
      };
      try { sessionStorage.setItem(llaveCache, JSON.stringify(resultado)); } catch (e) { /* ok */ }
      return resultado;
    }
    const codigo = j && j.code;
    if (codigo === 'V-02' || r.status === 404) {
      const sin = { estado: 'no_encontrado' };
      try { sessionStorage.setItem(llaveCache, JSON.stringify(sin)); } catch (e) { /* ok */ }
      return sin;
    }
    if (codigo === 'V-04') return { estado: 'invalida' };
    if (r.status === 429 || /LIMIT|QUOTA|RATE|EXCEED/i.test(String(codigo || '') + ' ' + String((j && j.message) || ''))) return { estado: 'limite' };
    if (r.status === 401 || r.status === 403) return { estado: 'clave_invalida' };
    if (r.status === 429) return { estado: 'limite' };
    return { estado: 'error', mensaje: (j && j.message) || `HTTP ${r.status}` };
  } catch (e) {
    return { estado: 'error', mensaje: e.name === 'AbortError' ? 'el servicio tardó demasiado en responder' : e.message };
  } finally {
    clearTimeout(timer);
  }
}

// Abre Gmail con el correo ya redactado (asunto + cuerpo). El usuario
// solo presiona Enviar. Funciona a cualquier destinatario, sin dominio.
function linkGmail(para, asunto, cuerpo) {
  const p = new URLSearchParams({ view: 'cm', fs: '1', to: para || '', su: asunto || '', body: cuerpo || '' });
  return 'https://mail.google.com/mail/?' + p.toString();
}

// Abre un enlace en pestaña nueva; si el navegador bloquea la ventana
// emergente, navega en la misma pestaña (así nunca "no pasa nada").
function abrirEnlace(url) {
  if (!url) return;
  let w = null;
  try { w = window.open(url, '_blank'); } catch (e) { w = null; }
  if (!w) window.location.href = url;
}

// Auto-numeración en textareas: al presionar Enter en una línea que empieza con
// "1. ", "a. ", "- ", "• " o "* ", la línea siguiente continúa la lista (2., b., -...).
// Enter sobre un ítem vacío termina la lista. Acepta el elemento o su id. Por defecto también «inicia» la lista:
// el primer Enter sobre una línea con texto la numera (opciones.iniciar === false lo desactiva).
function setupAutoList(textareaOrId, opciones = {}) {
  const textarea = typeof textareaOrId === 'string' ? document.getElementById(textareaOrId) : textareaOrId;
  if (!textarea || textarea.dataset.autoList) return;
  textarea.dataset.autoList = '1';
  textarea.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.shiftKey || e.isComposing) return;
    const text = textarea.value;
    const pos = textarea.selectionStart;
    const lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    const line = text.substring(lineStart, pos);
    const match = line.match(/^(\d+\.|[a-z]\.|[-•*])\s+/);
    if (!match) {
      // Modo «iniciar»: el primer Enter sobre una línea con texto la convierte en el ítem 1 y abre el 2.
      // Si más arriba ya hay una lista (o se cerró con un ítem vacío) no se toca nada.
      if (opciones.iniciar === false || !line.trim()) return;
      const antes = text.substring(0, lineStart);
      if (antes.split('\n').some(l => /^(\d+\.|[a-z]\.|[-•*])\s+/.test(l))) return;
      e.preventDefault();
      const nueva = antes + '1. ' + line + '\n2. ';
      textarea.value = nueva + text.substring(pos);
      textarea.selectionStart = textarea.selectionEnd = nueva.length;
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      return;
    }
    e.preventDefault();
    // Ítem vacío (solo el marcador): se quita y la lista termina
    if (!line.substring(match[0].length).trim()) {
      textarea.value = text.substring(0, lineStart) + text.substring(pos);
      textarea.selectionStart = textarea.selectionEnd = lineStart;
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      return;
    }
    const prefix = match[1];
    let nextPrefix = '';
    if (/^\d+\.$/.test(prefix)) {
      nextPrefix = (parseInt(prefix) + 1) + '. ';
    } else if (/^[a-z]\.$/.test(prefix)) {
      const char = prefix.charCodeAt(0);
      nextPrefix = char < 122 ? String.fromCharCode(char + 1) + '. ' : prefix + ' ';
    } else {
      nextPrefix = prefix + ' ';
    }
    textarea.value = text.substring(0, pos) + '\n' + nextPrefix + text.substring(pos);
    textarea.selectionStart = textarea.selectionEnd = pos + 1 + nextPrefix.length;
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

// Toda casilla de texto largo numera sola sus filas al escribir (1., 2., 3.…) y crece con el contenido,
// en cualquier pantalla y también en las que aparecen después. Se excluye con data-autolista="no" (en la
// casilla o en un contenedor), p. ej. las plantillas de mensajes de Configuración.
document.addEventListener('focusin', (e) => {
  const t = e.target;
  if (!t || t.tagName !== 'TEXTAREA' || t.readOnly || t.dataset.autoList || t.closest('[data-autolista="no"]')) return;
  setupAutoList(t);
});
function ajustarAltoTextarea(t) {
  if (!t.isConnected || !t.offsetParent) return;   // oculta: se ajusta al mostrarse o al tocarla
  t.style.height = 'auto';
  t.style.height = (t.scrollHeight + 2) + 'px';
}
document.addEventListener('input', (e) => {
  if (e.target && e.target.tagName === 'TEXTAREA' && e.target.dataset.autoalto !== undefined) ajustarAltoTextarea(e.target);
});
document.addEventListener('focusin', (e) => {
  if (e.target && e.target.tagName === 'TEXTAREA' && e.target.dataset.autoalto !== undefined) ajustarAltoTextarea(e.target);
});

// Texto del usuario listo para meter en HTML (sin interpretar etiquetas).
// htmlSeguroMulti además respeta los saltos de línea.
function htmlSeguro(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function htmlSeguroMulti(s) {
  return htmlSeguro(s).replace(/\n/g, '<br>');
}

// SO · navegador legible (ej. "Android · Chrome"), para el registro de
// auditoría de firmas electrónicas.
function detectarDispositivo() {
  const ua = navigator.userAgent || '';
  let so = 'Desconocido';
  if (/Android/i.test(ua)) so = 'Android';
  else if (/iPhone|iPad|iPod/i.test(ua)) so = 'iPhone/iPad (iOS)';
  else if (/Windows/i.test(ua)) so = 'Windows';
  else if (/Macintosh|Mac OS/i.test(ua)) so = 'Mac';
  else if (/Linux/i.test(ua)) so = 'Linux';

  let navegador = 'Navegador';
  if (/Edg\//i.test(ua)) navegador = 'Edge';
  else if (/OPR\//i.test(ua) || /Opera/i.test(ua)) navegador = 'Opera';
  else if (/CriOS\//i.test(ua)) navegador = 'Chrome';
  else if (/Chrome\//i.test(ua) && !/Edg\//i.test(ua)) navegador = 'Chrome';
  else if (/Firefox\//i.test(ua)) navegador = 'Firefox';
  else if (/Safari\//i.test(ua) && !/Chrome/i.test(ua)) navegador = 'Safari';

  return `${so} · ${navegador}`;
}

// Muestra el documento (cotización, OT, diagnóstico, inspección, libro contable) a pantalla completa dentro de
// la MISMA página, con una barra: «← Volver» · «🖨 Imprimir» · «📄 PDF».
//   · Imprimir: el diálogo del navegador (solo sale el documento).
//   · PDF: genera un archivo PDF real y lo comparte (WhatsApp, correo, Archivos…) o lo descarga. Es la vía que
//     funciona en el celular: en la app instalada en la pantalla de inicio (y en iPhone en general) el
//     navegador no deja imprimir desde la página, así que «Imprimir» puede no responder.
// Los botones se habilitan cuando cargaron las imágenes (logo, firmas, fotos), para que salgan en el documento.
function abrirVentanaImpresion(html, titulo) {
  cerrarVistaImpresion();
  const nombre = titulo || 'Documento';
  const cont = document.createElement('div');
  cont.id = 'vista-impresion';
  cont.setAttribute('role', 'dialog');
  cont.setAttribute('aria-label', nombre);
  cont.innerHTML = `
    <div class="barra-impresion">
      <button type="button" class="vi-volver">← Volver</button>
      <span class="vi-titulo">${htmlSeguro(nombre)}</span>
      <span class="vi-acciones">
        <button type="button" class="vi-imprimir" disabled>🖨 Imprimir</button>
        <button type="button" class="vi-pdf" disabled>Preparando…</button>
      </span>
    </div>
    <p class="vi-ayuda">En el celular usa <strong>«📄 PDF»</strong>: arma el archivo y luego puedes enviarlo por WhatsApp o correo, o guardarlo.</p>
    <div class="print-area" id="print-area">${html}</div>`;
  document.body.appendChild(cont);
  document.body.classList.add('con-vista-impresion');
  // El nombre sugerido al imprimir es el título de la página
  cont.dataset.tituloAnterior = document.title;
  document.title = nombre;
  cont.scrollTop = 0;

  const botonImprimir = cont.querySelector('.vi-imprimir');
  const botonPdf = cont.querySelector('.vi-pdf');
  botonImprimir.addEventListener('click', () => window.print());
  botonPdf.addEventListener('click', () => accionPdfDocumento(cont, nombre, botonPdf));
  cont.querySelector('.vi-volver').addEventListener('click', cerrarVistaImpresion);
  esperarImagenesImpresion(cont).then(() => {
    if (!document.body.contains(cont)) return;
    botonImprimir.disabled = false;
    botonPdf.disabled = false;
    botonPdf.textContent = '📄 PDF';
  });
}

// ---------- PDF como archivo (html2pdf.js, se carga solo la primera vez que se usa) ----------
const URL_HTML2PDF = 'https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js';
let cargaHtml2pdf = null;
function cargarHtml2pdf() {
  if (window.html2pdf) return Promise.resolve(window.html2pdf);
  if (!cargaHtml2pdf) {
    cargaHtml2pdf = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = URL_HTML2PDF;
      s.async = true;
      s.onload = () => (window.html2pdf ? resolve(window.html2pdf) : reject(new Error('el generador de PDF no se cargó')));
      s.onerror = () => { cargaHtml2pdf = null; reject(new Error('no se pudo cargar el generador de PDF: revisa la conexión a internet')); };
      document.head.appendChild(s);
    });
  }
  return cargaHtml2pdf;
}

// Arma el PDF (hoja A4, con el ancho de una hoja aunque se esté en el celular) y devuelve un File
async function generarPdfDocumento(cont, nombre) {
  const html2pdf = await cargarHtml2pdf();
  const hoja = document.createElement('div');
  hoja.className = 'print-area pdf-hoja';
  hoja.innerHTML = cont.querySelector('#print-area').innerHTML;
  // Nitidez: el doble de resolución, salvo en documentos largos (fotos, expedientes): los celulares no aceptan
  // imágenes de más de ~16 megapíxeles y el PDF saldría en blanco
  const medida = hoja.cloneNode(true);
  medida.style.cssText = 'position:absolute; left:-10000px; top:0; width:760px;';
  document.body.appendChild(medida);
  await esperarImagenesImpresion(medida);
  const alto = Math.max(medida.scrollHeight, 400);
  medida.remove();
  const escala = Math.max(0.75, Math.min(2, Math.sqrt(12e6 / (760 * alto))));
  const blob = await html2pdf().set({
    margin: [8, 6, 10, 6],
    filename: `${nombre}.pdf`,
    image: { type: 'jpeg', quality: 0.92 },
    // windowWidth = ancho de la hoja: se ve igual en el celular que en el computador.
    // scrollX/scrollY = 0: si la página de atrás estaba desplazada hacia abajo, el PDF salía en blanco.
    html2canvas: { scale: escala, useCORS: true, backgroundColor: '#ffffff', logging: false, windowWidth: 820, scrollX: 0, scrollY: 0 },
    jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
    pagebreak: { mode: ['css', 'legacy'], avoid: ['tr', 'img', '.print-brand', '.print-header'] },
  }).from(hoja).outputPdf('blob');
  return new File([blob], `${nombre.replace(/[\\/:*?"<>|]+/g, '-')}.pdf`, { type: 'application/pdf' });
}

function descargarArchivo(archivo) {
  const url = URL.createObjectURL(archivo);
  const a = document.createElement('a');
  a.href = url;
  a.download = archivo.name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

// 1.er toque: arma el PDF. 2.º toque: lo envía con el menú de compartir del teléfono (o lo descarga en el
// computador). Son dos toques porque el teléfono solo permite compartir justo después de tocar un botón.
async function accionPdfDocumento(cont, nombre, boton) {
  if (boton.disabled) return;
  if (cont._pdfListo) {
    const archivo = cont._pdfListo;
    if (navigator.canShare && navigator.canShare({ files: [archivo] })) {
      try { await navigator.share({ files: [archivo], title: nombre }); return; }
      catch (e) { if (e && e.name === 'AbortError') return; }   // cancelado por la persona: no se hace nada
    }
    descargarArchivo(archivo);
    return;
  }
  boton.disabled = true;
  boton.textContent = 'Armando PDF…';
  try {
    cont._pdfListo = await generarPdfDocumento(cont, nombre);
    boton.textContent = (navigator.canShare && navigator.canShare({ files: [cont._pdfListo] })) ? '📤 Enviar PDF' : '⬇ Descargar PDF';
    boton.classList.add('vi-pdf-listo');
  } catch (e) {
    boton.textContent = '📄 PDF';
    alert(`No se pudo generar el PDF: ${e && e.message ? e.message : e}`);
  } finally {
    boton.disabled = false;
  }
}

function cerrarVistaImpresion() {
  const cont = document.getElementById('vista-impresion');
  if (!cont) return;
  if (cont.dataset.tituloAnterior) document.title = cont.dataset.tituloAnterior;
  cont.remove();
  document.body.classList.remove('con-vista-impresion');
}

// Esc cierra la vista del documento
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && document.getElementById('vista-impresion')) cerrarVistaImpresion();
});

// Espera a que carguen las imágenes del documento (con un tope de 8 s para no quedar esperando una que falla)
function esperarImagenesImpresion(contenedor) {
  const imgs = Array.from(contenedor.querySelectorAll('img'));
  if (!imgs.length) return Promise.resolve();
  const todas = Promise.all(imgs.map(img => {
    if (img.complete) return Promise.resolve();
    return new Promise(resolve => {
      img.addEventListener('load', resolve, { once: true });
      img.addEventListener('error', resolve, { once: true });
    });
  }));
  return Promise.race([todas, new Promise(resolve => setTimeout(resolve, 8000))]);
}

// ---------- Bloqueos de agenda (compartido por Agenda y Configuración) ----------
// Ambas pantallas leen y escriben la misma tabla bloqueos_agenda, así que un
// bloqueo creado en una aparece en la otra al cargarla.

// Crea un bloqueo y devuelve las citas que ya existían en ese período (no se
// borran: se avisa para que el taller las reubique).
async function crearBloqueoAgenda({ desde, hasta, horaDesde, horaHasta, motivo }) {
  const fin = hasta || desde;
  const { error } = await supabaseClient.from('bloqueos_agenda').insert({
    fecha_desde: desde, fecha_hasta: fin,
    hora_desde: horaDesde || null, hora_hasta: horaHasta || null,
    motivo: motivo || null,
  });
  if (error) return { error, afectadas: [] };

  const inicio = new Date(`${desde}T00:00:00`);
  const { data: citas } = await supabaseClient.from('citas')
    .select('fecha_hora, nombre_contacto, clientes(nombre)')
    .neq('estado', 'cancelado')
    .gte('fecha_hora', new Date(Math.max(inicio.getTime(), Date.now())).toISOString())
    .lte('fecha_hora', new Date(`${fin}T23:59:59`).toISOString())
    .order('fecha_hora');
  const afectadas = (citas || []).filter(c => {
    if (!horaDesde) return true;
    const f = new Date(c.fecha_hora);
    const hm = `${String(f.getHours()).padStart(2, '0')}:${String(f.getMinutes()).padStart(2, '0')}`;
    return hm >= horaDesde && hm < horaHasta;
  });
  return { error: null, afectadas };
}

// Texto del aviso "hay citas dentro del bloqueo" ('' si no hay ninguna).
function textoCitasAfectadas(afectadas) {
  if (!afectadas || !afectadas.length) return '';
  const p2 = (n) => String(n).padStart(2, '0');
  return `⚠ Bloqueo guardado, pero ya hay ${afectadas.length} cita(s) en ese período (no se borraron, avísales tú):\n` +
    afectadas.map(c => {
      const f = new Date(c.fecha_hora);
      return `• ${p2(f.getDate())}-${p2(f.getMonth() + 1)} ${p2(f.getHours())}:${p2(f.getMinutes())} — ${(c.clientes && c.clientes.nombre) || c.nombre_contacto || 'Sin nombre'}`;
    }).join('\n');
}

// Pide confirmación y elimina un bloqueo. Devuelve { quitado, error }.
async function quitarBloqueoAgenda(id) {
  if (!confirm('¿Quitar este bloqueo? Esas horas volverán a estar disponibles.')) return { quitado: false };
  const { error } = await supabaseClient.from('bloqueos_agenda').delete().eq('id', id);
  return { quitado: !error, error };
}

// Mes (1-12) de revisión técnica según el último dígito de la patente
// (calendario para vehículos particulares).
const RT_MES_POR_DIGITO = { '9': 1, '0': 2, '1': 4, '2': 5, '3': 6, '4': 7, '5': 8, '6': 9, '7': 10, '8': 11 };
function rtMesPatente(patente) {
  const m = String(patente || '').match(/(\d)(?!.*\d)/); // último dígito
  return m ? (RT_MES_POR_DIGITO[m[1]] || null) : null;
}

const NOMBRE_MES = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

// Configuración del taller cacheada (valor hora, IVA, datos para impresión)
let tallerConfigCache = null;
async function getTallerConfig() {
  if (tallerConfigCache) return tallerConfigCache;
  const { data } = await supabaseClient.from('taller_config').select('*').eq('id', 1).single();
  tallerConfigCache = data || { nombre: 'Autonova', valor_hora: 0, iva_pct: 19 };
  return tallerConfigCache;
}

// ---------- Campanita de novedades ----------
// Muestra, arriba a la derecha, las novedades que genera el cliente (reservas online,
// cotizaciones y diagnósticos respondidos, inspecciones firmadas). Cada novedad vive en la
// tabla `notificaciones`; si esa tabla aún no existe (falta v38), la campanita no aparece.
function haceTiempo(iso) {
  const seg = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (seg < 60) return 'justo ahora';
  if (seg < 3600) return `hace ${Math.floor(seg / 60)} min`;
  if (seg < 86400) return `hace ${Math.floor(seg / 3600)} h`;
  if (seg < 172800) return 'ayer';
  return fmtFecha(iso);
}

function iniciarCampanita() {
  const topbar = document.querySelector('.topbar');
  if (!topbar || document.getElementById('campanita-btn')) return;

  const tituloBase = document.title;
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'campanita-btn';
  btn.className = 'campanita';
  btn.setAttribute('aria-label', 'Novedades');
  btn.title = 'Novedades';
  btn.hidden = true;                       // se muestra cuando se confirma que la tabla existe
  btn.innerHTML = '🔔<span class="campanita-badge" id="campanita-badge" hidden>0</span>';
  topbar.appendChild(btn);

  const panel = document.createElement('div');
  panel.id = 'campanita-panel';
  panel.className = 'campanita-panel';
  panel.hidden = true;
  document.body.appendChild(panel);

  let items = [];
  let sinLeer = 0;
  let baseline = false;                    // la primera carga no cuenta como "nueva"
  const vistos = new Set();

  const permisoNavegador = () => ('Notification' in window) ? Notification.permission : 'unsupported';

  function pintarBadge() {
    const badge = document.getElementById('campanita-badge');
    badge.hidden = sinLeer === 0;
    badge.textContent = sinLeer > 99 ? '99+' : String(sinLeer);
    document.title = sinLeer > 0 ? `(${sinLeer}) ${tituloBase}` : tituloBase;
  }

  function pintarPanel() {
    const avisos = permisoNavegador();
    panel.innerHTML = `
      <div class="campanita-cab">
        <strong>Novedades</strong>
        <span>
          <button type="button" class="campanita-link" data-accion="leer-todas" ${sinLeer ? '' : 'disabled'}>Marcar todas como leídas</button>
        </span>
      </div>
      <div class="campanita-lista">
        ${items.length ? items.map(n => `
          <div class="campanita-item${n.leida ? '' : ' sin-leer'}" data-id="${n.id}">
            <div class="campanita-titulo">${htmlSeguro(n.titulo)}</div>
            ${n.detalle ? `<div class="campanita-detalle">${htmlSeguro(n.detalle)}</div>` : ''}
            ${n.tipo === 'reserva_online' && n.ref_id && !n.leida ? '<div class="campanita-accion">✅ Confirmar agenda y dimensionar las horas →</div>' : ''}
            <div class="campanita-hora">${haceTiempo(n.creado_en)}</div>
          </div>`).join('') : '<p class="campanita-vacio">Sin novedades por ahora.</p>'}
      </div>
      <div class="campanita-pie">
        ${avisos === 'default' ? '<button type="button" class="campanita-link" data-accion="activar-avisos">🔔 Activar avisos del navegador</button>' : ''}
        ${avisos === 'granted' ? '<span>✓ Avisos del navegador activos</span>' : ''}
        ${avisos === 'denied' ? '<span>Avisos del navegador bloqueados en este navegador</span>' : ''}
        ${items.some(n => n.leida) ? '<button type="button" class="campanita-link" data-accion="borrar-leidas">Borrar leídas</button>' : ''}
      </div>`;
  }

  async function cargar() {
    const { data, error } = await supabaseClient.from('notificaciones').select('*')
      .order('creado_en', { ascending: false }).limit(40);
    if (error) { btn.hidden = true; return; }          // falta v38: sin campanita
    btn.hidden = false;
    items = data || [];
    sinLeer = items.filter(n => !n.leida).length;

    // Avisos nuevos desde la última vez: aviso del navegador si la pestaña no está a la vista
    const nuevos = items.filter(n => !n.leida && !vistos.has(n.id));
    items.forEach(n => vistos.add(n.id));
    if (baseline && nuevos.length && permisoNavegador() === 'granted' && document.visibilityState === 'hidden') {
      nuevos.slice(0, 3).forEach(n => { try { new Notification(n.titulo, { body: n.detalle || '' }); } catch (e) { /* sin permiso real */ } });
    }
    baseline = true;
    pintarBadge();
    if (!panel.hidden) pintarPanel();
  }

  btn.addEventListener('click', (e) => {
    e.stopPropagation();
    panel.hidden = !panel.hidden;
    if (!panel.hidden) { pintarPanel(); cargar(); }
  });
  document.addEventListener('click', (e) => {
    if (!panel.hidden && !panel.contains(e.target) && e.target !== btn) panel.hidden = true;
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') panel.hidden = true; });

  panel.addEventListener('click', async (e) => {
    const accion = e.target.closest('[data-accion]');
    if (accion) {
      const a = accion.dataset.accion;
      if (a === 'leer-todas') {
        await supabaseClient.from('notificaciones').update({ leida: true }).eq('leida', false);
        await cargar();
      } else if (a === 'borrar-leidas') {
        await supabaseClient.from('notificaciones').delete().eq('leida', true);
        await cargar();
      } else if (a === 'activar-avisos') {
        try { await Notification.requestPermission(); } catch (err) { /* navegador sin soporte */ }
        pintarPanel();
      }
      return;
    }
    const fila = e.target.closest('.campanita-item');
    if (!fila) return;
    const n = items.find(x => x.id === fila.dataset.id);
    if (!n) return;
    // Reserva online pendiente: se abre para confirmarla (queda sin leer hasta que se confirme o rechace)
    if (n.tipo === 'reserva_online' && n.ref_id && !n.leida) {
      panel.hidden = true;
      if (typeof window.abrirConfirmacionCita === 'function') { window.abrirConfirmacionCita(n.ref_id); return; }
      window.location.href = `/pages/agenda.html?confirmar=${encodeURIComponent(n.ref_id)}`;
      return;
    }
    if (!n.leida) await supabaseClient.from('notificaciones').update({ leida: true }).eq('id', n.id);
    if (n.url) window.location.href = `/pages/${n.url}`;
    else await cargar();
  });

  // Se mantiene al día sola: cada 45 s con la pestaña a la vista, y al volver a ella
  cargar();
  setInterval(() => { if (document.visibilityState === 'visible') cargar(); }, 45000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') cargar(); });
}

// Resalta en el submenú de Configuración la sección que se está mirando
function marcarSubmenuConfig(id) {
  if (!document.querySelector('.nav-sub')) return;
  const actual = SECCIONES_CONFIG.some(s => s.id === id) ? id : 'todo';
  document.querySelectorAll('.nav-sub a').forEach(a => a.classList.toggle('active', a.dataset.cfg === actual));
}

async function initLayout(activeKey) {
  const session = await requireAuth();
  if (!session) return;

  const sidebar = document.getElementById('sidebar');
  if (sidebar) {
    const navLinks = NAV_ITEMS.map(item => {
      const activeClass = item.key === activeKey ? ' class="active"' : '';
      if (item.key !== 'configuracion') return `<a href="${item.href}"${activeClass}>${item.label}</a>`;
      // Configuración se despliega con sus secciones (en su propia página queda abierto)
      const abierto = activeKey === 'configuracion';
      return `<a href="${item.href}" class="nav-padre${abierto ? ' active abierto' : ''}">${item.label} <span class="nav-flecha">▾</span></a>
        <div class="nav-sub"${abierto ? '' : ' hidden'}>${SECCIONES_CONFIG.map(s => `<a href="configuracion.html#${s.id}" data-cfg="${s.id}">${s.label}</a>`).join('')}</div>`;
    }).join('');

    // Logo opcional: si existe assets/img/logo.png se muestra; si no, se oculta solo.
    const logoTag = `<img class="brand-logo" src="../assets/img/logo.png" alt="" onerror="this.style.display='none'">`;

    sidebar.innerHTML = `
      <div class="brand">${logoTag}<span>Autonova<span class="brand-sub">Sistema de Taller</span></span></div>
      <nav>${navLinks}</nav>
      <div class="sidebar-footer">
        <button id="logout-btn" class="btn-secondary" style="border-color: rgba(255,255,255,0.4); color: #fff;">Cerrar sesión</button>
      </div>
    `;

    document.getElementById('logout-btn').addEventListener('click', logout);

    // «Configuración» abre y cierra su submenú ahí mismo (no cambia de página)
    sidebar.querySelectorAll('.nav-padre').forEach(a => a.addEventListener('click', (e) => {
      e.preventDefault();
      const sub = a.nextElementSibling;
      const abrir = sub.hidden;
      sub.hidden = !abrir;
      a.classList.toggle('abierto', abrir);
    }));
    if (activeKey === 'configuracion') marcarSubmenuConfig(window.location.hash.slice(1));

    // Menú móvil: botón hamburguesa + fondo oscuro
    const shell = sidebar.closest('.app-shell');
    const topbar = document.querySelector('.topbar');
    if (shell && topbar && !document.querySelector('.menu-toggle')) {
      const btn = document.createElement('button');
      btn.className = 'menu-toggle';
      btn.setAttribute('aria-label', 'Abrir menú');
      btn.innerHTML = '☰';
      topbar.insertBefore(btn, topbar.firstChild);

      const backdrop = document.createElement('div');
      backdrop.className = 'sidebar-backdrop';
      shell.appendChild(backdrop);

      const cerrar = () => shell.classList.remove('nav-open');
      btn.addEventListener('click', () => shell.classList.toggle('nav-open'));
      backdrop.addEventListener('click', cerrar);
      sidebar.querySelectorAll('nav a:not(.nav-padre)').forEach(a => a.addEventListener('click', cerrar));
    }
  }

  iniciarCampanita();
  return session;
}
