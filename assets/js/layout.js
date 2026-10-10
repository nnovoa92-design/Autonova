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
  { key: 'contabilidad', label: 'Contabilidad', href: 'contabilidad.html' },
  { key: 'configuracion', label: 'Configuración', href: 'configuracion.html' },
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

// ---------- Descuento (en % o en pesos) ----------
// Un descuento se guarda como { tipo: 'pct' | 'monto', pct, monto }:
//  · 'pct': un porcentaje; el monto en pesos se recalcula si cambian los ítems.
//  · 'monto': un valor fijo en pesos; el % es solo una referencia y cambia con los ítems.
// En las tablas viven en descuento_tipo, descuento_pct y descuento_monto.
// Acepta un número (porcentaje, como antes), una fila de la base o { tipo, pct, monto }.
function normalizarDescuento(d) {
  if (d == null || d === '') return { tipo: 'pct', pct: 0, monto: 0 };
  if (typeof d === 'number' || typeof d === 'string') return { tipo: 'pct', pct: Number(d) || 0, monto: 0 };
  const tipo = (d.tipo || d.descuento_tipo) === 'monto' ? 'monto' : 'pct';
  return {
    tipo,
    pct: Number(d.pct ?? d.descuento_pct ?? 0) || 0,
    monto: Number(d.monto ?? d.descuento_monto ?? 0) || 0,
  };
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
function campoDescuento(d, subtotal) {
  const n = normalizarDescuento(d);
  if (n.tipo === 'monto') {
    const c = calcularDescuento(subtotal, n);
    return { descuento_tipo: 'monto', descuento_monto: Math.round(n.monto), descuento_pct: Math.round(c.pct * 100) / 100 };
  }
  return { descuento_tipo: 'pct', descuento_pct: Math.min(100, Math.max(0, n.pct)), descuento_monto: 0 };
}

// Total (con IVA si corresponde) de una cotización, tomando de su OT los ítems, el descuento y el
// IVA cuando la OT ya existe (la OT manda). `cot` trae cotizacion_items y, si se quiere seguir la
// OT, ordenes(descuento_tipo, descuento_pct, descuento_monto, con_iva, orden_items(cantidad, precio_unitario)).
function totalVigenteCotizacion(cot, ivaPct = 19) {
  const o = (cot.ordenes || [])[0];
  const fuente = o || cot;
  const items = o ? (o.orden_items || []) : (cot.cotizacion_items || []);
  const subtotal = items.reduce((s, i) => s + Number(i.cantidad) * Number(i.precio_unitario), 0);
  const neto = subtotal - calcularDescuento(subtotal, fuente).monto;
  return fuente.con_iva !== false ? neto * (1 + Number(ivaPct) / 100) : neto;
}

// Valor NETO (sin IVA) de una cotización, con su descuento aplicado. Si ya tiene OT, valen los
// ítems y el descuento de la OT. Es el valor que se muestra al cliente en agenda y recordatorios.
function netoVigenteCotizacion(cot) {
  const o = (cot.ordenes || [])[0];
  const fuente = o || cot;
  const items = o ? (o.orden_items || []) : (cot.cotizacion_items || []);
  const subtotal = items.reduce((s, i) => s + Number(i.cantidad) * Number(i.precio_unitario), 0);
  return subtotal - calcularDescuento(subtotal, fuente).monto;
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
function leerDescuentoUI(idValor, idTipo) {
  const tipo = document.getElementById(idTipo).value === 'monto' ? 'monto' : 'pct';
  const v = Math.max(0, Number(document.getElementById(idValor).value) || 0);
  return tipo === 'monto' ? { tipo, pct: 0, monto: v } : { tipo, pct: Math.min(100, v), monto: 0 };
}
function escribirDescuentoUI(idValor, idTipo, d) {
  const n = normalizarDescuento(d);
  const tipoEl = document.getElementById(idTipo);
  tipoEl.value = n.tipo;
  tipoEl.dataset.tipoPrevio = n.tipo;     // para convertir bien si luego se cambia de unidad
  const el = document.getElementById(idValor);
  el.value = n.tipo === 'monto' ? Math.round(n.monto) : n.pct;
  el.max = n.tipo === 'monto' ? '' : '100';
  el.step = n.tipo === 'monto' ? '1' : '0.5';
}
function actualizarEquivDescuentoUI(idValor, idTipo, subtotal) {
  const el = document.getElementById(idValor + '-equiv');
  if (!el) return;
  const d = leerDescuentoUI(idValor, idTipo);
  const c = calcularDescuento(subtotal, d);
  if (!(c.monto > 0)) { el.textContent = ''; return; }
  el.textContent = d.tipo === 'pct' ? `= ${fmtMoneda(c.monto)}` : `= ${fmtPorcentaje(c.pct)} %`;
}
// Al cambiar de % a pesos (o al revés) el descuento sigue siendo el mismo: solo se expresa en la otra unidad.
// getSubtotal() entrega el subtotal vigente; onChange() vuelve a calcular totales.
function setupDescuentoUI(idValor, idTipo, getSubtotal, onChange) {
  const tipoEl = document.getElementById(idTipo);
  if (!tipoEl || tipoEl.dataset.descuentoUi) return;
  tipoEl.dataset.descuentoUi = '1';
  tipoEl.dataset.tipoPrevio = tipoEl.value;
  tipoEl.addEventListener('change', () => {
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

// El registro entrega MARCA Y MODELO EN MAYÚSCULAS: se pasan a "Marca Modelo" dejando
// en mayúsculas las siglas cortas y los códigos (WRX, 2.0T, AWD).
function tituloVehiculo(texto) {
  return String(texto || '').trim().split(/\s+/).map(p => {
    if (p.length < 5 || /\d/.test(p)) return p;
    return p.charAt(0) + p.slice(1).toLowerCase();
  }).join(' ');
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
      return {
        estado: 'ok',
        datos: {
          marca: tituloVehiculo(d.make),
          modelo: tituloVehiculo(d.model),
          anio: Number(d.year) > 1900 ? Number(d.year) : null,
          tipo: d.type ? (TIPOS_VEHICULO[String(d.type).trim().toUpperCase()] || tituloVehiculo(d.type)) : '',
          numero_motor: d.engine ? String(d.engine).trim() : '',
        },
      };
    }
    const codigo = j && j.code;
    if (codigo === 'V-02' || r.status === 404) return { estado: 'no_encontrado' };
    if (codigo === 'V-04') return { estado: 'invalida' };
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
// Enter sobre un ítem vacío termina la lista. Acepta el elemento o su id.
function setupAutoList(textareaOrId) {
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
    if (!match) return;
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

// Abre una ventana nueva con el documento a imprimir ya armado (sin el
// resto de la app alrededor) y dispara la impresión ahí. Reemplaza el
// método anterior (@media print sobre la misma página / html2canvas
// contra un contenedor oculto), que no siempre alcanzaba a renderizar
// imágenes como firmas o fotos antes de imprimir.
function abrirVentanaImpresion(html, titulo) {
  const w = window.open('', '_blank');
  if (!w) {
    alert('Tu navegador bloqueó la ventana de impresión. Permite ventanas emergentes para este sitio e intenta de nuevo.');
    return;
  }
  // Barra superior con Volver / Imprimir: no se imprime, y deja una salida
  // clara de la ventana (Esc también la cierra) en vez de un documento
  // "a pelo" sin forma de volver a la app.
  const estiloBoton = 'font:600 0.9rem system-ui,sans-serif; padding:0.45rem 1rem; border-radius:6px; cursor:pointer;';
  w.document.write(`<!DOCTYPE html><html><head><meta charset="UTF-8" />
<title>${titulo || 'Documento'}</title>
<base href="${window.location.href}" />
<style>@media print { .barra-impresion { display: none !important; } }</style>
<script>document.addEventListener('keydown', function (e) { if (e.key === 'Escape') window.close(); });</script>
</head><body style="margin:0;">
<div class="barra-impresion" style="position:sticky; top:0; z-index:10; display:flex; align-items:center; justify-content:space-between; gap:0.75rem; padding:0.6rem 1rem; background:#15181e; color:#fff; font-family:system-ui,sans-serif;">
  <button type="button" onclick="window.close()" style="${estiloBoton} background:transparent; color:#fff; border:1px solid #fff;">← Volver</button>
  <span style="font-size:0.85rem; opacity:0.8;">${titulo || 'Documento'}</span>
  <button type="button" onclick="window.print()" style="${estiloBoton} background:#fff; color:#15181e; border:1px solid #fff;">🖨 Imprimir / Guardar PDF</button>
</div>
<div class="print-area" id="print-area" style="display:block; max-width:900px; margin:0 auto;">${html}</div>
</body></html>`);
  w.document.close();

  // readyState/load de una ventana armada con document.write() no son
  // confiables (suelen marcar "complete" antes de que la hoja de estilo
  // externa termine de cargar) — se espera explícitamente el <link> y
  // las imágenes antes de imprimir, o el documento sale sin estilos.
  const cssLink = w.document.createElement('link');
  cssLink.rel = 'stylesheet';
  cssLink.href = `${window.location.origin}/assets/css/style.css`;
  const esperarCss = new Promise(resolve => {
    cssLink.addEventListener('load', resolve, { once: true });
    cssLink.addEventListener('error', resolve, { once: true });
  });
  w.document.head.appendChild(cssLink);

  esperarCss
    .then(() => esperarImagenesImpresion(w))
    .then(() => { w.focus(); w.print(); });
}

function esperarImagenesImpresion(w) {
  const imgs = Array.from(w.document.images);
  if (!imgs.length) return Promise.resolve();
  return Promise.all(imgs.map(img => {
    if (img.complete) return Promise.resolve();
    return new Promise(resolve => {
      img.addEventListener('load', resolve, { once: true });
      img.addEventListener('error', resolve, { once: true });
    });
  }));
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
    if (!n.leida) await supabaseClient.from('notificaciones').update({ leida: true }).eq('id', n.id);
    if (n.url) window.location.href = `/pages/${n.url}`;
    else await cargar();
  });

  // Se mantiene al día sola: cada 45 s con la pestaña a la vista, y al volver a ella
  cargar();
  setInterval(() => { if (document.visibilityState === 'visible') cargar(); }, 45000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') cargar(); });
}

async function initLayout(activeKey) {
  const session = await requireAuth();
  if (!session) return;

  const sidebar = document.getElementById('sidebar');
  if (sidebar) {
    const navLinks = NAV_ITEMS.map(item => {
      const activeClass = item.key === activeKey ? ' class="active"' : '';
      return `<a href="${item.href}"${activeClass}>${item.label}</a>`;
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
      sidebar.querySelectorAll('nav a').forEach(a => a.addEventListener('click', cerrar));
    }
  }

  iniciarCampanita();
  return session;
}
