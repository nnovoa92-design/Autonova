// ============================================================
// Robot de recordatorios automáticos por correo (Gmail)
// Se ejecuta a diario desde GitHub Actions.
//
// Envía por correo:
//  · Mantención: recordatorios pendientes cuya fecha objetivo ya llegó.
//  · Revisión técnica: el día 1 del mes, a los vehículos cuyo último
//    dígito de patente corresponde a ese mes.
//
// Variables de entorno requeridas (secrets de GitHub):
//   SUPABASE_URL, SUPABASE_SERVICE_KEY, GMAIL_USER, GMAIL_APP_PASSWORD
//   TEST_EMAIL (opcional): si está, solo manda un correo de prueba ahí.
// ============================================================
import nodemailer from 'nodemailer';

const {
  SUPABASE_URL, SUPABASE_SERVICE_KEY,
  GMAIL_USER, GMAIL_APP_PASSWORD, TEST_EMAIL,
} = process.env;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY || !GMAIL_USER || !GMAIL_APP_PASSWORD) {
  console.error('Faltan variables de entorno. Revisa los secrets de GitHub.');
  process.exit(1);
}

// Calendario de revisión técnica: último dígito de la patente -> mes (1-12)
const RT_MES_POR_DIGITO = { '9': 1, '0': 2, '1': 4, '2': 5, '3': 6, '4': 7, '5': 8, '6': 9, '7': 10, '8': 11 };
const NOMBRE_MES = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

function rtMesPatente(patente) {
  const m = String(patente || '').match(/(\d)(?!.*\d)/);
  return m ? (RT_MES_POR_DIGITO[m[1]] || null) : null;
}

// ---------- Helpers REST de Supabase (service role: ignora RLS) ----------
const headers = {
  apikey: SUPABASE_SERVICE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
  'Content-Type': 'application/json',
};
async function sbGet(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers });
  if (!res.ok) throw new Error(`GET ${path}: ${res.status} ${await res.text()}`);
  return res.json();
}
async function sbPatch(path, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { method: 'PATCH', headers, body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`PATCH ${path}: ${res.status} ${await res.text()}`);
}
async function sbPost(path, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { method: 'POST', headers: { ...headers, Prefer: 'return=representation' }, body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`POST ${path}: ${res.status} ${await res.text()}`);
  return res.json();
}

// ---------- Correo ----------
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com', port: 465, secure: true,
  auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
});

let tallerNombre = 'Autonova';
async function cargarTaller() {
  try {
    const cfg = await sbGet('taller_config?select=nombre&id=eq.1');
    if (cfg[0]?.nombre) tallerNombre = cfg[0].nombre;
  } catch {}
}

async function enviar(to, subject, text) {
  await transporter.sendMail({
    from: `${tallerNombre} <${GMAIL_USER}>`,
    to, subject, text,
  });
  console.log(`✓ Correo enviado a ${to} · ${subject}`);
}

// ---------- Lógica principal ----------
async function main() {
  await cargarTaller();

  if (TEST_EMAIL) {
    await enviar(TEST_EMAIL, `Prueba de recordatorios - ${tallerNombre}`,
      `Este es un correo de prueba del robot de recordatorios de ${tallerNombre}. Si lo recibiste, el envío automático funciona.`);
    console.log('Modo prueba: enviado y terminado.');
    return;
  }

  const hoy = new Date();
  const hoyStr = hoy.toISOString().slice(0, 10);
  const primeroDeMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1).toISOString().slice(0, 10);
  const mesActual = hoy.getMonth() + 1;
  let enviados = 0;

  // 1) MANTENCIÓN: recordatorios vencidos no enviados
  const mant = await sbGet(
    `recordatorios?tipo=eq.mantencion&enviado=eq.false&fecha_objetivo=lte.${hoyStr}` +
    `&select=id,clientes(nombre,email),vehiculos(patente,marca,modelo)`
  );
  for (const r of mant) {
    const email = r.clientes?.email;
    if (!email) continue;
    const veh = r.vehiculos ? `${r.vehiculos.patente} (${[r.vehiculos.marca, r.vehiculos.modelo].filter(Boolean).join(' ')})` : 'su vehículo';
    const texto =
      `Hola ${r.clientes?.nombre || ''},\n\n` +
      `Le recordamos que ${veh} está próximo a su mantención. ` +
      `En ${tallerNombre} quedamos atentos para coordinar una fecha y mantenerlo a punto.\n\n` +
      `Saludos,\n${tallerNombre}`;
    try {
      await enviar(email, `Recordatorio de mantención - ${tallerNombre}`, texto);
      await sbPatch(`recordatorios?id=eq.${r.id}`, { enviado: true, fecha_envio: new Date().toISOString() });
      enviados++;
    } catch (e) { console.error(`Error mantención ${r.id}:`, e.message); }
  }

  // 2) REVISIÓN TÉCNICA: solo el día 1 del mes
  if (hoy.getDate() === 1) {
    const vehiculos = await sbGet('vehiculos?activo=eq.true&select=id,patente,marca,modelo,cliente_id,clientes(nombre,email)');
    for (const v of vehiculos) {
      if (rtMesPatente(v.patente) !== mesActual) continue;
      const email = v.clientes?.email;
      if (!email) continue;
      // Dedup: ¿ya hay un recordatorio RT para este vehículo este mes?
      const existe = await sbGet(`recordatorios?tipo=eq.revision_tecnica&vehiculo_id=eq.${v.id}&fecha_objetivo=eq.${primeroDeMes}&select=id,enviado`);
      if (existe.length && existe[0].enviado) continue;
      const texto =
        `Hola ${v.clientes?.nombre || ''},\n\n` +
        `Le recordamos que la revisión técnica de su vehículo ${v.patente} ` +
        `(${[v.marca, v.modelo].filter(Boolean).join(' ')}) corresponde este mes (${NOMBRE_MES[mesActual]}). ` +
        `En ${tallerNombre} podemos dejarlo a punto antes para que la pase sin problemas.\n\n` +
        `Saludos,\n${tallerNombre}`;
      try {
        await enviar(email, `Recordatorio: Revisión Técnica - ${tallerNombre}`, texto);
        if (existe.length) {
          await sbPatch(`recordatorios?id=eq.${existe[0].id}`, { enviado: true, fecha_envio: new Date().toISOString() });
        } else {
          await sbPost('recordatorios', {
            vehiculo_id: v.id, cliente_id: v.cliente_id, tipo: 'revision_tecnica',
            fecha_objetivo: primeroDeMes, detalle: `Revisión técnica ${NOMBRE_MES[mesActual]}`,
            enviado: true, fecha_envio: new Date().toISOString(),
          });
        }
        enviados++;
      } catch (e) { console.error(`Error RT ${v.id}:`, e.message); }
    }
  }

  console.log(`Listo. Correos enviados: ${enviados}.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
