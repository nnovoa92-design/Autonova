// Checklist de inspección precompra. Cada ítem estándar tiene su importancia `p` (3 crítico, 2 importante,
// 1 menor), que pondera el puntaje (ver inspCalcular). Basado en el contenido de la versión
// anterior de la app. Usado por pages/inspecciones.html y por el
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
    { t: 'Batería — voltaje y estado', mode: 'std', p: 2 },
    { t: 'Alternador — carga correcta', mode: 'std', p: 2 },
    { t: 'Luces delanteras (cortas/largas)', mode: 'std', p: 2 },
    { t: 'Luces traseras y stop', mode: 'std', p: 2 },
    { t: 'Intermitentes y luces de emergencia', mode: 'std', p: 2 },
    { t: 'Luz reversa', mode: 'std', p: 1 },
    { t: 'Luz interior / tablero', mode: 'std', p: 1 },
    { t: 'Bocina', mode: 'std', p: 2 },
    { t: 'Sensor de estacionamiento / cámara', mode: 'std', p: 1 },
    { t: 'Sistema de alarma', mode: 'std', p: 1 },
    { t: 'Radio / pantalla / conectividad', mode: 'std', p: 1 },
  ]},
  { sec: '🔧 Motor y mecánica', items: [
    { t: 'Aceite motor — nivel y color', mode: 'std', p: 3 },
    { t: 'Aceite transmisión', mode: 'std', p: 3 },
    { t: 'Líquido de frenos', mode: 'std', p: 2 },
    { t: 'Líquido refrigerante — nivel y color', mode: 'std', p: 3 },
    { t: 'Líquido dirección hidráulica', mode: 'std', p: 2 },
    { t: 'Correa de distribución — estado y km', mode: 'std', p: 3 },
    { t: 'Correa alternador / accesorios', mode: 'std', p: 2 },
    { t: 'Mangueras y juntas — sin fugas', mode: 'std', p: 2 },
    { t: 'Filtro de aire', mode: 'std', p: 1 },
    { t: 'Filtro de combustible', mode: 'std', p: 1 },
    { t: 'Sistema de escape — sin fugas ni ruidos', mode: 'std', p: 2 },
    { t: 'Radiador — sin fugas', mode: 'std', p: 3 },
    { t: 'Arranque — sin ruidos anómalos', mode: 'std', p: 2 },
    { t: 'Ralentí — estable', mode: 'std', p: 2 },
    { t: 'Humo de escape — color y cantidad', mode: 'std', p: 3 },
  ]},
  { sec: '🛑 Frenos', items: [
    { t: 'Pastillas delanteras — espesor', mode: 'std', p: 3 },
    { t: 'Pastillas traseras — espesor', mode: 'std', p: 3 },
    { t: 'Discos delanteros — sin rayaduras ni deformación', mode: 'std', p: 3 },
    { t: 'Discos traseros — sin rayaduras ni deformación', mode: 'std', p: 3 },
    { t: 'Freno de mano — efectivo', mode: 'std', p: 2 },
    { t: 'Mangueras de freno — sin fisuras', mode: 'std', p: 3 },
    { t: 'Bomba de freno', mode: 'std', p: 3 },
    { t: 'ABS — sin luz en tablero', mode: 'std', p: 3 },
  ]},
  { sec: '🏎 Suspensión y dirección', items: [
    { t: 'Amortiguadores delanteros — sin fugas', mode: 'std', p: 2 },
    { t: 'Amortiguadores traseros — sin fugas', mode: 'std', p: 2 },
    { t: 'Rótulas y terminales — holgura', mode: 'std', p: 3 },
    { t: 'Bujes y Silent block', mode: 'std', p: 2 },
    { t: 'Cremallera de dirección', mode: 'std', p: 3 },
    { t: 'Dirección — sin vibraciones ni tirones', mode: 'std', p: 3 },
    { t: 'Alineación — verificación visual', mode: 'std', p: 1 },
    { t: 'Convergencia — desgaste uniforme', mode: 'std', p: 1 },
  ]},
  { sec: '🛞 Neumáticos y ruedas', items: [
    { t: 'Neumático delantero derecho — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático delantero izquierdo — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático trasero derecho — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático trasero izquierdo — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático de repuesto — estado', mode: 'std', p: 1 },
    { t: 'Rines — sin daños ni fisuras', mode: 'std', p: 2 },
    { t: 'Tapas de ruedas', mode: 'std', p: 1 },
  ]},
  { sec: '🚘 Carrocería y estructura', items: [
    { t: 'Capot — sin golpes ni óxido', mode: 'std', p: 1 },
    { t: 'Guardafangos delanteros', mode: 'std', p: 1 },
    { t: 'Puertas — apertura, cierre y bisagras', mode: 'std', p: 2 },
    { t: 'Techo — sin abolladuras', mode: 'std', p: 1 },
    { t: 'Parachoques delantero', mode: 'std', p: 1 },
    { t: 'Parachoques trasero', mode: 'std', p: 1 },
    { t: 'Parabrisas — sin fisuras', mode: 'std', p: 2 },
    { t: 'Vidrios laterales — sin fisuras', mode: 'std', p: 1 },
    { t: 'Luneta trasera', mode: 'std', p: 1 },
    { t: 'Pintura — color uniforme sin retoques', mode: 'std', p: 2 },
    { t: 'Corrosión u óxido en estructura', mode: 'std', p: 3 },
    { t: 'Sellos de puertas y techo', mode: 'std', p: 1 },
    { t: 'Maletero — cierre y estado interior', mode: 'std', p: 1 },
  ]},
  { sec: '🪑 Interior', items: [
    { t: 'Tapiz y asientos — estado general', mode: 'std', p: 1 },
    { t: 'Cinturones de seguridad — funcionamiento', mode: 'std', p: 3 },
    { t: 'Airbag — sin luz en tablero', mode: 'std', p: 3 },
    { t: 'Pedales — estado y respuesta', mode: 'std', p: 2 },
    { t: 'Alfombras y tapizado suelo', mode: 'std', p: 1 },
    { t: 'Elevavidrios — todos funcionan', mode: 'std', p: 1 },
    { t: 'Espejos — eléctricos y manuales', mode: 'std', p: 1 },
    { t: 'Aire acondicionado — enfría correctamente', mode: 'std', p: 2 },
    { t: 'Calefacción — funciona', mode: 'std', p: 1 },
    { t: 'Limpiaparabrisas — velocidades y agua', mode: 'std', p: 2 },
    { t: 'Sunroof / techo corredizo (si aplica)', mode: 'std', p: 1 },
  ]},
];

