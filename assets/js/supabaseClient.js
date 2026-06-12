// Configuración del cliente de Supabase (proyecto Autonova)
const SUPABASE_URL = 'https://vfjlrpaemwnnszgonbsh.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_rk2M43dAdK1ZffS9sPmo4w_dJEp31iI';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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
