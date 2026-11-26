// ============================================================
// Avance de la OT por categoría, ponderado por horas (sql/v81)
//
//  Categoría (del catálogo) → trabajo de la OT → tareas (del catálogo, en vivo).
//  · Cada tarea se marca ✓ con comentario y fotos (tabla ot_checks). Un trabajo sin tareas es una casilla.
//  · El trabajo pesa sus horas (las de la línea de la OT, o las del catálogo); sus tareas se lo reparten
//    según sus horas (o en partes iguales).
//  · Los repuestos se marcan pedido / recibido / instalado (los que se usen) y NO suman al avance.
//  · Un ✓ con comentario o foto entra también a «Trabajos realizados / avances» (ref = id del check),
//    así sigue apareciendo en el informe del cliente como hasta ahora.
//  · ordenes.progreso guarda el resumen para el seguimiento del cliente y el último envío.
// ============================================================
const AvanceOT = (() => {
  const ESTADOS_REP = [['pedido', '🛒 Pedido'], ['recibido', '📥 Recibido'], ['instalado', '🔧 Instalado']];
  const ETIQUETA_REP = Object.fromEntries(ESTADOS_REP);

  // Igual que categoriaItem de ordenes.html
  function tipoItem(i) {
    const sub = (i.tipo === 'otro' && i.tipo_otro) ? i.tipo_otro : i.tipo;
    if (sub === 'mano_obra') return 'mano_obra';
    if (sub === 'repuesto' || sub === 'insumo_vehiculo') return 'repuestos';
    if (sub === 'insumo_taller' || sub === 'insumo') return 'insumo_taller';
    return 'trabajo_externo';
  }
  const esRecargo = (i) => /^recargo por distancia/i.test(String(i.descripcion || ''));

  function iconoCategoria(nombre) {
    if (typeof iconoCategoriaServicio === 'function') return iconoCategoriaServicio(nombre);   // el mismo de layout.js
    const n = String(nombre || '').toLowerCase();
    const reglas = [[/motor|culata|distribuci/, '🔧'], [/fren/, '🛑'], [/suspens|amortig/, '🪛'], [/direcci/, '🛞'],
      [/el[eé]ctr|bater|luces/, '⚡'], [/a\/c|aire|clima/, '❄️'], [/manten|aceite|lubric|filtro/, '🛢️'],
      [/embrag|transmis|caja|diferencial/, '⚙️'], [/escape/, '💨'], [/neum|rueda/, '🛞'], [/diagn|scanner/, '🔍'],
      [/inspec|revisi/, '📋'], [/externo/, '🏭'], [/refriger|enfri/, '🌡️'], [/combust|inyec/, '⛽']];
    const r = reglas.find(([re]) => re.test(n));
    return r ? r[1] : '🔩';
  }

  // Horas con que pesa una línea de la OT
  function horasItem(i, t) {
    if (i.por_hora) return Math.max(0, Number(i.cantidad) || 0) || 1;
    const h = Number(i.horas) > 0 ? Number(i.horas) : (t && Number(t.horas_estimadas) > 0 ? Number(t.horas_estimadas) : 1);
    return h * Math.max(1, Number(i.cantidad) || 1);
  }

  // Modelo completo de la OT: categorías con sus trabajos y tareas, repuestos y totales
  function modelo(o, checks, trabajos, categorias) {
    const porClave = new Map((checks || []).map(c => [`${c.item_id}|${c.clave}`, c]));
    const cats = new Map();
    const repuestos = [];
    const catDe = (key, nombre, orden) => {
      if (!cats.has(key)) cats.set(key, { key, nombre, orden, icono: iconoCategoria(nombre), servicios: [], horas: 0, hechas: 0, pct: 0 });
      return cats.get(key);
    };
    const items = (o.orden_items || []).slice().sort((a, b) => (Number(a.orden) || 0) - (Number(b.orden) || 0));
    for (const i of items) {
      const tipo = tipoItem(i);
      if (tipo === 'repuestos') {
        const estados = {};
        ESTADOS_REP.forEach(([k]) => { const c = porClave.get(`${i.id}|${k}`); if (c) estados[k] = c; });
        repuestos.push({ item: i, nombre: i.descripcion || 'Repuesto', estados });
        continue;
      }
      if (tipo === 'insumo_taller' || esRecargo(i)) continue;
      const t = i.trabajo_id ? (trabajos || []).find(x => x.id === i.trabajo_id) : null;
      let cat;
      if (tipo === 'trabajo_externo') cat = catDe('_externo', 'Trabajos externos', 1e6);
      else {
        const catId = i.categoria_id || (t && t.categoria_id) || null;   // la de la línea (v82) manda sobre la del trabajo
        const c = catId ? (categorias || []).find(x => x.id === catId) : null;
        cat = c ? catDe(c.id, c.nombre, Number(c.orden) || 0) : catDe('_otros', 'Otros trabajos', 1e5);
      }
      const defs = t && Array.isArray(t.tareas) ? t.tareas.filter(x => x && x.id && String(x.nombre || '').trim()) : [];
      const conHoras = defs.filter(x => Number(x.horas) > 0);
      const prom = conHoras.length ? conHoras.reduce((s, x) => s + Number(x.horas), 0) / conHoras.length : 1;
      const tareas = defs.length
        ? defs.map(x => ({ clave: x.id, nombre: x.nombre, peso: Number(x.horas) > 0 ? Number(x.horas) : prom, check: porClave.get(`${i.id}|${x.id}`) || null }))
        : [{ clave: '_', nombre: i.descripcion || (t && t.nombre) || 'Trabajo', peso: 1, check: porClave.get(`${i.id}|_`) || null, unica: true }];
      const pesoTot = tareas.reduce((s, x) => s + x.peso, 0) || 1;
      const frac = tareas.filter(x => x.check).reduce((s, x) => s + x.peso, 0) / pesoTot;
      const horas = horasItem(i, t);
      const serv = { item: i, nombre: i.descripcion || (t && t.nombre) || 'Trabajo', horas, tareas, pct: Math.round(frac * 100), hechas: horas * frac };
      cat.servicios.push(serv);
      cat.horas += horas; cat.hechas += serv.hechas;
    }
    const categoriasOrd = [...cats.values()].sort((a, b) => a.orden - b.orden || a.nombre.localeCompare(b.nombre));
    categoriasOrd.forEach(c => { c.pct = c.horas ? Math.round(c.hechas / c.horas * 100) : 0; });
    const horas = categoriasOrd.reduce((s, c) => s + c.horas, 0);
    const hechas = categoriasOrd.reduce((s, c) => s + c.hechas, 0);
    return { categorias: categoriasOrd, repuestos, horas, hechas, pct: horas ? Math.round(hechas / horas * 100) : 0 };
  }

  // Resumen que se guarda en ordenes.progreso (conserva el último envío)
  function resumen(m, anterior) {
    const r = {
      pct: m.pct, horas: Math.round(m.horas * 10) / 10, hechas: Math.round(m.hechas * 10) / 10,
      categorias: m.categorias.map(c => ({ nombre: c.nombre, icono: c.icono, pct: c.pct })),
      actualizado: new Date().toISOString(),
    };
    if (anterior && anterior.enviado_en) { r.enviado_en = anterior.enviado_en; r.enviado_pct = anterior.enviado_pct; }
    return r;
  }

  // Texto del avance que entra a «Trabajos realizados / avances»
  function textoAvance(m, item_id, clave, comentario) {
    let titulo = '';
    const rep = m.repuestos.find(r => r.item.id === item_id);
    if (rep) titulo = `📦 ${rep.nombre}: ${(ETIQUETA_REP[clave] || clave).replace(/^\S+\s/, '')}`;
    else for (const c of m.categorias) for (const s of c.servicios) if (s.item.id === item_id) {
      const t = s.tareas.find(x => x.clave === clave);
      titulo = `✓ ${c.nombre} · ${s.nombre}${t && !t.unica ? `: ${t.nombre}` : ''}`;
    }
    return [titulo || '✓ Avance', String(comentario || '').trim()].filter(Boolean).join('\n');
  }

  // Lo nuevo desde el último envío al cliente (tareas hechas y estados de repuestos)
  function novedades(m, desde) {
    const t0 = desde ? new Date(desde).getTime() : 0;
    const nuevo = (c) => c && new Date(c.creado_en).getTime() > t0;
    const out = [];
    m.categorias.forEach(c => c.servicios.forEach(s => s.tareas.forEach(t => {
      if (nuevo(t.check)) out.push({ fecha: t.check.creado_en, texto: `${t.unica ? s.nombre : `${t.nombre} (${s.nombre})`}${(t.check.fotos || []).length ? ' 📷' : ''}` });
    })));
    m.repuestos.forEach(r => ESTADOS_REP.forEach(([k, et]) => {
      const c = r.estados[k];
      if (nuevo(c)) out.push({ fecha: c.creado_en, texto: `${r.nombre}: ${et.replace(/^\S+\s/, '').toLowerCase()}${(c.fotos || []).length ? ' 📷' : ''}` });
    }));
    return out.sort((a, b) => new Date(a.fecha) - new Date(b.fecha)).map(x => x.texto);
  }

  const barra = (pct) => { const n = Math.round(Math.max(0, Math.min(100, pct)) / 10); return '▰'.repeat(n) + '▱'.repeat(10 - n); };
  // Bloque del mensaje al cliente: % por categoría + lo nuevo
  function bloqueAvance(m, desde) {
    const lineas = m.categorias.map(c => `${c.icono} ${c.nombre}: ${barra(c.pct)} ${c.pct === 100 ? '✓ listo' : c.pct + ' %'}`);
    const nuevos = novedades(m, desde);
    return lineas.join('\n') + (nuevos.length ? `\n\n${desde ? 'Lo nuevo desde el último aviso' : 'Lo que ya hicimos'}:\n${nuevos.map(x => '• ' + x).join('\n')}` : '');
  }

  // Anillo SVG con el %
  function anillo(pct, size, color, texto) {
    const r = 15, L = 2 * Math.PI * r, p = Math.max(0, Math.min(100, pct));
    return `<svg width="${size}" height="${size}" viewBox="0 0 36 36" aria-hidden="true">
      <circle cx="18" cy="18" r="${r}" fill="none" stroke="#eceef2" stroke-width="4"/>
      ${p > 0 ? `<circle cx="18" cy="18" r="${r}" fill="none" stroke="${color}" stroke-width="4" stroke-linecap="round" stroke-dasharray="${(L * p / 100).toFixed(1)} ${L.toFixed(1)}" transform="rotate(-90 18 18)"/>` : ''}
      <text x="18" y="21" text-anchor="middle" font-size="${texto.length > 3 ? 7.5 : 8.5}" font-weight="700" fill="#15181e">${texto}</text></svg>`;
  }

  function estilos() {
    if (document.getElementById('avance-ot-css')) return;
    const st = document.createElement('style');
    st.id = 'avance-ot-css';
    st.textContent = `
      .av-anillos { display:flex; gap:0.9rem; flex-wrap:wrap; align-items:flex-end; margin:0.25rem 0 0.6rem; }
      .av-anillo { text-align:center; font-size:0.72rem; color:var(--color-text-muted); max-width:78px; line-height:1.15; }
      .av-anillo svg { display:block; margin:0 auto 2px; }
      .av-cat { border:1px solid var(--color-border); border-radius:var(--radius); margin-bottom:0.5rem; background:#fff; overflow:hidden; }
      .av-cat > summary { list-style:none; cursor:pointer; padding:0.55rem 0.7rem; background:#fafbfc; display:flex; align-items:center; gap:0.6rem; font-weight:700; }
      .av-cat > summary::-webkit-details-marker { display:none; }
      .av-mini { flex:1; height:7px; background:#eceef2; border-radius:99px; overflow:hidden; min-width:40px; }
      .av-mini i { display:block; height:100%; background:#1b8a4b; border-radius:99px; }
      .av-cp { font-size:0.8rem; color:var(--color-text-muted); min-width:2.6rem; text-align:right; font-weight:600; }
      .av-serv { padding:0.5rem 0.7rem; border-top:1px solid var(--color-border); }
      .av-sn { font-weight:600; font-size:0.9rem; display:flex; justify-content:space-between; gap:0.5rem; }
      .av-sn small { color:var(--color-text-muted); font-weight:400; white-space:nowrap; }
      .av-tarea { display:flex; gap:0.55rem; align-items:flex-start; padding:0.4rem 0 0.4rem 0.2rem; font-size:0.88rem; cursor:pointer; border-radius:6px; }
      .av-tarea:hover { background:#f6f8fb; }
      .av-caja { width:22px; height:22px; flex:none; border:2px solid #b8c0cc; border-radius:6px; display:flex; align-items:center; justify-content:center; font-size:0.85rem; color:#fff; background:#fff; margin-top:1px; }
      .av-tarea.hecha .av-caja { background:#1b8a4b; border-color:#1b8a4b; }
      .av-tarea.hecha .av-tn { color:var(--color-text-muted); }
      .av-meta { display:block; font-size:0.76rem; color:var(--color-text-muted); margin-top:1px; white-space:pre-wrap; }
      .av-fotos { display:flex; gap:4px; flex-wrap:wrap; margin-top:3px; }
      .av-fotos img { width:44px; height:34px; object-fit:cover; border-radius:4px; border:1px solid var(--color-border); }
      .av-hoja { margin:0.35rem 0 0.5rem 1.9rem; border:2px solid var(--color-primary); border-radius:10px; padding:0.6rem; background:#fff8f6; cursor:default; }
      .av-hoja textarea { width:100%; margin:0.35rem 0; }
      .av-hoja .av-acc { display:flex; gap:0.4rem; flex-wrap:wrap; align-items:center; }
      .av-rep { padding:0.5rem 0.7rem; border-top:1px solid var(--color-border); font-size:0.88rem; }
      .av-rep-estados { display:flex; gap:0.35rem; flex-wrap:wrap; margin-top:0.3rem; }
      .av-chip { border:1px solid var(--color-border); background:#fff; border-radius:99px; padding:0.2rem 0.6rem; font-size:0.78rem; cursor:pointer; color:var(--color-text-muted); }
      .av-chip.usado { background:#eef4ff; border-color:#b9cdf7; color:#1d3f8f; font-weight:600; }
      .av-enviar { display:flex; gap:0.6rem; align-items:center; flex-wrap:wrap; margin-top:0.6rem; }
      .av-envio-box { border:1px solid var(--color-border); border-radius:var(--radius); padding:0.7rem; margin-top:0.6rem; background:#fafbfc; }
      .av-envio-box textarea { width:100%; font-size:0.85rem; }
    `;
    document.head.appendChild(st);
  }

  return { ESTADOS_REP, ETIQUETA_REP, modelo, resumen, textoAvance, novedades, bloqueAvance, anillo, estilos, barra };
})();
