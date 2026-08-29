// Construye el sidebar de navegación y protege la página con autenticación.
const NAV_ITEMS = [
  { key: 'dashboard', label: 'Inicio', href: 'dashboard.html' },
  { key: 'agenda', label: 'Agenda', href: 'agenda.html' },
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

// Combobox de autocompletado: un campo de texto que, al escribir, muestra
// una lista desplegable con las coincidencias (por nombre). El <select>
// oculto sigue siendo la fuente de verdad (value + evento "change"), así
// el resto del código que ya lee/escucha ese <select> no necesita cambiar.
// dataArray se lee por referencia en cada apertura, así que basta con que
// el array se actualice en el sitio (push/sort) para que el buscador vea
// los cambios sin tener que volver a llamar a esta función.
function setupCombobox(inputId, selectId, listId, dataArray, labelFn) {
  const input = document.getElementById(inputId);
  const select = document.getElementById(selectId);
  const list = document.getElementById(listId);
  if (!input || !select || !list) return;
  let resultados = [];
  let resaltado = -1;

  function seleccionar(item) {
    select.value = item.id;
    input.value = labelFn(item);
    list.style.display = 'none';
    select.dispatchEvent(new Event('change'));
  }

  function marcarResaltado() {
    list.querySelectorAll('.combobox-item').forEach((el, i) => el.classList.toggle('resaltado', i === resaltado));
  }

  function render(query) {
    const q = query.trim().toLowerCase();
    resultados = (q ? dataArray.filter(d => labelFn(d).toLowerCase().includes(q)) : dataArray).slice(0, 30);
    resaltado = -1;
    if (!resultados.length) {
      list.innerHTML = '<div class="combobox-vacio">Sin coincidencias</div>';
    } else {
      list.innerHTML = resultados.map(d => `<div class="combobox-item">${labelFn(d)}</div>`).join('');
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

// Link wa.me con el mensaje prellenado. Acepta teléfonos chilenos
// con o sin +56 (ej: "+56 9 8765 4321" o "987654321").
function linkWhatsApp(telefono, mensaje) {
  if (!telefono) return null;
  let digits = String(telefono).replace(/\D/g, '');
  if (digits.length === 9 && digits.startsWith('9')) digits = '56' + digits;
  return `https://wa.me/${digits}?text=${encodeURIComponent(mensaje)}`;
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
  w.document.write(`<!DOCTYPE html><html><head><meta charset="UTF-8" />
<title>${titulo || 'Documento'}</title>
<base href="${window.location.href}" />
</head><body>
<div class="print-area" id="print-area" style="display:block;">${html}</div>
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

  return session;
}