const INSP_ESTADOS = {
  ok:   { label: 'Bien',     badge: 'badge-green' },
  warn: { label: 'Atención', badge: 'badge-yellow' },
  bad:  { label: 'Malo',     badge: 'badge-red' },
  na:   { label: 'N/A',      badge: 'badge-gray' },
};

// Importancia de cada ítem en el puntaje (p en INSP_CHECKLIST)
const INSP_IMPORTANCIA = {
  3: { label: 'Crítico',    badge: 'badge-red',    ayuda: 'seguridad o reparación costosa' },
  2: { label: 'Importante', badge: 'badge-yellow', ayuda: 'funcionamiento, exigencia legal o costo medio' },
  1: { label: 'Menor',      badge: 'badge-gray',   ayuda: 'confort o estética' },
};
const INSP_PESO_EXTRA = 2;   // ítems agregados a mano durante la inspección

const INSP_NIVELES = {
  recomendada:    { label: 'Recomendada',                  visual: 'ok' },
  observaciones:  { label: 'Recomendada con observaciones', visual: 'warn' },
  precaucion:     { label: 'Con precaución',               visual: 'warn' },
  no_recomendada: { label: 'No recomendada',               visual: 'bad' },
};

// Etiqueta de importancia para mostrar junto al ítem (crítico e importante; los menores no llevan)
function inspBadgeImportancia(p) {
  const imp = INSP_IMPORTANCIA[p];
  if (!imp || p < 2) return '';
  return ` <span class="badge ${imp.badge}" title="${imp.ayuda}" style="font-size:0.68rem;">${imp.label}</span>`;
}

