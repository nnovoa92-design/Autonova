// Configuración del cliente de Supabase (proyecto Autonova)
const SUPABASE_URL = 'https://vfjlrpaemwnnszgonbsh.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_rk2M43dAdK1ZffS9sPmo4w_dJEp31iI';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ---------- Red de seguridad: avisar cuando un guardado falla ----------
// Si una escritura (insert / update / upsert / delete) devuelve error y el código de la página
// no lo revisó, aparece un aviso visible en pantalla. Las páginas que sí manejan el error
// (y muestran su propio mensaje) no cambian: leer `error` cuenta como «manejado».
(function vigilarEscrituras() {
  const desdeOriginal = supabaseClient.from.bind(supabaseClient);
  const ESCRITURAS = ['insert', 'update', 'upsert', 'delete'];

  function traducir(err) {
    const m = String((err && err.message) || err || '');
    const c = String((err && err.code) || '');
    if (c === '42501' || /row-level security|permission denied/i.test(m)) return 'No tienes permiso para realizar esta acción.';
    if (c === '23505' || /duplicate key|already exists/i.test(m)) return 'Ya existe un registro igual (dato duplicado).';
    if (c === '23503' || /foreign key/i.test(m)) return 'Ese dato está en uso o depende de otro registro.';
    if (c === '23502' || /null value in column/i.test(m)) return 'Falta un dato obligatorio.';
    if (c === 'PGRST301' || /jwt|token/i.test(m)) return 'Tu sesión venció: vuelve a iniciar sesión.';
    if (/failed to fetch|networkerror|load failed/i.test(m)) return 'Sin conexión con el servidor.';
    return m || 'Error desconocido.';
  }

  let temporizador = null;
  function avisar(err, tabla) {
    console.error('No se pudo guardar (' + tabla + '):', err);
    let caja = document.getElementById('aviso-guardado');
    if (!caja) {
      caja = document.createElement('div');
      caja.id = 'aviso-guardado';
      caja.setAttribute('role', 'alert');
      caja.style.cssText = 'position:fixed; right:1rem; bottom:1rem; z-index:400; max-width:min(380px, calc(100vw - 2rem));' +
        'background:#fff4f2; border:1px solid #c0392b; border-left:5px solid #c0392b; border-radius:8px; padding:0.7rem 0.9rem;' +
        'box-shadow:0 8px 24px rgba(0,0,0,0.22); font-size:0.88rem; color:#7a1f14; cursor:pointer;';
      caja.addEventListener('click', () => { caja.style.display = 'none'; });
      (document.body || document.documentElement).appendChild(caja);
    }
    const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    caja.innerHTML = '<strong>⚠ No se pudo guardar</strong><div style="margin-top:0.2rem;">' + esc(traducir(err)) + '</div>' +
      '<div style="margin-top:0.3rem; font-size:0.78rem; opacity:0.85;">Revisa que se vea el cambio antes de seguir. Toca para cerrar.</div>';
    caja.style.display = 'block';
    clearTimeout(temporizador);
    temporizador = setTimeout(() => { caja.style.display = 'none'; }, 12000);
  }

  function vigilar(builder, tabla) {
    const thenOriginal = builder.then.bind(builder);
    builder.then = (alExito, alError) => thenOriginal((res) => {
      if (res && res.error) {
        let leido = false;
        const error = res.error;
        const envuelto = Object.assign({}, res);
        Object.defineProperty(envuelto, 'error', { get() { leido = true; return error; }, enumerable: true, configurable: true });
        setTimeout(() => { if (!leido) avisar(error, tabla); }, 800);
        return alExito ? alExito(envuelto) : envuelto;
      }
      return alExito ? alExito(res) : res;
    }, alError);
    return builder;
  }

  supabaseClient.from = function (tabla) {
    const qb = desdeOriginal(tabla);
    ESCRITURAS.forEach((m) => {
      const original = qb[m];
      if (typeof original !== 'function') return;
      qb[m] = function () { return vigilar(original.apply(qb, arguments), tabla); };
    });
    return qb;
  };
})();

// Redirige a login si no hay sesión activa. Llamar en páginas protegidas.
async function requireAuth() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    window.location.href = '/index.html';
    return null;
  }
  return session;
}

async function logout() {
  await supabaseClient.auth.signOut();
  window.location.href = '/index.html';
}
