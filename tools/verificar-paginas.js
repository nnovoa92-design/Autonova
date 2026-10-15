// Verificación rápida de las páginas (sintaxis y choques de nombres con layout.js / supabaseClient.js).
// Uso: abre el sitio (o el servidor local), pulsa F12 → Consola, pega este archivo completo y Enter.
// Devuelve { sintaxis: {...}, choques: [...] }: ambos deben salir vacíos.
(async () => {
  const paginas = ['index.html', 'reservar.html', 'portal.html', 'cotizacion.html', 'diagnostico.html', 'inspeccion.html', 'inspeccion-ingreso.html',
    'pages/agenda.html', 'pages/clientes.html', 'pages/configuracion.html', 'pages/contabilidad.html', 'pages/cotizaciones.html',
    'pages/dashboard.html', 'pages/diagnosticos.html', 'pages/inspecciones.html', 'pages/inventario.html', 'pages/ordenes.html',
    'pages/pagos.html', 'pages/trabajos.html', 'pages/vehiculos.html'];
  const salida = { sintaxis: {}, choques: [] };
  const declaraciones = (src, sangria) => {
    const o = {};
    const re = new RegExp('^' + sangria + '(async\s+function|function|const|let|class)\s+([A-Za-z_$][\w$]*)', 'gm');
    let m; while ((m = re.exec(src))) o[m[2]] = m[1];
    return o;
  };
  const layout = await fetch('/assets/js/layout.js', { cache: 'no-store' }).then(r => r.text());
  const cliente = await fetch('/assets/js/supabaseClient.js', { cache: 'no-store' }).then(r => r.text());
  for (const [nombre, src] of [['layout.js', layout], ['supabaseClient.js', cliente]]) {
    try { new Function(src); } catch (e) { salida.sintaxis[nombre] = e.message; }
  }
  const compartidas = Object.assign({}, declaraciones(cliente, ''), declaraciones(layout, ''));
  for (const p of paginas) {
    const html = await fetch('/' + p, { cache: 'no-store' }).then(r => r.text());
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const scripts = [...doc.querySelectorAll('script:not([src])')].map(s => s.textContent);
    scripts.forEach((s, i) => {
      try { new Function('return (async()=>{' + s + '\n})'); } catch (e) { (salida.sintaxis[p] = salida.sintaxis[p] || []).push(`script ${i}: ${e.message}`); }
    });
    const propias = Object.assign({}, declaraciones(scripts.join('\n'), '    '), declaraciones(scripts.join('\n'), '  '), declaraciones(scripts.join('\n'), ''));
    for (const [n, tipo] of Object.entries(propias)) {
      // function + function se permite (la de la página gana); const/let/class contra algo compartido rompe la página
      if (n in compartidas && !(/function/.test(tipo) && /function/.test(compartidas[n]))) salida.choques.push(`${p}: ${n}`);
    }
  }
  console.log('Verificación de páginas:', salida);
  return salida;
})();