// Texto libre de un ítem dtc/km (compatible con los datos migrados)
function inspTexto(datos, k) {
  return datos[k + '_txt'] || datos[k + '_dtc'] || datos[k + '_km'] || '';
}

// Todos los ítems con estado (estándar y extra): { k, t, p, si, v }
function inspItemsEvaluables(datos) {
  const items = [];
  INSP_CHECKLIST.forEach((sec, si) => {
    sec.items.forEach((item, ii) => {
      if (item.mode !== 'std') return;
      const k = si + '_' + ii;
      items.push({ k, t: item.t, p: item.p || 2, si, v: datos[k] || '' });
    });
    const customs = (datos._custom && datos._custom[si]) || [];
    customs.forEach((nombre, ci) => {
      const k = 'c_' + si + '_' + ci;
      items.push({ k, t: nombre, p: INSP_PESO_EXTRA, si, v: datos[k] || '' });
    });
  });
  return items;
}

// Clave del ítem de texto (dtc / km) según su título
function inspClaveTexto(titulo) {
  for (let si = 0; si < INSP_CHECKLIST.length; si++) {
    const ii = INSP_CHECKLIST[si].items.findIndex(it => it.t === titulo);
    if (ii >= 0) return si + '_' + ii;
  }
  return null;
}
const inspNumeroKm = (txt) => { const n = String(txt || '').replace(/[^\d]/g, ''); return n ? Number(n) : null; };
const inspMiles = (n) => Number(n).toLocaleString('es-CL');

