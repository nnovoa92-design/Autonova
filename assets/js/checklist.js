// Checklist de inspección precompra (mismo contenido que la versión
// anterior de la app). Usado por pages/inspecciones.html y por el
// informe público inspeccion.html.
//
// Formato de respuestas en `datos` (jsonb):
//   "si_ii"      -> 'ok' | 'warn' | 'bad' | 'na'   (ítems estándar)
//   "si_ii_txt"  -> texto libre                     (ítems dtc/km)
//   "_custom"    -> { si: ["nombre ítem extra", ...] }
//   "c_si_ci"    -> estado de un ítem extra
//   "_obs"       -> observaciones generales
const INSP_CHECKLIST = [
  { sec: '💻 Electrónica y diagnóstico', items: [
    { t: 'DTC Activos (códigos de falla)', mode: 'dtc' },
    { t: 'Km Panel', mode: 'km' },
    { t: 'Km Real (verificado)', mode: 'km' },
    { t: 'Batería — voltaje y estado', mode: 'std' },
    { t: 'Alternador — carga correcta', mode: 'std' },
    { t: 'Luces delanteras (cortas/largas)', mode: 'std' },
    { t: 'Luces traseras y stop', mode: 'std' },
    { t: 'Intermitentes y luces de emergencia', mode: 'std' },
    { t: 'Luz reversa', mode: 'std' },
    { t: 'Luz interior / tablero', mode: 'std' },
    { t: 'Bocina', mode: 'std' },
    { t: 'Sensor de estacionamiento / cámara', mode: 'std' },
    { t: 'Sistema de alarma', mode: 'std' },
    { t: 'Radio / pantalla / conectividad', mode: 'std' },
  ]},
  { sec: '🔧 Motor y mecánica', items: [
    { t: 'Aceite motor — nivel y color', mode: 'std' },
    { t: 'Aceite transmisión', mode: 'std' },
    { t: 'Líquido de frenos', mode: 'std' },
    { t: 'Líquido refrigerante — nivel y color', mode: 'std' },
    { t: 'Líquido dirección hidráulica', mode: 'std' },
    { t: 'Correa de distribución — estado y km', mode: 'std' },
    { t: 'Correa alternador / accesorios', mode: 'std' },
    { t: 'Mangueras y juntas — sin fugas', mode: 'std' },
    { t: 'Filtro de aire', mode: 'std' },
    { t: 'Filtro de combustible', mode: 'std' },
    { t: 'Sistema de escape — sin fugas ni ruidos', mode: 'std' },
    { t: 'Radiador — sin fugas', mode: 'std' },
    { t: 'Arranque — sin ruidos anómalos', mode: 'std' },
    { t: 'Ralentí — estable', mode: 'std' },
    { t: 'Humo de escape — color y cantidad', mode: 'std' },
  ]},
  { sec: '🛑 Frenos', items: [
    { t: 'Pastillas delanteras — espesor', mode: 'std' },
    { t: 'Pastillas traseras — espesor', mode: 'std' },
    { t: 'Discos delanteros — sin rayaduras ni deformación', mode: 'std' },
    { t: 'Discos traseros — sin rayaduras ni deformación', mode: 'std' },
    { t: 'Freno de mano — efectivo', mode: 'std' },
    { t: 'Mangueras de freno — sin fisuras', mode: 'std' },
    { t: 'Bomba de freno', mode: 'std' },
    { t: 'ABS — sin luz en tablero', mode: 'std' },
  ]},
  { sec: '🏎 Suspensión y dirección', items: [
    { t: 'Amortiguadores delanteros — sin fugas', mode: 'std' },
    { t: 'Amortiguadores traseros — sin fugas', mode: 'std' },
    { t: 'Rótulas y terminales — holgura', mode: 'std' },
    { t: 'Bujes y Silent block', mode: 'std' },
    { t: 'Cremallera de dirección', mode: 'std' },
    { t: 'Dirección — sin vibraciones ni tirones', mode: 'std' },
    { t: 'Alineación — verificación visual', mode: 'std' },
    { t: 'Convergencia — desgaste uniforme', mode: 'std' },
  ]},
  { sec: '🛞 Neumáticos y ruedas', items: [
    { t: 'Neumático delantero derecho — banda rodadura', mode: 'std' },
    { t: 'Neumático delantero izquierdo — banda rodadura', mode: 'std' },
    { t: 'Neumático trasero derecho — banda rodadura', mode: 'std' },
    { t: 'Neumático trasero izquierdo — banda rodadura', mode: 'std' },
    { t: 'Neumático de repuesto — estado', mode: 'std' },
    { t: 'Rines — sin daños ni fisuras', mode: 'std' },
    { t: 'Tapas de ruedas', mode: 'std' },
  ]},
  { sec: '🚘 Carrocería y estructura', items: [
    { t: 'Capot — sin golpes ni óxido', mode: 'std' },
    { t: 'Guardafangos delanteros', mode: 'std' },
    { t: 'Puertas — apertura, cierre y bisagras', mode: 'std' },
    { t: 'Techo — sin abolladuras', mode: 'std' },
    { t: 'Parachoques delantero', mode: 'std' },
    { t: 'Parachoques trasero', mode: 'std' },
    { t: 'Parabrisas — sin fisuras', mode: 'std' },
    { t: 'Vidrios laterales — sin fisuras', mode: 'std' },
    { t: 'Luneta trasera', mode: 'std' },
    { t: 'Pintura — color uniforme sin retoques', mode: 'std' },
    { t: 'Corrosión u óxido en estructura', mode: 'std' },
    { t: 'Sellos de puertas y techo', mode: 'std' },
    { t: 'Maletero — cierre y estado interior', mode: 'std' },
  ]},
  { sec: '🪑 Interior', items: [
    { t: 'Tapiz y asientos — estado general', mode: 'std' },
    { t: 'Cinturones de seguridad — funcionamiento', mode: 'std' },
    { t: 'Airbag — sin luz en tablero', mode: 'std' },
    { t: 'Pedales — estado y respuesta', mode: 'std' },
    { t: 'Alfombras y tapizado suelo', mode: 'std' },
    { t: 'Elevavidrios — todos funcionan', mode: 'std' },
    { t: 'Espejos — eléctricos y manuales', mode: 'std' },
    { t: 'Aire acondicionado — enfría correctamente', mode: 'std' },
    { t: 'Calefacción — funciona', mode: 'std' },
    { t: 'Limpiaparabrisas — velocidades y agua', mode: 'std' },
    { t: 'Sunroof / techo corredizo (si aplica)', mode: 'std' },
  ]},
];

