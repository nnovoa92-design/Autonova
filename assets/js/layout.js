// Construye el sidebar de navegación y protege la página con autenticación.
const NAV_ITEMS = [
  { key: 'dashboard', label: 'Inicio', href: 'dashboard.html' },
  { key: 'cotizaciones', label: 'Cotizaciones', href: 'cotizaciones.html' },
  { key: 'ordenes', label: 'Órdenes de trabajo', href: 'ordenes.html' },
  { key: 'clientes', label: 'Clientes', href: 'clientes.html' },
  { key: 'vehiculos', label: 'Vehículos', href: 'vehiculos.html' },
  { key: 'trabajos', label: 'Catálogo de trabajos', href: 'trabajos.html' },
  { key: 'inventario', label: 'Inventario', href: 'inventario.html' },
  { key: 'pagos', label: 'Pagos', href: 'pagos.html' },
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

// Link wa.me con el mensaje prellenado. Acepta teléfonos chilenos
// con o sin +56 (ej: "+56 9 8765 4321" o "987654321").
function linkWhatsApp(telefono, mensaje) {
  if (!telefono) return null;
  let digits = String(telefono).replace(/\D/g, '');
  if (digits.length === 9 && digits.startsWith('9')) digits = '56' + digits;
  return `https://wa.me/${digits}?text=${encodeURIComponent(mensaje)}`;
}

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

    sidebar.innerHTML = `
      <div class="brand">Autonova <span class="brand-sub">Taller</span></div>
      <nav>${navLinks}</nav>
      <div class="sidebar-footer">
        <button id="logout-btn" class="btn-secondary" style="border-color: rgba(255,255,255,0.4); color: #fff;">Cerrar sesión</button>
      </div>
    `;

    document.getElementById('logout-btn').addEventListener('click', logout);
  }

  return session;
}