// Evaluación de la inspección:
//  1. Puntaje ponderado: cada ítem pesa según su importancia (crítico ×3, importante ×2, menor ×1);
//     «Bien» vale 100, «Atención» 50 y «Malo» 0. N/A no cuenta.
//  2. Reglas que limitan la recomendación aunque el promedio sea alto:
//       · 2 o más fallas críticas, kilometraje que no coincide o puntaje < 50  → No recomendada (máx. 49)
//       · 1 falla crítica, códigos de falla activos, 3+ importantes malos o puntaje < 70 → Con precaución (máx. 69)
//       · algún crítico «Atención», algún importante «Malo» o puntaje < 85          → Con observaciones (máx. 84)
//       · si no                                                                 → Recomendada
// Devuelve contadores, score final, recomendación (con motivos) y el detalle en `evaluacion`.
function inspCalcular(datos) {
  let ok = 0, warn = 0, bad = 0, na = 0, total = 0, sumaPesos = 0, sumaPuntos = 0;
  const criticosMalos = [], criticosAtencion = [], importantesMalos = [], importantesAtencion = [];
  const secciones = INSP_CHECKLIST.map(s => ({ sec: s.sec, pesos: 0, puntos: 0, malos: 0, atencion: 0, criticos: 0 }));
  inspItemsEvaluables(datos).forEach(it => {
    total++;
    if (it.v === 'na') { na++; return; }
    if (it.v !== 'ok' && it.v !== 'warn' && it.v !== 'bad') return;
    const puntos = it.v === 'ok' ? 100 : (it.v === 'warn' ? 50 : 0);
    if (it.v === 'ok') ok++; else if (it.v === 'warn') warn++; else bad++;
    sumaPesos += it.p; sumaPuntos += it.p * puntos;
    const s = secciones[it.si];
    s.pesos += it.p; s.puntos += it.p * puntos;
    if (it.v === 'bad') s.malos++;
    if (it.v === 'warn') s.atencion++;
    if (it.p >= 3 && it.v === 'bad') { criticosMalos.push(it.t); s.criticos++; }
    if (it.p >= 3 && it.v === 'warn') criticosAtencion.push(it.t);
    if (it.p === 2 && it.v === 'bad') importantesMalos.push(it.t);
    if (it.p === 2 && it.v === 'warn') importantesAtencion.push(it.t);
  });
  const scoreBase = sumaPesos > 0 ? Math.round(sumaPuntos / sumaPesos) : 0;

  // Señales que no son de un ítem: kilometraje y códigos de falla
  const alertas = [];
  const kmPanel = inspNumeroKm(inspTexto(datos, inspClaveTexto('Km Panel')));
  const kmReal = inspNumeroKm(inspTexto(datos, inspClaveTexto('Km Real (verificado)')));
  if (kmPanel && kmReal && Math.abs(kmReal - kmPanel) > Math.max(2000, kmPanel * 0.05)) {
    alertas.push({ tipo: 'km', texto: `El kilometraje del panel (${inspMiles(kmPanel)} km) no coincide con el verificado (${inspMiles(kmReal)} km): posible adulteración.` });
  }
  const dtc = String(inspTexto(datos, inspClaveTexto('DTC Activos (códigos de falla)')) || '').toUpperCase();
  const codigos = [...new Set(dtc.match(/\b[PBCU][0-9][0-9A-F]{3}\b/g) || [])];
  if (codigos.length) alertas.push({ tipo: 'dtc', texto: `Códigos de falla activos: ${codigos.join(', ')}.` });

  let nivel;
  if (criticosMalos.length >= 2 || alertas.some(a => a.tipo === 'km') || scoreBase < 50) nivel = 'no_recomendada';
  else if (criticosMalos.length === 1 || alertas.some(a => a.tipo === 'dtc') || importantesMalos.length >= 3 || scoreBase < 70) nivel = 'precaucion';
  else if (scoreBase < 85 || criticosAtencion.length || importantesMalos.length) nivel = 'observaciones';
  else nivel = 'recomendada';
  // El número nunca contradice la recomendación (p. ej. no puede salir 92/100 y «No recomendada»)
  const score = Math.min(scoreBase, { no_recomendada: 49, precaucion: 69, observaciones: 84, recomendada: 100 }[nivel]);

  const motivos = [];
  if (criticosMalos.length) motivos.push(`Falla en ${criticosMalos.length > 1 ? 'componentes críticos' : 'componente crítico'}: ${criticosMalos.join('; ')}.`);
  alertas.forEach(a => motivos.push(a.texto));
  // Lo que no impide la compra pero conviene reparar o revisar (sirve para negociar el precio)
  const revisar = [...criticosAtencion, ...importantesMalos, ...importantesAtencion];
  const base = {
    recomendada: 'Buen estado general. Se recomienda la compra.',
    observaciones: 'Buen estado con observaciones. Se recomienda la compra, negociando el precio según las reparaciones indicadas.',
    precaucion: 'Se recomienda precaución: hay fallas que deben repararse antes de usar el vehículo. Evalúe el costo de las reparaciones antes de decidir.',
    no_recomendada: 'NO se recomienda la compra en el estado actual, salvo que se reparen las fallas indicadas y se ajuste el precio.',
  }[nivel];
  const rec = base + (motivos.length ? ` Motivos: ${motivos.join(' ')}` : '') + (revisar.length ? ` Reparar o revisar: ${revisar.join('; ')}.` : '');
  const visual = INSP_NIVELES[nivel].visual;

  const evaluacion = {
    metodo: 2, scoreBase, score, nivel, visual, criticosMalos, criticosAtencion, importantesMalos, importantesAtencion, alertas,
    secciones: secciones.filter(s => s.pesos > 0).map(s => ({ sec: s.sec, score: Math.round(s.puntos / s.pesos), malos: s.malos, atencion: s.atencion, criticos: s.criticos })),
  };
  return { ok, warn, bad, na, total, score, rec, nivel: visual, evaluacion };
}

// Color del puntaje de una inspección guardada (las antiguas usan los umbrales de antes)
function inspNivelDe(registro) {
  const e = registro && registro.datos && registro.datos._eval;
  if (e && e.visual) return e.visual;
  const s = Number(registro && registro.score);
  return s >= 90 ? 'ok' : (s >= 60 ? 'warn' : 'bad');
}