const INSP_ESTADOS = {
  ok:   { label: 'Bien',     badge: 'badge-green' },
  warn: { label: 'Atención', badge: 'badge-yellow' },
  bad:  { label: 'Malo',     badge: 'badge-red' },
  na:   { label: 'N/A',      badge: 'badge-gray' },
};

// Texto libre de un ítem dtc/km (compatible con los datos migrados)
function inspTexto(datos, k) {
  return datos[k + '_txt'] || datos[k + '_dtc'] || datos[k + '_km'] || '';
}

// Calcula contadores, score 0-100 y recomendación (misma fórmula
// y umbrales que la app anterior).
function inspCalcular(datos) {
  let ok = 0, warn = 0, bad = 0, na = 0, total = 0;
  INSP_CHECKLIST.forEach((sec, si) => {
    sec.items.forEach((item, ii) => {
      if (item.mode !== 'std') return;
      total++;
      const v = datos[si + '_' + ii] || '';
      if (v === 'ok') ok++; else if (v === 'warn') warn++;
      else if (v === 'bad') bad++; else if (v === 'na') na++;
    });
    const customs = (datos._custom && datos._custom[si]) || [];
    customs.forEach((c, ci) => {
      total++;
      const v = datos['c_' + si + '_' + ci] || '';
      if (v === 'ok') ok++; else if (v === 'warn') warn++;
      else if (v === 'bad') bad++; else if (v === 'na') na++;
    });
  });
  const evaluados = ok + warn + bad;
  const score = evaluados > 0 ? Math.round((ok * 100 + warn * 50) / evaluados) : 0;
  let rec, nivel;
  if (score >= 90) { rec = 'Excelente estado. Se recomienda la compra sin reparos.'; nivel = 'ok'; }
  else if (score >= 75) { rec = 'Buen estado con observaciones menores. Se recomienda la compra, pero negociar el precio considerando las reparaciones necesarias.'; nivel = 'warn'; }
  else if (score >= 60) { rec = 'Estado aceptable con defectos importantes. Se recomienda precaución. Evaluar costo de reparaciones antes de decidir.'; nivel = 'warn'; }
  else { rec = 'Múltiples defectos graves. NO se recomienda la compra en el estado actual, o comprar bajo responsabilidad del cliente con todos los antecedentes.'; nivel = 'bad'; }
  return { ok, warn, bad, na, total, score, rec, nivel };
}

// Observación + fotos asociadas a un ítem (cuando hay atención/malo).
function inspEvidencia(datos, k) {
  const obs = datos[k + '_obs'];
  const fotos = datos[k + '_fotos'] || [];
  if (!obs && !fotos.length) return '';
  let html = '';
  if (obs) html += `<div style="font-size:0.82rem; color:var(--color-text-muted); margin-top:3px;">${obs}</div>`;
  if (fotos.length) {
    html += `<div class="fotos-grid" style="margin-top:5px;">` +
      fotos.map(u => `<div class="foto-item"><a href="${u}" target="_blank"><img src="${u}" /></a></div>`).join('') +
      `</div>`;
  }
  return html;
}

// Render de solo lectura del checklist respondido (detalle interno
// e informe público). Muestra solo ítems con respuesta o texto.
function inspRenderDetalle(datos) {
  return INSP_CHECKLIST.map((sec, si) => {
    const filas = [];
    sec.items.forEach((item, ii) => {
      const k = si + '_' + ii;
      if (item.mode === 'std') {
        const v = datos[k];
        if (!v || !INSP_ESTADOS[v]) return;
        filas.push(`<tr><td>${item.t}${inspEvidencia(datos, k)}</td><td><span class="badge ${INSP_ESTADOS[v].badge}">${INSP_ESTADOS[v].label}</span></td></tr>`);
      } else {
        const txt = inspTexto(datos, k);
        if (!txt) return;
        filas.push(`<tr><td>${item.t}</td><td>${txt}</td></tr>`);
      }
    });
    const customs = (datos._custom && datos._custom[si]) || [];
    customs.forEach((nombre, ci) => {
      const k = 'c_' + si + '_' + ci;
      const v = datos[k];
      if (!v || !INSP_ESTADOS[v]) return;
      filas.push(`<tr><td>${nombre} <span class="badge">extra</span>${inspEvidencia(datos, k)}</td><td><span class="badge ${INSP_ESTADOS[v].badge}">${INSP_ESTADOS[v].label}</span></td></tr>`);
    });
    if (!filas.length) return '';
    return `<h3>${sec.sec}</h3><table><tbody>${filas.join('')}</tbody></table>`;
  }).join('');
}