// Resumen de la evaluación (nivel, alertas, fallas críticas y puntaje por sección). Solo inspecciones nuevas.
function inspRenderResumen(datos) {
  const e = datos && datos._eval;
  if (!e || e.metodo !== 2) return '';
  const color = { ok: '#1b6e3c', warn: '#92600a', bad: '#a93b33' }[e.visual] || '#333';
  const lista = (titulo, items, estilo) => items.length
    ? `<div style="margin:0.4rem 0;"><strong style="${estilo}">${titulo}</strong><ul style="margin:0.2rem 0 0; padding-left:1.2rem;">${items.map(t => `<li>${t}</li>`).join('')}</ul></div>` : '';
  const filas = (e.secciones || []).map(s => {
    // Una sección con falla en un componente crítico sale en rojo aunque su promedio sea alto
    const c = s.criticos ? '#a93b33' : (s.score >= 85 ? '#1b6e3c' : (s.score >= 60 ? '#92600a' : '#a93b33'));
    return `<tr><td>${s.sec}${s.criticos ? ' ⛔' : ''}</td><td style="text-align:center; font-weight:700; color:${c};">${s.score}</td><td style="text-align:center;">${s.malos || '–'}</td><td style="text-align:center;">${s.atencion || '–'}</td></tr>`;
  }).join('');
  return `
    <div class="insp-resumen" style="border:1px solid var(--color-border); border-left:4px solid ${color}; border-radius:8px; padding:0.75rem 1rem; margin:0.75rem 0 1rem;">
      <div style="font-weight:700; color:${color}; font-size:1.05rem;">${(INSP_NIVELES[e.nivel] || {}).label || ''}</div>
      ${lista('🚨 Alertas', (e.alertas || []).map(a => a.texto), 'color:#a93b33;')}
      ${lista('⛔ Fallas en componentes críticos', e.criticosMalos || [], 'color:#a93b33;')}
      ${lista('⚠ Componentes críticos que requieren atención', e.criticosAtencion || [], 'color:#92600a;')}
      ${lista('🔧 Para reparar o revisar (componentes importantes)', [...(e.importantesMalos || []).map(t => `${t} — malo`), ...(e.importantesAtencion || []).map(t => `${t} — atención`)], 'color:#5b4a12;')}
      ${filas ? `<table style="margin-top:0.5rem;"><thead><tr><th style="text-align:left;">Sección</th><th>Puntaje</th><th>Malos</th><th>Atención</th></tr></thead><tbody>${filas}</tbody></table>` : ''}
      <p style="font-size:0.78rem; color:var(--color-text-muted); margin:0.5rem 0 0;">
        Cómo se calcula: cada ítem pesa según su importancia (crítico ×3, importante ×2, menor ×1); «Atención» vale la mitad
        y «Malo» cero. Una falla en un componente crítico, un kilometraje que no coincide o códigos de falla activos limitan
        la recomendación aunque el promedio general sea alto.${e.score !== e.scoreBase ? ` Promedio ponderado sin límites: ${e.scoreBase}/100.` : ''}
      </p>
    </div>`;
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

// Render de solo lectura del checklist respondido (detalle interno e informe público). Muestra solo ítems con
// respuesta o texto; los componentes críticos con atención/malo llevan su etiqueta.
function inspRenderDetalle(datos) {
  const etiquetaCritico = (p, v) => (p >= 3 && (v === 'warn' || v === 'bad')) ? inspBadgeImportancia(3) : '';
  return INSP_CHECKLIST.map((sec, si) => {
    const filas = [];
    sec.items.forEach((item, ii) => {
      const k = si + '_' + ii;
      if (item.mode === 'std') {
        const v = datos[k];
        if (!v || !INSP_ESTADOS[v]) return;
        filas.push(`<tr><td>${item.t}${etiquetaCritico(item.p, v)}${inspEvidencia(datos, k)}</td><td><span class="badge ${INSP_ESTADOS[v].badge}">${INSP_ESTADOS[v].label}</span></td></tr>`);
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
